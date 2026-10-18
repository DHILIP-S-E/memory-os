"""Registering phones for push: one account per token, removed on sign-out."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.models.device import DeviceToken


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


def login(client, email):
    r = client.post("/auth/register", json={"email": email, "password": "correct horse"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}, r.json()["user"]["id"]


def devices(Session):
    async def q():
        async with Session() as db:
            return [(d.user_id, d.token, d.platform) for d in (await db.execute(select(DeviceToken))).scalars().all()]
    return asyncio.run(q())


def test_a_phone_registers_its_token_once(env):
    client, Session = env
    h, uid = login(client, "ada@example.com")
    for _ in range(2):
        assert client.post("/devices", headers=h, json={"token": "tok-1", "platform": "android"}).json() == {"registered": True}
    assert devices(Session) == [(uid, "tok-1", "android")]


def test_a_phone_that_signs_in_to_another_account_moves_with_it(env):
    client, Session = env
    a, _ = login(client, "ada@example.com")
    b, bob = login(client, "bob@example.com")
    client.post("/devices", headers=a, json={"token": "shared-phone"})
    client.post("/devices", headers=b, json={"token": "shared-phone"})
    assert devices(Session) == [(bob, "shared-phone", "android")], "Ada's reminders no longer go to Bob's phone"


def test_sign_out_removes_the_phone_and_only_the_owner_can(env):
    client, Session = env
    a, _ = login(client, "ada@example.com")
    b, _ = login(client, "bob@example.com")
    client.post("/devices", headers=a, json={"token": "tok-1"})
    assert client.post("/devices/unregister", headers=b, json={"token": "tok-1"}).json() == {"removed": False}
    assert len(devices(Session)) == 1
    assert client.post("/devices/unregister", headers=a, json={"token": "tok-1"}).json() == {"removed": True}
    assert devices(Session) == []


@pytest.mark.parametrize("body", [{"token": ""}, {"token": "   "}, {"token": "t", "platform": "pager"}, {"token": "x" * 4097}],
                         ids=["empty", "blank", "bad-platform", "huge"])
def test_bad_registrations_are_rejected(env, body):
    client, _ = env
    h, _ = login(client, "ada@example.com")
    assert client.post("/devices", headers=h, json=body).status_code == 422


def test_registration_needs_sign_in(env):
    client, _ = env
    assert client.post("/devices", json={"token": "t"}).status_code in (401, 403)
