"""Which Gemini model each AI feature uses, and how the AI routes report problems."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.services import gemini
from app.services import llm_service

REMINDER = '{"title": "Submit", "type": "deadline", "scheduled_at": null, "priority": "high", "offsets": []}'


class FakeGemini:
    def __init__(self, text=REMINDER):
        self.text, self.calls = text, []

    def __call__(self, prompt, **kw):
        self.calls.append(kw)
        if isinstance(self.text, Exception):
            raise self.text
        return self.text


@pytest.fixture
def fake(monkeypatch):
    f = FakeGemini()
    monkeypatch.setattr(gemini, "generate", f)
    return f


def test_fast_model_for_parsing_and_strong_model_for_summaries(fake, monkeypatch):
    monkeypatch.setattr(settings, "gemini_model_fast", "fast-model")
    monkeypatch.setattr(settings, "gemini_model_strong", "strong-model")
    llm_service.parse_reminder("remind me to submit")
    fake.text = '{"overview": "o"}'
    llm_service.summarize_event("Hackathon", "2026-10-04", "some captured notes")
    assert [c["model"] for c in fake.calls] == ["fast-model", "strong-model"]


def test_every_call_asks_for_json(fake):
    llm_service.parse_reminder("remind me to submit")
    assert fake.calls[0]["json_mode"] is True


def test_the_defaults_are_gemini_models():
    assert settings.gemini_model_fast.startswith("gemini") and settings.gemini_model_strong.startswith("gemini")


def test_fenced_json_replies_are_understood(fake):
    fake.text = '```json\n{"title": "Submit prototype", "type": "deadline", "scheduled_at": "2030-10-20T17:00:00+05:30", "priority": "high", "offsets": ["-1d"]}\n```'
    out = llm_service.parse_reminder("submit prototype by Oct 20 5pm")
    assert out["title"] == "Submit prototype" and out["type"] == "deadline" and out["offsets"] == ["-1d"]


def test_memory_answers_do_not_hide_an_ai_failure(fake):
    class Doc:
        event_title, overview, key_topics, key_takeaways, things_learned = "Hack", "o", "[]", "[]", "[]"

    fake.text = gemini.AIUnavailable("The AI service returned HTTP 500")
    with pytest.raises(gemini.AIUnavailable):
        llm_service.answer_memory_question("what did I learn?", [Doc()])


def test_an_event_summary_does_not_hide_an_ai_failure(fake):
    fake.text = gemini.AIUnavailable("The AI service returned HTTP 500")
    with pytest.raises(gemini.AIUnavailable):
        llm_service.summarize_event("Hack", "2026-10-04", "notes")


def test_an_unusable_summary_or_answer_is_an_error_not_filler(fake):
    class Doc:
        event_title, overview, key_topics, key_takeaways, things_learned = "Hack", "o", "[]", "[]", "[]"

    fake.text = "{}"
    with pytest.raises(ValueError):
        llm_service.summarize_event("Hack", "2026-10-04", "notes")
    with pytest.raises(ValueError):
        llm_service.answer_memory_question("q", [Doc()])
    with pytest.raises(ValueError):
        llm_service.summarize_event("Hack", "2026-10-04", "   ")


# --- the AI routes report problems in plain words --------------------------------------------

@pytest.fixture
def client(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})

    async def setup():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(setup())
    Session = async_sessionmaker(engine, expire_on_commit=False)

    async def override():
        async with Session() as s:
            yield s

    app.dependency_overrides[get_db] = override
    monkeypatch.setattr(settings, "jwt_secret", "q" * 48)
    c = TestClient(app)
    r = c.post("/auth/register", json={"email": "ada@example.com", "password": "correct horse"})
    c.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    assert c.put("/account/settings", json={"ai_enabled": True}).status_code == 200  # AI reading is opt-in
    yield c
    app.dependency_overrides.clear()


def test_without_a_key_the_ai_routes_say_it_is_not_configured(client):
    r = client.post("/ai/extract-event", json={"text": "AWS Student Hackathon on 20 November"})
    assert r.status_code == 503 and "not configured" in r.json()["detail"]
    r = client.post("/ai/parse-reminder", json={"text": "remind me tomorrow"})
    assert r.status_code == 503 and "not configured" in r.json()["detail"]


def test_an_unreadable_answer_is_a_422_that_does_not_echo_the_model(client, fake):
    fake.text = "I refuse to answer in JSON. Here is some private reasoning."
    r = client.post("/ai/parse-reminder", json={"text": "remind me tomorrow"})
    assert r.status_code == 422
    assert "private reasoning" not in r.json()["detail"] and "rewording" in r.json()["detail"]


def test_an_unexpected_failure_is_a_503_without_internals(client, fake):
    fake.text = RuntimeError("Traceback: secret internals at line 42")
    r = client.post("/ai/extract-event", json={"text": "AWS Student Hackathon on 20 November"})
    assert r.status_code == 503 and "internals" not in r.json()["detail"]


def _memory_document(client, fake):
    """An event with one capture and its generated summary, so /memory/ask has something to search."""
    r = client.post("/events", json={"title": "Hack", "event_type": "hackathon", "start_at": "2030-10-04T09:00:00"})
    assert r.status_code == 201, r.text
    event_id = r.json()["id"]
    assert client.post("/captures/note", json={"content": "learned about vector search", "event_id": event_id}).status_code == 201
    fake.text = '{"overview": "o", "key_topics": []}'
    assert client.post(f"/events/{event_id}/generate-summary").status_code == 201


def test_memory_ask_reports_an_ai_outage_instead_of_a_fake_answer(client, fake):
    _memory_document(client, fake)
    fake.text = gemini.AIUnavailable("The AI service returned HTTP 500")
    r = client.post("/memory/ask", json={"question": "what did I learn about vector search?"})
    assert r.status_code == 503 and "HTTP 500" in r.json()["detail"]


def test_memory_ask_with_an_unreadable_answer_is_a_502(client, fake):
    _memory_document(client, fake)
    fake.text = "no json here"
    r = client.post("/memory/ask", json={"question": "what did I learn about vector search?"})
    assert r.status_code == 502 and "no json" not in r.json()["detail"]


def test_summary_of_an_event_with_no_captures_is_a_422(client, fake):
    r = client.post("/events", json={"title": "Hack", "event_type": "hackathon", "start_at": "2030-10-04T09:00:00"})
    assert r.status_code == 201, r.text
    r = client.post(f"/events/{r.json()['id']}/generate-summary")
    assert r.status_code == 422 and fake.calls == []
