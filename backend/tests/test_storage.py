"""R2 file storage: signed links point at Cloudflare, are short-lived, and fail clearly when unconfigured."""

import io
from urllib.parse import parse_qs, urlparse

import pytest
from botocore.stub import Stubber

from app.config import settings
from app.services import storage


@pytest.fixture
def r2(monkeypatch):
    monkeypatch.setattr(settings, "r2_account_id", "acct123")
    monkeypatch.setattr(settings, "r2_access_key_id", "key-id")
    monkeypatch.setattr(settings, "r2_secret_access_key", "secret")
    monkeypatch.setattr(settings, "r2_bucket", "pmos-test")
    monkeypatch.setattr(settings, "r2_endpoint", "")
    storage._client_for.cache_clear()
    yield
    storage._client_for.cache_clear()


def test_without_keys_storage_is_not_configured_and_says_so():
    assert storage.is_configured() is False
    with pytest.raises(storage.StorageUnavailable, match="not configured"):
        storage.generate_upload_url("users/u1/misc/photo/a.jpg", "image/jpeg")


def test_deleting_without_storage_configured_is_a_no_op():
    storage.delete_object("users/u1/misc/photo/a.jpg")  # must not raise


def test_upload_links_go_to_the_accounts_r2_endpoint_and_expire_in_15_minutes(r2):
    url = urlparse(storage.generate_upload_url("users/u1/misc/photo/a.jpg", "image/jpeg"))
    assert url.netloc == "acct123.r2.cloudflarestorage.com"
    assert url.path == "/pmos-test/users/u1/misc/photo/a.jpg"
    query = parse_qs(url.query)
    assert query["X-Amz-Expires"] == ["900"]
    assert "content-type" in query["X-Amz-SignedHeaders"][0]
    assert "amazonaws.com" not in url.netloc


def test_download_links_expire_in_5_minutes(r2):
    query = parse_qs(urlparse(storage.generate_download_url("users/u1/misc/photo/a.jpg")).query)
    assert query["X-Amz-Expires"] == ["300"]


def test_an_endpoint_override_is_used_for_local_storage(r2, monkeypatch):
    monkeypatch.setattr(settings, "r2_endpoint", "http://localhost:9000")
    storage._client_for.cache_clear()
    assert urlparse(storage.generate_download_url("k")).netloc == "localhost:9000"


def stubbed():
    client = storage._client()
    return client, Stubber(client)


def test_reading_a_file_returns_its_bytes(r2):
    client, stub = stubbed()
    stub.add_response("get_object", {"Body": io.BytesIO(b"hello")}, {"Bucket": "pmos-test", "Key": "k"})
    with stub:
        assert storage.read_object("k") == b"hello"


def test_a_missing_file_is_file_not_found(r2):
    client, stub = stubbed()
    stub.add_client_error("head_object", service_error_code="404", http_status_code=404)
    stub.add_client_error("get_object", service_error_code="NoSuchKey", http_status_code=404)
    with stub:
        with pytest.raises(FileNotFoundError):
            storage.object_size("gone")
        with pytest.raises(FileNotFoundError):
            storage.read_object("gone")


def test_other_storage_errors_are_reported_without_details(r2):
    client, stub = stubbed()
    stub.add_client_error("get_object", service_error_code="AccessDenied", http_status_code=403)
    with stub:
        with pytest.raises(storage.StorageUnavailable, match="Could not read"):
            storage.read_object("k")


def test_the_size_comes_from_the_header_without_downloading(r2):
    client, stub = stubbed()
    stub.add_response("head_object", {"ContentLength": 1234}, {"Bucket": "pmos-test", "Key": "k"})
    with stub:
        assert storage.object_size("k") == 1234
