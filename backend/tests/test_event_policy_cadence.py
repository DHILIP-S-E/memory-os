"""Editable reminder cadence and "daily until registered" (spec 4.5)."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient
from hypothesis import given, strategies as st
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.models.job import Job
from app.services.event_policy import build_reminder_policy, clean_cadence, daily_until_deadline
from app.services.recurrence import occurrences

UTC = timezone.utc
IST = ZoneInfo("Asia/Kolkata")
NOW = datetime(2026, 10, 18, 6, 0, tzinfo=UTC)               # 11:30 IST
DEADLINE = datetime(2026, 10, 25, 18, 29, tzinfo=UTC)        # 23:59 IST on 25 Oct


def policy(**kw):
    return build_reminder_policy("Hack", "hackathon", DEADLINE + timedelta(days=10),
                                 [("Register", DEADLINE, "m1", "registration")], NOW, timezone_name="Asia/Kolkata", **kw)


def deadline_items(items):
    return [p for p in items if p.get("milestone_id") == "m1" and p["reminder_type"] == "deadline"]


def test_the_default_cadence_is_3_days_1_day_and_3_hours_before():
    assert [DEADLINE - p["scheduled_at"] for p in deadline_items(policy())] == [timedelta(days=3), timedelta(days=1), timedelta(hours=3)]


def test_a_custom_cadence_is_used_in_order():
    times = [p["scheduled_at"] for p in deadline_items(policy(cadence=["1d", "7d", "morning"]))]
    assert times[0] == DEADLINE - timedelta(days=7) and times[1] == DEADLINE - timedelta(days=1)
    assert times[2].astimezone(IST).strftime("%d %H:%M") == "25 09:00", "the deadline's morning on the event's clock"


def test_right_away_means_a_minute_from_now():
    first = deadline_items(policy(cadence=["now"]))[0]
    assert first["scheduled_at"] == NOW + timedelta(minutes=1)


def test_steps_that_would_land_in_the_past_or_after_the_deadline_are_left_out():
    soon = NOW + timedelta(hours=2)
    items = build_reminder_policy("Hack", "custom", soon + timedelta(days=1), [("Register", soon, "m1")], NOW,
                                  cadence=["7d", "1d", "1h"])
    assert [soon - p["scheduled_at"] for p in deadline_items(items)] == [timedelta(hours=1)]


def test_unknown_or_empty_cadence_falls_back_to_the_default():
    assert clean_cadence([]) == clean_cadence(None) == ("3d", "1d", "3h")
    assert clean_cadence(["bogus"]) == ("3d", "1d", "3h")
    assert clean_cadence(["1d", "1d", "7d"]) == ("7d", "1d")


def test_daily_until_registered_runs_each_morning_and_stops_the_day_before_the_deadline():
    daily = [p for p in policy(daily_until_registered=True) if p["reminder_type"] == "recurring"]
    assert len(daily) == 1 and daily[0]["milestone_id"] == "m1"
    fires = list(occurrences(daily[0]["recurrence_rule"], daily[0]["scheduled_at"], "Asia/Kolkata"))
    local = [f.astimezone(IST) for f in fires]
    assert local[0].strftime("%d %H:%M") == "19 09:00", "it is past 9 today, so it starts tomorrow"
    assert local[-1].strftime("%d %H:%M") == "24 09:00", "the deadline day itself has its own reminders"
    assert len(fires) == 6


def test_daily_is_only_for_registration_deadlines_and_only_when_asked():
    assert not [p for p in policy() if p["reminder_type"] == "recurring"]
    other = build_reminder_policy("Hack", "custom", DEADLINE, [("Submit", DEADLINE, "m2", "submission")], NOW,
                                  daily_until_registered=True)
    assert not [p for p in other if p["reminder_type"] == "recurring"]


def test_no_daily_reminder_when_the_deadline_is_tomorrow_or_sooner():
    assert daily_until_deadline("Hack", NOW + timedelta(hours=20), NOW, "Asia/Kolkata") is None


@given(st.lists(st.sampled_from(["7d", "3d", "2d", "1d", "12h", "3h", "1h", "morning", "now"]), max_size=9),
       st.integers(min_value=1, max_value=60 * 24 * 30))
def test_every_reminder_is_in_the_future_and_before_its_deadline(cadence, minutes_ahead):
    deadline = NOW + timedelta(minutes=minutes_ahead)
    items = build_reminder_policy("E", "custom", deadline + timedelta(days=1), [("Register", deadline, "m1", "registration")],
                                  NOW, cadence=cadence, daily_until_registered=True, timezone_name="Asia/Kolkata")
    for p in items:
        if p.get("milestone_id") == "m1":
            assert NOW < p["scheduled_at"] < deadline


# --- over HTTP ------------------------------------------------------------------------------

@pytest.fixture
def env(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})

    async def setup():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(setup())
    Session = async_sessionmaker(engine, expire_on_commit=False)

    async def override():
        async with Session() as s:
            yield s

    app.dependency_overrides[get_db] = override
    monkeypatch.setattr(settings, "jwt_secret", "q" * 48)
    client = TestClient(app)
    r = client.post("/auth/register", json={"email": "ada@example.com", "password": "correct horse"})
    client.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    yield client, Session
    app.dependency_overrides.clear()


def hackathon(client):
    deadline = (datetime.now(UTC) + timedelta(days=8)).replace(microsecond=0)
    event = client.post("/events", json={
        "title": "Hack", "event_type": "hackathon", "start_at": (deadline + timedelta(days=10)).isoformat(),
        "timezone": "Asia/Kolkata",
        "deadlines": [
            {"title": "Register", "deadline_type": "registration", "deadline_at": deadline.isoformat()},
            {"title": "Submit", "deadline_type": "submission", "deadline_at": (deadline + timedelta(days=5)).isoformat()},
        ],
    }).json()
    return event["id"]


def test_preview_uses_the_chosen_cadence_and_rejects_unknown_steps(env):
    client, _ = env
    eid = hackathon(client)
    preview = client.get(f"/events/{eid}/reminder-policy?cadence=7d,morning&daily_until_registered=true").json()
    kinds = [p["reminder_type"] for p in preview]
    assert "recurring" in kinds
    assert client.get(f"/events/{eid}/reminder-policy?cadence=7d,bogus").status_code == 422


def test_registering_also_stops_the_daily_reminder_and_its_queued_deliveries(env):
    client, Session = env
    eid = hackathon(client)
    created = client.post(f"/events/{eid}/reminder-policy", json={"cadence": ["1d"], "daily_until_registered": True}).json()
    daily = [r for r in created if r["reminder_type"] == "recurring"]
    assert len(daily) == 1 and daily[0]["recurrence_rule"].startswith("FREQ=DAILY;UNTIL=")

    stopped = client.post(f"/events/{eid}/registration-status", json={"status": "registered"}).json()["stopped_reminders"]
    assert daily[0]["id"] in stopped

    async def pending_for(reminder_id):
        async with Session() as db:
            rows = (await db.execute(select(Job).where(Job.idempotency_key.like(f"reminder:{reminder_id}:%")))).scalars().all()
            return [j.status for j in rows]

    assert set(asyncio.run(pending_for(daily[0]["id"]))) == {"cancelled"}


def test_applying_the_policy_twice_creates_no_duplicates(env):
    client, _ = env
    eid = hackathon(client)
    first = client.post(f"/events/{eid}/reminder-policy").json()
    again = client.post(f"/events/{eid}/reminder-policy").json()
    assert first and again == []
    assert len(client.get("/reminders").json()) == len(first)


def test_a_bad_cadence_body_is_rejected(env):
    client, _ = env
    eid = hackathon(client)
    assert client.post(f"/events/{eid}/reminder-policy", json={"cadence": ["soon"]}).status_code == 422
