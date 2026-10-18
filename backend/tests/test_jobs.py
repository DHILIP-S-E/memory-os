"""The Postgres job queue: idempotency, claiming, retries, recovery and cancellation."""

import asyncio
import json
from datetime import datetime, timedelta, timezone

import pytest
from hypothesis import given, strategies as st
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.database import Base
from app.models.job import Job
from app.services import jobs

UTC = timezone.utc
T0 = datetime(2026, 10, 18, 9, 0, tzinfo=UTC)


@pytest.fixture
def Session():
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})

    async def setup():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(setup())
    return async_sessionmaker(engine, expire_on_commit=False)


def run(coro):
    return asyncio.run(coro)


async def add(Session, kind="test.ok", key=None, run_at=T0, payload=None, max_attempts=5):
    async with Session() as db:
        job = await jobs.enqueue(db, kind, "u1", payload or {"n": 1}, run_at=run_at, idempotency_key=key, max_attempts=max_attempts)
        await db.commit()
        return job.id if job else None


async def get(Session, job_id):
    async with Session() as db:
        return await db.get(Job, job_id)


class Recorder:
    def __init__(self, fail_times=0, error=RuntimeError("temporary")):
        self.calls, self.fail_times, self.error = [], fail_times, error

    async def __call__(self, db, job, payload):
        self.calls.append(payload)
        if len(self.calls) <= self.fail_times:
            raise self.error


def test_the_same_key_is_queued_once(Session):
    first = run(add(Session, key="reminder:r1:2026-10-18T09:00"))
    second = run(add(Session, key="reminder:r1:2026-10-18T09:00"))
    assert first is not None and second is None


def test_cancelled_work_with_the_same_key_is_re_armed_not_duplicated(Session):
    job_id = run(add(Session, key="reminder:r1:t"))

    async def cancel():
        async with Session() as db:
            n = await jobs.cancel(db, user_id="u1", key_prefix="reminder:r1:")
            await db.commit()
            return n

    assert run(cancel()) == 1
    assert run(get(Session, job_id)).status == "cancelled"
    again = run(add(Session, key="reminder:r1:t"))
    assert again == job_id and run(get(Session, job_id)).status == "pending"


def test_only_due_jobs_run(Session):
    due = run(add(Session, run_at=T0))
    later = run(add(Session, run_at=T0 + timedelta(hours=1)))
    rec = Recorder()
    assert run(jobs.run_once(Session, {"test.ok": rec}, now=T0)) == 1
    assert run(get(Session, due)).status == "done"
    assert run(get(Session, later)).status == "pending"


def test_a_failure_is_retried_later_with_a_growing_delay(Session):
    job_id = run(add(Session))
    rec = Recorder(fail_times=2)
    run(jobs.run_once(Session, {"test.ok": rec}, now=T0))
    job = run(get(Session, job_id))
    assert job.status == "pending" and job.attempts == 1 and "temporary" in job.last_error
    assert jobs.as_utc(job.run_at) == T0 + timedelta(seconds=30)
    assert run(jobs.run_once(Session, {"test.ok": rec}, now=T0 + timedelta(seconds=10))) == 0, "not before its time"
    run(jobs.run_once(Session, {"test.ok": rec}, now=T0 + timedelta(seconds=30)))
    job = run(get(Session, job_id))
    assert job.attempts == 2 and jobs.as_utc(job.run_at) == T0 + timedelta(seconds=30) + timedelta(minutes=1)
    run(jobs.run_once(Session, {"test.ok": rec}, now=T0 + timedelta(minutes=5)))
    assert run(get(Session, job_id)).status == "done"


def test_after_the_last_attempt_the_job_fails_and_the_failure_hook_runs(Session):
    job_id = run(add(Session, max_attempts=2))
    seen = []

    async def hook(db, job, payload, error):
        seen.append((payload, error))

    rec = Recorder(fail_times=10)
    run(jobs.run_once(Session, {"test.ok": rec}, now=T0, on_failure={"test.ok": hook}))
    run(jobs.run_once(Session, {"test.ok": rec}, now=T0 + timedelta(hours=2), on_failure={"test.ok": hook}))
    job = run(get(Session, job_id))
    assert job.status == "failed" and job.attempts == 2
    assert seen == [({"n": 1}, "RuntimeError: temporary")]


def test_a_permanent_error_fails_at_once_without_retrying(Session):
    job_id = run(add(Session))
    rec = Recorder(fail_times=1, error=jobs.PermanentJobError("Cannot analyse a .exe document"))
    run(jobs.run_once(Session, {"test.ok": rec}, now=T0))
    job = run(get(Session, job_id))
    assert job.status == "failed" and job.attempts == 1 and job.last_error == "Cannot analyse a .exe document"


def test_a_failed_handlers_changes_are_rolled_back(Session):
    job_id = run(add(Session))

    async def half_done(db, job, payload):
        await jobs.enqueue(db, "test.other", "u1", {}, run_at=T0)  # would be a side effect
        raise RuntimeError("boom")

    run(jobs.run_once(Session, {"test.ok": half_done}, now=T0))

    async def count_other():
        async with Session() as db:
            from sqlalchemy import func, select
            return (await db.execute(select(func.count()).select_from(Job).where(Job.kind == "test.other"))).scalar()

    assert run(count_other()) == 0
    assert run(get(Session, job_id)).status == "pending"


def test_an_unknown_kind_fails_instead_of_looping(Session):
    job_id = run(add(Session, kind="test.nobody"))
    run(jobs.run_once(Session, {}, now=T0))
    assert run(get(Session, job_id)).status == "failed"


def test_a_job_left_running_by_a_dead_worker_is_picked_up_again(Session):
    job_id = run(add(Session))

    async def crash_mid_job():
        await jobs.claim(Session, now=T0, limit=10, worker_id="dead-worker")

    run(crash_mid_job())
    rec = Recorder()
    assert run(jobs.run_once(Session, {"test.ok": rec}, now=T0 + timedelta(minutes=5))) == 0, "not stale yet"
    assert run(jobs.run_once(Session, {"test.ok": rec}, now=T0 + timedelta(minutes=11))) == 1
    job = run(get(Session, job_id))
    assert job.status == "done" and job.attempts == 2


def test_a_claimed_job_is_not_claimed_twice(Session):
    run(add(Session))

    async def two_claims():
        a = await jobs.claim(Session, now=T0, limit=10, worker_id="w1")
        b = await jobs.claim(Session, now=T0, limit=10, worker_id="w2")
        return a, b

    a, b = run(two_claims())
    assert len(a) == 1 and b == []


def test_cancel_touches_only_that_users_pending_jobs_with_the_prefix(Session):
    keep_other_reminder = run(add(Session, key="reminder:r2:t"))
    target = run(add(Session, key="reminder:r1:t"))

    async def other_user():
        async with Session() as db:
            job = await jobs.enqueue(db, "test.ok", "u2", {}, run_at=T0, idempotency_key="reminder:r1:u2")
            await db.commit()
            return job.id

    theirs = run(other_user())

    async def cancel():
        async with Session() as db:
            await jobs.cancel(db, user_id="u1", key_prefix="reminder:r1:")
            await db.commit()

    run(cancel())
    assert run(get(Session, target)).status == "cancelled"
    assert run(get(Session, keep_other_reminder)).status == "pending"
    assert run(get(Session, theirs)).status == "pending"


@given(st.integers(min_value=1, max_value=50))
def test_backoff_grows_and_is_capped_at_an_hour(attempts):
    delay = jobs.backoff(attempts)
    assert timedelta(seconds=30) <= delay <= timedelta(hours=1)
    assert jobs.backoff(attempts + 1) >= delay
