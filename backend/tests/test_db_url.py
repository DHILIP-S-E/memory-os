import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import pytest

from app.db_url import resolve_urls, to_async, to_sync


def test_the_database_url_gives_both_driver_forms():
    a, s = resolve_urls("postgresql://u:p@h/d?sslmode=require")
    assert a == "postgresql+asyncpg://u:p@h/d?ssl=require" and s == "postgresql://u:p@h/d?sslmode=require"


def test_a_missing_database_url_says_what_to_set():
    with pytest.raises(RuntimeError, match="DATABASE_URL"):
        resolve_urls("")


def test_to_sync():
    assert to_sync("postgresql+asyncpg://a@b/c") == "postgresql://a@b/c"


def test_to_sync_translates_the_tls_option_libpq_understands():
    assert to_sync("postgresql+asyncpg://u:p@h/db?ssl=require") == "postgresql://u:p@h/db?sslmode=require"
    assert to_sync("postgresql+asyncpg://u:p@h/db?sslmode=require") == "postgresql://u:p@h/db?sslmode=require"
    assert to_sync("postgresql+asyncpg://u:p@h/db?a=1&ssl=require") == "postgresql://u:p@h/db?a=1&sslmode=require"


def test_to_async_is_the_reverse():
    assert to_async("postgresql://u:p@h/db?sslmode=require") == "postgresql+asyncpg://u:p@h/db?ssl=require"
    assert to_async("postgres://u:p@h/db") == "postgresql+asyncpg://u:p@h/db"
    assert to_async("postgresql+asyncpg://u:p@h/db?ssl=require") == "postgresql+asyncpg://u:p@h/db?ssl=require"
