"""
Redis Cache Client for Dollor.ai
Provides centralized Redis access with graceful fallback.
If Redis is unavailable, operations return None/False — the app continues working.
"""

import os
import json
import logging
import random
import time
from typing import Optional

import redis
from fastapi import HTTPException

logger = logging.getLogger(__name__)

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
_is_prod = os.getenv("ENVIRONMENT", "production").lower() in ("production", "prod")

try:
    _redis_kwargs = dict(
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
        retry_on_timeout=True,
    )
    # Enable TLS for production ElastiCache if not already using rediss://
    if _is_prod and REDIS_URL.startswith("redis://"):
        _redis_kwargs["ssl"] = True
        _redis_kwargs["ssl_cert_reqs"] = "none"  # ElastiCache uses AWS-managed certs
    redis_client = redis.Redis.from_url(
        REDIS_URL,
        **_redis_kwargs,
    )
    # Test connection at import time
    redis_client.ping()
    REDIS_AVAILABLE = True
    logger.info(f"Redis connected: {REDIS_URL}")
except Exception as e:
    redis_client = None
    REDIS_AVAILABLE = False
    logger.warning(f"Redis unavailable ({e}), falling back to in-memory")


# ── Cache helpers ─────────────────────────────────────────────────────────────

def cache_get(key: str) -> Optional[str]:
    """Get a cached value. Returns None if miss or Redis unavailable."""
    if not redis_client:
        return None
    try:
        return redis_client.get(key)
    except Exception:
        return None


def cache_set(key: str, value: str, ttl: int = 60) -> bool:
    """Set a cached value with TTL in seconds."""
    if not redis_client:
        return False
    try:
        redis_client.setex(key, ttl, value)
        return True
    except Exception:
        return False


def cache_json_get(key: str):
    """Get a cached JSON value, deserialized."""
    raw = cache_get(key)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None


def cache_json_set(key: str, value, ttl: int = 60) -> bool:
    """Cache a JSON-serializable value with TTL."""
    try:
        return cache_set(key, json.dumps(value, default=str), ttl)
    except (TypeError, ValueError):
        return False


def cache_delete(key: str) -> bool:
    """Delete a cached key."""
    if not redis_client:
        return False
    try:
        redis_client.delete(key)
        return True
    except Exception:
        return False


# ── Rate Limiting (Redis sorted sets) ─────────────────────────────────────────

# SECURITY (NSA-004): In-memory fallback rate limiter when Redis is unavailable.
# Per-worker only (not shared across ECS tasks), but still prevents abuse on each worker.
_memory_rate_limits: dict = {}  # key -> list of timestamps
_MEMORY_RL_MAX_KEYS = 10000  # Prevent unbounded memory growth


def _memory_rate_limit_check(key: str, max_requests: int, window_seconds: int) -> tuple[bool, int]:
    """In-memory sliding window rate limiter (fallback when Redis unavailable)."""
    global _memory_rate_limits
    now = time.time()
    window_cutoff = now - window_seconds

    # Lightweight per-key cleanup: always trim expired timestamps for this key first
    if key in _memory_rate_limits:
        _memory_rate_limits[key] = [t for t in _memory_rate_limits[key] if t > window_cutoff]

    # Probabilistic full cleanup: ~1% of requests, only when dict is large
    if len(_memory_rate_limits) > _MEMORY_RL_MAX_KEYS and random.random() < 0.01:
        cutoff = now - 3600
        _memory_rate_limits = {
            k: v for k, v in _memory_rate_limits.items()
            if v and v[-1] > cutoff  # keep only keys with a recent timestamp
        }

    if key not in _memory_rate_limits:
        _memory_rate_limits[key] = []

    if len(_memory_rate_limits[key]) >= max_requests:
        retry_after = max(0, int(window_seconds - (now - _memory_rate_limits[key][0])))
        return False, retry_after

    _memory_rate_limits[key].append(now)
    return True, 0


def reset_memory_rate_limits():
    """Clear all in-memory rate limit state. Used in tests to prevent cross-test pollution."""
    global _memory_rate_limits
    _memory_rate_limits = {}


def rate_limit_check(key: str, max_requests: int, window_seconds: int) -> tuple[bool, int]:
    """
    Check rate limit using Redis sorted sets (sliding window).
    Returns (is_allowed, retry_after_seconds).
    Falls back to in-memory rate limiter if Redis unavailable.
    """
    if not redis_client:
        return _memory_rate_limit_check(key, max_requests, window_seconds)

    try:
        now = time.time()
        window_start = now - window_seconds
        pipe = redis_client.pipeline()
        pipe.zremrangebyscore(key, 0, window_start)
        pipe.zcard(key)
        pipe.zadd(key, {str(now): now})
        pipe.expire(key, window_seconds + 1)
        results = pipe.execute()

        current_count = results[1]
        if current_count >= max_requests:
            # Over limit — remove the just-added entry
            redis_client.zrem(key, str(now))
            # Calculate retry-after from oldest entry
            oldest = redis_client.zrange(key, 0, 0, withscores=True)
            if oldest:
                retry_after = max(0, int(window_seconds - (now - oldest[0][1])))
            else:
                retry_after = window_seconds
            return False, retry_after

        return True, 0
    except Exception as e:
        logger.warning(f"Rate limit Redis error: {e}")
        return True, 0


# ── Rate Limiter (high-level) ────────────────────────────────────────────────

class RateLimiter:
    """Redis-backed rate limiter config (shared across all workers and ECS tasks)"""
    def __init__(self, max_requests: int = 10, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds


def check_rate_limit(request, limiter: RateLimiter, key_prefix: str = "", identifier: str = None):
    """Check rate limit and raise HTTPException(429) if exceeded.

    Args:
        request: FastAPI Request object
        limiter: RateLimiter config (max_requests, window_seconds)
        key_prefix: Redis key prefix (e.g., "password_reset", "payment")
        identifier: Optional override for key suffix (email, user_id).
                    If None, uses client IP from X-Forwarded-For or direct connection.
    """
    if identifier:
        key = f"ratelimit:{key_prefix}:{identifier}"
    else:
        # SECURITY (NSA-003): Use the second-to-last IP in X-Forwarded-For chain.
        # CloudFront appends the real client IP, so the first value may be attacker-injected.
        # Chain: [attacker-injected, ..., real_client_ip (added by CloudFront), ALB_ip]
        # We want the second-to-last (CloudFront's addition). If only one entry, use it.
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            ips = [ip.strip() for ip in forwarded.split(",")]
            # Use second-to-last IP (real client as seen by CloudFront)
            # If only 1 IP, use it (direct connection or single proxy)
            client_ip = ips[-2] if len(ips) >= 2 else ips[0]
        else:
            client_ip = request.client.host
        key = f"ratelimit:{key_prefix}:{client_ip}"

    is_allowed, retry_after = rate_limit_check(key, limiter.max_requests, limiter.window_seconds)
    if not is_allowed:
        raise HTTPException(
            status_code=429,
            detail=f"Too many requests. Please try again in {retry_after} seconds.",
            headers={"Retry-After": str(retry_after)}
        )


# ── Password Reset Codes (Redis with TTL) ─────────────────────────────────────

def store_reset_code(email: str, code: str, ttl_seconds: int = 900) -> bool:
    """Store a password reset code with TTL (default 15 min)."""
    if not redis_client:
        return False
    try:
        redis_client.setex(f"reset:{email}", ttl_seconds, code)
        return True
    except Exception:
        return False


def get_reset_code(email: str) -> Optional[str]:
    """Get a stored password reset code. Returns None if expired/missing."""
    if not redis_client:
        return None
    try:
        return redis_client.get(f"reset:{email}")
    except Exception:
        return None


def delete_reset_code(email: str) -> bool:
    """Delete a used reset code."""
    return cache_delete(f"reset:{email}")


# ── Per-Account Login Lockout (G5) ────────────────────────────────────────────
# Tracks consecutive login failures per email. After LOCKOUT_THRESHOLD failures
# within LOCKOUT_WINDOW, the account is temporarily locked.
# Short lockout (15 min) to avoid DoS where attacker intentionally locks real users.

LOCKOUT_THRESHOLD = 10    # failures before lockout
LOCKOUT_WINDOW = 900      # 15 minutes (seconds)

# In-memory fallback when Redis is unavailable
_login_fail_counts: dict = {}  # email -> {"count": int, "expires": float}


def record_login_failure(email: str) -> int:
    """Increment failed login counter for email. Returns new count."""
    import time
    key = f"login_fails:{email}"
    if redis_client:
        try:
            count = redis_client.incr(key)
            if count == 1:
                redis_client.expire(key, LOCKOUT_WINDOW)
            return int(count)
        except Exception:
            pass
    # In-memory fallback
    now = time.time()
    entry = _login_fail_counts.get(email)
    if entry and now < entry["expires"]:
        entry["count"] += 1
    else:
        _login_fail_counts[email] = {"count": 1, "expires": now + LOCKOUT_WINDOW}
    return _login_fail_counts[email]["count"]


def clear_login_failures(email: str) -> None:
    """Clear failed login counter on successful login."""
    key = f"login_fails:{email}"
    if redis_client:
        try:
            redis_client.delete(key)
            return
        except Exception:
            pass
    _login_fail_counts.pop(email, None)


# ── Token Blacklist (G3) ──────────────────────────────────────────────────────
# Invalidate JWTs on logout. Key: revoked:{jti}, TTL = remaining token lifetime.
# In-memory fallback: bound to single worker (acceptable — worst case: revoked
# token valid in other workers until Redis reconnects, max 30 days).

_revoked_tokens: set = set()  # in-memory fallback


def blacklist_token(jti: str, ttl_seconds: int) -> None:
    """Mark a token as revoked. ttl_seconds = remaining lifetime."""
    key = f"revoked:{jti}"
    if redis_client:
        try:
            redis_client.setex(key, ttl_seconds, "1")
            return
        except Exception:
            pass
    _revoked_tokens.add(jti)


_active_sessions: dict = {}


def rotate_active_session(session_key: str, new_jti: str, ttl_seconds: int) -> None:
    """Record `new_jti` as the only live session for `session_key` (e.g. "driver:48").

    The previously active token, if any, is revoked, so a second login signs the first device out.
    """
    redis_key = f"session:{session_key}"
    previous = None
    if redis_client:
        try:
            raw = redis_client.get(redis_key)
            previous = raw.decode() if isinstance(raw, bytes) else raw
            redis_client.setex(redis_key, ttl_seconds, new_jti)
        except Exception:
            previous = _active_sessions.get(session_key)
            _active_sessions[session_key] = new_jti
    else:
        previous = _active_sessions.get(session_key)
        _active_sessions[session_key] = new_jti
    if previous and previous != new_jti:
        blacklist_token(previous, ttl_seconds)


_revoked_accounts: set = set()  # in-memory fallback


def revoke_account(role: str, account_id: int, ttl_seconds: int = 31 * 24 * 3600) -> None:
    """Reject every token issued to this account (e.g. "customer", 12), whatever its jti.

    Used by account deletion: we cannot enumerate the live tokens, so the account itself is marked.
    The default TTL outlives the longest token lifetime.
    """
    key = f"revoked_account:{role}:{account_id}"
    if redis_client:
        try:
            redis_client.setex(key, ttl_seconds, "1")
            return
        except Exception:
            pass
    _revoked_accounts.add(key)


def is_account_revoked(role: str, account_id) -> bool:
    """Return True if revoke_account() was called for this account."""
    if account_id is None:
        return False
    key = f"revoked_account:{role}:{account_id}"
    if redis_client:
        try:
            if redis_client.exists(key):
                return True
        except Exception:
            pass
    return key in _revoked_accounts


def is_token_blacklisted(jti: str) -> bool:
    """Return True if token has been revoked."""
    key = f"revoked:{jti}"
    if redis_client:
        try:
            return bool(redis_client.exists(key))
        except Exception:
            pass
    return jti in _revoked_tokens


def get_login_failure_count(email: str) -> int:
    """Return current consecutive failure count for email."""
    import time
    key = f"login_fails:{email}"
    if redis_client:
        try:
            val = redis_client.get(key)
            return int(val) if val else 0
        except Exception:
            pass
    now = time.time()
    entry = _login_fail_counts.get(email)
    if entry and now < entry["expires"]:
        return entry["count"]
    return 0
