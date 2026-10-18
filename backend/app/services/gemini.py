"""
Google Gemini: every model call in the app goes through here. Backend only; the key
never reaches the phone, the web app or the browser.

Pure helpers (build_request, extract_text, build_embed_request) plus two thin HTTP calls.
The model is a setting (GEMINI_MODEL_FAST / GEMINI_MODEL_STRONG); nothing here is
specific to one model.
"""

import base64
from typing import Iterable

import httpx

from app.config import settings

API_ROOT = "https://generativelanguage.googleapis.com/v1beta"
# Gemini accepts at most 20 MB per request, prompt included. Stay clear of it.
MAX_INLINE_BYTES = 18 * 1024 * 1024


class AIUnavailable(RuntimeError):
    """The AI service is not configured, unreachable, or refused the request."""


def build_request(
    prompt: str,
    media: Iterable[tuple[str, bytes]] = (),
    *,
    max_tokens: int = 1024,
    temperature: float = 0.1,
    json_mode: bool = False,
    system: str | None = None,
) -> dict:
    """The JSON body for generateContent. `media` is (mime type, raw bytes) pairs sent inline
    before the prompt, so the prompt can refer to them."""
    parts = [
        {"inlineData": {"mimeType": mime, "data": base64.b64encode(data).decode("ascii")}}
        for mime, data in media
    ]
    parts.append({"text": prompt})
    config: dict = {"maxOutputTokens": max_tokens, "temperature": temperature}
    if json_mode:
        config["responseMimeType"] = "application/json"
    body: dict = {"contents": [{"role": "user", "parts": parts}], "generationConfig": config}
    if system:
        body["systemInstruction"] = {"parts": [{"text": system}]}
    return body


def extract_text(response: dict) -> str:
    """The model's answer from a generateContent response.

    Raises ValueError with a reason when there is no usable text: the prompt was blocked,
    no candidate came back, or the reply was cut off before any text."""
    if not isinstance(response, dict):
        raise ValueError("The AI service returned an unexpected answer")
    feedback = response.get("promptFeedback")
    if isinstance(feedback, dict) and feedback.get("blockReason"):
        raise ValueError(f"The request was blocked by the AI service ({feedback['blockReason']})")
    candidates = response.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise ValueError("The AI service returned no answer")
    first = candidates[0] if isinstance(candidates[0], dict) else {}
    content = first.get("content") if isinstance(first.get("content"), dict) else {}
    parts = content.get("parts") if isinstance(content.get("parts"), list) else []
    text = "".join(
        p["text"] for p in parts
        if isinstance(p, dict) and isinstance(p.get("text"), str) and not p.get("thought")
    ).strip()
    if not text:
        raise ValueError(f"The AI service returned no text (finish reason: {first.get('finishReason', 'unknown')})")
    return text


def build_embed_request(text: str) -> dict:
    return {"content": {"parts": [{"text": text}]}}


def _key() -> str:
    if not settings.gemini_api_key:
        raise AIUnavailable("AI is not configured: set GEMINI_API_KEY on the server")
    return settings.gemini_api_key


def _post(path: str, body: dict, timeout: float, client: httpx.Client | None) -> dict:
    headers = {"x-goog-api-key": _key(), "Content-Type": "application/json"}
    try:
        response = (client or httpx).post(f"{API_ROOT}/{path}", json=body, headers=headers, timeout=timeout)
    except httpx.HTTPError as exc:
        raise AIUnavailable(f"Could not reach the AI service ({type(exc).__name__})") from exc
    if response.status_code >= 400:
        # Report the status only: the body can echo the request, which may hold user content.
        raise AIUnavailable(f"The AI service returned HTTP {response.status_code}")
    return response.json()


def generate(
    prompt: str,
    *,
    model: str,
    media: Iterable[tuple[str, bytes]] = (),
    max_tokens: int = 1024,
    json_mode: bool = False,
    system: str | None = None,
    timeout: float = 60.0,
    client: httpx.Client | None = None,
) -> str:
    """Ask `model` and return its text. Raises AIUnavailable (not configured, network,
    HTTP error) or ValueError (blocked or empty answer)."""
    media = list(media)
    if sum(len(data) for _, data in media) > MAX_INLINE_BYTES:
        raise ValueError("The file is too large for the AI service")
    body = build_request(prompt, media, max_tokens=max_tokens, json_mode=json_mode, system=system)
    return extract_text(_post(f"models/{model}:generateContent", body, timeout, client))


def embed(text: str, *, model: str | None = None, timeout: float = 30.0, client: httpx.Client | None = None) -> list[float]:
    """A vector for `text`, for semantic search."""
    model = model or settings.gemini_embedding_model
    data = _post(f"models/{model}:embedContent", build_embed_request(text), timeout, client)
    try:
        return [float(v) for v in data["embedding"]["values"]]
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("The AI service returned no embedding") from exc
