import uuid
from datetime import datetime
from sqlalchemy import Boolean, DateTime, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class User(Base):
    """An account for the app's own email/password login."""
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    email: Mapped[str] = mapped_column(String(320), nullable=False, unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(100), nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(200))
    # Google's stable account id, set when the user signs in with Google. Accounts made only with
    # Google have an empty password_hash, which can never match a password.
    google_sub: Mapped[str | None] = mapped_column(String(255), unique=True)
    # Settings (spec 4.11). Quiet hours are hours of the day in `timezone`; null start/end = 10 PM to 7 AM.
    timezone: Mapped[str] = mapped_column(String(100), nullable=False, default="UTC")
    quiet_hours_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    quiet_hours_start: Mapped[int | None] = mapped_column(SmallInteger)
    quiet_hours_end: Mapped[int | None] = mapped_column(SmallInteger)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    def to_public(self) -> dict:
        """What the API may return. Never includes the password hash."""
        return {"id": self.id, "email": self.email, "display_name": self.display_name}

    def to_settings(self) -> dict:
        from app.services.quiet_hours import DEFAULT_END, DEFAULT_START
        return {
            "timezone": self.timezone,
            "quiet_hours_enabled": self.quiet_hours_enabled,
            "quiet_hours_start": DEFAULT_START if self.quiet_hours_start is None else self.quiet_hours_start,
            "quiet_hours_end": DEFAULT_END if self.quiet_hours_end is None else self.quiet_hours_end,
        }
