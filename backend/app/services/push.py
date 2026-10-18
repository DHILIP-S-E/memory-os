"""
Push notifications through Firebase Cloud Messaging (FCM HTTP v1).

The server signs in to FCM with a Firebase service-account key (a file path in
FCM_CREDENTIALS_FILE, kept out of git). Without it, push is "not configured" and the
reminder is recorded as not sent; the phone's own local alarm still rings.
"""

import json
import threading

import httpx

from app.config import settings

FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_lock = threading.Lock()
_credentials = None


class PushUnavailable(RuntimeError):
    """Push is not configured on the server."""


class InvalidToken(Exception):
    """The device token is no longer valid (app uninstalled or token rotated): forget it."""


def is_configured() -> bool:
    return bool(settings.fcm_project_id and settings.fcm_credentials_file)


def build_message(token: str, title: str, body: str, data: dict | None = None) -> dict:
    """The FCM v1 request body. Data values must be strings."""
    return {
        "message": {
            "token": token,
            "notification": {"title": title[:200], "body": body[:1000]},
            "data": {k: str(v) for k, v in (data or {}).items()},
            "android": {"priority": "high", "notification": {"channel_id": "reminders"}},
        }
    }


def _access_token() -> str:
    """A short-lived OAuth token from the service-account key, refreshed when it expires."""
    global _credentials
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    with _lock:
        if _credentials is None:
            with open(settings.fcm_credentials_file, encoding="utf-8") as fh:
                info = json.load(fh)
            _credentials = service_account.Credentials.from_service_account_info(info, scopes=[FCM_SCOPE])
        if not _credentials.valid:
            _credentials.refresh(Request())
        return _credentials.token


def send(token: str, title: str, body: str, data: dict | None = None, *, client: httpx.Client | None = None,
         access_token: str | None = None) -> str:
    """Send one notification; returns FCM's message name. Raises InvalidToken for a dead token,
    PushUnavailable when push is not set up, and RuntimeError for anything worth retrying."""
    if not is_configured():
        raise PushUnavailable("Push notifications are not configured on the server")
    url = f"https://fcm.googleapis.com/v1/projects/{settings.fcm_project_id}/messages:send"
    try:
        response = (client or httpx).post(
            url, json=build_message(token, title, body, data),
            headers={"Authorization": f"Bearer {access_token or _access_token()}"}, timeout=15.0,
        )
    except httpx.HTTPError as exc:
        raise RuntimeError(f"Could not reach FCM ({type(exc).__name__})") from exc
    if response.status_code == 200:
        return str(response.json().get("name", ""))
    try:
        status = response.json().get("error", {}).get("status", "")
    except ValueError:
        status = ""
    if response.status_code == 404 or status in ("UNREGISTERED", "NOT_FOUND") or (
        response.status_code == 400 and status == "INVALID_ARGUMENT"
    ):
        raise InvalidToken(status or str(response.status_code))
    raise RuntimeError(f"FCM returned HTTP {response.status_code} {status}".strip())
