from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    database_url: str = ""      # local dev; on AWS use db_secret_arn
    db_secret_arn: str = ""
    database_url_param: str = ""    # SSM SecureString holding the URL (Lambda workers)
    aws_region: str = "us-east-1"
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""
    s3_bucket: str = "personal-memory-os-captures"
    # Amazon Nova via the apac inference profile (Mumbai). Any Converse-capable
    # model works: change these settings, not code.
    bedrock_model_fast: str = "apac.amazon.nova-lite-v1:0"     # parsing, extraction, quick summaries
    bedrock_model_strong: str = "apac.amazon.nova-pro-v1:0"    # event summaries, memory Q&A
    bedrock_embedding_model: str = "amazon.titan-embed-text-v2:0"
    cognito_user_pool_id: str = ""
    cognito_region: str = "us-east-1"
    cognito_app_client_id: str = ""
    # Google Gemini, called only from the backend. An empty key turns AI features off with a
    # clear "not configured" message instead of failing. Models are settings, not code.
    gemini_api_key: str = ""
    gemini_model_fast: str = "gemini-3.8-flash"          # parsing, extraction, capture summaries
    gemini_model_strong: str = "gemini-4-argon"          # event summaries, memory Q&A
    gemini_embedding_model: str = "gemini-embedding-001"
    # Cloudflare R2 (S3-compatible) for private files. Empty keys = uploads report "not configured".
    r2_account_id: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_bucket: str = "personal-memory-os"
    r2_endpoint: str = ""        # optional override, e.g. a local MinIO; default is the account's R2 endpoint
    # Firebase Cloud Messaging for push. Empty = deliveries are recorded as not sent; the phone's
    # own alarm still rings. The credentials file is a Firebase service-account key, never in git.
    fcm_project_id: str = ""
    fcm_credentials_file: str = ""
    # Google sign-in: the OAuth client IDs whose ID tokens are accepted (web, Android, iOS),
    # comma-separated. Empty = the "Sign in with Google" route reports "not configured".
    google_client_ids: str = ""
    auto_create_tables: bool = False         # local dev with SQLite: create tables on startup
    cors_origins: str = "*"                  # comma-separated browser origins, e.g. https://app.example.com
    jwt_secret: str = ""                     # >= 32 chars; enables the app's own email/password login
    allow_insecure_dev_auth: bool = False  # local dev only; never set in production
    scheduler_target_arn: str = ""   # notification-dispatcher Lambda ARN
    scheduler_role_arn: str = ""     # role EventBridge Scheduler assumes
    scheduler_group: str = "personal-memory-os"
    notification_topic_arn: str = ""
    capture_queue_url: str = ""
    knowledge_base_id: str = ""              # empty = keyword search only
    knowledge_base_data_source_id: str = ""
    guardrail_id: str = ""                   # empty = no guardrail (local dev)
    guardrail_version: str = ""
    sns_platform_app_arn: str = ""           # FCM/APNs platform application

    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8",
        extra="ignore",  # a stale or unrelated key in .env must not stop the server
    )


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
