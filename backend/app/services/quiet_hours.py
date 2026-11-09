"""Quiet hours (spec 4.5). Pure: no I/O. Shared by the API and the background worker.

Rules that must hold:
  * Quiet hours are measured on the user's own clock, never UTC.
  * "UTC" is the app's default, not a place. With no real timezone nothing is suppressed,
    because quiet hours measured in the wrong zone would silently drop daytime reminders.
  * High-priority reminders always ring."""

from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DEFAULT_START = 22  # 10 PM
DEFAULT_END = 7     # 7 AM


def in_quiet_hours(hour: int, start: int = DEFAULT_START, end: int = DEFAULT_END) -> bool:
    """Hours [start, end) in a day, where the window may wrap past midnight (22 to 7)."""
    if start == end:
        return False
    return start <= hour < end if start < end else (hour >= start or hour < end)


def is_real_timezone(name: str | None) -> bool:
    return bool(name) and name.strip().upper() != "UTC"


def effective_timezone(reminder_tz: str | None, user_tz: str | None) -> str | None:
    """The reminder's own zone if it is a real one, else the user's saved zone, else None."""
    for candidate in (reminder_tz, user_tz):
        if is_real_timezone(candidate):
            return candidate.strip()
    return None


def should_suppress(
    priority: str,
    fire_at: datetime,
    reminder_tz: str | None = None,
    user_tz: str | None = None,
    enabled: bool = True,
    start: int | None = None,
    end: int | None = None,
) -> bool:
    if priority == "high" or not enabled:
        return False
    tz_name = effective_timezone(reminder_tz, user_tz)
    if tz_name is None:
        return False
    try:
        local = fire_at.astimezone(ZoneInfo(tz_name))
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return in_quiet_hours(
        local.hour,
        DEFAULT_START if start is None else start,
        DEFAULT_END if end is None else end,
    )
