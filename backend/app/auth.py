"""
Authentication for every API request.

Email/password and Google sign-in both end with the app's own access token (signed with
JWT_SECRET), so this is the one check every route uses. A server without JWT_SECRET refuses
every request: a misconfigured deployment must fail closed, never accept forged tokens.

ALLOW_INSECURE_DEV_AUTH=true accepts any token, for local development only.
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config import settings
from app.services.tokens import TokenError, verify_token

security = HTTPBearer(auto_error=True)


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    """FastAPI dependency: the signed-in user's id, from a valid access token."""
    token = credentials.credentials
    if settings.jwt_secret:
        try:
            return verify_token(token, "access", settings.jwt_secret)
        except TokenError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired authentication token",
                headers={"WWW-Authenticate": "Bearer"},
            )
    if settings.allow_insecure_dev_auth:
        try:
            return jwt.get_unverified_claims(token).get("sub", "dev_user")
        except JWTError:
            return "dev_user"
    raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Authentication is not configured")
