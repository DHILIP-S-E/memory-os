"""Captures are saved at once and read by the worker: notes, links and files, including failures."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
import json
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
import app.services.llm_service as llm_service
from app import worker
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.services import gemini, jobs, media_ai, storage

REPLY = json.dumps({
    "summary": "Plan to ship the prototype",
    "topics": ["Shipping"],
    "key_points": ["Deadline is Oct 20"],
    "actions": [{"title": "Submit the prototype", "due_at": "2026-10-20"}],
})


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
    monkeypatch.setattr(llm_service, "_invoke", lambda *a, **k: REPLY)
    client = TestClient(app)
    r = client.post("/auth/register", json={"email": "ada@example.com", "password": "correct horse"})
    client.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
    client.user_id = r.json()["user"]["id"]
    yield client, Session
    app.dependency_overrides.clear()


def work(Session, minutes=0):
    """Let the worker run everything that is due (optionally some minutes from now)."""
    now = datetime.now(timezone.utc) + timedelta(minutes=minutes)
    return asyncio.run(jobs.run_once(Session, worker.HANDLERS, on_failure=worker.ON_FAILURE, now=now, limit=50))


def capture(client, cid):
    return client.get(f"/captures/{cid}").json()


def test_a_note_is_saved_at_once_and_read_by_the_worker(env):
    client, Session = env
    created = client.post("/captures/note", json={"content": "I need to submit the prototype by October 20"})
    assert created.status_code == 201 and created.json()["processing_status"] == "queued"
    assert work(Session) == 1
    note = capture(client, created.json()["id"])
    assert note["processing_status"] == "processed"
    assert note["ai_result"]["summary"] == "Plan to ship the prototype"
    assert note["ai_result"]["actions"] == [{"title": "Submit the prototype", "due_at": "2026-10-20"}]


def test_a_link_is_kept_as_a_link(env):
    client, Session = env
    created = client.post("/captures/link", json={"url": "https://example.com/hackathon"})
    work(Session)
    link = capture(client, created.json()["id"])
    assert link["processing_status"] == "processed" and "https://example.com/hackathon" in link["ai_result"]["summary"]


def test_an_ai_outage_is_retried_and_finally_explained_never_stuck(env, monkeypatch):
    client, Session = env

    def down(*a, **k):
        raise gemini.AIUnavailable("The AI service returned HTTP 503")

    monkeypatch.setattr(llm_service, "_invoke", down)
    created = client.post("/captures/note", json={"content": "anything"})
    assert created.status_code == 201, "saving the note must not depend on the AI"
    work(Session)
    assert capture(client, created.json()["id"])["processing_status"] == "queued", "waiting to retry"
    for minutes in (5, 15, 40, 120):
        work(Session, minutes)
    note = capture(client, created.json()["id"])
    assert note["processing_status"] == "failed"
    assert note["ai_result"]["summary"] == "Could not analyse this capture: the AI service is not available right now."


def test_a_failed_capture_can_be_read_again(env, monkeypatch):
    client, Session = env
    monkeypatch.setattr(llm_service, "_invoke", lambda *a, **k: (_ for _ in ()).throw(gemini.AIUnavailable("down")))
    cid = client.post("/captures/note", json={"content": "anything"}).json()["id"]
    for minutes in (0, 5, 15, 40, 120):
        work(Session, minutes)
    assert capture(client, cid)["processing_status"] == "failed"

    monkeypatch.setattr(llm_service, "_invoke", lambda *a, **k: REPLY)
    again = client.post(f"/captures/{cid}/process")
    assert again.status_code == 200 and again.json()["processing_status"] == "queued"
    assert client.post(f"/captures/{cid}/process").status_code == 409, "not twice at once"
    work(Session, 121)
    assert capture(client, cid)["processing_status"] == "processed"


# --- files from R2 ----------------------------------------------------------------------------

@pytest.fixture
def files(env, monkeypatch):
    client, Session = env
    store = {}
    monkeypatch.setattr(storage, "object_size", lambda key: len(store[key]) if key in store else (_ for _ in ()).throw(FileNotFoundError(key)))
    monkeypatch.setattr(storage, "read_object", lambda key: store[key])
    calls = []

    def analyse(data, kind, mime, *, model, today_iso=None):
        calls.append((kind, mime, data))
        return ({"summary": f"Read a {kind}", "topics": [], "key_points": [], "actions": []},
                "Call the vendor on Friday" if kind == "audio" else None)

    monkeypatch.setattr(media_ai, "analyse", analyse)
    return client, Session, store, calls


def register(client, kind, ext, store=None, data=b"bytes"):
    key = f"users/{client.user_id}/misc/{kind}/c-{kind}.{ext}"
    if store is not None:
        store[key] = data
    return client.post("/captures", json={"capture_id": f"c-{kind}", "storage_key": key, "capture_type": kind}).json()["id"]


def test_a_voice_note_is_transcribed_and_summarised(files):
    client, Session, store, calls = files
    cid = register(client, "voice", "m4a", store)
    work(Session)
    c = capture(client, cid)
    assert c["processing_status"] == "processed" and c["transcription"] == "Call the vendor on Friday"
    assert calls == [("audio", "audio/m4a", b"bytes")]


def test_a_photo_is_read(files):
    client, Session, store, calls = files
    cid = register(client, "photo", "jpg", store)
    work(Session)
    assert capture(client, cid)["ai_result"]["summary"] == "Read a image"


def test_an_unsupported_file_fails_at_once_with_a_helpful_reason(files):
    client, Session, store, calls = files
    cid = register(client, "document", "docx", store)
    work(Session)
    c = capture(client, cid)
    assert c["processing_status"] == "failed" and "Save it as a PDF" in c["ai_result"]["summary"]
    assert calls == [], "the AI is never asked about a file it cannot read"


def test_a_file_that_has_not_arrived_yet_is_retried_not_lost(files):
    client, Session, store, calls = files
    cid = register(client, "photo", "jpg")  # registered before the upload finished
    work(Session)
    assert capture(client, cid)["processing_status"] == "queued"
    store[f"users/{client.user_id}/misc/photo/c-photo.jpg"] = b"late bytes"
    work(Session, 5)
    assert capture(client, cid)["processing_status"] == "processed"


def test_an_empty_file_fails_with_a_reason(files):
    client, Session, store, calls = files
    cid = register(client, "photo", "png", store, data=b"")
    work(Session)
    c = capture(client, cid)
    assert c["processing_status"] == "failed" and "empty" in c["ai_result"]["summary"]
