"""
Reading a capture in the background: the "capture.process" job.

Notes are summarised as text, links are kept as links, and files (photos, documents, voice
notes) are read from R2 and sent to Gemini in one call. Status goes queued -> processing ->
processed, or failed with a reason the user can read.
"""

import asyncio
import json
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.capture import Capture
from app.models.job import Job
from app.services import jobs, media_ai, storage
from app.services.capture_ai import summarise_text

PROCESS = "capture.process"
UTC = timezone.utc


def job_key(capture_id: str, attempt: int = 0) -> str:
    """One processing job per capture; a user-requested retry gets a new key."""
    return f"capture:{capture_id}:{attempt}"


async def queue(db: AsyncSession, capture: Capture, attempt: int = 0) -> None:
    """Queue the capture for reading. The caller commits."""
    capture.processing_status = "queued"
    await jobs.enqueue(db, PROCESS, capture.user_id, {"capture_id": capture.id},
                       idempotency_key=job_key(capture.id, attempt))


def _store(capture: Capture, result: dict, transcript: str | None) -> None:
    capture.ai_summary = result.get("summary", "")
    capture.ai_topics = json.dumps(result.get("topics", []))
    capture.ai_key_points = json.dumps(result.get("key_points", []))
    capture.ai_actions = json.dumps(result.get("actions", []))
    if transcript:
        capture.transcription = transcript
    capture.processing_status = "processed"
    capture.updated_at = datetime.now(UTC)


async def process_capture(db: AsyncSession, job: Job, payload: dict) -> None:
    capture = await db.get(Capture, payload["capture_id"])
    if capture is None or capture.user_id != job.user_id:
        return  # deleted since it was queued
    capture.processing_status = "processing"
    capture.updated_at = datetime.now(UTC)
    await db.commit()  # the app can show "processing" while the model works
    try:
        await _read(capture)
    except jobs.PermanentJobError:
        raise  # the failure hook marks it failed with the reason
    except Exception:
        # It will be retried: show it as waiting again, not as stuck "processing".
        capture.processing_status = "queued"
        capture.updated_at = datetime.now(UTC)
        await db.commit()
        raise


async def _read(capture: Capture) -> None:
    """Read one capture and store the result on it. Raises to retry, PermanentJobError to give up."""
    if capture.capture_type == "link":
        _store(capture, {"summary": f"Saved link: {capture.content}"}, None)
        return
    if capture.capture_type == "note":
        _store(capture, await asyncio.to_thread(summarise_text, capture.content or ""), None)
        return

    if not capture.storage_key:
        raise jobs.PermanentJobError("The file is missing")
    try:
        kind, mime = media_ai.detect(capture.storage_key, capture.capture_type)
    except media_ai.UnsupportedMedia as exc:
        raise jobs.PermanentJobError(str(exc)) from exc
    try:
        size = await asyncio.to_thread(storage.object_size, capture.storage_key)
    except FileNotFoundError:
        # The upload may still be finishing: retry a few times before giving up.
        raise RuntimeError("the uploaded file has not arrived yet")
    try:
        media_ai.check_size(size)
    except media_ai.UnsupportedMedia as exc:
        raise jobs.PermanentJobError(str(exc)) from exc
    data = await asyncio.to_thread(storage.read_object, capture.storage_key)
    summary, transcript = await asyncio.to_thread(
        media_ai.analyse, data, kind, mime, model=settings.gemini_model_fast,
    )
    _store(capture, summary, transcript)


async def capture_failed(db: AsyncSession, job: Job, payload: dict, error: str) -> None:
    """After the last attempt: mark the capture failed with a reason the user can read."""
    capture = await db.get(Capture, payload["capture_id"])
    if capture is None:
        return
    # A PermanentJobError message is written for people and shown as is. Anything else arrives
    # as "ExceptionName: details" and is summarised instead of leaking internals.
    name, sep, _ = error.partition(": ")
    if sep and name.isidentifier() and name[:1].isupper():
        reason = ("the AI service is not available right now" if name == "AIUnavailable"
                  else "something went wrong while reading it")
    else:
        reason = error.rstrip(".")
    capture.processing_status = "failed"
    capture.ai_summary = f"Could not analyse this capture: {reason}."
    capture.updated_at = datetime.now(UTC)
