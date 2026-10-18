"""
The background job queue, kept in Postgres (spec section 9). No Airflow, no cloud queue.

* enqueue()  adds work to the caller's session; one idempotency key = one job, ever.
* cancel()   stops pending work, e.g. every future delivery of a reminder.
* run_once() claims due jobs (FOR UPDATE SKIP LOCKED, so two workers never take the same job),
             runs them, and retries failures with growing delays up to a limit.

Jobs left "running" by a worker that died are picked up again after STALE_AFTER, so a
restart never loses work.
"""

import asyncio
import json
import logging
import os
import socket
import uuid
from datetime import datetime, timedelta, timezone
from typing import Awaitable, Callable

from sqlalchemy import or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.job import Job

logger = logging.getLogger(__name__)
UTC = timezone.utc
STALE_AFTER = timedelta(minutes=10)
MAX_BACKOFF = timedelta(hours=1)

Handler = Callable[[AsyncSession, Job, dict], Awaitable[None]]
FailureHandler = Callable[[AsyncSession, Job, dict, str], Awaitable[None]]


class PermanentJobError(Exception):
    """Retrying cannot help (for example an unsupported file). The job fails at once.
    The message may be shown to the user, so keep it plain and free of internals."""


def as_utc(value: datetime) -> datetime:
    """Databases may return naive datetimes; everything here is stored in UTC."""
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def now_utc() -> datetime:
    return datetime.now(UTC)


def backoff(attempts: int) -> timedelta:
    """30 s, 1 min, 2 min, 4 min ... capped at an hour."""
    exponent = min(max(attempts - 1, 0), 12)  # 30 s * 2^12 is already far past the cap; avoids overflow
    return min(timedelta(seconds=30 * 2 ** exponent), MAX_BACKOFF)


def worker_name() -> str:
    return f"{socket.gethostname()}:{os.getpid()}"[:100]


async def enqueue(
    db: AsyncSession,
    kind: str,
    user_id: str,
    payload: dict,
    *,
    run_at: datetime | None = None,
    idempotency_key: str | None = None,
    max_attempts: int = 5,
) -> Job | None:
    """Add a job to the session; the caller commits. Returns None when the same work is already
    queued or done. Cancelled work with the same key is re-armed instead of duplicated."""
    now = now_utc()
    when = as_utc(run_at) if run_at else now
    if idempotency_key:
        existing = (await db.execute(select(Job).where(Job.idempotency_key == idempotency_key))).scalar_one_or_none()
        if existing is not None:
            if existing.status != "cancelled":
                return None
            existing.status, existing.run_at, existing.attempts = "pending", when, 0
            existing.payload, existing.last_error, existing.updated_at = json.dumps(payload), None, now
            return existing
    job = Job(
        id=str(uuid.uuid4()), kind=kind, user_id=user_id, payload=json.dumps(payload),
        status="pending", run_at=when, attempts=0, max_attempts=max_attempts,
        idempotency_key=idempotency_key, created_at=now, updated_at=now,
    )
    db.add(job)
    return job


async def cancel(db: AsyncSession, *, user_id: str, key_prefix: str) -> int:
    """Cancel this user's pending jobs whose key starts with key_prefix. Running jobs finish."""
    result = await db.execute(
        update(Job)
        .where(Job.user_id == user_id, Job.status == "pending", Job.idempotency_key.like(f"{key_prefix}%"))
        .values(status="cancelled", updated_at=now_utc())
    )
    return result.rowcount or 0


async def claim(session_factory, *, now: datetime, limit: int, worker_id: str) -> list[str]:
    """Take up to `limit` due jobs for this worker, marking them running."""
    async with session_factory() as db:
        rows = (await db.execute(
            select(Job)
            .where(or_(
                (Job.status == "pending") & (Job.run_at <= now),
                (Job.status == "running") & (Job.locked_at < now - STALE_AFTER),  # a worker died mid-job
            ))
            .order_by(Job.run_at)
            .limit(limit)
            .with_for_update(skip_locked=True)
        )).scalars().all()
        for job in rows:
            job.status, job.locked_at, job.locked_by = "running", now, worker_id
            job.attempts += 1
            job.updated_at = now
        await db.commit()
        return [job.id for job in rows]


async def run_job(
    session_factory,
    job_id: str,
    handlers: dict[str, Handler],
    *,
    now: datetime,
    on_failure: dict[str, FailureHandler] | None = None,
) -> str:
    """Run one claimed job. Returns its new status."""
    async with session_factory() as db:
        job = await db.get(Job, job_id)
        if job is None or job.status != "running":
            return job.status if job else "missing"
        payload = json.loads(job.payload or "{}")
        handler = handlers.get(job.kind)
        error: str | None = None
        final = False
        try:
            if handler is None:
                raise PermanentJobError(f"No handler for job kind {job.kind}")
            await handler(db, job, payload)
            job.status, job.last_error = "done", None
        except PermanentJobError as exc:
            error, final = str(exc), True
        except Exception as exc:  # anything else may be temporary: retry later
            logger.exception("Job %s (%s) failed on attempt %s", job_id, job.kind, job.attempts)
            error = f"{type(exc).__name__}: {exc}"
            final = job.attempts >= job.max_attempts
        if error is not None:
            await db.rollback()  # throw away the handler's half-done changes
            job = await db.get(Job, job_id)
            job.last_error = error[:1000]
            if final:
                job.status = "failed"
                hook = (on_failure or {}).get(job.kind)
                if hook is not None:
                    try:
                        await hook(db, job, payload, error)
                    except Exception:
                        logger.exception("Failure handler for job %s failed", job_id)
            else:
                job.status, job.run_at = "pending", now + backoff(job.attempts)
        job.locked_at, job.locked_by, job.updated_at = None, None, now
        await db.commit()
        return job.status


async def run_once(
    session_factory,
    handlers: dict[str, Handler],
    *,
    now: datetime | None = None,
    limit: int = 10,
    worker_id: str | None = None,
    on_failure: dict[str, FailureHandler] | None = None,
) -> int:
    """Claim and run the jobs that are due now. Returns how many ran."""
    now = now or now_utc()
    ids = await claim(session_factory, now=now, limit=limit, worker_id=worker_id or worker_name())
    for job_id in ids:
        await run_job(session_factory, job_id, handlers, now=now, on_failure=on_failure)
    return len(ids)


async def run_forever(
    session_factory,
    handlers: dict[str, Handler],
    *,
    poll_seconds: float = 2.0,
    on_failure: dict[str, FailureHandler] | None = None,
    stop: asyncio.Event | None = None,
) -> None:
    """The worker loop: run what is due, sleep briefly when there is nothing to do."""
    worker_id = worker_name()
    logger.info("Worker %s started", worker_id)
    while not (stop and stop.is_set()):
        try:
            ran = await run_once(session_factory, handlers, worker_id=worker_id, on_failure=on_failure)
        except Exception:
            logger.exception("Worker loop error; retrying shortly")
            ran = 0
        if ran == 0:
            await asyncio.sleep(poll_seconds)
