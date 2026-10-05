"""
Lambda: SQS -> capture processing (S3 upload -> EventBridge -> SQS -> here).

Two kinds of messages arrive on the queue:

1. A new capture object under users/...  -> start extraction.
   * notes/links: summarise the stored text directly.
   * photos/documents: start a Bedrock Data Automation job (async).
   * voice: start an Amazon Transcribe job (async).
2. A result object under processed/...   -> finish the capture.
   Transcribe and BDA write their output there; we read the text, summarise
   with the Bedrock text model, and store the AI result (spec R3.4-R3.7).

Partial batch failures are reported so SQS retries only failed messages and,
after maxReceiveCount, moves them to the DLQ.
"""

import json
import logging
import os
import re
from datetime import datetime, timezone

import boto3
import psycopg2

from app.db_url import sync_database_url
from app.services.action_items import normalize_actions
from app.services import media_ai
from app.services.capture_ai import build_prompt, parse_summary
from app.services.converse import build_request, extract_text

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_KEY_RE = re.compile(
    r"users/(?P<user>[^/]+)/(?:events/(?P<event>[^/]+)/|misc/)(?P<type>[^/]+)/(?P<id>[^./]+)\."
)
_TRANSCRIBE_RESULT_RE = re.compile(
    r"^users/[^/]+/(?:events/[^/]+/|misc/)[^/]+/[^/]+\.json$"
)
PROCESSED_PREFIX = "processed/"


class AsyncJobStarted(Exception):
    """An async extraction job was started; a later result message finishes the capture."""


class NotRegisteredYet(Exception):
    """The file reached S3 before the app registered it in the database (slow or offline
    sync). Raising lets SQS redeliver the message instead of losing the result."""


def parse_s3_key(key: str) -> dict | None:
    """users/{user}/events/{event}/{type}/{id}.ext -> parts; None if not a capture key."""
    match = _KEY_RE.match(key)
    return match.groupdict() if match else None


def parse_result_key(key: str) -> dict | None:
    """processed/<original capture key>[/...]/result.json -> the capture's parts.

    Only real result files count: Transcribe's `<key>.json` and BDA's
    `.../standard_output/<n>/result.json`. BDA's job_metadata.json is ignored."""
    if not key.startswith(PROCESSED_PREFIX):
        return None
    inner = key[len(PROCESSED_PREFIX):]
    is_bda = inner.endswith("/result.json") and "/standard_output/" in inner
    is_transcribe = bool(_TRANSCRIBE_RESULT_RE.match(inner))
    if not (is_bda or is_transcribe):
        return None
    match = _KEY_RE.search(inner)
    return match.groupdict() if match else None


def s3_keys(body: dict) -> list[str]:
    """Object keys from an S3 notification, direct or delivered via EventBridge."""
    if "Records" in body:
        return [r["s3"]["object"]["key"] for r in body["Records"]]
    key = body.get("detail", {}).get("object", {}).get("key")
    return [key] if key else []


def text_from_result(result: dict) -> str:
    """Readable text out of a Transcribe or Bedrock Data Automation result document."""
    def obj(value) -> dict:
        return value if isinstance(value, dict) else {}

    def text(value) -> str:
        return value if isinstance(value, str) else ""

    parts: list[str] = []
    transcripts = obj(result.get("results")).get("transcripts")
    if isinstance(transcripts, list):
        parts.append(" ".join(text(obj(t).get("transcript")) for t in transcripts))
    doc = obj(result.get("document"))
    parts.append(text(obj(doc.get("representation")).get("markdown")))
    parts.append(text(doc.get("summary")))
    image = obj(result.get("image"))
    parts.append(text(image.get("summary")))
    lines = image.get("text_lines")
    if isinstance(lines, list):
        parts.extend(text(obj(line).get("text")) for line in lines)
    parts.append(text(obj(result.get("audio")).get("summary")))
    return "\n".join(p for p in parts if p.strip())


def _guardrail():
    return {
        "guardrail_id": os.environ.get("GUARDRAIL_ID", ""),
        "guardrail_version": os.environ.get("GUARDRAIL_VERSION", ""),
    }


def summarise(text: str) -> dict:
    request = build_request(
        os.environ["BEDROCK_MODEL_FAST"], build_prompt(text), max_tokens=800, **_guardrail()
    )
    return parse_summary(extract_text(boto3.client("bedrock-runtime").converse(**request)))


def summarise_media(bucket: str, key: str, capture_type: str) -> dict:
    """Photo or document: let Nova read it directly. Raises UnsupportedMedia (with a
    user-safe reason) for unknown types and files over the model's size limit."""
    kind, fmt = media_ai.detect(key, capture_type)
    s3 = boto3.client("s3")
    media_ai.check_size(kind, s3.head_object(Bucket=bucket, Key=key)["ContentLength"])  # before downloading
    data = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    request = media_ai.build_request(
        os.environ["BEDROCK_MODEL_FAST"], kind, fmt, data, media_ai.media_prompt(kind), **_guardrail()
    )
    return parse_summary(extract_text(boto3.client("bedrock-runtime").converse(**request)))


def _start_extraction(capture_type: str, bucket: str, key: str) -> None:
    project_arn = os.environ.get("BDA_PROJECT_ARN")
    if capture_type in ("photo", "document") and project_arn:
        boto3.client("bedrock-data-automation-runtime").invoke_data_automation_async(
            inputConfiguration={"s3Uri": f"s3://{bucket}/{key}"},
            outputConfiguration={"s3Uri": f"s3://{bucket}/{PROCESSED_PREFIX}{key}/"},
            dataAutomationConfiguration={"dataAutomationProjectArn": project_arn, "stage": "LIVE"},
            dataAutomationProfileArn=os.environ["BDA_PROFILE_ARN"],
        )
        raise AsyncJobStarted(key)
    if capture_type == "voice":
        transcribe = boto3.client("transcribe")
        try:
            transcribe.start_transcription_job(
                TranscriptionJobName=f"capture-{os.path.basename(key).split('.')[0]}",
                IdentifyLanguage=True,
                Media={"MediaFileUri": f"s3://{bucket}/{key}"},
                OutputBucketName=bucket,
                OutputKey=f"{PROCESSED_PREFIX}{key}.json",
            )
        except transcribe.exceptions.ConflictException:
            pass  # a retried message: the job is already running
        raise AsyncJobStarted(key)


def _stored_text(conn, capture_id: str) -> str:
    with conn.cursor() as cur:
        cur.execute("SELECT content FROM captures WHERE id=%s", (capture_id,))
        row = cur.fetchone()
    return row[0] if row and row[0] else ""


def _set_status(conn, capture_id: str, status: str) -> bool:
    """Returns False when there is no such capture row (yet)."""
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE captures SET processing_status=%s, updated_at=now() WHERE id=%s",
            (status, capture_id),
        )
        found = cur.rowcount > 0
    conn.commit()
    return found


def _store_summary(conn, capture_id: str, result: dict, transcript_text: str | None = None) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE captures SET processing_status='processed', ai_summary=%s, ai_topics=%s, "
            "ai_key_points=%s, ai_actions=%s, "
            "transcription=COALESCE(%s, transcription), updated_at=now() WHERE id=%s",
            (
                result.get("summary", ""),
                json.dumps(result.get("topics", [])),
                json.dumps(result.get("key_points", [])),
                json.dumps(normalize_actions(result.get("actions"))),
                transcript_text,
                capture_id,
            ),
        )
    conn.commit()


def _store_result(conn, capture_id: str, text: str, transcript: bool) -> None:
    result = summarise(text) if text.strip() else {"summary": ""}
    _store_summary(conn, capture_id, result, text if transcript else None)


def _store_failure(conn, capture_id: str, reason: str) -> None:
    """Failed, but say why: the reason shows in the app instead of a silent spinner."""
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE captures SET processing_status='failed', ai_summary=%s, updated_at=now() WHERE id=%s",
            (f"Could not analyse this file: {reason}", capture_id),
        )
    conn.commit()


def _process_text_capture(conn, capture_id: str) -> None:
    """Notes and links: no S3 object, the text lives in the captures table."""
    with conn.cursor() as cur:
        cur.execute("SELECT capture_type, content FROM captures WHERE id=%s", (capture_id,))
        row = cur.fetchone()
    if not row:
        logger.warning("Capture %s not found", capture_id)
        return
    capture_type, content = row
    _set_status(conn, capture_id, "processing")
    if capture_type == "link":
        # Fetching and reading arbitrary pages is out of scope; keep the link itself.
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE captures SET processing_status='processed', ai_summary=%s, "
                "updated_at=now() WHERE id=%s",
                (f"Saved link: {content}", capture_id),
            )
        conn.commit()
        return
    _store_result(conn, capture_id, content or "", transcript=False)


def _process_new(conn, bucket: str, key: str) -> None:
    parts = parse_s3_key(key)
    if not parts:
        logger.info("Ignoring non-capture key %s", key)
        return
    capture_id = parts["id"]
    if not _set_status(conn, capture_id, "processing"):
        raise NotRegisteredYet(capture_id)
    text = _stored_text(conn, capture_id)
    if not text:
        if parts["type"] in ("photo", "document") and not os.environ.get("BDA_PROJECT_ARN"):
            try:
                _store_summary(conn, capture_id, summarise_media(bucket, key, parts["type"]))
            except media_ai.UnsupportedMedia as exc:
                _store_failure(conn, capture_id, str(exc))
            return
        _start_extraction(parts["type"], bucket, key)  # raises AsyncJobStarted
    _store_result(conn, capture_id, text, transcript=False)


def _process_result(conn, bucket: str, key: str, parts: dict) -> None:
    body = boto3.client("s3").get_object(Bucket=bucket, Key=key)["Body"].read()
    text = text_from_result(json.loads(body))
    _store_result(conn, parts["id"], text, transcript=parts["type"] == "voice")


def process_key(conn, bucket: str, key: str) -> None:
    result_parts = parse_result_key(key)
    if result_parts:
        _process_result(conn, bucket, key, result_parts)
    elif key.startswith(PROCESSED_PREFIX):
        logger.info("Ignoring auxiliary output %s", key)
    else:
        _process_new(conn, bucket, key)


def _failed_capture_id(key: str) -> str | None:
    parts = parse_result_key(key) or parse_s3_key(key)
    return parts["id"] if parts else None


def handler(event, _context):
    bucket = os.environ["CAPTURE_BUCKET"]
    conn = psycopg2.connect(sync_database_url())
    failures = []
    try:
        for record in event["Records"]:
            try:
                body = json.loads(record["body"])
                if "capture_id" in body:
                    try:
                        _process_text_capture(conn, body["capture_id"])
                    except Exception:
                        logger.exception("Text capture failed: %s", body["capture_id"])
                        conn.rollback()
                        _set_status(conn, body["capture_id"], "failed")
                        raise
                    continue
                for key in s3_keys(body):
                    try:
                        process_key(conn, bucket, key)
                    except AsyncJobStarted:
                        pass
                    except Exception:
                        logger.exception("Processing failed for %s", key)
                        conn.rollback()
                        capture_id = _failed_capture_id(key)
                        if capture_id:
                            _set_status(conn, capture_id, "failed")
                        raise
            except Exception:
                failures.append({"itemIdentifier": record["messageId"]})
    finally:
        conn.close()
    return {"batchItemFailures": failures}
