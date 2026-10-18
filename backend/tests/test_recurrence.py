"""Repeating reminders fire on the user's own clock, and always stop when told to."""

from datetime import datetime, timedelta, timezone
from itertools import islice
from zoneinfo import ZoneInfo

import pytest
from hypothesis import given, strategies as st

from app.services.recurrence import next_occurrence, occurrences, parse_rrule

UTC = timezone.utc
IST = ZoneInfo("Asia/Kolkata")
START = datetime(2026, 10, 5, 9, 30, tzinfo=IST)  # Monday 09:30 India time


def local(instants, tz=IST):
    return [i.astimezone(tz).strftime("%a %Y-%m-%d %H:%M") for i in instants]


def first(rule, n=4, anchor=START, tz="Asia/Kolkata"):
    return local(islice(occurrences(rule, anchor, tz), n), ZoneInfo(tz))


def test_daily_at_the_same_local_time():
    assert first("FREQ=DAILY", 3) == ["Mon 2026-10-05 09:30", "Tue 2026-10-06 09:30", "Wed 2026-10-07 09:30"]


def test_every_third_day():
    assert first("FREQ=DAILY;INTERVAL=3", 3) == ["Mon 2026-10-05 09:30", "Thu 2026-10-08 09:30", "Sun 2026-10-11 09:30"]


def test_weekly_on_chosen_days_and_every_other_week():
    assert first("RRULE:FREQ=WEEKLY;BYDAY=MO,WE", 3) == ["Mon 2026-10-05 09:30", "Wed 2026-10-07 09:30", "Mon 2026-10-12 09:30"]
    assert first("FREQ=WEEKLY;INTERVAL=2", 3) == ["Mon 2026-10-05 09:30", "Mon 2026-10-19 09:30", "Mon 2026-11-02 09:30"]


def test_monthly_skips_months_without_that_day():
    anchor = datetime(2027, 1, 31, 8, 0, tzinfo=IST)
    assert first("FREQ=MONTHLY", 3, anchor) == ["Sun 2027-01-31 08:00", "Wed 2027-03-31 08:00", "Mon 2027-05-31 08:00"]


def test_yearly():
    assert first("FREQ=YEARLY", 2) == ["Mon 2026-10-05 09:30", "Tue 2027-10-05 09:30"]


def test_until_stops_the_rule_on_that_day():
    assert first("FREQ=DAILY;UNTIL=20261007", 10) == ["Mon 2026-10-05 09:30", "Tue 2026-10-06 09:30", "Wed 2026-10-07 09:30"]


def test_count_stops_after_that_many():
    assert len(first("FREQ=DAILY;COUNT=2", 10)) == 2


def test_the_local_time_holds_across_a_clock_change():
    ny = ZoneInfo("America/New_York")
    anchor = datetime(2026, 10, 30, 9, 0, tzinfo=ny)  # clocks go back on 1 November
    times = list(islice(occurrences("FREQ=DAILY", anchor, "America/New_York"), 4))
    assert [t.astimezone(ny).hour for t in times] == [9, 9, 9, 9]
    assert times[2] - times[1] == timedelta(hours=25), "the night the clocks go back is an hour longer"


def test_next_occurrence_is_strictly_after_the_given_time():
    after = datetime(2026, 10, 6, 4, 0, tzinfo=UTC)  # 09:30 IST on Tue 6 Oct exactly
    assert local([next_occurrence("FREQ=DAILY", START, after, "Asia/Kolkata")]) == ["Wed 2026-10-07 09:30"]


def test_a_finished_rule_has_no_next_occurrence():
    assert next_occurrence("FREQ=DAILY;COUNT=1", START, START, "Asia/Kolkata") is None
    assert next_occurrence("FREQ=DAILY;UNTIL=20261005", START, START, "Asia/Kolkata") is None


@pytest.mark.parametrize("rule", ["", "nonsense", "FREQ=HOURLY", "FREQ=SECONDLY", "FREQ=DAILY;INTERVAL=0",
                                  "FREQ=DAILY;INTERVAL=x", "FREQ=WEEKLY;BYDAY=XX", "FREQ=MONTHLY;BYMONTHDAY=40",
                                  "FREQ=DAILY;UNTIL=garbage"])
def test_unsupported_or_malformed_rules_never_fire(rule):
    assert list(occurrences(rule, START, "Asia/Kolkata")) == []


def test_parse_rrule():
    assert parse_rrule("RRULE:FREQ=WEEKLY;BYDAY=MO") == {"FREQ": "WEEKLY", "BYDAY": "MO"}
    assert parse_rrule("FREQ=MINUTELY") is None
    assert parse_rrule(None) is None


@given(
    st.sampled_from(["FREQ=DAILY", "FREQ=DAILY;INTERVAL=2", "FREQ=WEEKLY;BYDAY=MO,FR", "FREQ=MONTHLY", "FREQ=YEARLY"]),
    st.datetimes(min_value=datetime(2024, 1, 1), max_value=datetime(2030, 1, 1), timezones=st.just(UTC)),
    st.sampled_from(["UTC", "Asia/Kolkata", "America/New_York", "Europe/London"]),
)
def test_occurrences_are_strictly_increasing_and_start_at_the_anchor(rule, anchor, tz):
    times = list(islice(occurrences(rule, anchor, tz), 5))
    assert times, "a supported rule always fires"
    assert times[0] >= anchor - timedelta(hours=1)  # the anchor day itself counts
    assert all(a < b for a, b in zip(times, times[1:]))
    nxt = next_occurrence(rule, anchor, times[0], tz)
    assert nxt == times[1]
