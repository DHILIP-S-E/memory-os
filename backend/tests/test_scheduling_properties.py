"""Property tests for reminder fire times, quiet hours, and event policy."""

import os
from datetime import datetime, timedelta, timezone

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

from hypothesis import given, strategies as st

from app.services.event_policy import build_reminder_policy
from app.services.reminder_parser import offset_to_minutes
from app.services.quiet_hours import in_quiet_hours, should_suppress
from app.services.scheduling import compute_fire_times, delivery_times, job_key, key_prefix

NOW = datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc)
future = st.datetimes(
    min_value=datetime(2026, 10, 1), max_value=datetime(2030, 1, 1), timezones=st.just(timezone.utc)
)
offset = st.builds(lambda n, u: f"-{n}{u}", st.integers(1, 999), st.sampled_from("mhdw"))


@given(future, st.lists(offset, max_size=8))
def test_fire_times_future_sorted_unique(target, offsets):
    times = compute_fire_times(target, offsets, now=NOW)
    assert times == sorted(set(times))
    assert all(t > NOW for t in times)
    assert all(t <= target for t in times)


@given(future, st.lists(offset, max_size=8))
def test_fire_times_are_exactly_target_minus_offsets(target, offsets):
    expected = {target} | {target - timedelta(minutes=offset_to_minutes(o)) for o in offsets}
    assert set(compute_fire_times(target, offsets, now=NOW)) == {t for t in expected if t > NOW}


@given(future)
def test_past_target_never_schedules(target):
    assert compute_fire_times(target, ["-1h"], now=target + timedelta(seconds=1)) == []


@given(st.integers(0, 23), st.integers(0, 23), st.integers(0, 23))
def test_quiet_hours_matches_definition(hour, start, end):
    if start == end:
        assert not in_quiet_hours(hour, start, end)
    elif start < end:
        assert in_quiet_hours(hour, start, end) == (start <= hour < end)
    else:
        assert in_quiet_hours(hour, start, end) == (hour >= start or hour < end)


def test_quiet_hours_default_window():
    assert in_quiet_hours(23) and in_quiet_hours(3) and not in_quiet_hours(12)


@given(future)
def test_high_priority_never_suppressed(fire_at):
    assert should_suppress("high", fire_at) is False


@given(st.uuids(), future, future)
def test_each_fire_time_has_its_own_key_under_the_reminders_prefix(reminder_id, a, b):
    rid = str(reminder_id)
    assert job_key(rid, a).startswith(key_prefix(rid))
    assert (job_key(rid, a) == job_key(rid, b)) == (int(a.timestamp()) == int(b.timestamp()))
    assert len(job_key(rid, a)) <= 200


@given(future, st.lists(offset, max_size=5))
def test_a_one_off_reminder_is_delivered_at_its_fire_times(target, offsets):
    assert delivery_times(target, offsets, None, "UTC", NOW) == compute_fire_times(target, offsets, NOW)


@given(future)
def test_a_repeating_reminder_queues_only_its_next_occurrence(target):
    times = delivery_times(target, ["-1h", "-1d"], "FREQ=DAILY", "Asia/Kolkata", NOW)
    assert len(times) == 1 and times[0] > NOW - timedelta(seconds=1)


def test_an_unsupported_rule_falls_back_to_a_one_off_reminder():
    target = NOW + timedelta(days=1)
    assert delivery_times(target, [], "FREQ=SECONDLY", "UTC", NOW) == [target]


def test_no_time_means_nothing_to_deliver():
    assert delivery_times(None, ["-1h"], None, "UTC", NOW) == []


EVENT_TYPES = ["hackathon", "conference", "workshop", "webinar", "meetup", "meeting", "appointment", "deadline", "custom"]


@given(st.sampled_from(EVENT_TYPES), future, st.lists(future, max_size=3))
def test_event_policy_only_future_sorted_and_before_targets(etype, start, deadline_ats):
    deadlines = [(f"D{i}", d) for i, d in enumerate(deadline_ats)]
    policy = build_reminder_policy("Ev", etype, start, deadlines, NOW)
    times = [p["scheduled_at"] for p in policy]
    assert times == sorted(times)
    assert all(t > NOW for t in times)
    assert all(p["reminder_type"] in ("time", "deadline") for p in policy)
    latest = max([start] + deadline_ats)
    assert all(t < latest for t in times)


def test_hackathon_policy_example():
    start = NOW + timedelta(days=2)
    policy = build_reminder_policy("AWS Hackathon", "hackathon", start, [("Register", NOW + timedelta(days=5))], NOW)
    titles = [p["title"] for p in policy]
    assert "AWS Hackathon starts in 30m" in titles
    assert any(t.startswith("Register due in 1d") for t in titles)
