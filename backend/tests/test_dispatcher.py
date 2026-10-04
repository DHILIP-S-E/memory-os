import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import json
from datetime import datetime, timezone

import pytest
from hypothesis import given, strategies as st

import workers.notification_dispatcher as d
from tests.test_capture_worker import FakeConn

UTC = timezone.utc


def at(h, m=0):
    return datetime(2026, 10, 5, h, m, tzinfo=UTC)


# 09:00 India time is 03:30 UTC. Measured in UTC that is "night": the bug that would
# have silently dropped every normal-priority morning reminder for an Indian user.
def test_morning_reminder_in_india_is_not_quiet():
    assert d.should_suppress("medium", at(3, 30), "Asia/Kolkata") is False


def test_late_night_in_the_users_own_zone_is_quiet():
    assert d.should_suppress("medium", at(17, 30), "Asia/Kolkata") is True   # 23:00 IST
    assert d.should_suppress("medium", at(1, 0), "Asia/Kolkata") is True     # 06:30 IST


def test_high_priority_always_rings():
    assert d.should_suppress("high", at(17, 30), "Asia/Kolkata") is False


@pytest.mark.parametrize("tz", [None, "", "UTC", "utc", "Not/AZone"])
def test_without_a_real_timezone_nothing_is_suppressed(tz):
    assert d.should_suppress("low", at(1, 0), tz) is False


@given(st.integers(0, 23), st.sampled_from(["medium", "low"]))
def test_never_suppressed_without_a_timezone(hour, priority):
    assert d.should_suppress(priority, at(hour), None) is False


def test_message_has_the_required_default_key_and_only_protocol_keys():
    body = d.build_message("Submit the prototype")
    assert set(body) == {"default"} and "Submit the prototype" in body["default"]
    json.dumps(body)  # serialisable


@given(st.text(max_size=300))
def test_email_subject_is_always_valid_for_sns(title):
    s = d.email_subject(title)
    assert len(s) <= 100 and "\n" not in s and "\r" not in s and s.isascii()


class FakeSns:
    def __init__(self, fail=False):
        self.published, self.fail = [], fail

    def publish(self, **kw):
        if self.fail:
            raise RuntimeError("sns down")
        self.published.append(kw)
        return {"MessageId": "m-1"}


@pytest.fixture
def env(monkeypatch):
    conn = FakeConn()
    sns = FakeSns()
    monkeypatch.setenv("NOTIFICATION_TOPIC_ARN", "arn:aws:sns:ap-south-1:1:t")
    monkeypatch.setattr(d, "sync_database_url", lambda: "postgresql://x")
    monkeypatch.setattr(d.psycopg2, "connect", lambda url: conn)
    monkeypatch.setattr(d, "_sns", sns)
    monkeypatch.setattr(d.boto3, "client", lambda *a, **k: sns)
    return conn, sns


def event(**kw):
    base = {"reminder_id": "r1", "user_id": "u1", "title": "Submit the prototype",
            "priority": "medium", "fire_at": at(4).isoformat(), "timezone": "Asia/Kolkata"}
    return {**base, **kw}


def statuses(conn):
    return [p[3] for s, p in conn.statements if s.startswith("INSERT")]


def test_a_normal_reminder_is_published_and_recorded_as_sent(env):
    conn, sns = env
    out = d.handler(event(), None)
    assert out == {"sent": True, "message_id": "m-1"}
    sent = sns.published[0]
    assert sent["MessageAttributes"]["user_id"]["StringValue"] == "u1"
    assert sent["Subject"] == "Reminder: Submit the prototype"
    assert statuses(conn) == ["triggered", "sent"]


def test_a_quiet_hours_suppression_is_recorded_not_left_hanging(env):
    conn, sns = env
    out = d.handler(event(fire_at=at(17, 30).isoformat()), None)  # 23:00 IST
    assert out == {"suppressed": True} and sns.published == []
    assert statuses(conn) == ["triggered", "cancelled"]


def test_a_conditional_reminder_is_skipped_once_its_dependency_is_done(env):
    conn, sns = env
    conn.row = ("completed",)
    out = d.handler(event(depends_on_id="r0"), None)
    assert out == {"skipped": True} and sns.published == []
    assert statuses(conn) == ["triggered", "cancelled"]


def test_a_missing_dependency_still_fires(env):
    conn, sns = env
    conn.row = None
    assert d.handler(event(depends_on_id="gone"), None)["sent"] is True


def test_an_sns_failure_is_recorded_and_raised_so_the_scheduler_retries(env, monkeypatch):
    conn, _ = env
    failing = FakeSns(fail=True)
    monkeypatch.setattr(d, "_sns", failing)
    with pytest.raises(RuntimeError):
        d.handler(event(), None)
    assert statuses(conn) == ["triggered", "failed"]
