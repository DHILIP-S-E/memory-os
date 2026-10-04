"""
Database URL resolution.

Locally: DATABASE_URL from .env. On AWS: DB_SECRET_ARN points at the Aurora
credentials secret in Secrets Manager (spec R5.5 — no secrets in env vars or
source). The password is fetched at cold start and never written to config.
"""

import json
import re
from urllib.parse import quote_plus

import boto3


def urls_from_secret(secret: dict) -> tuple[str, str]:
    """(async_url, sync_url) from an RDS-style secret {username,password,host,port,dbname}."""
    user = quote_plus(secret["username"])
    password = quote_plus(secret["password"])
    host, port = secret["host"], secret.get("port", 5432)
    db = secret.get("dbname", "postgres")
    base = f"{user}:{password}@{host}:{port}/{db}"
    return f"postgresql+asyncpg://{base}?ssl=require", f"postgresql://{base}?sslmode=require"


def _from_arn(secret_arn: str, region: str) -> tuple[str, str]:
    client = boto3.client("secretsmanager", region_name=region)
    secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
    return urls_from_secret(secret)


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


def _from_ssm(name: str, region: str) -> tuple[str, str]:
    """URL kept as an encrypted SSM parameter (free, unlike a Secrets Manager secret)."""
    client = boto3.client("ssm", region_name=region)
    value = client.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
    return to_async(value), to_sync(value)


def resolve_urls(
    database_url: str, db_secret_arn: str, region: str, ssm_param: str = ""
) -> tuple[str, str]:
    """(async_url, sync_url). Order: explicit DATABASE_URL (local dev), then an SSM
    parameter, then a Secrets Manager secret."""
    if database_url:
        return to_async(database_url), to_sync(database_url)
    if ssm_param:
        return _from_ssm(ssm_param, region)
    if db_secret_arn:
        return _from_arn(db_secret_arn, region)
    raise RuntimeError("Set DATABASE_URL, DATABASE_URL_PARAM or DB_SECRET_ARN")


def sync_database_url() -> str:
    """psycopg2 URL for the Lambda workers (which do not use the async engine)."""
    from app.config import settings

    return resolve_urls(
        settings.database_url, settings.db_secret_arn, settings.aws_region, settings.database_url_param
    )[1]
