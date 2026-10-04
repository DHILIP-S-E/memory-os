import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import json

import pytest
from fastapi.testclient import TestClient

from app.auth import get_current_user_id
from app.config import settings
from app.main import app
from app.routers import devices


class FakeSns:
    def __init__(self, fail=False):
        self.calls, self.fail = [], fail

    def subscribe(self, **kw):
        if self.fail:
            raise RuntimeError("boom")
        self.calls.append(kw)
        return {"SubscriptionArn": "pending confirmation"}


@pytest.fixture
def client(monkeypatch):
    sns = FakeSns()
    monkeypatch.setattr(settings, "notification_topic_arn", "arn:aws:sns:ap-south-1:1:topic")
    monkeypatch.setattr(devices.boto3, "client", lambda *a, **k: sns)
    app.dependency_overrides[get_current_user_id] = lambda: "user-7"
    yield TestClient(app), sns
    app.dependency_overrides.clear()


def test_subscribes_the_email_filtered_to_this_user_only(client):
    c, sns = client
    r = c.post("/devices/email", json={"email": "  Ada@Example.com "})
    assert r.status_code == 200 and r.json()["status"] == "pending_confirmation"
    call = sns.calls[0]
    assert call["Protocol"] == "email" and call["Endpoint"] == "Ada@example.com"
    assert json.loads(call["Attributes"]["FilterPolicy"]) == {"user_id": ["user-7"]}
    assert call["TopicArn"].endswith(":topic")


@pytest.mark.parametrize("bad", ["", "not-an-email", "a@", "@b.co"])
def test_invalid_addresses_are_rejected_before_calling_aws(client, bad):
    c, sns = client
    assert c.post("/devices/email", json={"email": bad}).status_code == 422
    assert sns.calls == []


def test_unconfigured_topic_is_a_clear_503(client, monkeypatch):
    c, _ = client
    monkeypatch.setattr(settings, "notification_topic_arn", "")
    assert c.post("/devices/email", json={"email": "a@b.co"}).status_code == 503


def test_an_sns_error_is_a_502_not_a_crash(client, monkeypatch):
    c, _ = client
    monkeypatch.setattr(devices.boto3, "client", lambda *a, **k: FakeSns(fail=True))
    assert c.post("/devices/email", json={"email": "a@b.co"}).status_code == 502


def test_requires_sign_in(monkeypatch):
    monkeypatch.setattr(settings, "notification_topic_arn", "arn:x")
    app.dependency_overrides.clear()
    assert TestClient(app).post("/devices/email", json={"email": "a@b.co"}).status_code in (401, 403, 503)
