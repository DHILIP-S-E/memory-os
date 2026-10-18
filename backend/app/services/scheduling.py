"""
Reminder scheduling (spec 4.5 and 9).

Pure functions decide *when* a reminder fires; each fire time becomes one "reminder.deliver"
job in the Postgres queue, keyed so it can never be queued twice. The worker delivers it at
that time, even with every app and browser closed. The LLM never schedules anything.

A repeating reminder queues only its next occurrence; delivering it queues the one after.
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.services import jobs
from app.services.recurrence import is_supported, next_occurrence
from app.services.reminder_parser import offset_to_minutes

DELIVER = "reminder.deliver"
UTC = timezone.utc


def _utc(dt: datetime) -> datetime:
    return dt.replace(tzinfo=UTC) if dt.tzinfo is None else dt.astimezone(UTC)


def fire_instants(scheduled_at: datetime, offsets: list[str]) -> set[datetime]:
    """scheduled_at itself plus each valid offset before it (UTC, unfiltered)."""
    target = _utc(scheduled_at)
    instants = {target}
    for offset in offsets:
        minutes = offset_to_minutes(offset)
        if minutes:
            instants.add(target - timedelta(minutes=minutes))
    return instants


def compute_fire_times(scheduled_at: datetime, offsets: list[str], now: datetime | None = None) -> list[datetime]:
    """Strictly-future fire instants, sorted ascending and unique."""
    now = _utc(now or datetime.now(UTC))
    return sorted(t for t in fire_instants(scheduled_at, offsets) if t > now)


def key_prefix(reminder_id: str) -> str:
    return f"reminder:{reminder_id}:"


def job_key(reminder_id: str, fire_at: datetime) -> str:
    """One delivery per reminder per fire time, whatever happens."""
    return f"{key_prefix(reminder_id)}{int(_utc(fire_at).timestamp())}"


def delivery_times(
    scheduled_at: datetime | None,
    offsets: list[str],
    recurrence_rule: str | None,
    timezone_name: str | None,
    now: datetime,
) -> list[datetime]:
    """When to deliver: the next occurrence of a repeating reminder, or the future fire times
    (the time itself and each offset before it) of a one-off reminder."""
    if scheduled_at is None:
        return []
    now = _utc(now)
    if recurrence_rule and is_supported(recurrence_rule):
        nxt = next_occurrence(recurrence_rule, _utc(scheduled_at), now - timedelta(microseconds=1), timezone_name)
        return [nxt] if nxt else []
    return compute_fire_times(scheduled_at, offsets, now)


async def schedule_reminder(db: AsyncSession, reminder, now: datetime | None = None) -> int:
    """Queue the deliveries for an active reminder. The caller commits. Returns how many."""
    import json

    if reminder.status != "active":
        return 0
    offsets = json.loads(reminder.offsets or "[]") if isinstance(reminder.offsets, str) else list(reminder.offsets or [])
    queued = 0
    for fire_at in delivery_times(reminder.scheduled_at, offsets, reminder.recurrence_rule,
                                  reminder.timezone, now or datetime.now(UTC)):
        job = await jobs.enqueue(
            db, DELIVER, reminder.user_id,
            {"reminder_id": reminder.id, "fire_at": fire_at.isoformat()},
            run_at=fire_at, idempotency_key=job_key(reminder.id, fire_at),
        )
        queued += job is not None
    return queued


async def cancel_reminder(db: AsyncSession, reminder) -> int:
    """Cancel every pending delivery of a reminder. The caller commits."""
    return await jobs.cancel(db, user_id=reminder.user_id, key_prefix=key_prefix(reminder.id))


def next_after(recurrence_rule: str | None, scheduled_at: datetime, fired_at: datetime, timezone_name: str | None) -> datetime | None:
    """For a repeating reminder that just fired: when it fires next (None when the rule has ended)."""
    if not recurrence_rule or not is_supported(recurrence_rule):
        return None
    return next_occurrence(recurrence_rule, _utc(scheduled_at), _utc(fired_at), timezone_name)
