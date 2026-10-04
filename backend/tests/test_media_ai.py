import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import pytest
from hypothesis import given, strategies as st

from app.services.media_ai import (
    MAX_DOCUMENT_BYTES, MAX_IMAGE_BYTES, UnsupportedMedia, build_request, check_size, detect, media_prompt,
)

KEY = "users/u1/events/e1/photo/c1"


@pytest.mark.parametrize("ext,fmt", [("jpg", "jpeg"), ("JPEG", "jpeg"), ("png", "png"), ("webp", "webp"), ("gif", "gif")])
def test_photos_map_to_converse_image_formats(ext, fmt):
    assert detect(f"{KEY}.{ext}", "photo") == ("image", fmt)


@pytest.mark.parametrize("ext,kind,fmt", [("pdf", "document", "pdf"), ("docx", "document", "docx"), ("txt", "document", "txt"), ("png", "image", "png")])
def test_documents_include_scanned_pictures(ext, kind, fmt):
    assert detect(f"{KEY}.{ext}", "document") == (kind, fmt)


@pytest.mark.parametrize("key,ctype", [(f"{KEY}.heic", "photo"), (f"{KEY}.exe", "document"), (f"{KEY}", "photo"), (f"{KEY}.pdf", "photo")])
def test_unknown_types_are_refused_with_a_clear_message(key, ctype):
    with pytest.raises(UnsupportedMedia):
        detect(key, ctype)


def test_size_limits():
    check_size("image", MAX_IMAGE_BYTES)
    check_size("document", MAX_DOCUMENT_BYTES)
    with pytest.raises(UnsupportedMedia, match="too large"):
        check_size("image", MAX_IMAGE_BYTES + 1)
    with pytest.raises(UnsupportedMedia, match="too large"):
        check_size("document", MAX_DOCUMENT_BYTES + 1)
    with pytest.raises(UnsupportedMedia, match="empty"):
        check_size("image", 0)


def test_image_request_has_the_image_block_then_the_prompt():
    r = build_request("m", "image", "png", b"\x89PNG-bytes", "Describe it")
    content = r["messages"][0]["content"]
    assert content[0] == {"image": {"format": "png", "source": {"bytes": b"\x89PNG-bytes"}}}
    assert content[1] == {"text": "Describe it"}
    assert r["modelId"] == "m" and "guardrailConfig" not in r


def test_document_request_uses_a_neutral_name_not_the_filename():
    r = build_request("m", "document", "pdf", b"%PDF", "Summarise", guardrail_id="g", guardrail_version="1")
    doc = r["messages"][0]["content"][0]["document"]
    assert doc["format"] == "pdf" and doc["name"] == "captured document"
    assert r["guardrailConfig"] == {"guardrailIdentifier": "g", "guardrailVersion": "1"}


def test_oversized_files_never_reach_the_model():
    with pytest.raises(UnsupportedMedia):
        build_request("m", "image", "png", b"x" * (MAX_IMAGE_BYTES + 1), "p")


def test_prompt_asks_for_the_same_json_as_text_notes():
    p = media_prompt("image", "2026-10-04")
    assert "photo" in p and "Today is 2026-10-04" in p and '"actions"' in p
    assert "document" in media_prompt("document")


@given(st.text(max_size=40), st.sampled_from(["photo", "document", "voice", "note"]))
def test_detect_only_returns_known_pairs_or_raises(key, ctype):
    try:
        kind, fmt = detect(key, ctype)
    except UnsupportedMedia:
        return
    assert kind in ("image", "document") and fmt
