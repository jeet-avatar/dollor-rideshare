"""Sign in with Apple token storage and revocation (App Store 5.1.1(v)).

Everything here is best-effort and a no-op until APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY and
APPLE_CLIENT_ID are all set. No function raises: Apple trouble must never break sign-in or account deletion.
See docs/APPLE_SIGNIN_REVOKE.md.
"""
import logging
import os
import time
from typing import Optional

import requests
from jose import jwt
from sqlalchemy.orm import Session

from encryption import decrypt_field, encrypt_field
from models import AppleSigninToken

logger = logging.getLogger(__name__)

APPLE_AUDIENCE = "https://appleid.apple.com"
TOKEN_URL = "https://appleid.apple.com/auth/token"
REVOKE_URL = "https://appleid.apple.com/auth/revoke"
REQUEST_TIMEOUT_SECONDS = 8
REQUIRED_ENV = ("APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY", "APPLE_CLIENT_ID")


def is_configured() -> bool:
    return all(os.getenv(name) for name in REQUIRED_ENV)


def _build_client_secret() -> str:
    now = int(time.time())
    private_key = os.environ["APPLE_PRIVATE_KEY"].replace("\\n", "\n")
    return jwt.encode(
        {"iss": os.environ["APPLE_TEAM_ID"], "iat": now, "exp": now + 300,
         "aud": APPLE_AUDIENCE, "sub": os.environ["APPLE_CLIENT_ID"]},
        private_key, algorithm="ES256", headers={"kid": os.environ["APPLE_KEY_ID"]})


def exchange_authorization_code(code: str) -> Optional[str]:
    """Swap the one-time authorizationCode from the app for a refresh token; None on any failure."""
    try:
        response = requests.post(TOKEN_URL, data={
            "client_id": os.environ["APPLE_CLIENT_ID"], "client_secret": _build_client_secret(),
            "code": code, "grant_type": "authorization_code"}, timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            logger.warning("apple token exchange failed: HTTP %s", response.status_code)
            return None
        return response.json().get("refresh_token")
    except Exception as exc:
        logger.warning("apple token exchange error: %s", type(exc).__name__)
        return None


def store_refresh_token_from_code(db: Session, account_type: str, account_id: int, code: Optional[str]) -> bool:
    """Exchange `code` and keep the encrypted refresh token for later revocation. Skips silently when unconfigured."""
    if not code:
        return False
    if not is_configured():
        logger.info("apple authorization_code received but APPLE_* credentials are not configured: not stored")
        return False
    try:
        refresh_token = exchange_authorization_code(code)
        if not refresh_token:
            return False
        encrypted = encrypt_field(refresh_token)
        if not encrypted or not encrypted.startswith("enc:"):
            logger.warning("apple refresh token not stored: ENCRYPTION_KEY is not configured")
            return False
        row = db.query(AppleSigninToken).filter(
            AppleSigninToken.account_type == account_type, AppleSigninToken.account_id == account_id).first()
        if row:
            row.refresh_token_encrypted = encrypted
        else:
            db.add(AppleSigninToken(account_type=account_type, account_id=account_id,
                                    refresh_token_encrypted=encrypted))
        db.commit()
        return True
    except Exception as exc:
        db.rollback()
        logger.warning("apple refresh token storage error: %s", type(exc).__name__)
        return False


def revoke_for_account(db: Session, account_type: str, account_id: int) -> bool:
    """Revoke the stored Apple token of a deleted account. True only when Apple accepted the revocation."""
    try:
        row = db.query(AppleSigninToken).filter(
            AppleSigninToken.account_type == account_type, AppleSigninToken.account_id == account_id).first()
        if not row:
            return False
        if not is_configured():
            logger.info("apple token revocation skipped for %s %s: APPLE_* credentials are not configured",
                        account_type, account_id)
            return False
        response = requests.post(REVOKE_URL, data={
            "client_id": os.environ["APPLE_CLIENT_ID"], "client_secret": _build_client_secret(),
            "token": decrypt_field(row.refresh_token_encrypted), "token_type_hint": "refresh_token"},
            timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            logger.warning("apple token revocation failed for %s %s: HTTP %s", account_type, account_id,
                           response.status_code)
            return False
        db.delete(row)
        db.commit()
        logger.info("apple token revoked for %s %s", account_type, account_id)
        return True
    except Exception as exc:
        logger.warning("apple token revocation error for %s %s: %s", account_type, account_id, type(exc).__name__)
        return False
