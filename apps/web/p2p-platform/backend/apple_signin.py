"""Sign in with Apple token storage and revocation (App Store 5.1.1(v)).

Everything here is best-effort and a no-op until APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_PRIVATE_KEY are set.
The client id is chosen per account role (rider app vs driver app are different Apple clients); the exchange and
the revoke for one account always use the same client id and client secret. No function raises: Apple trouble must never break sign-in or account deletion.
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
DEFAULT_CLIENT_IDS = {"customer": "com.dollorai.customer", "driver": "com.dollorai.delivery"}
ROLE_CLIENT_ID_ENV = {"customer": "APPLE_CLIENT_ID_CUSTOMER", "driver": "APPLE_CLIENT_ID_DRIVER"}
SHARED_ENV = ("APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY")
REQUIRED_ENV = SHARED_ENV  # kept for callers/tests that list the credential variables


def client_id_for_role(role: str) -> Optional[str]:
    """Bundle id a role's refresh tokens were issued to: role env var, then legacy APPLE_CLIENT_ID, then default."""
    if role not in DEFAULT_CLIENT_IDS:
        return None
    return os.getenv(ROLE_CLIENT_ID_ENV[role]) or os.getenv("APPLE_CLIENT_ID") or DEFAULT_CLIENT_IDS[role]


def accepted_audiences() -> set:
    """Bundle ids an Apple identity token may be issued to: every role's client id plus the legacy one."""
    audiences = {client_id_for_role(role) for role in DEFAULT_CLIENT_IDS}
    audiences.add(os.getenv("APPLE_CLIENT_ID") or None)
    audiences.discard(None)
    return audiences


def _key_for_role(role: str) -> tuple:
    """(key_id, private_key): the driver override pair when both are set, else the shared key."""
    if role == "driver" and os.getenv("APPLE_KEY_ID_DRIVER") and os.getenv("APPLE_PRIVATE_KEY_DRIVER"):
        return os.environ["APPLE_KEY_ID_DRIVER"], os.environ["APPLE_PRIVATE_KEY_DRIVER"]
    return os.getenv("APPLE_KEY_ID"), os.getenv("APPLE_PRIVATE_KEY")


def is_configured(role: str = "customer") -> bool:
    key_id, private_key = _key_for_role(role)
    return bool(os.getenv("APPLE_TEAM_ID") and key_id and private_key and client_id_for_role(role))


def _build_client_secret(role: str) -> str:
    now = int(time.time())
    key_id, private_key = _key_for_role(role)
    return jwt.encode(
        {"iss": os.environ["APPLE_TEAM_ID"], "iat": now, "exp": now + 300,
         "aud": APPLE_AUDIENCE, "sub": client_id_for_role(role)},
        private_key.replace("\\n", "\n"), algorithm="ES256", headers={"kid": key_id})


def exchange_authorization_code(role: str, code: str) -> Optional[str]:
    """Swap the one-time authorizationCode from the app for a refresh token; None on any failure."""
    try:
        response = requests.post(TOKEN_URL, data={
            "client_id": client_id_for_role(role), "client_secret": _build_client_secret(role),
            "code": code, "grant_type": "authorization_code"}, timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            logger.warning("apple token exchange failed for %s: HTTP %s", role, response.status_code)
            return None
        return response.json().get("refresh_token")
    except Exception as exc:
        logger.warning("apple token exchange error: %s", type(exc).__name__)
        return None


def store_refresh_token_from_code(db: Session, account_type: str, account_id: int, code: Optional[str]) -> bool:
    """Exchange `code` and keep the encrypted refresh token for later revocation. Skips silently when unconfigured."""
    if not code:
        return False
    if not is_configured(account_type):
        logger.info("apple authorization_code received but APPLE_* credentials are not configured: not stored")
        return False
    try:
        refresh_token = exchange_authorization_code(account_type, code)
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
        if not is_configured(account_type):
            logger.info("apple token revocation skipped for %s %s: APPLE_* credentials are not configured",
                        account_type, account_id)
            return False
        response = requests.post(REVOKE_URL, data={
            "client_id": client_id_for_role(account_type), "client_secret": _build_client_secret(account_type),
            "token": decrypt_field(row.refresh_token_encrypted), "token_type_hint": "refresh_token"},
            timeout=REQUEST_TIMEOUT_SECONDS)
        if response.status_code != 200:
            logger.warning("apple token revocation failed for %s %s: HTTP %s", account_type, account_id,
                           response.status_code)
            return False
        db.delete(row)
        db.commit()
        logger.info("apple revoke ok for %s %s", account_type, account_id)
        return True
    except Exception as exc:
        logger.warning("apple token revocation error for %s %s: %s", account_type, account_id, type(exc).__name__)
        return False
