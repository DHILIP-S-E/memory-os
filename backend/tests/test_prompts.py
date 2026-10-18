import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import pytest

from app.services.llm_service import _load_prompt, _render


@pytest.mark.parametrize(
    "name,values",
    [
        ("parse_reminder", dict(current_datetime="NOW", timezone="UTC", input="hi")),
        ("extract_event", dict(current_date="TODAY", text="hi")),
        ("memory_qa", dict(context="CTX", question="Q?")),
        ("summarize_event", dict(event_title="T", event_date="D", captures_text="C")),
    ],
)
def test_prompt_renders_with_literal_json_braces(name, values):
    out = _render(_load_prompt(name), **values)
    for value in values.values():
        assert value in out
    for key in values:
        assert "{" + key + "}" not in out
