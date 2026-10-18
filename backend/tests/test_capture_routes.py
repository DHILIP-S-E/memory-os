"""A note created through the API is processed in the background (no queue needed)."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
import json

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
import app.database as database_module
import app.services.llm_service as llm_service
from app.config import settings
from app.database import Base, get_db
from app.main import app

REPLY = json.dumps({
    "summary": "Plan to ship the prototype",
    "topics": ["Shipping"],
    "key_points": ["Deadline is Oct 20"],
    "actions": [{"title": "Submit the prototype", "due_at": "2026-10-20"}],
})


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
    monkeypatch.setattr(database_module, "AsyncSessionLocal", Session)  # the background task's own session
    monkeypatch.setattr(settings, "jwt_secret", "q" * 48)
    monkeypatch.setattr(settings, "capture_queue_url", "")           # lean deployment: no queue
    monkeypatch.setattr(llm_service, "_invoke", lambda *a, **k: REPLY)
    yield TestClient(app)
    app.dependency_overrides.clear()


def headers(client):
    r = client.post("/auth/register", json={"email": "ada@example.com", "password": "correct horse"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_note_comes_back_processed_with_its_action(client):
    h = headers(client)
    created = client.post("/captures/note", headers=h, json={"content": "I need to submit the prototype by October 20"})
    assert created.status_code == 201
    note = client.get(f"/captures/{created.json()['id']}", headers=h).json()
    assert note["processing_status"] == "processed"
    assert note["ai_result"]["summary"] == "Plan to ship the prototype"
    assert note["ai_result"]["actions"] == [{"title": "Submit the prototype", "due_at": "2026-10-20"}]


def test_link_is_processed_too(client):
    h = headers(client)
    created = client.post("/captures/link", headers=h, json={"url": "https://example.com/hackathon"})
    link = client.get(f"/captures/{created.json()['id']}", headers=h).json()
    assert link["processing_status"] == "processed"
    assert "https://example.com/hackathon" in link["ai_result"]["summary"]


def test_a_model_outage_never_leaves_the_note_stuck(client, monkeypatch):
    def down(*a, **k):
        raise RuntimeError("AI service unavailable")

    monkeypatch.setattr(llm_service, "_invoke", down)
    h = headers(client)
    created = client.post("/captures/note", headers=h, json={"content": "anything"})
    assert created.status_code == 201, "saving the note must not depend on the AI"
    assert client.get(f"/captures/{created.json()['id']}", headers=h).json()["processing_status"] == "failed"


def test_with_a_queue_configured_the_api_does_not_process_inline(client, monkeypatch):
    sent = []
    monkeypatch.setattr(settings, "capture_queue_url", "https://sqs.example/queue")
    monkeypatch.setattr("app.routers.captures.enqueue_text_capture", lambda cid: sent.append(cid) or True)
    h = headers(client)
    created = client.post("/captures/note", headers=h, json={"content": "queued path"})
    assert sent == [created.json()["id"]]
    assert client.get(f"/captures/{created.json()['id']}", headers=h).json()["processing_status"] == "queued"
