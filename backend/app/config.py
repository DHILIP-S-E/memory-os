from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Server settings, from the environment or the git-ignored backend/.env.

    Every external service is optional: with its settings blank, the feature reports
    "not configured" in plain words instead of failing, so the app and the tests run
    without any keys."""

    # Postgres is the source of truth (and the job queue).
    database_url: str = ""
    auto_create_tables: bool = False         # local dev with SQLite: create tables on startup

    # Sign-in. JWT_SECRET (32+ characters) signs the app's own tokens for email/password and
    # Google sign-in. Google: the OAuth client IDs whose ID tokens are accepted, comma-separated.
    jwt_secret: str = ""
    google_client_ids: str = ""
    allow_insecure_dev_auth: bool = False    # local development only; never in production
    cors_origins: str = "*"                  # comma-separated browser origins, e.g. https://app.example.com

    # Google Gemini, called only from the backend. Models are settings, not code.
    gemini_api_key: str = ""
    gemini_model_fast: str = "gemini-3.8-flash"          # parsing, extraction, capture summaries
    gemini_model_strong: str = "gemini-4-argon"          # event summaries, memory Q&A
    gemini_embedding_model: str = "gemini-embedding-001"

    # Cloudflare R2 (S3-compatible) for private files.
    r2_account_id: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_bucket: str = "personal-memory-os"
    r2_endpoint: str = ""        # optional override, e.g. a local MinIO; default is the account's R2 endpoint

    # Firebase Cloud Messaging for push. The credentials file is a Firebase service-account key,
    # never in git. Without it, deliveries are recorded as not sent; the phone's own alarm still rings.
    fcm_project_id: str = ""
    fcm_credentials_file: str = ""

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8",
        extra="ignore",  # a stale or unrelated key in .env must not stop the server
    )


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
