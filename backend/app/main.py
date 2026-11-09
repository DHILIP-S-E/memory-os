import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth import get_current_user_id
from app.config import settings
from app.routers import reminders, events, captures, memory, ai, account, devices, auth, notifications, dashboard
from app.services import push, storage

logger = logging.getLogger(__name__)

def check_settings() -> list[str]:
    """Plain-words problems with the server's settings, logged at startup. DATABASE_URL is
    already required at import; the rest degrade one feature each, so they warn instead of
    stopping the server."""
    problems = []
    if not settings.jwt_secret:
        problems.append("JWT_SECRET is not set: every request is refused"
                        + (" (ALLOW_INSECURE_DEV_AUTH accepts any token)" if settings.allow_insecure_dev_auth else ""))
    elif len(settings.jwt_secret) < 32:
        problems.append("JWT_SECRET is shorter than 32 characters")
    if settings.allow_insecure_dev_auth:
        problems.append("ALLOW_INSECURE_DEV_AUTH is on: never use this in production")
    if not settings.gemini_api_key:
        problems.append("GEMINI_API_KEY is not set: AI features answer 503")
    if not settings.google_client_ids:
        problems.append("GOOGLE_CLIENT_IDS is not set: Google sign-in is disabled")
    if not storage.is_configured():
        problems.append("R2 settings are incomplete: file captures are disabled")
    if not push.is_configured():
        problems.append("FCM settings are incomplete: push is not sent")
    return problems


@asynccontextmanager
async def lifespan(_app: FastAPI):
    for problem in check_settings():
        logger.warning("Configuration: %s", problem)
    if settings.auto_create_tables:
        # Local development only. Production schemas come from `alembic upgrade head`.
        import app.models  # noqa: F401  (register every table)
        from app.database import Base, engine

        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    lifespan=lifespan,
    title="Personal Memory OS API",
    version="1.0.0",
    description="Personal reminder and memory platform",
)

# Auth is a Bearer header (no cookies), so credentials are not needed; that also makes
# a specific origin list safe. Set CORS_ORIGINS to the web app's address in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.cors_origins.split(",") if o.strip()],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(reminders.router, prefix="/reminders", tags=["reminders"])
app.include_router(events.router, prefix="/events", tags=["events"])
app.include_router(captures.router, prefix="/captures", tags=["captures"])
app.include_router(memory.router, prefix="/memory", tags=["memory"])
app.include_router(ai.router, prefix="/ai", tags=["ai"])
app.include_router(account.router, prefix="/account", tags=["account"])
app.include_router(devices.router, prefix="/devices", tags=["devices"])
app.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
app.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])


@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok", "service": "Personal Memory OS API", "version": "1.0.0"}


@app.get("/health/me", tags=["health"])
async def health_me(user_id: str = Depends(get_current_user_id)):
    """Protected health check - returns the authenticated user's ID."""
    return {"status": "ok", "user_id": user_id}
