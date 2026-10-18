"""
Database URL handling.

DATABASE_URL comes from the environment (or the git-ignored backend/.env). The app uses
the asyncpg driver; tools that need a plain libpq URL get the converted form.
"""

import re


def to_sync(url: str) -> str:
    """Convert a SQLAlchemy asyncpg URL into a psycopg2 one.

    asyncpg spells the TLS option `ssl=require`; libpq (psycopg2) only knows
    `sslmode=require` and rejects `ssl=` as an unknown option."""
    url = url.replace("postgresql+asyncpg://", "postgresql://", 1)
    return re.sub(r"([?&])ssl=", r"\1sslmode=", url)


def to_async(url: str) -> str:
    """The reverse: a plain postgresql:// URL for SQLAlchemy's asyncpg driver."""
    url = re.sub(r"^postgres(ql)?://", "postgresql+asyncpg://", url, count=1)
    return re.sub(r"([?&])sslmode=", r"\1ssl=", url)


def resolve_urls(database_url: str) -> tuple[str, str]:
    """(async_url, sync_url) from DATABASE_URL."""
    if not database_url:
        raise RuntimeError("Set DATABASE_URL (in the environment or backend/.env)")
    return to_async(database_url), to_sync(database_url)
