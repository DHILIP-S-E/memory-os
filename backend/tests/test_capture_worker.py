"""The capture worker end to end, with fake AWS clients and a fake DB connection."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import json

import pytest

import workers.capture_processor as w

REPLY = json.dumps({
    "summary": "Slide about Bedrock Agents",
    "topics": ["Agents"],
    "key_points": ["Agents call tools"],
    "actions": [{"title": "Try AgentCore", "due_at": "2026-10-20"}],
})
PHOTO = "users/u1/events/e1/photo/c1.jpg"
VOICE = "users/u1/events/e1/voice/c2.m4a"


class FakeCursor:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=()):
        self.conn.statements.append((sql, params))

    def fetchone(self):
        return self.conn.row


class FakeConn:
    def __init__(self, row=None):
        self.statements, self.row, self.commits = [], row, 0

    def cursor(self):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        pass

    def updates(self):
        return [(s, p) for s, p in self.statements if s.strip().upper().startswith("UPDATE")]


class FakeS3:
    def __init__(self, size=1000, body=b"\xff\xd8jpeg"):
        self.size, self.body = size, body

    def head_object(self, Bucket, Key):
        return {"ContentLength": self.size}

    def get_object(self, Bucket, Key):
        import io
        return {"Body": io.BytesIO(self.body)}


class FakeRuntime:
    def __init__(self):
        self.requests = []

    def converse(self, **kw):
        self.requests.append(kw)
        return {"output": {"message": {"content": [{"text": REPLY}]}}, "stopReason": "end_turn"}


class FakeTranscribe:
    class exceptions:
        class ConflictException(Exception):
            pass

    def __init__(self, conflict=False):
        self.jobs, self.conflict = [], conflict

    def start_transcription_job(self, **kw):
        if self.conflict:
            raise self.exceptions.ConflictException("exists")
        self.jobs.append(kw)


@pytest.fixture
def aws(monkeypatch):
    monkeypatch.setenv("BEDROCK_MODEL_FAST", "apac.amazon.nova-lite-v1:0")
    monkeypatch.delenv("BDA_PROJECT_ARN", raising=False)
    monkeypatch.delenv("GUARDRAIL_ID", raising=False)
    clients = {"s3": FakeS3(), "bedrock-runtime": FakeRuntime(), "transcribe": FakeTranscribe()}
    monkeypatch.setattr(w.boto3, "client", lambda name, **kw: clients[name])
    return clients


def test_photo_is_read_by_nova_and_stored_as_processed(aws):
    conn = FakeConn(row=(None,))  # no stored text content
    w.process_key(conn, "bucket", PHOTO)
    sent = aws["bedrock-runtime"].requests[0]
    block = sent["messages"][0]["content"][0]
    assert block["image"]["format"] == "jpeg" and block["image"]["source"]["bytes"] == b"\xff\xd8jpeg"
    assert sent["modelId"] == "apac.amazon.nova-lite-v1:0"
    sql, params = conn.updates()[-1]
    assert "processing_status='processed'" in sql
    assert params[0] == "Slide about Bedrock Agents"
    assert json.loads(params[3]) == [{"title": "Try AgentCore", "due_at": "2026-10-20"}]


def test_oversized_photo_fails_with_a_reason_and_never_calls_the_model(aws):
    aws["s3"].size = 9_000_000
    conn = FakeConn(row=(None,))
    w.process_key(conn, "bucket", PHOTO)
    assert aws["bedrock-runtime"].requests == []
    sql, params = conn.updates()[-1]
    assert "processing_status='failed'" in sql and "too large" in params[0]


def test_unsupported_file_type_fails_with_a_reason(aws):
    conn = FakeConn(row=(None,))
    w.process_key(conn, "bucket", "users/u1/misc/photo/c9.heic")
    sql, params = conn.updates()[-1]
    assert "processing_status='failed'" in sql and ".heic" in params[0]


def test_voice_starts_a_transcription_job_instead(aws):
    conn = FakeConn(row=(None,))
    with pytest.raises(w.AsyncJobStarted):
        w._process_new(conn, "bucket", VOICE)
    job = aws["transcribe"].jobs[0]
    assert job["TranscriptionJobName"] == "capture-c2"
    assert job["OutputKey"] == f"processed/{VOICE}.json"


def test_a_retried_message_does_not_fail_when_the_job_already_exists(aws):
    aws["transcribe"].conflict = True
    with pytest.raises(w.AsyncJobStarted):  # still "started": the existing job will finish it
        w._process_new(FakeConn(row=(None,)), "bucket", VOICE)


def test_transcript_result_is_summarised_and_keeps_the_transcript(aws, monkeypatch):
    import io
    transcript = {"results": {"transcripts": [{"transcript": "I need to submit the prototype by October 20"}]}}
    aws["s3"].get_object = lambda Bucket, Key: {"Body": io.BytesIO(json.dumps(transcript).encode())}
    conn = FakeConn()
    w.process_key(conn, "bucket", f"processed/{VOICE}.json")
    sql, params = conn.updates()[-1]
    assert "transcription=COALESCE" in sql
    assert params[4] == "I need to submit the prototype by October 20"


def test_the_same_prompt_is_used_for_text_and_media(aws):
    from app.services.capture_ai import build_prompt

    assert '"actions"' in build_prompt("x") and "Never invent a date" in build_prompt("x")
    conn = FakeConn(row=(None,))
    w.process_key(conn, "bucket", PHOTO)
    text_block = aws["bedrock-runtime"].requests[0]["messages"][0]["content"][1]["text"]
    assert "Never invent a date" in text_block and "photo" in text_block
