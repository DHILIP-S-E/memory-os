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
    "cognito_user_pool_id": "",
    "cognito_app_client_id": "",
    "allow_insecure_dev_auth": False,
    "guardrail_id": "",
    "guardrail_version": "",
    "scheduler_target_arn": "",
    "scheduler_role_arn": "",
    "capture_queue_url": "",
    "knowledge_base_id": "",
    "notification_topic_arn": "",
    "sns_platform_app_arn": "",
    "auto_create_tables": False,
    "cors_origins": "*",
}


@pytest.fixture(autouse=True)
def blank_settings(monkeypatch):
    for name, value in _BLANK.items():
        monkeypatch.setattr(settings, name, value)
