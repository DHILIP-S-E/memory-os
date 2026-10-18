"""Every request needs a valid token from this app; a misconfigured server fails closed."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.services.tokens import create_access_token, create_refresh_token

SECRET = "q" * 48


def get_me(token):
    return TestClient(app).get("/health/me", headers={"Authorization": f"Bearer {token}"})


def test_a_valid_access_token_identifies_the_user(monkeypatch):
    monkeypatch.setattr(settings, "jwt_secret", SECRET)
    r = get_me(create_access_token("u1", SECRET))
    assert r.status_code == 200 and r.json()["user_id"] == "u1"


def test_a_forged_expired_or_wrong_kind_of_token_is_refused(monkeypatch):
    monkeypatch.setattr(settings, "jwt_secret", SECRET)
    for token in ("forged.token.value", create_access_token("u1", "x" * 48), create_refresh_token("u1", SECRET)):
        assert get_me(token).status_code == 401


def test_without_a_secret_the_server_fails_closed(monkeypatch):
    monkeypatch.setattr(settings, "jwt_secret", "")
    monkeypatch.setattr(settings, "allow_insecure_dev_auth", False)
    assert get_me("forged.token.value").status_code == 503


def test_a_missing_token_is_refused():
    assert TestClient(app).get("/health/me").status_code in (401, 403)


def test_dev_mode_is_an_explicit_opt_in(monkeypatch):
    monkeypatch.setattr(settings, "jwt_secret", "")
    monkeypatch.setattr(settings, "allow_insecure_dev_auth", True)
    r = get_me("not-a-jwt")
    assert r.status_code == 200 and r.json()["user_id"] == "dev_user"
