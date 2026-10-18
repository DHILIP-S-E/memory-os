"""Google sign-in: only genuine, verified tokens for this app; accounts created or linked safely."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.services import google_auth

WEB, ANDROID = "web-client.apps.googleusercontent.com", "android-client.apps.googleusercontent.com"


def claims(**kw):
    return {"iss": "https://accounts.google.com", "aud": ANDROID, "sub": "g-123",
            "email": "Ada@Example.com", "email_verified": True, "name": "Ada Lovelace", **kw}


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
    monkeypatch.setattr(settings, "google_client_ids", f"{WEB}, {ANDROID}")
    tokens = {}  # what Google's library would say about each token

    def fake_verify(token, audience):
        assert audience == [WEB, ANDROID]
        if token not in tokens:
            raise ValueError("Could not verify token signature.")
        return tokens[token]

    monkeypatch.setattr(google_auth, "_verify_with_google", fake_verify)
    yield TestClient(app), tokens
    app.dependency_overrides.clear()


def google(client, token):
    return client.post("/auth/google", json={"id_token": token})


def test_a_new_google_user_gets_an_account(env):
    client, tokens = env
    tokens["t1"] = claims()
    r = google(client, "t1")
    assert r.status_code == 200
    body = r.json()
    assert body["user"]["email"] == "ada@example.com" and body["user"]["display_name"] == "Ada Lovelace"
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.json()["email"] == "ada@example.com"


def test_signing_in_again_is_the_same_account(env):
    client, tokens = env
    tokens["t1"] = claims()
    first = google(client, "t1").json()["user"]["id"]
    tokens["t2"] = claims(email="ada.new@example.com")  # the Google id is what counts, even if the email changed
    assert google(client, "t2").json()["user"]["id"] == first


def test_an_existing_password_account_with_that_email_is_linked_not_duplicated(env):
    client, tokens = env
    made = client.post("/auth/register", json={"email": "ada@example.com", "password": "correct horse"}).json()
    tokens["t1"] = claims()
    assert google(client, "t1").json()["user"]["id"] == made["user"]["id"]
    assert client.post("/auth/login", json={"email": "ada@example.com", "password": "correct horse"}).status_code == 200


def test_a_google_only_account_cannot_be_entered_with_any_password(env):
    client, tokens = env
    tokens["t1"] = claims()
    google(client, "t1")
    for guess in ("", "correct horse", "password1"):
        assert client.post("/auth/login", json={"email": "ada@example.com", "password": guess}).status_code == 401


def test_an_email_linked_to_another_google_account_is_refused(env):
    client, tokens = env
    tokens["t1"] = claims()
    google(client, "t1")
    tokens["t2"] = claims(sub="g-999")  # same email, a different Google account
    r = google(client, "t2")
    assert r.status_code == 409 and "different Google account" in r.json()["detail"]


@pytest.mark.parametrize("bad", [
    {"email_verified": False},
    {"email_verified": None},
    {"aud": "someone-elses-app.apps.googleusercontent.com"},
    {"iss": "https://evil.example.com"},
    {"sub": ""},
    {"email": ""},
], ids=["unverified", "no-verified-flag", "other-app", "bad-issuer", "no-sub", "no-email"])
def test_unacceptable_tokens_are_refused(env, bad):
    client, tokens = env
    tokens["t"] = claims(**bad)
    assert google(client, "t").status_code == 401


def test_a_forged_or_expired_token_is_refused(env):
    client, _ = env
    r = google(client, "forged.jwt.value")
    assert r.status_code == 401 and r.json()["detail"] == "Google sign-in failed. Please try again."


def test_an_oversized_or_blank_token_is_refused_before_any_check(env):
    client, _ = env
    assert google(client, "   ").status_code == 401
    assert google(client, "x" * 9000).status_code == 401


def test_when_google_cannot_be_reached_it_says_try_again(env, monkeypatch):
    client, _ = env

    def offline(token, audience):
        raise ConnectionError("no network")

    monkeypatch.setattr(google_auth, "_verify_with_google", offline)
    r = google(client, "t1")
    assert r.status_code == 503 and "try again" in r.json()["detail"]


def test_without_client_ids_google_sign_in_is_not_configured(env, monkeypatch):
    client, tokens = env
    monkeypatch.setattr(settings, "google_client_ids", "")
    tokens["t1"] = claims()
    r = google(client, "t1")
    assert r.status_code == 503 and "not configured" in r.json()["detail"]
