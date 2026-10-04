import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")

import pytest

from app.db_url import resolve_urls, to_sync, urls_from_secret


def test_secret_password_is_url_encoded():
    a, s = urls_from_secret(
        {"username": "pg", "password": "p@ss/w:rd%!", "host": "h.rds.amazonaws.com", "port": 5432, "dbname": "memos"}
    )
    assert a == "postgresql+asyncpg://pg:p%40ss%2Fw%3Ard%25%21@h.rds.amazonaws.com:5432/memos?ssl=require"
    assert s.startswith("postgresql://pg:p%40ss%2Fw%3Ard%25%21@h.rds.amazonaws.com:5432/memos?sslmode=require")


def test_explicit_database_url_wins():
    a, s = resolve_urls("postgresql+asyncpg://u:p@h/d", "arn:ignored", "us-east-1")
    assert a.startswith("postgresql+asyncpg://") and s == "postgresql://u:p@h/d"


def test_requires_some_configuration():
    with pytest.raises(RuntimeError):
        resolve_urls("", "", "us-east-1")


def test_to_sync():
    assert to_sync("postgresql+asyncpg://a@b/c") == "postgresql://a@b/c"


def test_to_sync_translates_the_tls_option_libpq_understands():
    assert to_sync("postgresql+asyncpg://u:p@h/db?ssl=require") == "postgresql://u:p@h/db?sslmode=require"
    assert to_sync("postgresql+asyncpg://u:p@h/db?sslmode=require") == "postgresql://u:p@h/db?sslmode=require"
    assert to_sync("postgresql+asyncpg://u:p@h/db?a=1&ssl=require") == "postgresql://u:p@h/db?a=1&sslmode=require"


def test_to_async_is_the_reverse():
    from app.db_url import to_async

    assert to_async("postgresql://u:p@h/db?sslmode=require") == "postgresql+asyncpg://u:p@h/db?ssl=require"
    assert to_async("postgres://u:p@h/db") == "postgresql+asyncpg://u:p@h/db"
    assert to_async("postgresql+asyncpg://u:p@h/db?ssl=require") == "postgresql+asyncpg://u:p@h/db?ssl=require"


def test_url_can_come_from_an_ssm_parameter(monkeypatch):
    asked = {}

    class FakeSsm:
        def get_parameter(self, Name, WithDecryption):
            asked.update(name=Name, decrypt=WithDecryption)
            return {"Parameter": {"Value": "postgresql+asyncpg://u:p@ep-x.neon.tech/db?ssl=require"}}

    monkeypatch.setattr("app.db_url.boto3.client", lambda svc, region_name=None: FakeSsm())
    a, s = resolve_urls("", "", "ap-south-1", "/pmos/DATABASE_URL")
    assert asked == {"name": "/pmos/DATABASE_URL", "decrypt": True}
    assert a.startswith("postgresql+asyncpg://") and a.endswith("?ssl=require")
    assert s == "postgresql://u:p@ep-x.neon.tech/db?sslmode=require"


def test_explicit_url_beats_the_ssm_parameter(monkeypatch):
    monkeypatch.setattr("app.db_url.boto3.client", lambda *a, **k: (_ for _ in ()).throw(AssertionError("must not call AWS")))
    a, _ = resolve_urls("postgresql+asyncpg://x:y@local/db", "", "ap-south-1", "/pmos/DATABASE_URL")
    assert "local" in a
