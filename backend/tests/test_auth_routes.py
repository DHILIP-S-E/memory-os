"""End-to-end tests of /auth through real HTTP routes and an in-memory database."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

import app.models  # noqa: F401  (register all tables)
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.routers import auth as auth_router
from app.services.login_throttle import LoginThrottle

SECRET = "t" * 48


@pytest.fixture
def client(monkeypatch):
    # one shared in-memory connection for the whole test
    from sqlalchemy.pool import StaticPool
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
    monkeypatch.setattr(settings, "jwt_secret", SECRET)
    monkeypatch.setattr(auth_router, "throttle", LoginThrottle(max_failures=3))
    yield TestClient(app)
    app.dependency_overrides.clear()


def register(c, email="Ada@Example.com", password="correct horse"):
    return c.post("/auth/register", json={"email": email, "password": password, "display_name": "Ada"})


def test_register_returns_tokens_and_normalises_email(client):
    r = register(client)
    assert r.status_code == 201
    body = r.json()
    assert body["user"]["email"] == "ada@example.com"
    assert body["access_token"] and body["refresh_token"]
    assert "correct horse" not in str(body)
    assert "password_hash" not in body["user"]


def test_duplicate_email_rejected_case_insensitively(client):
    assert register(client).status_code == 201
    assert register(client, email="ADA@example.com").status_code == 409


@pytest.mark.parametrize("email,password", [("not-an-email", "correct horse"), ("a@b.co", "short"), ("a@b.co", "x" * 80)])
def test_bad_input_rejected(client, email, password):
    assert register(client, email=email, password=password).status_code == 422


def test_login_succeeds_then_me_works_with_the_access_token(client):
    register(client)
    r = client.post("/auth/login", json={"email": "ada@example.com", "password": "correct horse"})
    assert r.status_code == 200
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {r.json()['access_token']}"})
    assert me.status_code == 200 and me.json()["email"] == "ada@example.com"


def test_wrong_password_and_unknown_user_look_identical(client):
    register(client)
    a = client.post("/auth/login", json={"email": "ada@example.com", "password": "wrong password"})
    b = client.post("/auth/login", json={"email": "nobody@example.com", "password": "wrong password"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_repeated_failures_lock_the_account_even_for_the_right_password(client):
    register(client)
    for _ in range(3):
        client.post("/auth/login", json={"email": "ada@example.com", "password": "nope nope"})
    r = client.post("/auth/login", json={"email": "ada@example.com", "password": "correct horse"})
    assert r.status_code == 429 and int(r.headers["Retry-After"]) > 0


def test_refresh_token_cannot_be_used_as_an_access_token(client):
    tokens = register(client).json()
    r = client.get("/auth/me", headers={"Authorization": f"Bearer {tokens['refresh_token']}"})
    assert r.status_code == 401


def test_access_token_cannot_be_used_to_refresh(client):
    tokens = register(client).json()
    assert client.post("/auth/refresh", json={"refresh_token": tokens["access_token"]}).status_code == 401


def test_refresh_issues_a_working_access_token(client):
    tokens = register(client).json()
    r = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {r.json()['access_token']}"})
    assert me.status_code == 200


def test_protected_routes_reject_missing_and_forged_tokens(client):
    assert client.get("/auth/me").status_code in (401, 403)
    assert client.get("/auth/me", headers={"Authorization": "Bearer forged.token.here"}).status_code == 401


def test_login_unavailable_without_a_secret(client, monkeypatch):
    monkeypatch.setattr(settings, "jwt_secret", "")
    assert client.post("/auth/login", json={"email": "a@b.co", "password": "whatever1"}).status_code == 503


def test_deleting_the_account_removes_the_login_too(client):
    tokens = register(client).json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    assert client.delete("/account", headers=headers).status_code == 200
    # the old token is still cryptographically valid, but the account is gone
    assert client.get("/auth/me", headers=headers).status_code == 401
    assert client.post("/auth/login", json={"email": "ada@example.com", "password": "correct horse"}).status_code == 401


def test_export_includes_everything_the_user_created(client):
    tokens = register(client).json()
    h = {"Authorization": f"Bearer {tokens['access_token']}"}
    assert client.post("/reminders", headers=h, json={"title": "Pay bill", "scheduled_at": "2030-01-01T09:00:00+00:00"}).status_code == 201
    assert client.post("/events", headers=h, json={
        "title": "AWS Hackathon", "event_type": "hackathon", "start_at": "2030-10-15T10:00:00+00:00",
        "deadlines": [{"title": "Register", "deadline_type": "registration", "deadline_at": "2030-10-10T23:59:00+00:00"}],
    }).status_code == 201
    r = client.get("/account/export", headers=h)
    assert r.status_code == 200
    data = r.json()
    assert [x["title"] for x in data["reminders"]] == ["Pay bill"]
    assert data["events"][0]["title"] == "AWS Hackathon"
    assert data["events"][0]["deadlines"][0]["title"] == "Register"
    assert data["user_id"] == tokens["user"]["id"]


def test_one_users_data_is_never_in_another_users_export(client):
    a = register(client, email="a@example.com").json()
    b = register(client, email="b@example.com").json()
    ha = {"Authorization": f"Bearer {a['access_token']}"}
    hb = {"Authorization": f"Bearer {b['access_token']}"}
    client.post("/reminders", headers=ha, json={"title": "A's secret"})
    assert client.get("/account/export", headers=hb).json()["reminders"] == []
    assert client.get("/reminders", headers=hb).json() == []
