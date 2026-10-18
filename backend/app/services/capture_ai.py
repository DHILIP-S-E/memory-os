"""
AI processing of captured text (notes, links).

With the queue pipeline (SQS -> worker) this runs in the worker Lambda; in the lean
deployment there is no queue, so the API runs the same steps in a background task.
The prompt and the parsing of the model's reply live here so both paths agree.
"""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any, Callable

from app.services.action_items import normalize_actions

logger = logging.getLogger(__name__)
MAX_ITEMS = 8
MAX_TEXT = 8000


def build_prompt(text: str, today_iso: str | None = None) -> str:
    today = today_iso or datetime.now(timezone.utc).date().isoformat()
    return (
        "Summarise this captured content. Return ONLY JSON: "
        '{"summary": str, "topics": [str], "key_points": [str], '
        '"actions": [{"title": str, "due_at": "YYYY-MM-DD or null"}]}\n'
        "actions are things the speaker says they must do in the future. "
        f"Today is {today}; resolve relative or partial dates against it, "
        "and use null when no date is stated. Never invent a date.\n\n"
        + text[:MAX_TEXT]
    )


def _strings(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    out = [v.strip() for v in value if isinstance(v, str) and v.strip()]
    return out[:MAX_ITEMS]


def parse_summary(raw: str) -> dict:
    """Model reply (possibly fenced or chatty) -> {summary, topics, key_points, actions}.
    Never raises on shape problems: unusable parts become empty."""
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    try:
        data = json.loads(match.group()) if match else {}
    except json.JSONDecodeError:
        data = {}
    if not isinstance(data, dict):
        data = {}
    summary = data.get("summary")
    return {
        "summary": summary.strip()[:2000] if isinstance(summary, str) else raw.strip()[:500],
        "topics": _strings(data.get("topics")),
        "key_points": _strings(data.get("key_points")),
        "actions": normalize_actions(data.get("actions")),
    }


def summarise_text(text: str) -> dict:
    """Call the fast Gemini model (blocking) and parse its reply."""
    from app.config import settings
    from app.services.llm_service import _invoke

    return parse_summary(_invoke(settings.gemini_model_fast, build_prompt(text), max_tokens=800))


async def process_text_capture(
    capture_id: str,
    session_factory: Callable | None = None,
    summarise: Callable[[str], dict] = summarise_text,
) -> None:
    """queued -> processing -> processed | failed for a note or link. Never raises."""
    from app.database import AsyncSessionLocal
    from app.models.capture import Capture

    factory = session_factory or AsyncSessionLocal
    try:
        async with factory() as db:
            capture = await db.get(Capture, capture_id)
            if capture is None or capture.capture_type not in ("note", "link"):
                return
            capture.processing_status = "processing"
            await db.commit()
            try:
                if capture.capture_type == "link":
                    result = {"summary": f"Saved link: {capture.content}", "topics": [], "key_points": [], "actions": []}
                else:
                    result = await asyncio.to_thread(summarise, capture.content or "")
                capture.ai_summary = result["summary"]
                capture.ai_topics = json.dumps(result["topics"])
                capture.ai_key_points = json.dumps(result["key_points"])
                capture.ai_actions = json.dumps(result["actions"])
                capture.processing_status = "processed"
            except Exception:
                logger.exception("AI processing failed for capture %s", capture_id)
                capture.processing_status = "failed"
            capture.updated_at = datetime.utcnow()
            await db.commit()
    except Exception:
        logger.exception("Could not update capture %s", capture_id)
