"""
Repeating reminders (spec 4.5): when an RFC 5545 rule fires next, on the user's own clock.

Supported: FREQ=DAILY | WEEKLY | MONTHLY | YEARLY with INTERVAL, BYDAY (weekly), BYMONTHDAY
(monthly), and the stop conditions UNTIL and COUNT. Anything else is "not supported" (None):
the reminder then fires once instead of looping in a way nobody asked for.

The time of day is the anchor's local time in the reminder's timezone, so "every day at 9"
stays 9:00 across daylight-saving changes.
"""

from datetime import date, datetime, time, timedelta, timezone
from typing import Iterator
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

UTC = timezone.utc
_WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
MAX_SCAN_DAYS = 4000      # about 11 years: enough for any supported rule to fire again
MAX_COUNT = 1000


def parse_rrule(rule: str) -> dict[str, str] | None:
    """'RRULE:FREQ=WEEKLY;BYDAY=MO' -> {'FREQ': 'WEEKLY', 'BYDAY': 'MO'}; None if malformed."""
    if not isinstance(rule, str):
        return None
    body = rule.strip()
    if body.upper().startswith("RRULE:"):
        body = body[6:]
    parts: dict[str, str] = {}
    for item in body.split(";"):
        if "=" not in item:
            return None
        key, value = item.split("=", 1)
        parts[key.strip().upper()] = value.strip().upper()
    return parts if parts.get("FREQ") in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY") else None


def _zone(name: str | None):
    try:
        return ZoneInfo(name) if name else UTC
    except (ZoneInfoNotFoundError, ValueError):
        return UTC


def _until(value: str, tz) -> datetime | None:
    """UNTIL as a UTC instant. 'YYYYMMDD' means the end of that local day."""
    try:
        if len(value) == 8:
            day = datetime.strptime(value, "%Y%m%d").date()
            return datetime.combine(day, time(23, 59, 59), tzinfo=tz).astimezone(UTC)
        if value.endswith("Z"):
            return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
        return datetime.strptime(value, "%Y%m%dT%H%M%S").replace(tzinfo=tz).astimezone(UTC)
    except ValueError:
        return None


class _Rule:
    def __init__(self, parts: dict[str, str], anchor_local: datetime):
        self.freq = parts["FREQ"]
        self.interval = int(parts.get("INTERVAL", "1"))
        self.start = anchor_local.date()
        days = parts.get("BYDAY") or _WEEKDAYS[self.start.weekday()]
        self.weekdays = {_WEEKDAYS.index(d) for d in days.split(",")}
        self.month_day = int(parts.get("BYMONTHDAY", str(self.start.day)))
        if self.interval < 1 or not 1 <= self.month_day <= 31:
            raise ValueError("bad rule")

    def matches(self, day: date) -> bool:
        if day < self.start:
            return False
        if self.freq == "DAILY":
            return (day - self.start).days % self.interval == 0
        if self.freq == "WEEKLY":
            week0 = self.start - timedelta(days=self.start.weekday())
            weeks = (day - timedelta(days=day.weekday()) - week0).days // 7
            return day.weekday() in self.weekdays and weeks % self.interval == 0
        if self.freq == "MONTHLY":
            months = (day.year - self.start.year) * 12 + day.month - self.start.month
            return day.day == self.month_day and months % self.interval == 0
        return (day.month, day.day) == (self.start.month, self.start.day) and (day.year - self.start.year) % self.interval == 0


def occurrences(rule: str, anchor: datetime, tz_name: str | None = None) -> Iterator[datetime]:
    """Every instant the rule fires, in order, from the anchor on (UTC). Empty if unsupported."""
    parts = parse_rrule(rule)
    if not parts:
        return
    tz = _zone(tz_name)
    anchor_local = (anchor if anchor.tzinfo else anchor.replace(tzinfo=UTC)).astimezone(tz)
    try:
        spec = _Rule(parts, anchor_local)
        count = int(parts["COUNT"]) if "COUNT" in parts else None
    except (ValueError, KeyError):
        return
    until = _until(parts["UNTIL"], tz) if "UNTIL" in parts else None
    if "UNTIL" in parts and until is None:
        return
    at = anchor_local.timetz().replace(tzinfo=None)
    produced = 0
    for offset in range(MAX_SCAN_DAYS):
        day = spec.start + timedelta(days=offset)
        if not spec.matches(day):
            continue
        instant = datetime.combine(day, at, tzinfo=tz).astimezone(UTC)
        if until is not None and instant > until:
            return
        yield instant
        produced += 1
        if count is not None and produced >= min(count, MAX_COUNT):
            return


def next_occurrence(rule: str, anchor: datetime, after: datetime, tz_name: str | None = None) -> datetime | None:
    """The first time the rule fires strictly after `after`, or None when it never will again."""
    after = after if after.tzinfo else after.replace(tzinfo=UTC)
    for instant in occurrences(rule, anchor, tz_name):
        if instant > after:
            return instant
    return None


def is_supported(rule: str | None) -> bool:
    return bool(rule) and parse_rrule(rule) is not None
