import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
import json

import pytest
from hypothesis import given, strategies as st
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.database import Base
from app.models.capture import Capture
from app.services.capture_ai import build_prompt, parse_summary, process_text_capture


def test_prompt_includes_today_and_the_text_and_forbids_inventing_dates():
    p = build_prompt("I must submit by Oct 20", "2026-10-02")
    assert "Today is 2026-10-02" in p and "I must submit by Oct 20" in p and "Never invent a date" in p


def test_parses_clean_json():
    r = parse_summary('{"summary": "S", "topics": ["a"], "key_points": ["k"], "actions": [{"title": "Ship", "due_at": "2026-10-20"}]}')
    assert r == {"summary": "S", "topics": ["a"], "key_points": ["k"], "actions": [{"title": "Ship", "due_at": "2026-10-20"}]}


def test_parses_fenced_and_chatty_replies():
    r = parse_summary('Sure!\n```json\n{"summary": "S", "actions": [{"title": "Go", "due_at": "null"}]}\n```\nHope that helps')
    assert r["summary"] == "S" and r["actions"] == [{"title": "Go", "due_at": None}]


def test_unusable_reply_falls_back_to_the_raw_text():
    assert parse_summary("just words, no json")["summary"] == "just words, no json"
    assert parse_summary("{broken")["actions"] == []


@given(st.text(max_size=300))
def test_never_raises_and_always_has_the_four_keys(raw):
    r = parse_summary(raw)
    assert set(r) == {"summary", "topics", "key_points", "actions"}
    assert isinstance(r["summary"], str) and len(r["topics"]) <= 8


@pytest.fixture
def factory():
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})

    async def setup():
        async with engine.begin() as c:
            await c.run_sync(Base.metadata.create_all)

    asyncio.run(setup())
    return async_sessionmaker(engine, expire_on_commit=False)


def add(factory, ctype="note", content="I need to ship by Oct 20"):
    async def go():
        async with factory() as s:
            s.add(Capture(id="c1", user_id="u1", capture_type=ctype, content=content, processing_status="queued"))
            await s.commit()

    asyncio.run(go())


def load(factory):
    async def go():
        async with factory() as s:
            return await s.get(Capture, "c1")

    return asyncio.run(go())


def test_note_is_summarised_and_marked_processed(factory):
    add(factory)
    fake = lambda text: {"summary": "Plan", "topics": ["Shipping"], "key_points": ["k"], "actions": [{"title": "Ship", "due_at": "2026-10-20"}]}
    asyncio.run(process_text_capture("c1", factory, fake))
    c = load(factory)
    assert c.processing_status == "processed" and c.ai_summary == "Plan"
    assert json.loads(c.ai_actions) == [{"title": "Ship", "due_at": "2026-10-20"}]
    assert c.to_dict()["ai_result"]["actions"][0]["title"] == "Ship"


def test_model_failure_marks_failed_not_stuck(factory):
    add(factory)

    def boom(text):
        raise RuntimeError("AI service down")

    asyncio.run(process_text_capture("c1", factory, boom))
    assert load(factory).processing_status == "failed"


def test_link_is_processed_without_calling_the_model(factory):
    add(factory, ctype="link", content="https://example.com")

    def must_not_call(text):
        raise AssertionError("the model must not be called for links")

    asyncio.run(process_text_capture("c1", factory, must_not_call))
    c = load(factory)
    assert c.processing_status == "processed" and "https://example.com" in c.ai_summary


def test_missing_capture_and_media_captures_are_ignored(factory):
    asyncio.run(process_text_capture("nope", factory, lambda t: {}))  # no crash
    add(factory, ctype="photo")
    asyncio.run(process_text_capture("c1", factory, lambda t: {"summary": "x", "topics": [], "key_points": [], "actions": []}))
    assert load(factory).processing_status == "queued", "media is handled by the pipeline, not here"
