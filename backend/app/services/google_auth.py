"""
Google sign-in: checking the ID token the app got from Google.

The token is verified against Google's published keys (signature, expiry and issuer), it
must be meant for one of this app's client IDs, and the email must be verified by Google.
Only then is the person signed in.
"""

from dataclasses import dataclass

from app.config import settings

ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


class GoogleSignInError(ValueError):
    """The token is not acceptable. The message is safe to show."""


class GoogleNotConfigured(RuntimeError):
    pass


class GoogleUnavailable(RuntimeError):
    """Google could not be reached to check the token. Worth trying again."""


@dataclass(frozen=True)
class GoogleIdentity:
    sub: str
    email: str
    name: str | None


def client_ids() -> list[str]:
    return [c.strip() for c in settings.google_client_ids.split(",") if c.strip()]


def _verify_with_google(token: str, audience: list[str]) -> dict:
    """Signature, expiry, issuer and audience, checked by Google's own library."""
    from google.auth.transport.requests import Request
    from google.oauth2 import id_token

    return id_token.verify_oauth2_token(token, Request(), audience=audience)


def verify(token: str) -> GoogleIdentity:
    audience = client_ids()
    if not audience:
        raise GoogleNotConfigured("Google sign-in is not configured on the server")
    if not isinstance(token, str) or not token.strip() or len(token) > 8192:
        raise GoogleSignInError("Google sign-in failed. Please try again.")
    try:
        claims = _verify_with_google(token.strip(), audience)
    except ValueError as exc:  # bad signature, expired, wrong audience, malformed
        raise GoogleSignInError("Google sign-in failed. Please try again.") from exc
    except Exception as exc:  # e.g. Google's keys could not be fetched
        raise GoogleUnavailable("Could not reach Google to check the sign-in. Please try again.") from exc
    if claims.get("iss") not in ISSUERS or claims.get("aud") not in audience:
        raise GoogleSignInError("Google sign-in failed. Please try again.")
    if not claims.get("email") or claims.get("email_verified") not in (True, "true"):
        raise GoogleSignInError("Your Google account's email is not verified.")
    if not claims.get("sub"):
        raise GoogleSignInError("Google sign-in failed. Please try again.")
    return GoogleIdentity(sub=str(claims["sub"]), email=str(claims["email"]).strip().lower(), name=claims.get("name"))
