"""
Consent before content goes to the AI (spec 11).

Every route that sends the user's own text, files or memory to Gemini checks this first.
With AI reading off, captures are still saved; they are simply not read.
"""

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.models.user import User

TURNED_OFF = "AI reading is turned off for your account. Turn it on in Settings to use this."


async def ai_allowed(db: AsyncSession, user_id: str) -> bool:
    """True when the user agreed to AI reading. An unknown user id (e.g. local dev auth) is not."""
    enabled = (await db.execute(select(User.ai_enabled).where(User.id == user_id))).scalar_one_or_none()
    return bool(enabled)


async def require_ai(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> str:
    """Route dependency: refuse with a plain 403 unless the user turned AI reading on."""
    if not await ai_allowed(db, user_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=TURNED_OFF)
    return user_id
