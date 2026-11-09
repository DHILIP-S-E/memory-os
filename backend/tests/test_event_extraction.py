"""What the model says about an event is cleaned before anyone sees it."""

import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import asyncio
import json
from datetime import datetime

import pytest
from fastapi.testclient import TestClient
from hypothesis import given, strategies as st
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
import app.services.llm_service as llm_service
from app.config import settings
from app.database import Base, get_db
from app.main import app
from app.services.event_extraction import normalize_extraction as norm

PAGE = (
    "AWS Student Hackathon. Register by 5 November 2026 at https://example.org/register. "
    "The event runs 20-21 November 2026 in Chennai. Submissions close 22 November 2026."
)


def good(**kw):
    return {
        "title": "AWS Student Hackathon", "event_type": "hackathon",
        "start_at": "2026-11-20T09:00:00", "end_at": "2026-11-21T18:00:00",
        "registration_deadline": "2026-11-05T23:59:00", "submission_deadline": "2026-11-22T23:59:00",
        "registration_url": "https://example.org/register", "location": "Chennai",
        "assumed_times": ["start_at", "registration_deadline"],
        "evidence": {"registration_deadline": "Register by 5 November 2026"},
        **kw,
    }


def test_a_good_answer_passes_through_and_is_marked_for_review():
    out = norm(good(), PAGE)
    assert out["title"] == "AWS Student Hackathon" and out["event_type"] == "hackathon"
    assert out["registration_deadline"] == "2026-11-05T23:59:00"
    assert out["registration_url"] == "https://example.org/register"
    assert out["needs_user_review"] is True and out["missing_fields"] == []
    assert out["assumed_times"] == ["start_at", "registration_deadline"]
    assert out["evidence"] == {"registration_deadline": "Register by 5 November 2026"}


def test_a_date_that_does_not_parse_becomes_null_and_is_reported_missing():
    out = norm(good(registration_deadline="next Friday-ish", start_at="32/13/2026"), PAGE)
    assert out["registration_deadline"] is None and out["start_at"] is None
    assert {"start_at", "registration_deadline"} <= set(out["missing_fields"])
    assert "registration_deadline" not in out["assumed_times"], "no assumed time for a date that is not there"


@pytest.mark.parametrize("bad", ["javascript:alert(1)", "data:text/html,x", "ftp://x.co", "example.org", "http://", 42, None])
def test_links_that_are_not_http_are_dropped(bad):
    out = norm(good(registration_url=bad, event_url=bad), PAGE)
    assert out["registration_url"] is None and out["event_url"] is None


def test_the_page_address_fills_in_a_missing_event_link_only_if_it_is_http():
    assert norm(good(), PAGE, "https://example.org/hack")["event_url"] == "https://example.org/hack"
    assert norm(good(), PAGE, "javascript:alert(1)")["event_url"] is None


def test_evidence_that_is_not_in_the_text_is_thrown_away():
    out = norm(good(evidence={
        "registration_deadline": "Register by 5 November 2026",
        "submission_deadline": "Submissions close on 1 January 2099",   # invented
        "location": "Chennai",                                          # location is not a date or link field
    }), PAGE)
    assert out["evidence"] == {"registration_deadline": "Register by 5 November 2026"}


def test_evidence_matching_ignores_case_and_spacing():
    out = norm(good(evidence={"registration_deadline": "REGISTER   BY 5 november 2026"}), PAGE)
    assert "registration_deadline" in out["evidence"]


def test_an_event_that_ends_before_it_starts_loses_the_end():
    out = norm(good(start_at="2026-11-21T09:00:00", end_at="2026-11-20T09:00:00"), PAGE)
    assert out["start_at"] == "2026-11-21T09:00:00" and out["end_at"] is None


def test_unknown_types_and_wrong_value_types_are_made_safe():
    out = norm({"title": 123, "event_type": "party", "is_virtual": "yes", "description": ["x"], "location": {"a": 1},
                "evidence": "not a dict", "assumed_times": "start_at", "ambiguous_dates": [1, "04/05/2027", ""]})
    assert out["title"] == "Event" and out["event_type"] == "custom" and out["is_virtual"] is False
    assert out["description"] is None and out["location"] is None and out["evidence"] == {}
    assert out["assumed_times"] == [] and out["ambiguous_dates"] == ["04/05/2027"]


def test_very_long_text_is_capped():
    out = norm({"title": "x" * 5000, "description": "y " * 5000})
    assert len(out["title"]) == 500 and len(out["description"]) <= 2000


JSON_LIKE = st.recursive(
    st.none() | st.booleans() | st.integers() | st.text(max_size=30),
    lambda kids: st.lists(kids, max_size=4) | st.dictionaries(st.text(max_size=12), kids, max_size=4),
    max_leaves=12,
)


@given(st.dictionaries(st.sampled_from(["title", "event_type", "start_at", "end_at", "registration_deadline", "event_url",
                                         "registration_url", "evidence", "assumed_times", "is_virtual", "location"]),
                       JSON_LIKE, max_size=8))
def test_whatever_the_model_returns_the_output_is_always_valid(raw):
    out = norm(raw, PAGE)
    assert out["needs_user_review"] is True and isinstance(out["title"], str) and out["title"]
    for field in ("start_at", "end_at", "registration_deadline", "submission_deadline"):
        assert out[field] is None or datetime.fromisoformat(out[field])
    for field in ("event_url", "registration_url"):
        assert out[field] is None or out[field].startswith(("http://", "https://"))
    assert out["event_type"] in {"hackathon", "conference", "workshop", "webinar", "meetup", "meeting", "appointment", "deadline", "custom"}
    assert set(out["evidence"]) <= {f for f in out if out[f]}


# --- over HTTP ------------------------------------------------------------------------------

@pytest.fixture
def client(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})

    async def setup():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(setup())
    Session = async_sessionmaker(engine, expire_on_commit=False)

    async def override():
        async with Session() as s:
            yield s

    app.dependency_overrides[get_db] = override
    monkeypatch.setattr(settings, "jwt_secret", "q" * 48)
    hostile = good(registration_url="javascript:alert(1)", evidence={"submission_deadline": "made up quote"})
    monkeypatch.setattr(llm_service, "_invoke", lambda *a, **k: "Sure! " + json.dumps(hostile))
    yield TestClient(app)
    app.dependency_overrides.clear()


def headers(client):
    r = client.post("/auth/register", json={"email": "ada@example.com", "password": "correct horse"})
    headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.put("/account/settings", headers=headers, json={"ai_enabled": True}).status_code == 200  # opt-in
    return headers


def test_the_endpoint_returns_only_the_cleaned_proposal(client):
    out = client.post("/ai/extract-event", headers=headers(client), json={"text": PAGE, "source_url": "https://example.org/hack"}).json()
    assert out["registration_url"] is None, "the unsafe link the model produced is gone"
    assert out["evidence"] == {}, "so is the quote that is not in the page"
    assert out["event_url"] == "https://example.org/hack" and out["needs_user_review"] is True


@pytest.mark.parametrize("body", [{"text": ""}, {"text": "   "}, {"text": "x" * 20_001}, {"text": "ok", "source_url": "javascript:alert(1)"}],
                         ids=["empty", "blank", "too-long", "bad-source"])
def test_bad_requests_are_rejected_before_the_model_is_called(client, body):
    assert client.post("/ai/extract-event", headers=headers(client), json=body).status_code == 422
