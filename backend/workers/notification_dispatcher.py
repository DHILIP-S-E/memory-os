"""
Lambda: EventBridge Scheduler -> SNS push (cloud layer of the two-layer alarm).

Invoked at each reminder fire time with the payload written by
app.services.scheduling. Publishes to the notifications SNS topic (fans out to
APNs/FCM platform endpoints) and records every attempt in notification_deliveries
(spec R7.4). Quiet hours (R7.3) suppress non-critical pushes; the device layer
still fires locally.
"""

import json
import logging
import os
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import boto3
import psycopg2

from app.db_url import sync_database_url
from app.services.conditions import should_fire

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_sns = None


def in_quiet_hours(hour: int, start: int = 22, end: int = 7) -> bool:
    if start == end:
        return False
    return start <= hour < end if start < end else (hour >= start or hour < end)


def should_suppress(priority: str, fire_at: datetime, timezone_name: str | None = None) -> bool:
    """High-priority reminders always ring; others respect quiet hours in the user's
    own timezone. Without a real timezone ("UTC" is the app's default, not a place) we do NOT
    suppress: quiet hours measured in the wrong zone would silently drop daytime reminders."""
    if priority == "high" or not timezone_name or timezone_name.upper() == "UTC":
        return False
    try:
        local = fire_at.astimezone(ZoneInfo(timezone_name))
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return in_quiet_hours(local.hour)


def build_message(title: str) -> dict:
    """SNS message body (MessageStructure=json): only protocol keys are allowed, and
    `default` is required. Email and any protocol without its own key use `default`."""
    return {"default": title + "\n\nOpen Personal Memory OS to snooze or complete it."}


def email_subject(title: str) -> str:
    """SNS email subjects: ASCII only, no line breaks, at most 100 characters."""
    clean = "".join(ch for ch in f"Reminder: {title}" if 32 <= ord(ch) < 127)
    return clean[:100]


def _record(conn, reminder_id, user_id, status, fire_at, message_id=None, error=None):
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO notification_deliveries "
            "(id, reminder_id, user_id, channel, status, fire_at, message_id, error, created_at) "
            "VALUES (%s,%s,%s,'push',%s,%s,%s,%s,now())",
            (str(uuid.uuid4()), reminder_id, user_id, status, fire_at, message_id, error),
        )
    conn.commit()


def _dependency_status(conn, depends_on_id, user_id):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT status FROM reminders WHERE id=%s AND user_id=%s", (depends_on_id, user_id)
        )
        row = cur.fetchone()
    return row[0] if row else None


def handler(event, _context):
    global _sns
    _sns = _sns or boto3.client("sns")
    reminder_id, user_id = event["reminder_id"], event["user_id"]
    fire_at = datetime.fromisoformat(event["fire_at"])
    conn = psycopg2.connect(sync_database_url())
    try:
        _record(conn, reminder_id, user_id, "triggered", fire_at)
        depends_on = event.get("depends_on_id")
        if depends_on and not should_fire(_dependency_status(conn, depends_on, user_id)):
            logger.info("Condition met, skipping %s", reminder_id)
            _record(conn, reminder_id, user_id, "cancelled", fire_at)
            return {"skipped": True}
        if should_suppress(event.get("priority", "medium"), fire_at, event.get("timezone")):
            logger.info("Quiet hours: suppressed push for %s", reminder_id)
            _record(conn, reminder_id, user_id, "cancelled", fire_at, error="quiet hours")
            return {"suppressed": True}
        try:
            resp = _sns.publish(
                TopicArn=os.environ["NOTIFICATION_TOPIC_ARN"],
                Subject=email_subject(event["title"]),
                Message=json.dumps(build_message(event["title"])),
                MessageStructure="json",
                MessageAttributes={"user_id": {"DataType": "String", "StringValue": user_id}},
            )
            _record(conn, reminder_id, user_id, "sent", fire_at, message_id=resp["MessageId"])
            return {"sent": True, "message_id": resp["MessageId"]}
        except Exception as exc:  # never lose a reminder silently
            logger.exception("SNS publish failed")
            _record(conn, reminder_id, user_id, "failed", fire_at, error=str(exc)[:1000])
            raise
    finally:
        conn.close()
