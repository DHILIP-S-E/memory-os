from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.config import settings
from app.db_url import resolve_urls

ASYNC_DATABASE_URL, SYNC_DATABASE_URL = resolve_urls(
    settings.database_url, settings.db_secret_arn, settings.aws_region, settings.database_url_param
)


# Connection pooling only applies to server databases; SQLite (local dev) has none.
_pool_args = (
    {} if ASYNC_DATABASE_URL.startswith("sqlite")
    else {"pool_size": 10, "max_overflow": 20}
)

engine = create_async_engine(
    ASYNC_DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
    **_pool_args,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:  # type: ignore[override]
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
