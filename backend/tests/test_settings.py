"""Timezone and quiet hours saved per user, and used when a reminder fires."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from hypothesis import given, strategies as st
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
import workers.notification_dispatcher as d
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.services import quiet_hours as q
from tests.test_capture_worker import FakeConn
from tests.test_dispatcher import FakeSns, event

UTC = timezone.utc


def at(h, m=0):
    return datetime(2026, 10, 5, h, m, tzinfo=UTC)


# --- the pure rules --------------------------------------------------------------------------

@pytest.mark.parametrize("hour,expected", [(21, False), (22, True), (23, True), (0, True), (6, True), (7, False), (12, False)])
def test_the_default_window_wraps_past_midnight(hour, expected):
    assert q.in_quiet_hours(hour) is expected


@given(st.integers(0, 23), st.integers(0, 23))
def test_an_empty_window_never_suppresses(hour, start):
    assert q.in_quiet_hours(hour, start, start) is False


@given(st.integers(0, 23), st.integers(0, 23), st.integers(0, 23))
def test_a_window_and_its_complement_cover_every_hour_exactly_once(hour, start, end):
    if start == end:
        return
    assert q.in_quiet_hours(hour, start, end) != q.in_quiet_hours(hour, end, start)


def test_the_reminders_own_zone_wins_then_the_users_saved_zone_then_nothing():
    assert q.effective_timezone("Asia/Kolkata", "Europe/London") == "Asia/Kolkata"
    assert q.effective_timezone("UTC", "Europe/London") == "Europe/London"
    assert q.effective_timezone(None, " Asia/Kolkata ") == "Asia/Kolkata"
    assert q.effective_timezone("UTC", "utc") is None
    assert q.effective_timezone("", None) is None


def test_the_users_saved_zone_makes_quiet_hours_work_for_an_app_that_sends_utc():
    # 23:00 in India is 17:30 UTC. The reminder says "UTC", but the user saved Asia/Kolkata.
    assert q.should_suppress("medium", at(17, 30), "UTC", "Asia/Kolkata") is True
    assert q.should_suppress("medium", at(17, 30), "UTC", None) is False


def test_turning_quiet_hours_off_and_custom_windows_are_respected():
    assert q.should_suppress("medium", at(17, 30), "UTC", "Asia/Kolkata", enabled=False) is False
    assert q.should_suppress("medium", at(17, 30), "UTC", "Asia/Kolkata", start=23, end=6) is True    # 23:00 is inside 23-6
    assert q.should_suppress("medium", at(17, 0), "UTC", "Asia/Kolkata", start=23, end=6) is False   # 22:30 is not
    assert q.should_suppress("high", at(17, 30), "UTC", "Asia/Kolkata") is False


# --- the dispatcher reads the settings when the reminder fires --------------------------------

def run(monkeypatch, row, **ev):
    conn = FakeConn(row=row)
    sns = FakeSns()
    monkeypatch.setenv("NOTIFICATION_TOPIC_ARN", "arn:aws:sns:ap-south-1:1:t")
    monkeypatch.setattr(d, "sync_database_url", lambda: "postgresql://x")
    monkeypatch.setattr(d.psycopg2, "connect", lambda url: conn)
    monkeypatch.setattr(d, "_sns", sns)
    return d.handler(event(**{"timezone": "UTC", "fire_at": at(17, 30).isoformat(), **ev}), None), sns


def test_a_saved_zone_suppresses_a_night_time_reminder_the_app_sent_as_utc(monkeypatch):
    out, sns = run(monkeypatch, ("Asia/Kolkata", True, None, None))
    assert out == {"suppressed": True} and sns.published == []


def test_a_user_who_turned_quiet_hours_off_still_gets_it(monkeypatch):
    out, sns = run(monkeypatch, ("Asia/Kolkata", False, None, None))
    assert out["sent"] is True and len(sns.published) == 1


def test_a_settings_lookup_failure_still_sends_the_reminder(monkeypatch):
    def boom(conn, user_id):
        raise RuntimeError("column does not exist")

    monkeypatch.setattr(d, "_user_settings", boom)
    out, sns = run(monkeypatch, None)
    assert out["sent"] is True and len(sns.published) == 1


def test_an_unknown_user_gets_the_safe_default_of_no_suppression(monkeypatch):
    out, _ = run(monkeypatch, None)
    assert out["sent"] is True


# --- the settings API ------------------------------------------------------------------------

@pytest.fixture
def client(monkeypatch):
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
    yield TestClient(app)
    app.dependency_overrides.clear()


def login(client, email="ada@example.com"):
    r = client.post("/auth/register", json={"email": email, "password": "correct horse"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_new_accounts_start_with_utc_and_the_default_window(client):
    h = login(client)
    assert client.get("/account/settings", headers=h).json() == {
        "timezone": "UTC", "quiet_hours_enabled": True, "quiet_hours_start": 22, "quiet_hours_end": 7}


def test_settings_can_be_changed_a_field_at_a_time(client):
    h = login(client)
    assert client.put("/account/settings", headers=h, json={"timezone": "Asia/Kolkata"}).json()["timezone"] == "Asia/Kolkata"
    after = client.put("/account/settings", headers=h, json={"quiet_hours_start": 23, "quiet_hours_end": 6}).json()
    assert after == {"timezone": "Asia/Kolkata", "quiet_hours_enabled": True, "quiet_hours_start": 23, "quiet_hours_end": 6}
    assert client.put("/account/settings", headers=h, json={"quiet_hours_enabled": False}).json()["quiet_hours_enabled"] is False
    assert client.get("/account/settings", headers=h).json()["timezone"] == "Asia/Kolkata"


@pytest.mark.parametrize("bad", [
    {"timezone": "Not/AZone"}, {"quiet_hours_start": 24}, {"quiet_hours_end": -1},
    {"quiet_hours_start": 8, "quiet_hours_end": 8},
])
def test_bad_settings_are_rejected(client, bad):
    h = login(client)
    assert client.put("/account/settings", headers=h, json=bad).status_code == 422


def test_each_user_has_their_own_settings(client):
    a, b = login(client), login(client, "bob@example.com")
    client.put("/account/settings", headers=a, json={"timezone": "Asia/Kolkata"})
    assert client.get("/account/settings", headers=b).json()["timezone"] == "UTC"
    assert client.get("/account/settings").status_code in (401, 403)


def test_a_reminder_sent_as_utc_takes_the_users_saved_timezone(client):
    h = login(client)
    client.put("/account/settings", headers=h, json={"timezone": "Asia/Kolkata"})
    made = client.post("/reminders", headers=h, json={"title": "Pay rent", "scheduled_at": "2031-01-01T05:00:00Z", "timezone": "UTC"}).json()
    assert made["timezone"] == "Asia/Kolkata"
    explicit = client.post("/reminders", headers=h, json={"title": "Call", "scheduled_at": "2031-01-01T05:00:00Z", "timezone": "Europe/London"}).json()
    assert explicit["timezone"] == "Europe/London", "a zone the client chose is never overridden"
