"""
Phones that can receive push notifications (Firebase Cloud Messaging tokens).

The app registers its token after sign-in and removes it on sign-out. A token belongs to
one account at a time: if the phone signs in to another account, the token moves with it,
so nobody receives someone else's reminders.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel, field_validator
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.device import DeviceToken
from app.validation import clean_text, one_of

router = APIRouter()
PLATFORMS = {"android", "ios", "web", "fcm", "apns"}


class DeviceIn(BaseModel):
    token: str
    platform: str = "android"

    @field_validator("token")
    @classmethod
    def _token(cls, v):
        return clean_text(v, "Device token", max_len=4096)

    @field_validator("platform")
    @classmethod
    def _platform(cls, v):
        return one_of(v.lower(), PLATFORMS, "Platform")


@router.post("")
async def register_device(
    body: DeviceIn,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    now = datetime.now(timezone.utc)
    device = (await db.execute(select(DeviceToken).where(DeviceToken.token == body.token))).scalar_one_or_none()
    if device is None:
        db.add(DeviceToken(user_id=user_id, token=body.token, platform=body.platform, created_at=now, last_seen_at=now))
    else:
        device.user_id, device.platform, device.last_seen_at = user_id, body.platform, now
    await db.commit()
    return {"registered": True}


class DeviceOut(BaseModel):
    token: str


@router.post("/unregister")
async def unregister_device(
    body: DeviceOut,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Called on sign-out so this phone stops getting the account's reminders."""
    result = await db.execute(delete(DeviceToken).where(DeviceToken.token == body.token, DeviceToken.user_id == user_id))
    await db.commit()
    return {"removed": bool(result.rowcount)}
