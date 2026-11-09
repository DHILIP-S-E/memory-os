"""
Private file storage on Cloudflare R2 (spec 4.9 and 10).

The phone uploads straight to R2 with a short-lived signed PUT link and downloads with a
short-lived signed GET link, so files never pass through the API server. R2 speaks the S3
API, so boto3 is used purely as an S3 client pointed at Cloudflare; no AWS service is involved.
"""

import logging
from functools import lru_cache

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from app.config import settings

logger = logging.getLogger(__name__)
UPLOAD_LINK_SECONDS = 15 * 60
DOWNLOAD_LINK_SECONDS = 5 * 60


class StorageUnavailable(RuntimeError):
    """File storage is not configured, or R2 could not be reached. The message is user-safe."""


def is_configured() -> bool:
    return bool(
        settings.r2_access_key_id and settings.r2_secret_access_key and settings.r2_bucket
        and (settings.r2_endpoint or settings.r2_account_id)
    )


def endpoint() -> str:
    return settings.r2_endpoint or f"https://{settings.r2_account_id}.r2.cloudflarestorage.com"


@lru_cache(maxsize=1)
def _client_for(endpoint_url: str, key_id: str, secret: str):
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=key_id,
        aws_secret_access_key=secret,
        region_name="auto",  # R2 ignores regions; "auto" is what Cloudflare documents
        config=Config(signature_version="s3v4", retries={"max_attempts": 3, "mode": "standard"}),
    )


def _client():
    if not is_configured():
        raise StorageUnavailable("File storage is not configured on the server")
    return _client_for(endpoint(), settings.r2_access_key_id, settings.r2_secret_access_key)


def generate_upload_url(key: str, content_type: str, expires_in: int = UPLOAD_LINK_SECONDS) -> str:
    """A signed PUT link the app uploads to directly. The content type is part of the signature."""
    return _client().generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.r2_bucket, "Key": key, "ContentType": content_type},
        ExpiresIn=expires_in,
    )


def generate_download_url(key: str, expires_in: int = DOWNLOAD_LINK_SECONDS) -> str:
    """A signed GET link for one private file."""
    return _client().generate_presigned_url(
        "get_object", Params={"Bucket": settings.r2_bucket, "Key": key}, ExpiresIn=expires_in,
    )


def object_size(key: str) -> int:
    """The stored size in bytes, without downloading. Raises FileNotFoundError if it is not there."""
    try:
        return int(_client().head_object(Bucket=settings.r2_bucket, Key=key)["ContentLength"])
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
            raise FileNotFoundError(key) from exc
        raise StorageUnavailable("Could not read from file storage") from exc


def read_object(key: str) -> bytes:
    try:
        return _client().get_object(Bucket=settings.r2_bucket, Key=key)["Body"].read()
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound"):
            raise FileNotFoundError(key) from exc
        raise StorageUnavailable("Could not read from file storage") from exc


def delete_object(key: str) -> None:
    """Remove one file. A file that is already gone, or storage that is not configured, is not an error."""
    if not is_configured():
        return
    try:
        _client().delete_object(Bucket=settings.r2_bucket, Key=key)
    except ClientError:
        # The caller has already removed the database row, so do not fail it; but say so, since
        # the file may be left behind in the bucket.
        logger.exception("Could not delete %s from file storage", key)
