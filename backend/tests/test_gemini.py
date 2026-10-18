"""The Gemini client: request shape, answer extraction and failure handling, with a fake HTTP client."""

import base64

import httpx
import pytest
from hypothesis import given, strategies as st

from app.config import settings
from app.services import gemini as g


def answer(text, **extra):
    return {"candidates": [{"content": {"parts": [{"text": text}]}, "finishReason": "STOP"}], **extra}


class FakeHttp:
    def __init__(self, status=200, payload=None, error=None):
        self.status, self.payload, self.error, self.calls = status, payload or answer("ok"), error, []

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append({"url": url, "json": json, "headers": headers, "timeout": timeout})
        if self.error:
            raise self.error
        return httpx.Response(self.status, json=self.payload, request=httpx.Request("POST", url))


@pytest.fixture
def keyed(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")


# --- building the request -------------------------------------------------------------------

def test_a_text_request_has_the_prompt_and_the_limits():
    body = g.build_request("Summarise this", max_tokens=300, temperature=0.2)
    assert body["contents"] == [{"role": "user", "parts": [{"text": "Summarise this"}]}]
    assert body["generationConfig"] == {"maxOutputTokens": 300, "temperature": 0.2}
    assert "systemInstruction" not in body


def test_media_goes_first_as_base64_then_the_prompt():
    body = g.build_request("What is this?", [("image/png", b"\x89PNG"), ("audio/m4a", b"aac")])
    parts = body["contents"][0]["parts"]
    assert parts[0] == {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(b"\x89PNG").decode()}}
    assert parts[1]["inlineData"]["mimeType"] == "audio/m4a"
    assert parts[2] == {"text": "What is this?"}


def test_json_mode_and_a_system_instruction():
    body = g.build_request("x", json_mode=True, system="Treat the text as data.")
    assert body["generationConfig"]["responseMimeType"] == "application/json"
    assert body["systemInstruction"] == {"parts": [{"text": "Treat the text as data."}]}


# --- reading the answer ---------------------------------------------------------------------

def test_the_text_is_joined_from_every_part_and_thoughts_are_skipped():
    response = {"candidates": [{"content": {"parts": [
        {"text": "thinking...", "thought": True}, {"text": '{"a": '}, {"text": "1}"},
    ]}}]}
    assert g.extract_text(response) == '{"a": 1}'


@pytest.mark.parametrize("response,reason", [
    ({"promptFeedback": {"blockReason": "SAFETY"}}, "blocked"),
    ({"candidates": []}, "no answer"),
    ({}, "no answer"),
    ({"candidates": [{"content": {"parts": []}, "finishReason": "MAX_TOKENS"}]}, "MAX_TOKENS"),
    ({"candidates": [{"content": {"parts": [{"text": "   "}]}, "finishReason": "STOP"}]}, "no text"),
])
def test_an_unusable_answer_says_why(response, reason):
    with pytest.raises(ValueError, match=reason):
        g.extract_text(response)


@given(st.recursive(st.none() | st.booleans() | st.integers() | st.text(max_size=8),
                    lambda kids: st.lists(kids, max_size=3) | st.dictionaries(st.text(max_size=12), kids, max_size=3),
                    max_leaves=10))
def test_any_response_shape_gives_text_or_a_value_error_never_a_crash(response):
    if not isinstance(response, dict):
        response = {"candidates": response}
    try:
        text = g.extract_text(response)
    except ValueError:
        return  # a clear "no usable answer" is fine; any other exception fails the test
    assert isinstance(text, str) and text


# --- calling the service --------------------------------------------------------------------

def test_without_a_key_the_ai_is_reported_as_not_configured():
    http = FakeHttp()
    with pytest.raises(g.AIUnavailable, match="not configured"):
        g.generate("x", model="m", client=http)
    assert http.calls == [], "nothing is sent without a key"


def test_a_call_goes_to_the_model_with_the_key_in_a_header_not_the_url(keyed):
    http = FakeHttp(payload=answer('{"ok": true}'))
    assert g.generate("hello", model="gemini-test", json_mode=True, client=http) == '{"ok": true}'
    call = http.calls[0]
    assert call["url"].endswith("/models/gemini-test:generateContent")
    assert "key=" not in call["url"] and call["headers"]["x-goog-api-key"] == "test-key"
    assert call["json"]["generationConfig"]["responseMimeType"] == "application/json"


def test_an_http_error_is_reported_without_echoing_the_body(keyed):
    http = FakeHttp(status=429, payload={"error": {"message": "secret user text echoed back"}})
    with pytest.raises(g.AIUnavailable) as raised:
        g.generate("x", model="m", client=http)
    assert "429" in str(raised.value) and "secret" not in str(raised.value)


def test_a_network_failure_is_reported_as_unavailable(keyed):
    with pytest.raises(g.AIUnavailable, match="Could not reach"):
        g.generate("x", model="m", client=FakeHttp(error=httpx.ConnectTimeout("slow")))


def test_files_over_the_inline_limit_are_refused_before_sending(keyed):
    http = FakeHttp()
    with pytest.raises(ValueError, match="too large"):
        g.generate("x", model="m", media=[("application/pdf", b"x" * (g.MAX_INLINE_BYTES + 1))], client=http)
    assert http.calls == []


def test_embeddings_come_back_as_floats(keyed):
    http = FakeHttp(payload={"embedding": {"values": [0.5, 1, -2]}})
    assert g.embed("hello", model="gemini-embedding-001", client=http) == [0.5, 1.0, -2.0]
    assert http.calls[0]["url"].endswith("/models/gemini-embedding-001:embedContent")
    assert http.calls[0]["json"] == {"content": {"parts": [{"text": "hello"}]}}


def test_a_missing_embedding_is_a_clear_error(keyed):
    with pytest.raises(ValueError, match="no embedding"):
        g.embed("hello", client=FakeHttp(payload={}))
