"""Registering stops only the registration reminders; submission reminders keep running."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio

import pytest
from fastapi.testclient import TestClient
from hypothesis import given, strategies as st
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
import app.routers.events as events_module
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.services import milestones as m


# --- the pure rules --------------------------------------------------------------------------

def test_only_finished_states_stop_registration_reminders():
    assert {s for s in m.REGISTRATION_STATES if m.stops_registration_reminders(s)} == {
        "registered", "skipped", "not_eligible", "expired"}


@pytest.mark.parametrize("state", ["not_started", "planned", "in_progress", "waitlisted", "failed"])
def test_in_between_states_keep_the_reminders_going(state):
    assert not m.stops_registration_reminders(state)


def test_each_stopping_state_closes_the_milestone_the_right_way():
    assert m.milestone_status_for("registered") == "completed"
    assert m.milestone_status_for("skipped") == "skipped"
    assert m.milestone_status_for("not_eligible") == "skipped"
    assert m.milestone_status_for("expired") == "expired"
    assert m.milestone_status_for("in_progress") is None


def test_only_active_reminders_of_a_closed_milestone_are_stopped():
    reminders = [
        {"id": "a", "status": "active", "milestone_id": "reg"},
        {"id": "b", "status": "active", "milestone_id": "sub"},
        {"id": "c", "status": "active", "milestone_id": None},      # event-day or manual
        {"id": "d", "status": "completed", "milestone_id": "reg"},  # already done
    ]
    assert m.reminders_to_stop(reminders, {"reg"}) == ["a"]
    assert m.reminders_to_stop(reminders, set()) == []


def test_free_text_deadline_types_still_match_registration():
    deadlines = [
        {"id": "1", "deadline_type": " Registration ", "status": "active"},
        {"id": "2", "deadline_type": "submission", "status": "active"},
        {"id": "3", "deadline_type": "registration", "status": "completed"},
    ]
    assert m.registration_milestone_ids(deadlines) == {"1"}
    assert m.normalize_type("Team  Formation ") == "team_formation"
    assert m.normalize_type("   ") == "custom"


@given(st.text(max_size=40))
def test_normalized_types_are_always_lowercase_and_space_free(raw):
    t = m.normalize_type(raw)
    assert t == t.lower() and " " not in t and t


# --- the whole scenario over HTTP ------------------------------------------------------------

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
    scheduled, cancelled = [], []

    async def fake_schedule(db, r):
        scheduled.append(r.id)

    async def fake_cancel(db, r):
        cancelled.append(r.id)

    monkeypatch.setattr(events_module, "_schedule_cloud_layer", fake_schedule)
    monkeypatch.setattr(events_module, "_cancel_cloud_layer", fake_cancel)
    c = TestClient(app)
    c.scheduled, c.cancelled = scheduled, cancelled
    yield c
    app.dependency_overrides.clear()


def login(client, email="ada@example.com"):
    r = client.post("/auth/register", json={"email": email, "password": "correct horse"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def hackathon(client, h):
    body = {
        "title": "Hack", "event_type": "hackathon", "start_at": "2031-03-01T10:00:00Z",
        "deadlines": [
            {"title": "Register", "deadline_type": "Registration", "deadline_at": "2031-02-01T10:00:00Z"},
            {"title": "Submit", "deadline_type": "submission", "deadline_at": "2031-02-20T10:00:00Z"},
        ],
    }
    event = client.post("/events", headers=h, json=body).json()
    ids = {d["deadline_type"]: d["id"] for d in client.get(f"/events/{event['id']}", headers=h).json()["deadlines"]}
    return event["id"], ids


def reminders_by_milestone(client, h):
    out = {}
    for r in client.get("/reminders", headers=h).json():
        out.setdefault(r["milestone_id"], []).append(r)
    return out


def test_registering_stops_only_registration_reminders_and_submission_stays_active(client):
    h = login(client)
    event_id, ids = hackathon(client, h)
    created = client.post(f"/events/{event_id}/reminder-policy", headers=h).json()
    assert len(client.scheduled) == len(created) > 0, "every reminder also reaches the cloud layer"
    by = reminders_by_milestone(client, h)
    assert len(by[ids["registration"]]) == 3 and len(by[ids["submission"]]) == 3

    res = client.post(f"/events/{event_id}/registration-status", headers=h, json={"status": "registered"})
    assert res.status_code == 200
    body = res.json()
    assert body["event"]["registration_status"] == "registered"
    assert sorted(body["stopped_reminders"]) == sorted(r["id"] for r in by[ids["registration"]])
    assert sorted(client.cancelled) == sorted(body["stopped_reminders"]), "and they leave the cloud schedule"

    by = reminders_by_milestone(client, h)
    assert {r["status"] for r in by[ids["registration"]]} == {"cancelled"}
    assert {r["status"] for r in by[ids["submission"]]} == {"active"}
    assert {r["status"] for r in by[None]} == {"active"}  # the event-day reminders are untouched
    deadlines = {d["deadline_type"]: d for d in client.get(f"/events/{event_id}", headers=h).json()["deadlines"]}
    assert deadlines["registration"]["status"] == "completed" and deadlines["submission"]["status"] == "active"


def test_in_progress_does_not_stop_anything(client):
    h = login(client)
    event_id, ids = hackathon(client, h)
    client.post(f"/events/{event_id}/reminder-policy", headers=h)
    res = client.post(f"/events/{event_id}/registration-status", headers=h, json={"status": "in_progress"}).json()
    assert res["stopped_reminders"] == [] and client.cancelled == []


def test_completing_the_submission_milestone_leaves_registration_alone(client):
    h = login(client)
    event_id, ids = hackathon(client, h)
    client.post(f"/events/{event_id}/reminder-policy", headers=h)
    res = client.post(f"/events/{event_id}/deadlines/{ids['submission']}/complete", headers=h).json()
    assert len(res["stopped_reminders"]) == 3 and res["milestone"]["status"] == "completed"
    by = reminders_by_milestone(client, h)
    assert {r["status"] for r in by[ids["registration"]]} == {"active"}


def test_skipping_registration_marks_the_event_skipped(client):
    h = login(client)
    event_id, ids = hackathon(client, h)
    client.post(f"/events/{event_id}/reminder-policy", headers=h)
    client.post(f"/events/{event_id}/deadlines/{ids['registration']}/skip", headers=h)
    event = client.get(f"/events/{event_id}", headers=h).json()
    assert event["registration_status"] == "skipped"


def test_finished_milestones_get_no_new_reminders(client):
    h = login(client)
    event_id, ids = hackathon(client, h)
    client.post(f"/events/{event_id}/registration-status", headers=h, json={"status": "registered"})
    preview = client.get(f"/events/{event_id}/reminder-policy", headers=h).json()
    assert preview and all(p.get("milestone_id") != ids["registration"] for p in preview)


def test_bad_status_and_other_users_are_refused(client):
    h = login(client)
    event_id, ids = hackathon(client, h)
    assert client.post(f"/events/{event_id}/registration-status", headers=h, json={"status": "bogus"}).status_code == 422
    other = login(client, "bob@example.com")
    assert client.post(f"/events/{event_id}/registration-status", headers=other, json={"status": "registered"}).status_code == 404
    assert client.post(f"/events/{event_id}/deadlines/{ids['submission']}/complete", headers=other).status_code == 404
    assert client.post(f"/events/{event_id}/deadlines/not-real/complete", headers=h).status_code == 404
