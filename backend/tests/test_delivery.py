"""Delivering reminders from the job queue: who gets what, what is recorded, and no duplicates."""

import asyncio
import json
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.config import settings
from app.database import Base
from app.models.delivery import NotificationDelivery
from app.models.device import DeviceToken
from app.models.job import Job
from app.models.reminder import Reminder
from app.models.user import User
from app.services import delivery, jobs, push, scheduling

UTC = timezone.utc
# 09:00 India time = 03:30 UTC. 23:00 India time = 17:30 UTC.
DAY = datetime(2031, 3, 3, 3, 30, tzinfo=UTC)
NIGHT = datetime(2031, 3, 3, 17, 30, tzinfo=UTC)


class FakePush:
    def __init__(self, fail_tokens=(), invalid_tokens=()):
        self.sent, self.fail_tokens, self.invalid_tokens = [], set(fail_tokens), set(invalid_tokens)

    def __call__(self, token, title, body, data=None, **kw):
        if token in self.invalid_tokens:
            raise push.InvalidToken("UNREGISTERED")
        if token in self.fail_tokens:
            raise RuntimeError("FCM returned HTTP 503")
        self.sent.append((token, title, data["reminder_id"]))
        return f"projects/p/messages/{len(self.sent)}"


@pytest.fixture
def env(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})

    async def setup():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(setup())
    Session = async_sessionmaker(engine, expire_on_commit=False)
    monkeypatch.setattr(settings, "fcm_project_id", "p")
    monkeypatch.setattr(settings, "fcm_credentials_file", "creds.json")
    fake = FakePush()
    monkeypatch.setattr(push, "send", fake)
    return Session, fake


def run(coro):
    return asyncio.run(coro)


async def seed(Session, *, fire_at=DAY, priority="medium", tz="Asia/Kolkata", devices=("tok-a", "tok-b"),
               status="active", rule=None, depends_on=None, user_tz="UTC", quiet=True):
    async with Session() as db:
        db.add(User(id="u1", email="ada@example.com", password_hash="x", timezone=user_tz, quiet_hours_enabled=quiet))
        for i, token in enumerate(devices):
            db.add(DeviceToken(id=f"d{i}", user_id="u1", token=token))
        reminder = Reminder(id="r1", user_id="u1", title="Pay rent", scheduled_at=fire_at, timezone=tz,
                            priority=priority, status=status, recurrence_rule=rule, depends_on_id=depends_on,
                            offsets="[]", created_at=fire_at, updated_at=fire_at)
        db.add(reminder)
        await db.flush()
        await scheduling.schedule_reminder(db, reminder, now=fire_at - timedelta(days=1))
        await db.commit()


def fire(Session, at=DAY):
    return run(jobs.run_once(Session, {scheduling.DELIVER: delivery.deliver_reminder}, now=at))


async def history(Session):
    async with Session() as db:
        rows = (await db.execute(select(NotificationDelivery).order_by(NotificationDelivery.created_at))).scalars().all()
        return [(r.status, r.error, r.device_id) for r in rows]


async def job_statuses(Session):
    async with Session() as db:
        return [(j.status, j.attempts) for j in (await db.execute(select(Job).order_by(Job.run_at))).scalars().all()]


def test_a_due_reminder_is_pushed_to_every_phone_and_recorded(env):
    Session, fake = env
    run(seed(Session))
    assert fire(Session) == 1
    assert sorted(t for t, _, _ in fake.sent) == ["tok-a", "tok-b"]
    statuses = [s for s, _, _ in run(history(Session))]
    assert statuses.count("triggered") == 1 and statuses.count("sent") == 2
    assert run(job_statuses(Session)) == [("done", 1)]


def test_nothing_is_sent_before_its_time(env):
    Session, fake = env
    run(seed(Session))
    assert fire(Session, DAY - timedelta(minutes=1)) == 0 and fake.sent == []


def test_quiet_hours_on_the_users_own_clock_hold_it_back_with_the_reason(env):
    Session, fake = env
    run(seed(Session, fire_at=NIGHT))
    fire(Session, NIGHT)
    assert fake.sent == []
    assert ("cancelled", "quiet hours", None) in run(history(Session))


def test_the_users_saved_timezone_applies_when_the_reminder_says_utc(env):
    Session, fake = env
    run(seed(Session, fire_at=NIGHT, tz="UTC", user_tz="Asia/Kolkata"))
    fire(Session, NIGHT)
    assert fake.sent == []


def test_high_priority_rings_even_in_quiet_hours(env):
    Session, fake = env
    run(seed(Session, fire_at=NIGHT, priority="high"))
    fire(Session, NIGHT)
    assert len(fake.sent) == 2


def test_a_reminder_whose_condition_is_met_is_not_sent(env):
    Session, fake = env

    async def add_done_dependency():
        async with Session() as db:
            db.add(Reminder(id="r0", user_id="u1", title="Register", status="completed", offsets="[]",
                            created_at=DAY, updated_at=DAY))
            await db.commit()

    run(add_done_dependency())
    run(seed(Session, depends_on="r0"))
    fire(Session)
    assert fake.sent == []
    assert ("cancelled", "its condition was already met", None) in run(history(Session))


def test_without_push_configured_it_is_recorded_as_not_sent(env, monkeypatch):
    Session, fake = env
    monkeypatch.setattr(settings, "fcm_credentials_file", "")
    run(seed(Session))
    fire(Session)
    assert fake.sent == [] and ("skipped", "push not configured", None) in run(history(Session))
    assert run(job_statuses(Session)) == [("done", 1)], "not retried forever"


def test_without_a_registered_phone_it_is_recorded_as_not_sent(env):
    Session, fake = env
    run(seed(Session, devices=()))
    fire(Session)
    assert ("skipped", "no device registered", None) in run(history(Session))


def test_an_expired_phone_registration_is_removed(env):
    Session, fake = env
    fake.invalid_tokens = {"tok-a"}
    run(seed(Session))
    fire(Session)

    async def tokens():
        async with Session() as db:
            return [d.token for d in (await db.execute(select(DeviceToken))).scalars().all()]

    assert run(tokens()) == ["tok-b"]
    assert [t for t, _, _ in fake.sent] == ["tok-b"]


def test_a_failed_phone_is_retried_later_without_resending_to_the_others(env):
    Session, fake = env
    fake.fail_tokens = {"tok-b"}
    run(seed(Session))
    fire(Session)
    assert [t for t, _, _ in fake.sent] == ["tok-a"]
    assert run(job_statuses(Session)) == [("pending", 1)]
    assert ("failed", "push failed (RuntimeError)", "d1") in run(history(Session)), "the failure is kept"

    fake.fail_tokens = set()
    fire(Session, DAY + timedelta(minutes=1))
    assert [t for t, _, _ in fake.sent] == ["tok-a", "tok-b"], "tok-a is not sent a second time"
    statuses = [s for s, _, _ in run(history(Session))]
    assert statuses.count("triggered") == 1


def test_a_cancelled_reminder_is_not_sent(env):
    Session, fake = env
    run(seed(Session))

    async def cancel_after_queueing():
        async with Session() as db:
            r = await db.get(Reminder, "r1")
            r.status = "cancelled"
            await db.commit()

    run(cancel_after_queueing())
    fire(Session)
    assert fake.sent == []


def test_a_deleted_reminder_finishes_quietly(env):
    Session, fake = env
    run(seed(Session))

    async def delete():
        async with Session() as db:
            await db.delete(await db.get(Reminder, "r1"))
            await db.commit()

    run(delete())
    fire(Session)
    assert fake.sent == [] and run(history(Session)) == []


def test_a_repeating_reminder_queues_its_next_occurrence(env):
    Session, fake = env
    run(seed(Session, rule="FREQ=DAILY;COUNT=3"))
    fire(Session)

    async def pending():
        async with Session() as db:
            rows = (await db.execute(select(Job).where(Job.status == "pending"))).scalars().all()
            return [jobs.as_utc(j.run_at) for j in rows]

    assert run(pending()) == [DAY + timedelta(days=1)]
    fire(Session, DAY + timedelta(days=1))
    fire(Session, DAY + timedelta(days=2))
    assert run(pending()) == [], "COUNT=3 stops after the third"
    assert len(fake.sent) == 6
