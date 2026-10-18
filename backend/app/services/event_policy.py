"""Smart reminder policy per event (spec 4.3 and 4.5). Pure: no I/O.

Event-day reminders depend on the event type. Each deadline gets reminders on a cadence the
user can edit ("7d", "3d", "1d", "3h", the deadline's morning, or right away). Optionally a
registration deadline also gets a daily reminder that stops on its own the day before the
deadline, and is cancelled as soon as the user registers (it is tagged with the milestone).
"""

from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

# Minutes before event start at which to remind, by event type.
_EVENT_OFFSETS = {
    "hackathon": [1440, 60, 30],
    "conference": [1440, 120, 30],
    "workshop": [1440, 60, 15],
    "webinar": [60, 10],
    "meetup": [180, 30],
    "meeting": [30, 10],
    "appointment": [1440, 60],
    "deadline": [4320, 1440, 180],
}
_DEFAULT_OFFSETS = [1440, 30]

# Cadence steps for deadlines: minutes before the deadline, plus two special steps.
CADENCE_MINUTES = {"7d": 10080, "3d": 4320, "2d": 2880, "1d": 1440, "12h": 720, "3h": 180, "1h": 60}
MORNING, NOW = "morning", "now"
CADENCE_CHOICES = set(CADENCE_MINUTES) | {MORNING, NOW}
DEFAULT_CADENCE = ("3d", "1d", "3h")
MORNING_HOUR = 9


def _label(minutes: int) -> str:
    if minutes % 1440 == 0:
        return f"{minutes // 1440}d"
    if minutes % 60 == 0:
        return f"{minutes // 60}h"
    return f"{minutes}m"


def _zone(name: str | None):
    try:
        return ZoneInfo(name) if name else timezone.utc
    except (ZoneInfoNotFoundError, ValueError):
        return timezone.utc


def clean_cadence(cadence) -> tuple[str, ...]:
    """Known steps only, in a stable order, without duplicates. Empty or unknown = the default."""
    if not cadence:
        return DEFAULT_CADENCE
    order = [NOW, "7d", "3d", "2d", "1d", MORNING, "12h", "3h", "1h"]
    chosen = {c for c in cadence if c in CADENCE_CHOICES}
    return tuple(c for c in order if c in chosen) or DEFAULT_CADENCE


def _deadline_times(deadline: datetime, cadence: tuple[str, ...], now: datetime, tz) -> list[tuple[str, datetime]]:
    out = []
    for step in cadence:
        if step == NOW:
            at = now + timedelta(minutes=1)
            label = "due soon" if deadline - now < timedelta(days=1) else f"due {deadline.astimezone(tz):%d %b}"
        elif step == MORNING:
            local_day = deadline.astimezone(tz).date()
            at = datetime.combine(local_day, time(MORNING_HOUR), tzinfo=tz).astimezone(timezone.utc)
            label = "due today"
        else:
            at = deadline - timedelta(minutes=CADENCE_MINUTES[step])
            label = f"due in {step}"
        if now < at < deadline:
            out.append((label, at))
    return out


def daily_until_deadline(title: str, deadline: datetime, now: datetime, timezone_name: str | None):
    """A daily 9 AM reminder from the next morning until the day before the deadline, or None if
    there is no such day. The UNTIL stop condition means it can never loop forever."""
    tz = _zone(timezone_name)
    local_now = now.astimezone(tz)
    first_day = local_now.date() if local_now.hour < MORNING_HOUR else local_now.date() + timedelta(days=1)
    last_day = deadline.astimezone(tz).date() - timedelta(days=1)
    if first_day > last_day:
        return None
    first = datetime.combine(first_day, time(MORNING_HOUR), tzinfo=tz).astimezone(timezone.utc)
    return {
        "title": f"Register for {title} (deadline {deadline.astimezone(tz):%d %b})",
        "reminder_type": "recurring",
        "scheduled_at": first,
        "recurrence_rule": f"FREQ=DAILY;UNTIL={last_day:%Y%m%d}",
        "priority": "medium",
    }


def build_reminder_policy(
    title: str,
    event_type: str,
    start_at: datetime,
    deadlines: list[tuple],
    now: datetime,
    *,
    cadence=None,
    daily_until_registered: bool = False,
    timezone_name: str | None = None,
) -> list[dict]:
    """Reminder specs for an event, only future instants, sorted by time.

    A deadline is (title, at), (title, at, milestone_id) or (title, at, milestone_id, deadline_type).
    The milestone id tags each of its reminders so finishing that milestone stops exactly those."""
    tz = _zone(timezone_name)
    steps = clean_cadence(cadence)
    out: list[dict] = []
    for minutes in _EVENT_OFFSETS.get(event_type, _DEFAULT_OFFSETS):
        at = start_at - timedelta(minutes=minutes)
        if at > now:
            out.append({
                "title": f"{title} starts in {_label(minutes)}",
                "reminder_type": "time",
                "scheduled_at": at,
                "priority": "medium",
            })
    for dl_title, dl_at, *rest in deadlines:
        milestone_id = rest[0] if rest else None
        deadline_type = rest[1] if len(rest) > 1 else None
        for label, at in _deadline_times(dl_at, steps, now, tz):
            out.append({
                "title": f"{dl_title} {label} — {title}",
                "reminder_type": "deadline",
                "scheduled_at": at,
                "priority": "high",
                "milestone_id": milestone_id,
            })
        if daily_until_registered and deadline_type == "registration":
            daily = daily_until_deadline(title, dl_at, now, timezone_name)
            if daily is not None:
                out.append({**daily, "milestone_id": milestone_id})
    return sorted(out, key=lambda r: r["scheduled_at"])
