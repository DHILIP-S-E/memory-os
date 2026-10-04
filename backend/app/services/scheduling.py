"""
Reminder scheduling (spec R1.4, R1.5, R7.3).

Pure functions compute *when* notifications fire; the boto3 helpers register
one EventBridge Scheduler one-time schedule per fire time. The LLM never
schedules — it only parses (see reminder_parser).
"""

import json
from datetime import datetime, timedelta, timezone

import boto3

from app.config import settings
from app.services.recurrence import to_schedule_expression
from app.services.reminder_parser import offset_to_minutes


def _utc(dt: datetime) -> datetime:
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


def fire_instants(scheduled_at: datetime, offsets: list[str]) -> set[datetime]:
    """scheduled_at itself plus each valid offset before it (UTC, unfiltered)."""
    target = _utc(scheduled_at)
    instants = {target}
    for offset in offsets:
        minutes = offset_to_minutes(offset)
        if minutes:
            instants.add(target - timedelta(minutes=minutes))
    return instants


def compute_fire_times(
    scheduled_at: datetime, offsets: list[str], now: datetime | None = None
) -> list[datetime]:
    """Strictly-future fire instants, sorted ascending and unique."""
    now = _utc(now or datetime.now(timezone.utc))
    return sorted(t for t in fire_instants(scheduled_at, offsets) if t > now)


def in_quiet_hours(hour: int, start: int = 22, end: int = 7) -> bool:
    """True if a local hour (0-23) falls in the quiet window; window may wrap midnight."""
    if start == end:
        return False
    return start <= hour < end if start < end else (hour >= start or hour < end)


def recurring_schedule_name(reminder_id: str) -> str:
    return f"rem-{reminder_id}-rec"[:64]


def schedule_name(reminder_id: str, fire_at: datetime) -> str:
    return f"rem-{reminder_id}-{int(_utc(fire_at).timestamp())}"[:64]


_client = None


def _scheduler():
    global _client
    if _client is None:
        _client = boto3.client("scheduler", region_name=settings.aws_region)
    return _client


def _configured() -> bool:
    return bool(settings.scheduler_target_arn and settings.scheduler_role_arn)


def schedule_reminder(
    reminder_id: str,
    user_id: str,
    title: str,
    priority: str,
    scheduled_at: datetime,
    offsets: list[str],
    depends_on_id: str | None = None,
    recurrence_rule: str | None = None,
    timezone_name: str = "UTC",
) -> list[str]:
    """Create one-time EventBridge schedules; returns their names.
    Returns [] when the cloud layer is not configured — the device layer
    still fires locally."""
    if not _configured():
        return []
    created = []
    expression = to_schedule_expression(recurrence_rule, scheduled_at) if recurrence_rule else None
    if expression:
        # One recurring schedule replaces the per-offset one-time schedules.
        name = recurring_schedule_name(reminder_id)
        _scheduler().create_schedule(
            Name=name,
            GroupName=settings.scheduler_group,
            ScheduleExpression=expression,
            ScheduleExpressionTimezone=timezone_name,
            StartDate=_utc(scheduled_at),
            FlexibleTimeWindow={"Mode": "OFF"},
            Target={
                "Arn": settings.scheduler_target_arn,
                "RoleArn": settings.scheduler_role_arn,
                "Input": json.dumps({
                    "reminder_id": reminder_id,
                    "user_id": user_id,
                    "title": title,
                    "priority": priority,
                    "fire_at": _utc(scheduled_at).isoformat(),
                    "depends_on_id": depends_on_id,
                    "timezone": timezone_name,
                    "recurring": True,
                }),
            },
        )
        return [name]
    for fire_at in compute_fire_times(scheduled_at, offsets):
        name = schedule_name(reminder_id, fire_at)
        _scheduler().create_schedule(
            Name=name,
            GroupName=settings.scheduler_group,
            ScheduleExpression=f"at({fire_at.strftime('%Y-%m-%dT%H:%M:%S')})",
            FlexibleTimeWindow={"Mode": "OFF"},
            ActionAfterCompletion="DELETE",
            Target={
                "Arn": settings.scheduler_target_arn,
                "RoleArn": settings.scheduler_role_arn,
                "Input": json.dumps({
                    "reminder_id": reminder_id,
                    "user_id": user_id,
                    "title": title,
                    "priority": priority,
                    "fire_at": fire_at.isoformat(),
                    "depends_on_id": depends_on_id,
                    "timezone": timezone_name,
                }),
            },
        )
        created.append(name)
    return created


def cancel_reminder(reminder_id: str, scheduled_at: datetime | None, offsets: list[str]) -> None:
    """Delete pending schedules for a reminder. Missing schedules are ignored."""
    if not _configured() or scheduled_at is None:
        return
    client = _scheduler()
    try:
        client.delete_schedule(
            Name=recurring_schedule_name(reminder_id), GroupName=settings.scheduler_group
        )
    except client.exceptions.ResourceNotFoundException:
        pass
    for fire_at in fire_instants(scheduled_at, offsets):
        try:
            client.delete_schedule(
                Name=schedule_name(reminder_id, fire_at), GroupName=settings.scheduler_group
            )
        except client.exceptions.ResourceNotFoundException:
            pass
