"""
The app's AI features: reminder parsing, event extraction, event summaries and memory Q&A.
Every model call goes through app.services.gemini; the phone and web never call the model.
"""

import json
import re
from datetime import datetime
from pathlib import Path

from app.config import settings
from app.services import gemini
from app.services.event_extraction import normalize_extraction
from app.services.reminder_parser import detect_ambiguities, normalize_reminder


def _load_prompt(name: str) -> str:
    path = Path(__file__).parent.parent / "prompts" / f"{name}.txt"
    return path.read_text(encoding="utf-8")


def _render(template: str, **values: str) -> str:
    """Substitute {name} placeholders only; prompts contain literal JSON braces."""
    for key, value in values.items():
        template = template.replace("{" + key + "}", str(value))
    return template


def _invoke(model_id: str, prompt: str, max_tokens: int = 1024) -> str:
    """Ask a Gemini model and return its text. Every prompt here asks for JSON, so JSON
    mode is on. The model is a setting (GEMINI_MODEL_FAST / _STRONG), not code."""
    return gemini.generate(prompt, model=model_id, max_tokens=max_tokens, json_mode=True)


def _extract_json(raw: str) -> dict:
    """Extract the first JSON object from a raw LLM response."""
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if not match:
        raise ValueError(f"No JSON object found in response: {raw[:200]}")
    return json.loads(match.group())


def parse_reminder(text: str, timezone: str = "UTC") -> dict:
    """
    Parse natural language into a structured reminder dict.
    Uses the fast model (GEMINI_MODEL_FAST) for speed and cost efficiency.
    Returns: {title, type, scheduled_at, priority, offsets}
    """
    template = _load_prompt("parse_reminder")
    prompt = _render(
        template,
        current_datetime=datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S UTC"),
        timezone=timezone,
        input=text,
    )
    raw = _invoke(settings.gemini_model_fast, prompt, max_tokens=512)
    result = normalize_reminder(_extract_json(raw), fallback_text=text[:100])
    # The user must confirm anything uncertain before a reminder is created.
    result["ambiguities"] = detect_ambiguities(result, text, datetime.utcnow())
    return result


def extract_event(text: str, source_url: str | None = None) -> dict:
    """
    Extract event metadata from pasted text / URL / email.
    Uses the fast model (GEMINI_MODEL_FAST). The model's answer is untrusted, so it is
    cleaned by event_extraction.normalize_extraction before it is returned.
    Returns: {title, event_type, start_at, end_at, location, event_url, registration_deadline,
              submission_deadline, evidence, missing_fields, needs_user_review, ...}
    """
    template = _load_prompt("extract_event")
    prompt = _render(
        template,
        current_date=datetime.utcnow().date().isoformat(),
        text=text,
    )
    raw = _invoke(settings.gemini_model_fast, prompt, max_tokens=512)
    return normalize_extraction(_extract_json(raw), source_text=text, source_url=source_url)


def answer_memory_question(question: str, docs: list) -> dict:
    """
    RAG-style memory Q&A using the strong model (GEMINI_MODEL_STRONG).
    Builds context from MemoryDocument rows, calls Gemini, returns a grounded answer.

    Args:
        question: the user's natural language question
        docs: list of MemoryDocument ORM objects

    Returns: {"answer": str, "sources": [{"event_title": str, "capture_ref": str|None}]}
    Raises gemini.AIUnavailable (not configured, network, HTTP error) or ValueError (blocked,
    empty or unreadable answer); the route turns those into HTTP errors.
    """
    if not docs:
        return {
            "answer": "I couldn't find anything in your memory related to that question.",
            "sources": [],
        }

    # Build context string from memory documents
    context_parts = []
    for doc in docs:
        topics = json.loads(doc.key_topics or "[]")
        takeaways = json.loads(doc.key_takeaways or "[]")
        things_learned = json.loads(doc.things_learned or "[]")

        section = f"Event: {doc.event_title or 'Unknown event'}\n"
        if doc.overview:
            section += f"Overview: {doc.overview}\n"
        if topics:
            section += f"Topics: {', '.join(topics)}\n"
        if takeaways:
            section += f"Key takeaways: {'; '.join(takeaways[:3])}\n"
        if things_learned:
            section += f"Things learned: {'; '.join(things_learned[:3])}\n"
        context_parts.append(section)

    context = "\n---\n".join(context_parts)

    template = _load_prompt("memory_qa")
    prompt = _render(template, context=context, question=question)

    raw = _invoke(settings.gemini_model_strong, prompt, max_tokens=1024)
    result = _extract_json(raw)
    if not isinstance(result.get("answer"), str) or not result["answer"].strip():
        raise ValueError("The AI answer had no text")
    if not isinstance(result.get("sources"), list):
        result["sources"] = []
    return result


def summarize_event(event_title: str, event_date: str, captures_text: str) -> dict:
    """
    Generate a structured event summary from capture content.
    Uses the strong model (GEMINI_MODEL_STRONG) for quality summarization.

    Args:
        event_title: name of the event
        event_date: ISO 8601 date string
        captures_text: concatenated text from all captures for this event

    Returns structured summary dict with topics, takeaways, action_items, etc.
    Raises ValueError when there is nothing to summarize or the answer is unusable, and
    gemini.AIUnavailable when the AI service cannot be used; the caller reports both.
    """
    if not captures_text.strip():
        raise ValueError("There is nothing captured for this event to summarize")

    template = _load_prompt("summarize_event")
    prompt = _render(
        template,
        event_title=event_title,
        event_date=event_date,
        captures_text=captures_text[:8000],  # truncate to stay within token budget
    )
    raw = _invoke(settings.gemini_model_strong, prompt, max_tokens=2048)
    result = _extract_json(raw)
    # Fill list fields the model left out; a non-list value is not usable.
    for key in ["key_topics", "key_takeaways", "things_learned",
                "important_people", "resources", "links",
                "decisions", "action_items"]:
        if not isinstance(result.get(key), list):
            result[key] = []
    if not isinstance(result.get("overview"), str) or not result["overview"].strip():
        raise ValueError("The AI summary had no overview")
    return result
