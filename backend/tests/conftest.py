"""Tests must not depend on whoever's local .env is lying around.

Every test starts from a blank configuration; a test that needs a setting
sets it explicitly with monkeypatch."""

import os

# Never touch a real database from tests, whatever is in a local .env.
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///:memory:"

import pytest

from app.config import settings

_BLANK = {
    "jwt_secret": "",
    "gemini_api_key": "",
    "r2_account_id": "",
    "r2_access_key_id": "",
    "r2_secret_access_key": "",
    "r2_endpoint": "",
    "fcm_project_id": "",
    "fcm_credentials_file": "",
    "google_client_ids": "",
    "allow_insecure_dev_auth": False,
    "auto_create_tables": False,
    "cors_origins": "*",
}


@pytest.fixture(autouse=True)
def blank_settings(monkeypatch):
    for name, value in _BLANK.items():
        monkeypatch.setattr(settings, name, value)
