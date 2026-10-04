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
