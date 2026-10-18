"""
Delivering a reminder when its time comes (spec 4.6). Runs in the worker as the
"reminder.deliver" job handler.

Every attempt is written to notification_deliveries, and what each status proves is kept
precise: "sent" means Firebase accepted the message, not that anyone saw it. A reminder is
never dropped silently: quiet hours, a met condition or a missing push channel are recorded
with the reason.
"""

import asyncio
import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.delivery import NotificationDelivery
from app.models.device import DeviceToken
from app.models.job import Job
from app.models.reminder import Reminder
from app.models.user import User
from app.services import jobs, push, scheduling
from app.services.conditions import should_fire
from app.services.quiet_hours import should_suppress

UTC = timezone.utc
BODY = "Open Personal Memory OS to snooze or complete it."


def _record(db: AsyncSession, reminder_id: str, user_id: str, status: str, fire_at: datetime, *,
            job_id: str, device_id: str | None = None, message_id: str | None = None, error: str | None = None) -> None:
    db.add(NotificationDelivery(
        id=str(uuid.uuid4()), reminder_id=reminder_id, user_id=user_id, channel="push", status=status,
        fire_at=fire_at, message_id=message_id, error=error, job_id=job_id, device_id=device_id,
        created_at=datetime.now(UTC),
    ))


async def _queue_next(db: AsyncSession, reminder: Reminder, fired_at: datetime) -> None:
    """A repeating reminder queues its next occurrence, whatever happened to this one."""
    nxt = scheduling.next_after(reminder.recurrence_rule, reminder.scheduled_at, fired_at, reminder.timezone)
    if nxt is not None:
        await jobs.enqueue(
            db, scheduling.DELIVER, reminder.user_id,
            {"reminder_id": reminder.id, "fire_at": nxt.isoformat()},
            run_at=nxt, idempotency_key=scheduling.job_key(reminder.id, nxt),
        )


async def deliver_reminder(db: AsyncSession, job: Job, payload: dict) -> None:
    fire_at = jobs.as_utc(datetime.fromisoformat(payload["fire_at"]))
    reminder = await db.get(Reminder, payload["reminder_id"])
    if reminder is None or reminder.user_id != job.user_id:
        return  # deleted since it was queued: nothing left to remind about

    def record(status, **kw):
        _record(db, reminder.id, reminder.user_id, status, fire_at, job_id=job.id, **kw)

    if reminder.status != "active":
        record("cancelled", error="the reminder is no longer active")
        return
    if job.attempts <= 1:
        record("triggered")
    await _queue_next(db, reminder, fire_at)

    if reminder.depends_on_id:
        dependency = await db.get(Reminder, reminder.depends_on_id)
        status = dependency.status if dependency is not None and dependency.user_id == reminder.user_id else None
        if not should_fire(status):
            record("cancelled", error="its condition was already met")
            return

    user = await db.get(User, reminder.user_id)
    settings = {}
    if user is not None:
        settings = {"user_tz": user.timezone, "enabled": user.quiet_hours_enabled,
                    "start": user.quiet_hours_start, "end": user.quiet_hours_end}
    if should_suppress(reminder.priority, fire_at, reminder.timezone, **settings):
        record("cancelled", error="quiet hours")
        return

    if not push.is_configured():
        record("skipped", error="push not configured")
        return
    devices = (await db.execute(select(DeviceToken).where(DeviceToken.user_id == reminder.user_id))).scalars().all()
    if not devices:
        record("skipped", error="no device registered")
        return

    # On a retry, phones that already got it are not sent it again.
    already = set((await db.execute(
        select(NotificationDelivery.device_id).where(
            NotificationDelivery.job_id == job.id, NotificationDelivery.status == "sent")
    )).scalars().all())
    failures = 0
    data = {"reminder_id": reminder.id, "fire_at": fire_at.isoformat()}
    for device in devices:
        if device.id in already:
            continue
        try:
            message_id = await asyncio.to_thread(push.send, device.token, reminder.title, BODY, data)
            record("sent", device_id=device.id, message_id=message_id)
        except push.InvalidToken:
            await db.delete(device)  # the app was uninstalled or the token changed
            record("failed", device_id=device.id, error="this phone's push registration expired; it was removed")
        except Exception as exc:
            failures += 1
            record("failed", device_id=device.id, error=f"push failed ({type(exc).__name__})")
    # Keep the history of this attempt even if the job is retried.
    await db.commit()
    if failures:
        raise RuntimeError(f"{failures} phone(s) could not be reached; will retry")
