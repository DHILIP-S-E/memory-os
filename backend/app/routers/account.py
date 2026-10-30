"""
Account data rights (spec R5.7, R5.8): export everything, delete everything.
Deletion cascades S3 objects, DB rows, and pending cloud reminder schedules.
"""

import logging

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.capture import Capture
from app.models.delivery import NotificationDelivery
from app.models.device import DeviceToken
from app.models.job import Job
from app.models.event import Event, EventDeadline
from app.models.memory import MemoryDocument
from app.models.reminder import Reminder
from app.models.user import User
from app.services.storage import delete_object
from app.validation import real_timezone

router = APIRouter()
logger = logging.getLogger(__name__)


class SettingsIn(BaseModel):
    """Only the fields sent are changed."""
    timezone: Optional[str] = None
    quiet_hours_enabled: Optional[bool] = None
    quiet_hours_start: Optional[int] = Field(None, ge=0, le=23)
    quiet_hours_end: Optional[int] = Field(None, ge=0, le=23)
    ai_enabled: Optional[bool] = None

    @field_validator("timezone")
    @classmethod
    def _timezone(cls, v):
        return None if v is None else real_timezone(v)


async def _get_user(user_id: str, db: AsyncSession) -> User:
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="Account not found")
    return user


@router.get("/settings")
async def get_settings(user_id: str = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    """Timezone and quiet hours. The cloud dispatcher reads these when a reminder fires."""
    return (await _get_user(user_id, db)).to_settings()


@router.put("/settings")
async def update_settings(
    body: SettingsIn,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    user = await _get_user(user_id, db)
    if body.timezone is not None:
        user.timezone = body.timezone
    if body.quiet_hours_enabled is not None:
        user.quiet_hours_enabled = body.quiet_hours_enabled
    if body.quiet_hours_start is not None:
        user.quiet_hours_start = body.quiet_hours_start
    if body.quiet_hours_end is not None:
        user.quiet_hours_end = body.quiet_hours_end
    if body.ai_enabled is not None:
        user.ai_enabled = body.ai_enabled
    if user.quiet_hours_start is not None and user.quiet_hours_start == user.quiet_hours_end:
        raise HTTPException(status_code=422, detail="Quiet hours need different start and end hours")
    await db.commit()
    return user.to_settings()


@router.get("/export")
async def export_account(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Return all of the user's data as one JSON document."""

    async def rows(model, *options):
        result = await db.execute(select(model).options(*options).where(model.user_id == user_id))
        return [r.to_dict() for r in result.scalars().all()]

    return {
        "user_id": user_id,
        "reminders": await rows(Reminder),
        # Event.to_dict() reads deadlines; load them up front (no lazy IO in async code).
        "events": await rows(Event, selectinload(Event.deadlines)),
        "event_deadlines": await rows(EventDeadline),
        "captures": await rows(Capture),
        "memory_documents": await rows(MemoryDocument),
        "notification_deliveries": await rows(NotificationDelivery),
    }


@router.delete("")
async def delete_account(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete all user data: stored files, queued deliveries, devices and every row."""
    reminders = (
        await db.execute(select(Reminder).where(Reminder.user_id == user_id))
    ).scalars().all()

    captures = (
        await db.execute(select(Capture).where(Capture.user_id == user_id))
    ).scalars().all()
    for c in captures:
        if c.storage_key:
            delete_object(c.storage_key)

    for model in (Job, DeviceToken, NotificationDelivery, MemoryDocument, Capture, EventDeadline, Reminder, Event):
        await db.execute(delete(model).where(model.user_id == user_id))
    # Last: the login itself, so the user cannot sign back into an emptied account.
    await db.execute(delete(User).where(User.id == user_id))
    await db.commit()
    return {"deleted": True, "reminders": len(reminders), "captures": len(captures)}
