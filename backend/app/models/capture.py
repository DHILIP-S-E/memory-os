import uuid
from datetime import datetime
from sqlalchemy import String, DateTime, Text, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class Capture(Base):
    __tablename__ = "captures"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    user_id: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    event_id: Mapped[str | None] = mapped_column(String(36), index=True)
    capture_type: Mapped[str] = mapped_column(String(20), nullable=False)  # photo, voice, note, document, link
    storage_key: Mapped[str | None] = mapped_column(String(1000))          # R2 object key
    mime_type: Mapped[str | None] = mapped_column(String(100))
    duration: Mapped[int | None] = mapped_column(Integer)                  # seconds for audio/video
    transcription: Mapped[str | None] = mapped_column(Text)
    content: Mapped[str | None] = mapped_column(Text)                      # text notes, URLs
    processing_status: Mapped[str] = mapped_column(String(20), default="uploaded")
    ai_summary: Mapped[str | None] = mapped_column(Text)
    ai_topics: Mapped[str | None] = mapped_column(Text)      # JSON array
    ai_key_points: Mapped[str | None] = mapped_column(Text)  # JSON array
    ai_actions: Mapped[str | None] = mapped_column(Text)     # JSON array
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    def to_dict(self) -> dict:
        import json
        return {
            "id": self.id,
            "user_id": self.user_id,
            "event_id": self.event_id,
            "capture_type": self.capture_type,
            "storage_key": self.storage_key,
            "mime_type": self.mime_type,
            "duration": self.duration,
            "transcription": self.transcription,
            "content": self.content,
            "processing_status": self.processing_status,
            "ai_result": {
                "summary": self.ai_summary,
                "topics": json.loads(self.ai_topics) if self.ai_topics else [],
                "key_points": json.loads(self.ai_key_points) if self.ai_key_points else [],
                "actions": json.loads(self.ai_actions) if self.ai_actions else [],
            } if self.ai_summary else None,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }
