"""Firebase Cloud Messaging: message shape and how each response is treated."""

import httpx
import pytest

from app.config import settings
from app.services import push


class FakeHttp:
    def __init__(self, status=200, payload=None, error=None):
        self.status, self.payload, self.error, self.calls = status, payload, error, []

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append({"url": url, "json": json, "headers": headers})
        if self.error:
            raise self.error
        return httpx.Response(self.status, json=self.payload or {}, request=httpx.Request("POST", url))


@pytest.fixture
def fcm(monkeypatch):
    monkeypatch.setattr(settings, "fcm_project_id", "pmos-test")
    monkeypatch.setattr(settings, "fcm_credentials_file", "creds.json")


def test_the_message_is_a_high_priority_notification_with_string_data():
    msg = push.build_message("tok", "Pay rent", "Open the app", {"reminder_id": "r1", "n": 2})["message"]
    assert msg["token"] == "tok"
    assert msg["notification"] == {"title": "Pay rent", "body": "Open the app"}
    assert msg["data"] == {"reminder_id": "r1", "n": "2"}
    assert msg["android"]["priority"] == "high"


def test_without_settings_push_is_not_configured_and_nothing_is_sent():
    http = FakeHttp()
    with pytest.raises(push.PushUnavailable):
        push.send("tok", "t", "b", client=http, access_token="x")
    assert http.calls == []


def test_a_send_goes_to_the_projects_endpoint_with_a_bearer_token(fcm):
    http = FakeHttp(payload={"name": "projects/pmos-test/messages/1"})
    assert push.send("tok", "Pay rent", "b", client=http, access_token="ya29.token") == "projects/pmos-test/messages/1"
    assert http.calls[0]["url"] == "https://fcm.googleapis.com/v1/projects/pmos-test/messages:send"
    assert http.calls[0]["headers"]["Authorization"] == "Bearer ya29.token"


@pytest.mark.parametrize("status,payload", [
    (404, {"error": {"status": "NOT_FOUND"}}),
    (404, {}),
    (400, {"error": {"status": "INVALID_ARGUMENT"}}),
    (403, {"error": {"status": "UNREGISTERED"}}),
])
def test_a_dead_token_is_reported_so_it_can_be_removed(fcm, status, payload):
    with pytest.raises(push.InvalidToken):
        push.send("tok", "t", "b", client=FakeHttp(status, payload), access_token="x")


@pytest.mark.parametrize("status", [429, 500, 503])
def test_temporary_failures_are_errors_worth_retrying(fcm, status):
    with pytest.raises(RuntimeError, match=str(status)):
        push.send("tok", "t", "b", client=FakeHttp(status, {"error": {"status": "UNAVAILABLE"}}), access_token="x")


def test_a_network_failure_is_worth_retrying(fcm):
    with pytest.raises(RuntimeError, match="Could not reach FCM"):
        push.send("tok", "t", "b", client=FakeHttp(error=httpx.ConnectError("down")), access_token="x")
