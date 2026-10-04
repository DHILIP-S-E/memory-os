"""
Photos and documents -> notes, using Amazon Nova's own image/document understanding
through the Converse API. No extra service: one model call, a fraction of a cent per photo.

Pure helpers (kind detection, size rules, request building) so they are easy to test;
the worker does the S3 read and the call.
"""

import os

# Converse limits for Amazon Nova (bytes). Larger files are refused, not truncated.
MAX_IMAGE_BYTES = 3_750_000
MAX_DOCUMENT_BYTES = 4_500_000

_IMAGE_FORMATS = {"jpg": "jpeg", "jpeg": "jpeg", "png": "png", "gif": "gif", "webp": "webp"}
_DOCUMENT_FORMATS = {"pdf": "pdf", "txt": "txt", "md": "md", "csv": "csv", "doc": "doc",
                     "docx": "docx", "xls": "xls", "xlsx": "xlsx", "html": "html"}


class UnsupportedMedia(ValueError):
    """The file cannot be summarised (unknown type or too large). The message is user-safe."""


def detect(key: str, capture_type: str) -> tuple[str, str]:
    """('image' | 'document', converse_format) from the object key's extension.
    capture_type is the app's own label (photo, document) and decides which table applies."""
    ext = os.path.splitext(key)[1].lower().lstrip(".")
    if capture_type == "photo":
        if ext in _IMAGE_FORMATS:
            return "image", _IMAGE_FORMATS[ext]
    elif capture_type == "document":
        if ext in _DOCUMENT_FORMATS:
            return "document", _DOCUMENT_FORMATS[ext]
        if ext in _IMAGE_FORMATS:  # a scanned page saved as a picture
            return "image", _IMAGE_FORMATS[ext]
    raise UnsupportedMedia(f"Cannot analyse a .{ext or '?'} {capture_type}")


def check_size(kind: str, size: int) -> None:
    limit = MAX_IMAGE_BYTES if kind == "image" else MAX_DOCUMENT_BYTES
    if size > limit:
        raise UnsupportedMedia(f"File is too large to analyse ({size // 1024} KB; limit {limit // 1024} KB)")
    if size == 0:
        raise UnsupportedMedia("File is empty")


def build_request(
    model_id: str,
    kind: str,
    fmt: str,
    data: bytes,
    prompt: str,
    max_tokens: int = 800,
    guardrail_id: str = "",
    guardrail_version: str = "",
) -> dict:
    """Keyword arguments for bedrock-runtime `converse` with the file attached."""
    check_size(kind, len(data))
    if kind == "image":
        block = {"image": {"format": fmt, "source": {"bytes": data}}}
    else:
        # Converse requires a name; keep it neutral so a filename cannot steer the model.
        block = {"document": {"format": fmt, "name": "captured document", "source": {"bytes": data}}}
    request = {
        "modelId": model_id,
        "messages": [{"role": "user", "content": [block, {"text": prompt}]}],
        "inferenceConfig": {"maxTokens": max_tokens, "temperature": 0.1},
    }
    if guardrail_id and guardrail_version:
        request["guardrailConfig"] = {"guardrailIdentifier": guardrail_id, "guardrailVersion": guardrail_version}
    return request


def media_prompt(kind: str, today_iso: str | None = None) -> str:
    """The text prompt that goes with the file: what to extract, as notes."""
    from app.services.capture_ai import build_prompt

    what = "photo (for example a slide, whiteboard or note)" if kind == "image" else "document"
    return build_prompt(
        f"The attached file is a {what}. Read any text in it and describe what it shows or says, "
        "then summarise it as notes.",
        today_iso,
    )
