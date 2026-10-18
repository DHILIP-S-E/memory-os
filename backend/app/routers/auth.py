"""
Sign-in: the app's own email/password accounts, and Google sign-in.

  POST /auth/register  create an account, returns tokens
  POST /auth/login     returns tokens (throttled against brute force)
  POST /auth/google    sign in with a Google ID token; creates or links the account
  POST /auth/refresh   new access token from a refresh token
  GET  /auth/me        the signed-in user
"""

import uuid
from datetime import datetime

from email_validator import EmailNotValidError, validate_email
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.config import settings
from app.database import get_db
from app.models.user import User
from app.services import google_auth
from app.services.login_throttle import LoginThrottle
from app.services.passwords import WeakPassword, hash_password, verify_password
from app.services.tokens import (
    TokenError, create_access_token, create_refresh_token, verify_token,
)

router = APIRouter()
throttle = LoginThrottle()

# A real bcrypt hash of a random string: verifying against it when the email is
# unknown makes "no such user" take as long as "wrong password" (no user probing).
_DUMMY_HASH = hash_password("dummy-password-for-timing")


class Credentials(BaseModel):
    email: str
    password: str
    display_name: str | None = None


class RefreshRequest(BaseModel):
    refresh_token: str


class GoogleSignIn(BaseModel):
    id_token: str


def _secret() -> str:
    if not settings.jwt_secret:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Login is not configured")
    return settings.jwt_secret


def normalise_email(raw: str) -> str:
    try:
        return validate_email(raw.strip(), check_deliverability=False).normalized.lower()
    except EmailNotValidError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Enter a valid email address")


def _tokens(user: User) -> dict:
    secret = _secret()
    return {
        "access_token": create_access_token(user.id, secret),
        "refresh_token": create_refresh_token(user.id, secret),
        "token_type": "bearer",
        "user": user.to_public(),
    }


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(body: Credentials, db: AsyncSession = Depends(get_db)):
    _secret()
    email = normalise_email(body.email)
    try:
        password_hash = hash_password(body.password)
    except WeakPassword as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc))
    user = User(
        id=str(uuid.uuid4()),
        email=email,
        password_hash=password_hash,
        display_name=(body.display_name or "").strip() or email.split("@")[0],
        created_at=datetime.utcnow(),
    )
    db.add(user)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT, "An account with that email already exists")
    return _tokens(user)


@router.post("/login")
async def login(body: Credentials, request: Request, db: AsyncSession = Depends(get_db)):
    _secret()
    email = body.email.strip().lower()
    key = f"{email}|{request.client.host if request.client else '?'}"
    if throttle.is_locked(key):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many failed attempts. Try again later.",
            headers={"Retry-After": str(throttle.retry_after(key))},
        )
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    ok = verify_password(body.password, user.password_hash if user else _DUMMY_HASH)
    if not (user and ok):
        throttle.record_failure(key)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Incorrect email or password")
    throttle.reset(key)
    return _tokens(user)


@router.post("/google")
async def sign_in_with_google(body: GoogleSignIn, db: AsyncSession = Depends(get_db)):
    """Sign in with the ID token from Google. A new person gets an account; someone who already
    has a password account with the same (Google-verified) email is linked to it."""
    _secret()
    try:
        identity = google_auth.verify(body.id_token)
    except (google_auth.GoogleNotConfigured, google_auth.GoogleUnavailable) as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc))
    except google_auth.GoogleSignInError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, str(exc))

    user = (await db.execute(select(User).where(User.google_sub == identity.sub))).scalar_one_or_none()
    if user is None:
        user = (await db.execute(select(User).where(User.email == identity.email))).scalar_one_or_none()
        if user is not None:
            if user.google_sub and user.google_sub != identity.sub:
                raise HTTPException(status.HTTP_409_CONFLICT, "This email is linked to a different Google account")
            user.google_sub = identity.sub
        else:
            user = User(
                id=str(uuid.uuid4()), email=identity.email,
                password_hash="",  # Google-only: no password can ever match
                display_name=(identity.name or "").strip() or identity.email.split("@")[0],
                google_sub=identity.sub, created_at=datetime.utcnow(),
            )
            db.add(user)
    try:
        await db.commit()
    except IntegrityError:  # the same person signing in twice at once
        await db.rollback()
        user = (await db.execute(select(User).where(User.google_sub == identity.sub))).scalar_one_or_none()
        if user is None:
            raise HTTPException(status.HTTP_409_CONFLICT, "Could not sign in. Please try again.")
    return _tokens(user)


@router.post("/refresh")
async def refresh(body: RefreshRequest, db: AsyncSession = Depends(get_db)):
    secret = _secret()
    try:
        user_id = verify_token(body.refresh_token, "refresh", secret)
    except TokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired. Please sign in again.")
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Session expired. Please sign in again.")
    return {"access_token": create_access_token(user.id, secret), "token_type": "bearer"}


@router.get("/me")
async def me(user_id: str = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)):
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Account no longer exists")
    return user.to_public()
