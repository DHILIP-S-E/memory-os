"""
Capture API router.

Upload flow:
  1. Flutter  →  POST /captures/upload-url  →  gets {upload_url, capture_id, s3_key}
  2. Flutter  →  PUT  <upload_url>          →  uploads the file directly to R2
  3. Flutter  →  POST /captures             →  registers capture in DB
  4. Flutter  →  GET  /captures/{id}/download-url  →  gets pre-signed GET URL

Text notes and links skip file storage entirely (content stored in DB).
"""

import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from pydantic import BaseModel, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.capture import Capture
from app import validation as v
from app.services.capture_ai import process_text_capture
from app.services.capture_queue import enqueue_text_capture
from app.services.storage import (
    StorageUnavailable,
    generate_upload_url,
    generate_download_url,
    delete_object,
)

router = APIRouter()

# Storage key pattern:  users/{user_id}/events/{event_id}/{type}/{capture_id}.{ext}
#                  users/{user_id}/misc/{type}/{capture_id}.{ext}
_S3_KEY_TEMPLATE = "users/{user_id}/{event_part}{capture_type}/{capture_id}.{ext}"


# ── Pydantic schemas ──────────────────────────────────────────────────────────

FILE_TYPES = {"photo", "voice", "document", "video"}


class UploadUrlRequest(BaseModel):
    capture_type: str          # photo | voice | document | video
    file_extension: str        # jpg | m4a | pdf | mp4
    content_type: str          # image/jpeg | audio/m4a | application/pdf
    event_id: Optional[str] = None

    @field_validator("capture_type")
    @classmethod
    def _type(cls, x):
        return v.one_of(x, FILE_TYPES, "Capture type")

    @field_validator("file_extension")
    @classmethod
    def _ext(cls, x):
        return v.file_extension(x)

    @field_validator("content_type")
    @classmethod
    def _ctype(cls, x):
        return v.content_type(x)

    @field_validator("event_id")
    @classmethod
    def _event(cls, x):
        return None if x in (None, "") else v.safe_id(x, "Event id")


class RegisterCaptureRequest(BaseModel):
    capture_id: str
    storage_key: str
    capture_type: str
    event_id: Optional[str] = None
    mime_type: Optional[str] = None
    duration: Optional[int] = None   # seconds, for audio/video

    @field_validator("capture_id")
    @classmethod
    def _id(cls, x):
        return v.safe_id(x, "Capture id")

    @field_validator("capture_type")
    @classmethod
    def _type(cls, x):
        return v.one_of(x, FILE_TYPES, "Capture type")

    @field_validator("event_id")
    @classmethod
    def _event(cls, x):
        return None if x in (None, "") else v.safe_id(x, "Event id")


MAX_NOTE = 50_000


class TextNoteRequest(BaseModel):
    content: str
    event_id: Optional[str] = None

    @field_validator("content")
    @classmethod
    def _content(cls, x):
        return v.clean_text(x, "Note", max_len=MAX_NOTE)

    @field_validator("event_id")
    @classmethod
    def _event(cls, x):
        return None if x in (None, "") else v.safe_id(x, "Event id")


class LinkRequest(BaseModel):
    url: str
    event_id: Optional[str] = None

    @field_validator("url")
    @classmethod
    def _url(cls, x):
        return v.http_url(x, "Link")

    @field_validator("event_id")
    @classmethod
    def _event(cls, x):
        return None if x in (None, "") else v.safe_id(x, "Event id")


class CaptureUpdateRequest(BaseModel):
    processing_status: Optional[str] = None
    transcription: Optional[str] = None
    ai_summary: Optional[str] = None
    ai_topics: Optional[str] = None      # JSON string
    ai_key_points: Optional[str] = None  # JSON string
    ai_actions: Optional[str] = None     # JSON string


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/upload-url")
async def get_upload_url(
    body: UploadUrlRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Step 1 — get a short-lived signed PUT URL for direct upload to R2."""
    capture_id = str(uuid.uuid4())
    event_part = f"events/{body.event_id}/" if body.event_id else "misc/"
    s3_key = _S3_KEY_TEMPLATE.format(
        user_id=user_id,
        event_part=event_part,
        capture_type=body.capture_type,
        capture_id=capture_id,
        ext=body.file_extension,
    )
    try:
        upload_url = generate_upload_url(s3_key, body.content_type)
    except StorageUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    return {
        "upload_url": upload_url,
        "capture_id": capture_id,
        "s3_key": s3_key,
        "expires_in": 15 * 60,
    }


@router.post("", status_code=status.HTTP_201_CREATED)
async def register_capture(
    body: RegisterCaptureRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Step 3 — register capture in DB after a successful upload."""
    if not v.owns_storage_key(body.storage_key, user_id):
        # Otherwise a user could register someone else's file and then download or delete it.
        raise HTTPException(status_code=422, detail="storage_key does not belong to you")
    now = datetime.utcnow()
    capture = Capture(
        id=body.capture_id,
        user_id=user_id,
        event_id=body.event_id,
        capture_type=body.capture_type,
        storage_key=body.storage_key,
        mime_type=body.mime_type,
        duration=body.duration,
        processing_status="queued",
        created_at=now,
        updated_at=now,
    )
    db.add(capture)
    await db.commit()
    await db.refresh(capture)
    return capture.to_dict()


@router.post("/note", status_code=status.HTTP_201_CREATED)
async def create_text_note(
    body: TextNoteRequest,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Create a text note — no file upload needed."""
    now = datetime.utcnow()
    capture = Capture(
        id=str(uuid.uuid4()),
        user_id=user_id,
        event_id=body.event_id,
        capture_type="note",
        content=body.content,
        processing_status="queued",
        created_at=now,
        updated_at=now,
    )
    db.add(capture)
    await db.commit()
    await db.refresh(capture)
    # With the queue pipeline the worker processes it; without one (lean deployment),
    # or if queueing fails, process it here in the background so it never sticks at 'queued'.
    if not enqueue_text_capture(capture.id):
        background_tasks.add_task(process_text_capture, capture.id)
    return capture.to_dict()


@router.post("/link", status_code=status.HTTP_201_CREATED)
async def save_link(
    body: LinkRequest,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Save a URL — no file upload needed."""
    now = datetime.utcnow()
    capture = Capture(
        id=str(uuid.uuid4()),
        user_id=user_id,
        event_id=body.event_id,
        capture_type="link",
        content=body.url,
        processing_status="queued",
        created_at=now,
        updated_at=now,
    )
    db.add(capture)
    await db.commit()
    await db.refresh(capture)
    # With the queue pipeline the worker processes it; without one (lean deployment),
    # or if queueing fails, process it here in the background so it never sticks at 'queued'.
    if not enqueue_text_capture(capture.id):
        background_tasks.add_task(process_text_capture, capture.id)
    return capture.to_dict()


@router.get("")
async def list_captures(
    event_id: Optional[str] = None,
    capture_type: Optional[str] = None,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    query = select(Capture).where(Capture.user_id == user_id)
    if event_id:
        query = query.where(Capture.event_id == event_id)
    if capture_type:
        query = query.where(Capture.capture_type == capture_type)
    query = query.order_by(Capture.created_at.desc())
    result = await db.execute(query)
    return [c.to_dict() for c in result.scalars().all()]


@router.get("/{capture_id}")
async def get_capture(
    capture_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    capture = await _get_owned(capture_id, user_id, db)
    return capture.to_dict()


@router.get("/{capture_id}/download-url")
async def get_download_url(
    capture_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Return a short-lived signed GET URL for the capture's file."""
    capture = await _get_owned(capture_id, user_id, db)
    if not capture.storage_key:
        raise HTTPException(
            status_code=404,
            detail="This capture has no associated file",
        )
    if not v.owns_storage_key(capture.storage_key, user_id):
        raise HTTPException(status_code=404, detail="This capture has no associated file")
    try:
        url = generate_download_url(capture.storage_key)
    except StorageUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    return {"download_url": url, "expires_in": 5 * 60}


@router.patch("/{capture_id}")
async def update_capture(
    capture_id: str,
    body: CaptureUpdateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Update processing status and AI result fields (called by backend workers)."""
    capture = await _get_owned(capture_id, user_id, db)
    if body.processing_status is not None:
        capture.processing_status = body.processing_status
    if body.transcription is not None:
        capture.transcription = body.transcription
    if body.ai_summary is not None:
        capture.ai_summary = body.ai_summary
    if body.ai_topics is not None:
        capture.ai_topics = body.ai_topics
    if body.ai_key_points is not None:
        capture.ai_key_points = body.ai_key_points
    if body.ai_actions is not None:
        capture.ai_actions = body.ai_actions
    capture.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(capture)
    return capture.to_dict()


@router.delete("/{capture_id}", status_code=status.HTTP_200_OK)
async def delete_capture(
    capture_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    capture = await _get_owned(capture_id, user_id, db)
    # Remove the stored file if there is one
    if capture.storage_key and v.owns_storage_key(capture.storage_key, user_id):
        delete_object(capture.storage_key)
    await db.delete(capture)
    await db.commit()
    return {"deleted": capture_id}


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _get_owned(capture_id: str, user_id: str, db: AsyncSession) -> Capture:
    result = await db.execute(
        select(Capture).where(
            Capture.id == capture_id, Capture.user_id == user_id
        )
    )
    capture = result.scalar_one_or_none()
    if not capture:
        raise HTTPException(status_code=404, detail="Capture not found")
    return capture
