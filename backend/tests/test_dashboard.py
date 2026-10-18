"""Today, upcoming and notification history: right user, right day, right order."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from hypothesis import given, strategies as st
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.models.delivery import NotificationDelivery
from app.services.agenda import day_bounds

UTC = timezone.utc


# --- where a day starts and ends -------------------------------------------------------------

def test_a_day_in_india_starts_at_half_past_six_pm_utc_the_evening_before():
    now = datetime(2026, 10, 11, 12, 0, tzinfo=UTC)  # 17:30 IST on 11 Oct
    start, end = day_bounds(now, "Asia/Kolkata")
    assert start == datetime(2026, 10, 10, 18, 30, tzinfo=UTC)
    assert end == datetime(2026, 10, 11, 18, 30, tzinfo=UTC)


def test_a_day_with_a_clock_change_is_not_24_hours_long():
    spring = day_bounds(datetime(2026, 3, 8, 18, 0, tzinfo=UTC), "America/New_York")   # clocks go forward
    autumn = day_bounds(datetime(2026, 11, 1, 18, 0, tzinfo=UTC), "America/New_York")  # clocks go back
    assert spring[1] - spring[0] == timedelta(hours=23)
    assert autumn[1] - autumn[0] == timedelta(hours=25)


@given(
    st.datetimes(min_value=datetime(2020, 1, 1), max_value=datetime(2035, 1, 1), timezones=st.just(UTC)),
    st.sampled_from(["UTC", "Asia/Kolkata", "America/New_York", "Pacific/Auckland", "Europe/London", "Asia/Kathmandu"]),
)
def test_now_is_always_inside_its_own_day_and_a_day_is_23_to_25_hours(now, tz):
    start, end = day_bounds(now, tz)
    assert start <= now < end
    assert timedelta(hours=23) <= end - start <= timedelta(hours=25)


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
    yield TestClient(app), Session
    app.dependency_overrides.clear()


def login(client, email="ada@example.com"):
    r = client.post("/auth/register", json={"email": email, "password": "correct horse"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}, r.json()["user"]["id"]


def midday_utc():
    start, end = day_bounds(datetime.now(UTC), "UTC")
    return start + (end - start) / 2


def test_today_separates_overdue_from_due_today(env):
    client, _ = env
    h, _ = login(client)
    mid = midday_utc()
    for title, at in (("old", mid - timedelta(days=3)), ("today", mid), ("later", mid + timedelta(days=3))):
        client.post("/reminders", headers=h, json={"title": title, "scheduled_at": at.isoformat()})
    body = client.get("/dashboard/today", headers=h).json()
    assert [r["title"] for r in body["overdue"]] == ["old"]
    assert [r["title"] for r in body["today"]] == ["today"]
    assert body["counts"] == {"overdue": 1, "today": 1, "pending_registrations": 0}


def test_a_completed_reminder_is_not_on_the_dashboard(env):
    client, _ = env
    h, _ = login(client)
    r = client.post("/reminders", headers=h, json={"title": "done", "scheduled_at": midday_utc().isoformat()}).json()
    client.patch(f"/reminders/{r['id']}", headers=h, json={"status": "completed"})
    assert client.get("/dashboard/today", headers=h).json()["today"] == []


def test_pending_registrations_list_only_open_ones_until_registered(env):
    client, _ = env
    h, _ = login(client)
    event = client.post("/events", headers=h, json={
        "title": "Hack", "start_at": "2031-03-01T10:00:00Z",
        "deadlines": [{"title": "Register", "deadline_type": "registration", "deadline_at": "2031-02-01T10:00:00Z"}],
    }).json()
    pending = client.get("/dashboard/today", headers=h).json()["pending_registrations"]
    assert [p["title"] for p in pending] == ["Hack"] and pending[0]["registration_status"] == "not_started"
    client.post(f"/events/{event['id']}/registration-status", headers=h, json={"status": "registered"})
    assert client.get("/dashboard/today", headers=h).json()["pending_registrations"] == []


def test_the_dashboard_only_shows_the_signed_in_users_data(env):
    client, _ = env
    h, _ = login(client)
    other, _ = login(client, "bob@example.com")
    client.post("/reminders", headers=h, json={"title": "mine", "scheduled_at": midday_utc().isoformat()})
    assert client.get("/dashboard/today", headers=other).json()["counts"]["today"] == 0
    assert client.get("/dashboard/upcoming", headers=other).json()["reminders"] == []


def test_upcoming_lists_deadlines_and_reminders_within_the_window_soonest_first(env):
    client, _ = env
    h, _ = login(client)
    now = datetime.now(UTC)
    for title, days in (("soon", 2), ("sooner", 1), ("far", 60)):
        client.post("/reminders", headers=h, json={"title": title, "scheduled_at": (now + timedelta(days=days)).isoformat()})
    client.post("/events", headers=h, json={
        "title": "Hack", "start_at": "2031-03-01T10:00:00Z",
        "deadlines": [{"title": "Submit", "deadline_type": "submission", "deadline_at": (now + timedelta(days=5)).isoformat()}],
    })
    body = client.get("/dashboard/upcoming?days=14", headers=h).json()
    assert [r["title"] for r in body["reminders"]] == ["sooner", "soon"]
    assert [m["title"] for m in body["milestones"]] == ["Submit"] and body["milestones"][0]["event_title"] == "Hack"


def test_bad_inputs_are_rejected(env):
    client, _ = env
    h, _ = login(client)
    assert client.get("/dashboard/today?timezone=Not/AZone", headers=h).status_code == 422
    assert client.get("/dashboard/upcoming?days=0", headers=h).status_code == 422
    assert client.get("/dashboard/upcoming?days=500", headers=h).status_code == 422
    assert client.get("/dashboard/today").status_code in (401, 403)


def test_notification_history_is_newest_first_paged_and_private(env):
    client, Session = env
    h, uid = login(client)
    other, other_id = login(client, "bob@example.com")
    r = client.post("/reminders", headers=h, json={"title": "Pay rent", "scheduled_at": midday_utc().isoformat()}).json()
    base = datetime(2026, 10, 1, tzinfo=UTC)

    async def seed():
        async with Session() as s:
            for i, status in enumerate(["triggered", "sent", "failed"]):
                s.add(NotificationDelivery(reminder_id=r["id"], user_id=uid, status=status, created_at=base + timedelta(minutes=i)))
            s.add(NotificationDelivery(reminder_id="x", user_id=other_id, status="sent", created_at=base))
            await s.commit()

    asyncio.run(seed())
    page = client.get("/notifications/history", headers=h).json()
    assert [i["status"] for i in page["items"]] == ["failed", "sent", "triggered"]
    assert {i["reminder_title"] for i in page["items"]} == {"Pay rent"}
    second = client.get("/notifications/history?limit=1&offset=1", headers=h).json()
    assert [i["status"] for i in second["items"]] == ["sent"]
    assert len(client.get("/notifications/history", headers=other).json()["items"]) == 1
    assert client.get("/notifications/history?limit=0", headers=h).status_code == 422
    assert client.get("/notifications/history?limit=101", headers=h).status_code == 422
