"""
Event API router — full CRUD with nested deadlines, user-scoped.
"""

import json
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ValidationError, field_validator, model_validator
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.validation import clean_text, one_of, optional_http_url, real_timezone
from app.routers.reminders import _cancel_cloud_layer, _schedule_cloud_layer
from app.services import milestones
from app.auth import get_current_user_id
from app.services.ai_consent import require_ai
from app.database import get_db
from app.models.event import Event, EventDeadline
from app.models.capture import Capture
from app.models.reminder import Reminder
from app.services.event_policy import CADENCE_CHOICES, build_reminder_policy

router = APIRouter()


# ── Pydantic schemas ──────────────────────────────────────────────────────────

class DeadlineIn(BaseModel):
    title: str
    deadline_type: str = "custom"
    deadline_at: datetime

    @field_validator("title")
    @classmethod
    def _title(cls, v):
        return clean_text(v, "Title")

    @field_validator("deadline_type")
    @classmethod
    def _deadline_type(cls, v):
        return milestones.normalize_type(v)[:50]


class EventCreate(BaseModel):
    title: str
    description: Optional[str] = None
    event_type: str = "custom"
    start_at: datetime
    end_at: Optional[datetime] = None
    timezone: str = "UTC"
    location: Optional[str] = None
    is_virtual: bool = False
    event_url: Optional[str] = None
    organizer: Optional[str] = None
    registration_url: Optional[str] = None
    deadlines: list[DeadlineIn] = []

    @field_validator("title")
    @classmethod
    def _title(cls, v):
        return clean_text(v, "Title")

    @field_validator("timezone")
    @classmethod
    def _timezone(cls, v):
        return real_timezone(v)

    @field_validator("event_url", "registration_url")
    @classmethod
    def _links(cls, v):
        return optional_http_url(v, "Link")

    @model_validator(mode="after")
    def _end_not_before_start(self):
        if self.end_at is not None and self.end_at < self.start_at:
            raise ValueError("The event cannot end before it starts")
        return self


class EventUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    start_at: Optional[datetime] = None
    end_at: Optional[datetime] = None
    location: Optional[str] = None
    event_url: Optional[str] = None
    organizer: Optional[str] = None


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("", status_code=status.HTTP_201_CREATED)
async def create_event(
    body: EventCreate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    now = datetime.utcnow()
    event_id = str(uuid.uuid4())

    event = Event(
        id=event_id,
        user_id=user_id,
        title=body.title,
        description=body.description,
        event_type=body.event_type,
        start_at=body.start_at,
        end_at=body.end_at,
        timezone=body.timezone,
        location=body.location,
        is_virtual=body.is_virtual,
        event_url=body.event_url,
        organizer=body.organizer,
        registration_url=body.registration_url,
        created_at=now,
        updated_at=now,
    )
    db.add(event)

    for dl in body.deadlines:
        deadline = EventDeadline(
            id=str(uuid.uuid4()),
            event_id=event_id,
            user_id=user_id,
            title=dl.title,
            deadline_type=dl.deadline_type,
            deadline_at=dl.deadline_at,
            created_at=now,
        )
        db.add(deadline)

    await db.commit()

    # Re-fetch with deadlines loaded
    result = await db.execute(
        select(Event)
        .options(selectinload(Event.deadlines))
        .where(Event.id == event_id)
    )
    event = result.scalar_one()
    return event.to_dict()


@router.get("")
async def list_events(
    event_status: Optional[str] = None,
    event_type: Optional[str] = None,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    query = (
        select(Event)
        .options(selectinload(Event.deadlines))
        .where(Event.user_id == user_id)
    )
    if event_status:
        query = query.where(Event.status == event_status)
    if event_type:
        query = query.where(Event.event_type == event_type)
    query = query.order_by(Event.start_at.desc())
    result = await db.execute(query)
    events = result.scalars().all()

    # Attach live capture counts
    out = []
    for e in events:
        d = e.to_dict()
        counts = await _capture_counts(e.id, user_id, db)
        d.update(counts)
        out.append(d)
    return out


@router.get("/{event_id}")
async def get_event(
    event_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    event = await _get_owned(event_id, user_id, db)
    d = event.to_dict()
    counts = await _capture_counts(event_id, user_id, db)
    d.update(counts)
    return d


@router.patch("/{event_id}")
async def update_event(
    event_id: str,
    body: EventUpdate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    event = await _get_owned(event_id, user_id, db)
    if body.title is not None:
        event.title = body.title
    if body.description is not None:
        event.description = body.description
    if body.status is not None:
        event.status = body.status
    if body.start_at is not None:
        event.start_at = body.start_at
    if body.end_at is not None:
        event.end_at = body.end_at
    if body.location is not None:
        event.location = body.location
    if body.event_url is not None:
        event.event_url = body.event_url
    if body.organizer is not None:
        event.organizer = body.organizer
    event.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(event)
    return event.to_dict()


@router.delete("/{event_id}", status_code=status.HTTP_200_OK)
async def delete_event(
    event_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    event = await _get_owned(event_id, user_id, db)
    await db.delete(event)
    await db.commit()
    return {"deleted": event_id}


@router.post("/{event_id}/deadlines", status_code=status.HTTP_201_CREATED)
async def add_deadline(
    event_id: str,
    body: DeadlineIn,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    await _get_owned(event_id, user_id, db)
    deadline = EventDeadline(
        id=str(uuid.uuid4()),
        event_id=event_id,
        user_id=user_id,
        title=body.title,
        deadline_type=body.deadline_type,
        deadline_at=body.deadline_at,
        created_at=datetime.utcnow(),
    )
    db.add(deadline)
    await db.commit()
    await db.refresh(deadline)
    return deadline.to_dict()


@router.get("/{event_id}/reminder-policy")
async def preview_reminder_policy(
    event_id: str,
    cadence: Optional[str] = None,
    daily_until_registered: bool = False,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Preview the reminder policy for this event. Nothing is created.
    cadence: comma-separated steps such as "7d,3d,1d,morning" (see PolicyChoice)."""
    try:
        choice = PolicyChoice(
            cadence=[c.strip() for c in cadence.split(",") if c.strip()] if cadence else [],
            daily_until_registered=daily_until_registered,
        )
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()[0]["msg"].replace("Value error, ", ""))
    event = await _get_owned(event_id, user_id, db)
    return [
        {**r, "scheduled_at": r["scheduled_at"].isoformat()}
        for r in _policy_for(event, choice)
    ]


class PolicyChoice(BaseModel):
    """The user's cadence for deadline reminders, and whether to be reminded daily until registered."""
    cadence: list[str] = []
    daily_until_registered: bool = False

    @field_validator("cadence")
    @classmethod
    def _cadence(cls, v):
        if len(v) > 10:
            raise ValueError("Choose at most 10 reminder times")
        return [one_of(step, CADENCE_CHOICES, "Reminder time") for step in v]


@router.post("/{event_id}/reminder-policy", status_code=status.HTTP_201_CREATED)
async def apply_reminder_policy(
    event_id: str,
    body: Optional[PolicyChoice] = None,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Create the reminders from the policy the user confirmed, on both alarm layers.
    Applying it again never duplicates a reminder that already exists."""
    event = await _get_owned(event_id, user_id, db)
    now = datetime.utcnow()
    existing = {
        (r.title, _aware(r.scheduled_at), r.milestone_id)
        for r in (await db.execute(
            select(Reminder).where(Reminder.user_id == user_id, Reminder.context_id == event_id,
                                   Reminder.source == "event", Reminder.status == "active")
        )).scalars().all()
        if r.scheduled_at is not None
    }
    created = []
    for spec in _policy_for(event, body or PolicyChoice()):
        if (spec["title"], spec["scheduled_at"], spec.get("milestone_id")) in existing:
            continue
        reminder = Reminder(
            id=str(uuid.uuid4()), user_id=user_id, source="event",
            context_id=event_id, timezone=event.timezone,
            created_at=now, updated_at=now, offsets="[]", **spec,
        )
        db.add(reminder)
        created.append(reminder)
    await db.flush()
    for reminder in created:
        await _schedule_cloud_layer(db, reminder)  # queued with the reminders, in one transaction
    await db.commit()
    return [r.to_dict() for r in created]


class RegistrationStatusIn(BaseModel):
    status: str

    @field_validator("status")
    @classmethod
    def _status(cls, v):
        return one_of(v, milestones.REGISTRATION_STATES, "Registration status")


@router.post("/{event_id}/registration-status")
async def set_registration_status(
    event_id: str,
    body: RegistrationStatusIn,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Track registration. Reaching registered, skipped, not eligible or expired stops the
    registration reminders only; every other milestone's reminders keep running."""
    event = await _get_owned(event_id, user_id, db)
    event.registration_status = body.status
    event.updated_at = datetime.utcnow()
    stopped: list[str] = []
    if milestones.stops_registration_reminders(body.status):
        closed_status = milestones.milestone_status_for(body.status)
        closed_ids = milestones.registration_milestone_ids([d.to_dict() for d in event.deadlines])
        for d in event.deadlines:
            if d.id in closed_ids:
                d.status = closed_status
                d.completed_at = datetime.utcnow()
        stopped = await _stop_reminders(closed_ids, user_id, db)
    await db.commit()
    return {"event": event.to_dict(), "stopped_reminders": stopped}


async def _milestone_action(event_id: str, deadline_id: str, new_status: str, user_id: str, db: AsyncSession):
    event = await _get_owned(event_id, user_id, db)
    deadline = next((d for d in event.deadlines if d.id == deadline_id), None)
    if deadline is None:
        raise HTTPException(status_code=404, detail="Milestone not found")
    deadline.status = new_status
    deadline.completed_at = datetime.utcnow()
    stopped = await _stop_reminders({deadline.id}, user_id, db)
    if milestones.normalize_type(deadline.deadline_type) == milestones.REGISTRATION_TYPE:
        event.registration_status = {"completed": "registered", "skipped": "skipped"}.get(new_status, event.registration_status)
    await db.commit()
    return {"milestone": deadline.to_dict(), "stopped_reminders": stopped}


@router.post("/{event_id}/deadlines/{deadline_id}/complete")
async def complete_milestone(
    event_id: str, deadline_id: str,
    user_id: str = Depends(get_current_user_id), db: AsyncSession = Depends(get_db),
):
    """Mark one milestone done. Only its own reminders stop."""
    return await _milestone_action(event_id, deadline_id, "completed", user_id, db)


@router.post("/{event_id}/deadlines/{deadline_id}/skip")
async def skip_milestone(
    event_id: str, deadline_id: str,
    user_id: str = Depends(get_current_user_id), db: AsyncSession = Depends(get_db),
):
    return await _milestone_action(event_id, deadline_id, "skipped", user_id, db)


async def _stop_reminders(milestone_ids: set[str], user_id: str, db: AsyncSession) -> list[str]:
    """Cancel the active reminders that belong to these milestones, on both layers."""
    if not milestone_ids:
        return []
    rows = (await db.execute(
        select(Reminder).where(
            Reminder.user_id == user_id,
            Reminder.status == "active",
            Reminder.milestone_id.in_(milestone_ids),
        )
    )).scalars().all()
    ids = milestones.reminders_to_stop([r.to_dict() for r in rows], milestone_ids)
    for reminder in rows:
        if reminder.id in ids:
            await _cancel_cloud_layer(db, reminder)  # its pending deliveries are cancelled too
            reminder.status = "cancelled"
            reminder.updated_at = datetime.utcnow()
    return ids


def _aware(dt: datetime) -> datetime:
    from datetime import timezone as tz

    return dt if dt.tzinfo else dt.replace(tzinfo=tz.utc)


def _policy_for(event: Event, choice: "PolicyChoice | None" = None) -> list[dict]:
    from datetime import timezone as tz

    choice = choice or PolicyChoice()
    # Finished milestones (done, skipped, expired) get no reminders.
    deadlines = [
        (d.title, _aware(d.deadline_at), d.id, milestones.normalize_type(d.deadline_type))
        for d in event.deadlines if d.status == milestones.ACTIVE
    ]
    return build_reminder_policy(
        event.title, event.event_type, _aware(event.start_at), deadlines,
        datetime.now(tz.utc),
        cadence=choice.cadence, daily_until_registered=choice.daily_until_registered,
        timezone_name=event.timezone,
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _get_owned(event_id: str, user_id: str, db: AsyncSession) -> Event:
    result = await db.execute(
        select(Event)
        .options(selectinload(Event.deadlines))
        .where(Event.id == event_id, Event.user_id == user_id)
    )
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")
    return event


async def _capture_counts(event_id: str, user_id: str, db: AsyncSession) -> dict:
    result = await db.execute(
        select(Capture.capture_type, func.count(Capture.id))
        .where(Capture.event_id == event_id, Capture.user_id == user_id)
        .group_by(Capture.capture_type)
    )
    rows = result.all()
    counts = {"photo_count": 0, "voice_note_count": 0, "document_count": 0}
    for ctype, cnt in rows:
        if ctype == "photo":
            counts["photo_count"] = cnt
        elif ctype == "voice":
            counts["voice_note_count"] = cnt
        elif ctype == "document":
            counts["document_count"] = cnt
    return counts


# ── Summary generation ────────────────────────────────────────────────────────

@router.post("/{event_id}/generate-summary", status_code=status.HTTP_201_CREATED)
async def generate_event_summary(
    event_id: str,
    user_id: str = Depends(require_ai),
    db: AsyncSession = Depends(get_db),
):
    """
    Generate an AI summary for an event from all its captures.
    Saves result as a MemoryDocument and updates event.summary_id.

    Flow:
      1. Fetch event + all captures for the event
      2. Build captures_text from content/transcription fields
      3. Call the strong Gemini model (summarize_event)
      4. Save MemoryDocument to DB
      5. Update event.summary_id
    """
    from app.services.llm_service import summarize_event
    from app.models.memory import MemoryDocument

    # Verify event ownership
    event = await _get_owned(event_id, user_id, db)

    # Fetch all captures for this event
    captures_result = await db.execute(
        select(Capture)
        .where(Capture.event_id == event_id, Capture.user_id == user_id)
        .order_by(Capture.created_at.asc())
    )
    captures = captures_result.scalars().all()

    # Build text from captures
    lines = []
    for c in captures:
        label = c.capture_type.upper()
        text = c.content or c.transcription
        if text:
            lines.append(f"[{label}] {text}")
        elif c.ai_summary:
            lines.append(f"[{label} AI SUMMARY] {c.ai_summary}")
    captures_text = "\n\n".join(lines)

    # Call Gemini
    summary_data = summarize_event(
        event_title=event.title,
        event_date=event.start_at.date().isoformat(),
        captures_text=captures_text,
    )

    # Build search_vector for keyword search
    topics = summary_data.get("key_topics", [])
    takeaways = summary_data.get("key_takeaways", [])
    search_vector = " ".join(
        filter(None, [
            event.title,
            summary_data.get("overview", ""),
            " ".join(topics),
            " ".join(takeaways[:3]),
        ])
    )

    # Save MemoryDocument
    doc_id = str(uuid.uuid4())
    doc = MemoryDocument(
        id=doc_id,
        user_id=user_id,
        event_id=event_id,
        event_title=event.title,
        overview=summary_data.get("overview"),
        key_topics=json.dumps(summary_data.get("key_topics", [])),
        key_takeaways=json.dumps(summary_data.get("key_takeaways", [])),
        things_learned=json.dumps(summary_data.get("things_learned", [])),
        important_people=json.dumps(summary_data.get("important_people", [])),
        resources=json.dumps(summary_data.get("resources", [])),
        links=json.dumps(summary_data.get("links", [])),
        decisions=json.dumps(summary_data.get("decisions", [])),
        action_items=json.dumps(summary_data.get("action_items", [])),
        search_vector=search_vector,
        event_date=event.start_at,
    )
    db.add(doc)

    # Link summary to event
    event.summary_id = doc_id
    event.updated_at = datetime.utcnow()

    await db.commit()
    await db.refresh(doc)
    return doc.to_dict()


@router.get("/{event_id}/summary")
async def get_event_summary(
    event_id: str,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve the existing AI summary for an event."""
    from app.models.memory import MemoryDocument

    result = await db.execute(
        select(MemoryDocument).where(
            MemoryDocument.event_id == event_id,
            MemoryDocument.user_id == user_id,
        )
    )
    doc = result.scalar_one_or_none()
    if not doc:
        raise HTTPException(
            status_code=404,
            detail="No summary found. Call POST /events/{id}/generate-summary first.",
        )
    return doc.to_dict()
