import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

# R1.7 lifecycle: scheduled -> triggered -> sent -> delivered | failed
# "skipped": nothing was sent because there is no push channel (not configured, or no device).
DELIVERY_STATUSES = ("scheduled", "triggered", "sent", "delivered", "failed", "retrying", "cancelled", "skipped")


class NotificationDelivery(Base):
    """One row per notification delivery attempt (spec R7.4)."""
    __tablename__ = "notification_deliveries"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    reminder_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    channel: Mapped[str] = mapped_column(String(20), default="push")  # push | local
    status: Mapped[str] = mapped_column(String(20), default="triggered")
    fire_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    message_id: Mapped[str | None] = mapped_column(String(255))
    error: Mapped[str | None] = mapped_column(Text)
    job_id: Mapped[str | None] = mapped_column(String(36), index=True)      # the delivery job it came from
    device_id: Mapped[str | None] = mapped_column(String(255))             # the phone it went to (column from 001)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "reminder_id": self.reminder_id,
            "user_id": self.user_id,
            "channel": self.channel,
            "status": self.status,
            "fire_at": self.fire_at.isoformat() if self.fire_at else None,
            "message_id": self.message_id,
            "error": self.error,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
