"""
Pure validation/normalisation for LLM-parsed reminders (spec R1.2, R1.4).

Model output is untrusted. Whatever the model returns, this module
guarantees the result is a well-formed reminder dict: known type/priority,
bounded non-empty title, ISO-8601 scheduled_at or None, and a sorted,
de-duplicated list of valid offsets (largest lead time first).

No I/O — property-tested in tests/test_reminder_parser_properties.py.
"""

import re
from datetime import datetime, timezone
from typing import Any

VALID_TYPES = ("time", "date", "deadline", "recurring", "follow_up", "multi_stage", "conditional")
VALID_PRIORITIES = ("high", "medium", "low")
MAX_TITLE_LENGTH = 500

_OFFSET_RE = re.compile(r"^-(\d{1,3})([mhdw])$")
_UNIT_MINUTES = {"m": 1, "h": 60, "d": 1440, "w": 10080}


def offset_to_minutes(offset: str) -> int | None:
    """'-3h' -> 180. Returns None for anything that is not a valid offset."""
    match = _OFFSET_RE.match(offset)
    if not match:
        return None
    minutes = int(match.group(1)) * _UNIT_MINUTES[match.group(2)]
    return minutes if minutes > 0 else None


def normalize_offsets(raw: Any) -> list[str]:
    """Keep valid, unique offsets, ordered from furthest to nearest the deadline."""
    if not isinstance(raw, list):
        return []
    seen: dict[int, str] = {}
    for item in raw:
        if not isinstance(item, str):
            continue
        item = item.strip().lower()
        minutes = offset_to_minutes(item)
        if minutes is not None:
            seen.setdefault(minutes, item)
    return [seen[m] for m in sorted(seen, reverse=True)]


def normalize_scheduled_at(raw: Any) -> str | None:
    """Return the value only if it parses as ISO-8601, else None."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    value = raw.strip()
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return value


def normalize_reminder(raw: Any, fallback_text: str = "") -> dict:
    """Coerce arbitrary model output into a valid reminder dict. Idempotent."""
    data = raw if isinstance(raw, dict) else {}

    title = data.get("title")
    title = title.strip() if isinstance(title, str) else ""
    if not title:
        title = fallback_text.strip() or "Reminder"
    title = title[:MAX_TITLE_LENGTH].strip() or "Reminder"

    rtype = data.get("type")
    rtype = rtype.strip().lower() if isinstance(rtype, str) else ""
    if rtype not in VALID_TYPES:
        rtype = "time"

    priority = data.get("priority")
    priority = priority.strip().lower() if isinstance(priority, str) else ""
    if priority not in VALID_PRIORITIES:
        priority = "medium"

    return {
        "title": title,
        "type": rtype,
        "scheduled_at": normalize_scheduled_at(data.get("scheduled_at")),
        "priority": priority,
        "offsets": normalize_offsets(data.get("offsets")),
    }


_TIME_HINT_RE = re.compile(r"\d\s*(?::\d{2}|am|pm|a\.m\.|p\.m\.)|noon|midnight|morning|evening|night", re.I)
_TZ_SUFFIX_RE = re.compile(r"(Z|[+-]\d{2}:?\d{2})$")


def detect_ambiguities(parsed: dict, original_text: str, now: datetime) -> list[dict]:
    """Things the user must confirm before the reminder is created (product
    principle: AI suggests, the user confirms). Pure; `parsed` is the output of
    normalize_reminder. Each item is {"code", "message"}."""
    found: list[dict] = []
    scheduled = parsed.get("scheduled_at")
    if scheduled is None:
        if parsed.get("type") != "recurring":
            found.append({"code": "no_date", "message": "No date or time was found. When should this fire?"})
        return found

    value = datetime.fromisoformat(scheduled.replace("Z", "+00:00"))
    if not _TZ_SUFFIX_RE.search(scheduled):
        found.append({"code": "no_timezone", "message": "No timezone was given; your device timezone will be used."})
        compare_now = now.replace(tzinfo=None)
    else:
        compare_now = now if now.tzinfo else now.replace(tzinfo=timezone.utc)
    if value <= compare_now:
        found.append({"code": "in_past", "message": "That time has already passed. Did you mean a later date?"})
    if value.hour == 0 and value.minute == 0 and not _TIME_HINT_RE.search(original_text):
        found.append({"code": "time_assumed", "message": "No time of day was given; midnight was assumed. What time?"})
    return found
