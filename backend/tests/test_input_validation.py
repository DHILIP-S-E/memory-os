"""Bad input is a clear 422 (never a 500, never stored), and files can only belong to their owner."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
import app.routers.captures as captures_module
from app import validation as v
from app.config import settings
from app.database import Base, get_db
from app.main import app


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
    monkeypatch.setattr(captures_module, "generate_upload_url", lambda key, ctype: f"https://s3.test/{key}")
    yield TestClient(app)
    app.dependency_overrides.clear()


def signup(client, email="ada@example.com"):
    r = client.post("/auth/register", json={"email": email, "password": "correct horse"})
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.put("/account/settings", headers=headers, json={"ai_enabled": True}).status_code == 200  # opt-in
    return headers, r.json()["user"]["id"]


# --- the shared rules -----------------------------------------------------------------------

def test_a_key_must_sit_under_the_owners_own_folder():
    assert v.owns_storage_key("users/u1/misc/photo/a.png", "u1")
    assert not v.owns_storage_key("users/u2/misc/photo/a.png", "u1")
    assert not v.owns_storage_key("users/u1/../u2/misc/photo/a.png", "u1")
    assert not v.owns_storage_key("users/u10/x.png", "u1")      # prefix of the id is not the id
    assert not v.owns_storage_key("", "u1")


@pytest.mark.parametrize("url", ["javascript:alert(1)", "data:text/html,x", "file:///etc/passwd", "ftp://x.co", "not a url", "http://", ""])
def test_only_http_links_are_allowed(url):
    with pytest.raises(ValueError):
        v.http_url(url)


def test_http_and_https_links_pass():
    assert v.http_url(" https://example.com/a?b=1 ") == "https://example.com/a?b=1"


@pytest.mark.parametrize("ext", ["../../etc/passwd", "p/ng", "", "toolongext1", "p g"])
def test_file_extensions_cannot_carry_a_path(ext):
    with pytest.raises(ValueError):
        v.file_extension(ext)


# --- captures over HTTP ---------------------------------------------------------------------

def test_cannot_register_someone_elses_file(client):
    h, uid = signup(client)
    body = {"capture_id": str(uuid.uuid4()), "storage_key": "users/someone-else/misc/photo/x.png", "capture_type": "photo"}
    assert client.post("/captures", headers=h, json=body).status_code == 422
    own = {**body, "storage_key": f"users/{uid}/misc/photo/x.png"}
    assert client.post("/captures", headers=h, json=own).status_code == 201


def test_bad_upload_requests_are_rejected(client):
    h, _ = signup(client)
    ok = {"capture_type": "photo", "file_extension": "png", "content_type": "image/png"}
    assert client.post("/captures/upload-url", headers=h, json=ok).status_code == 200
    for bad in (
        {**ok, "capture_type": "exe"},
        {**ok, "file_extension": "../../etc/passwd"},
        {**ok, "content_type": "nonsense"},
        {**ok, "event_id": "../other"},
    ):
        assert client.post("/captures/upload-url", headers=h, json=bad).status_code == 422, bad


@pytest.mark.parametrize("content", ["", "   ", "x" * 50_001], ids=["empty", "blank", "too-long"])
def test_empty_or_enormous_notes_are_rejected(client, content):
    h, _ = signup(client)
    assert client.post("/captures/note", headers=h, json={"content": content}).status_code == 422


def test_links_must_be_http(client):
    h, _ = signup(client)
    assert client.post("/captures/link", headers=h, json={"url": "javascript:alert(1)"}).status_code == 422
    assert client.post("/captures/link", headers=h, json={"url": "https://example.com"}).status_code == 201


# --- events and questions over HTTP -----------------------------------------------------------

def test_event_input_is_checked(client):
    h, _ = signup(client)
    ok = {"title": "Hack", "start_at": "2030-01-10T10:00:00Z"}
    assert client.post("/events", headers=h, json=ok).status_code == 201
    for bad in (
        {**ok, "title": "  "},
        {**ok, "title": "x" * 501},
        {**ok, "timezone": "Not/AZone"},
        {**ok, "end_at": "2030-01-09T10:00:00Z"},
        {**ok, "event_url": "javascript:alert(1)"},
        {**ok, "deadlines": [{"title": "", "deadline_at": "2030-01-09T10:00:00Z"}]},
    ):
        assert client.post("/events", headers=h, json=bad).status_code == 422, bad


def test_an_event_may_end_when_it_starts(client):
    h, _ = signup(client)
    same = "2030-01-10T10:00:00Z"
    assert client.post("/events", headers=h, json={"title": "Moment", "start_at": same, "end_at": same}).status_code == 201


def test_empty_questions_are_rejected(client):
    h, _ = signup(client)
    for q in ("", "   ", "x" * 2001):
        assert client.post("/memory/ask", headers=h, json={"question": q}).status_code == 422
