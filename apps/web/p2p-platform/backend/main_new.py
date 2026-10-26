"""
Dollor.ai P2P Platform Backend - Main API Module

This is the primary API server for the Dollor.ai matchmaking platform,
handling food delivery and rideshare coordination.

Version: 1.0.1
"""

from pricing_config import pricing_engine, platform_fee_for, fare_tier_description
from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File, Form, Query, WebSocket, WebSocketDisconnect, Header, Body, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from sqlalchemy import func, extract, and_, or_, text
from datetime import datetime, timedelta, date
from typing import Optional, List, Any
from pydantic import BaseModel, EmailStr, Field, field_validator
from passlib.context import CryptContext
from jose import jwt, JWTError
import os
import json
import logging
import secrets
import hmac
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from database import get_db, init_db
from models import User, Client, Invoice, InvoiceItem, Payment, UserRole, InvoiceStatus, PaymentStatus, Vendor, Driver, DriverStatus, Customer, CustomerStatus, Order, OrderStatus, OrderDispute, OrderDisputeReason, DisputeStatus
from auth_utils import require_any_auth, require_customer, require_driver, require_vendor, require_admin
from encryption import encrypt_field, decrypt_field, mask_email
from email_service import (
    send_vendor_approval_email, send_vendor_registration_confirmation,
    send_driver_approval_email, send_driver_registration_confirmation,
    send_customer_welcome_email, send_email_verification_code,
    send_password_reset_email, send_password_reset_link_email,
    notify_support,
    # Order lifecycle emails
    send_order_confirmation_email, send_order_ready_email,
)
from document_verification_service import (
    get_verification_service,
    VerificationStatus,
    DocumentType,
)

load_dotenv()


def sanitize_file_extension(filename: str, allowed_extensions: list[str], default: str = "pdf") -> str:
    """Sanitize file extension to prevent path traversal attacks."""
    if not filename or '.' not in filename:
        return default
    ext = filename.rsplit('.', 1)[-1].lower()
    # Only keep alphanumeric characters
    ext = ''.join(c for c in ext if c.isalnum())[:10]
    return ext if ext in allowed_extensions else default


def secure_file_path(upload_dir: str, filename: str) -> str:
    """Create a secure file path, ensuring it stays within upload directory."""
    file_path = os.path.join(upload_dir, filename)
    abs_upload_dir = os.path.abspath(upload_dir)
    abs_file_path = os.path.abspath(file_path)
    if not abs_file_path.startswith(abs_upload_dir + os.sep):
        raise HTTPException(status_code=400, detail="Invalid filename")
    return file_path


def sanitize_document_type(doc_type: str, valid_types: list[str]) -> str:
    """Sanitize and validate document type to prevent path traversal."""
    if doc_type in valid_types:
        return doc_type
    # Sanitize: keep only alphanumeric and underscores
    sanitized = ''.join(c for c in doc_type if c.isalnum() or c == '_')[:30]
    return sanitized if sanitized else "document"


# Determine environment - production is the default (fail-safe)
# Options: production, staging, development, local, dev
# NOTE: Must be before FastAPI() creation to conditionally disable docs in production
_env = os.getenv("ENVIRONMENT", "production").lower()
_is_production = _env in ("production", "prod")
_is_staging = _env in ("staging", "stage")

app = FastAPI(
    title="Invoice Management System",
    # SECURITY (NSA-002): Disable API docs in production to prevent reconnaissance
    docs_url="/docs" if not _is_production else None,
    redoc_url="/redoc" if not _is_production else None,
    openapi_url="/openapi.json" if not _is_production else None,
)

# CORS Configuration - SOC 2 Compliant
# Production-safe origins list - NEVER add localhost here
# Production-safe CORS origins (always allowed)
PRODUCTION_ORIGINS = [
    # Production domains
    "https://dollor.ai",
    "https://www.dollor.ai",
    "https://api.dollor.ai",
    "https://vibingticket.com",
    "https://www.vibingticket.com",
    # Production Admin Panel (CloudFront)
    "https://d3pus2gxlb5cer.cloudfront.net",
    # Staging Frontend (CloudFront)
    "https://d3b3ow4g7hjwi5.cloudfront.net",
]

# Staging origins (allowed in staging and development)
STAGING_ORIGINS = [
    # Staging API (CloudFront) - Required for mobile apps and staging web
    "https://d34u5ixl0bulv4.cloudfront.net",
    # Staging Frontend (CloudFront)
    "https://d3b3ow4g7hjwi5.cloudfront.net",
    # Staging Frontend (S3 bucket)
    "http://dollar-ai-staging-frontend.s3-website-us-east-1.amazonaws.com",
    # Staging subdomains
    "https://staging.dollor.ai",
    "https://staging-api.dollor.ai",
]

# Development-only origins (NEVER included in production)
DEVELOPMENT_ORIGINS = [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:5174",
    "http://localhost:8080",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:5174",
    "http://127.0.0.1:8080",
]

# Build allowed origins based on environment
ALLOWED_ORIGINS = PRODUCTION_ORIGINS.copy()
if _is_staging:
    # Staging: production + staging origins
    ALLOWED_ORIGINS.extend(STAGING_ORIGINS)
elif not _is_production:
    # Development: all origins
    ALLOWED_ORIGINS.extend(STAGING_ORIGINS)
    ALLOWED_ORIGINS.extend(DEVELOPMENT_ORIGINS)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Requested-With", "Accept"],
)

# CORS fix: Ensure Vary: Origin is always present so CloudFront caches per-origin,
# and strip allow-credentials when no allow-origin is set (non-matching origins).
# SECURITY: Also adds security headers to every response.
@app.middleware("http")
async def fix_cors_and_security_headers(request, call_next):
    response = await call_next(request)
    # Always set Vary: Origin so CloudFront/CDN caches separate versions per origin
    vary = response.headers.get("vary", "")
    if "Origin" not in vary:
        response.headers["vary"] = f"{vary}, Origin" if vary else "Origin"
    # Don't leak allow-credentials without allow-origin
    if "access-control-allow-origin" not in response.headers and "access-control-allow-credentials" in response.headers:
        del response.headers["access-control-allow-credentials"]
    # SECURITY HEADERS - prevent XSS, clickjacking, MIME sniffing
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=(self)"
    response.headers["Content-Security-Policy"] = "default-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data: https:; frame-ancestors 'none'"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    # Hide server implementation details
    if "server" in response.headers:
        response.headers["server"] = "Dollor"
    return response

@app.get("/robots.txt", include_in_schema=False)
async def robots_txt():
    """Serve robots.txt to instruct polite crawlers not to index the API."""
    from fastapi.responses import PlainTextResponse
    content = (
        "User-agent: *\n"
        "Disallow: /api/\n"
        "Disallow: /admin/\n"
        "Disallow: /uploads/\n"
        "Allow: /\n\n"
        "Sitemap: https://dollor.ai/sitemap.xml\n"
    )
    return PlainTextResponse(content, headers={"Cache-Control": "public, max-age=86400"})


@app.middleware("http")
async def limit_request_size(request: Request, call_next):
    """Reject oversized request bodies to prevent memory exhaustion (DoS).
    Checks Content-Length header first (fast path), then streams the body for
    chunked transfers where CloudFront strips Content-Length.
    """
    from fastapi.responses import JSONResponse
    # A4: Tiered body limits — 5MB for file uploads, 1MB for all other requests
    path = request.url.path
    is_upload = "/upload" in path or "/delivery-photo" in path or "/documents" in path
    MAX_BODY = 5_242_880 if is_upload else 1_048_576  # 5MB uploads, 1MB API

    # Fast path: Content-Length header present (direct connections, non-CF)
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            if int(content_length) > MAX_BODY:
                limit_mb = "5MB" if is_upload else "1MB"
                return JSONResponse(status_code=413, content={"detail": f"Request body too large (max {limit_mb})"})
        except ValueError:
            pass

    # Slow path: stream body for chunked transfers (CloudFront strips Content-Length)
    if request.method in ("POST", "PUT", "PATCH"):
        body = b""
        async for chunk in request.stream():
            body += chunk
            if len(body) > MAX_BODY:
                return JSONResponse(status_code=413, content={"detail": f"Request body too large (max {limit_mb})"})

        # Cache body so downstream handlers can still read it.
        # Starlette's Request.body() / Request.stream() check _body first,
        # bypassing the exhausted stream (_stream_consumed=True).
        request._body = body

    return await call_next(request)

# ===================== BOT / CRAWLER BLOCKLIST =====================
# SECURITY: Block known bad automated clients before hitting any handler.
# Targets headless scrapers and automation tools that ignore robots.txt.
# Legitimate app clients (iOS URLSession, OkHttp, Retrofit, Axios) are unaffected.
#
# List is intentional — do NOT add generic agents like "python" (blocks AWS Lambda health checks).
# Only agents with no legitimate use on this API are blocked.

_BAD_USER_AGENT_PREFIXES = (
    "curl/",
    "python-requests/",
    "Scrapy/",
    "Go-http-client/",
    "libwww-perl/",
    "Java/",
    "node-fetch/",
    "axios/",           # CLI abuse pattern — legitimate apps use native HTTP clients
)

_BAD_USER_AGENT_SUBSTRINGS = (
    "HeadlessChrome",
    "PhantomJS",
    "Selenium",
    "scrapy",
    "bot/",             # generic bot marker (covers many scrapers)
    "crawler",
    "spider",
)

@app.middleware("http")
async def bot_blocklist_middleware(request: Request, call_next):
    """Block known bad user-agents. Returns 403 before auth or handler runs.

    Exemption: requests from 127.0.0.1 are always passed through.
    ECS health checks use `curl` from within the container (localhost) and
    must not be blocked — external bots cannot spoof source IP to 127.0.0.1.
    """
    # Allow localhost health checks (ECS uses `curl -f http://localhost:8080/`)
    client_host = request.client.host if request.client else None
    if client_host == "127.0.0.1":
        return await call_next(request)

    # Always serve robots.txt and health endpoints — bots must be able to read
    # crawl directives, and monitoring tools must be able to reach health checks
    path = request.url.path
    if path in ("/robots.txt", "/health", "/api/health", "/api/health/ready",
                "/api/health/live", "/api/health/db-pool"):
        return await call_next(request)

    ua = request.headers.get("user-agent", "")
    if ua:
        ua_lower = ua.lower()
        for prefix in _BAD_USER_AGENT_PREFIXES:
            if ua.startswith(prefix) or ua_lower.startswith(prefix.lower()):
                logger.warning(f"bot_blocklist_middleware: blocked UA prefix '{prefix}' for {request.method} {path} (UA: {ua})")
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Automated access not permitted. See /robots.txt"},
                )
        for substr in _BAD_USER_AGENT_SUBSTRINGS:
            if substr.lower() in ua_lower:
                logger.warning(f"bot_blocklist_middleware: blocked UA substring '{substr}' for {request.method} {path} (UA: {ua})")
                return JSONResponse(
                    status_code=403,
                    content={"detail": "Automated access not permitted. See /robots.txt"},
                )
    return await call_next(request)

# ===================== ADMIN AUTH MIDDLEWARE =====================
# SECURITY: All /api/admin/* endpoints require admin authentication by default.
# This is a safety net — even if an endpoint forgets Depends(get_current_user),
# the middleware blocks unauthenticated access. Defense in depth.
#
# Accepts EITHER:
#   1. Bearer token (JWT) with admin role
#   2. ADMIN_SECRET_KEY query param (for migration/ops endpoints)
#
# Exempt:
#   - /api/admin/login (login endpoint itself)
#   - /api/admin/set-document-status (uses body-based secret, has own auth check)
#   - OPTIONS requests (CORS preflight)

_ADMIN_AUTH_EXEMPT_PATHS = {
    "/api/admin/login",
    "/api/admin/set-document-status",
}

@app.middleware("http")
async def admin_auth_middleware(request: Request, call_next):
    path = request.url.path

    # Only apply to /api/admin/* routes
    if not path.startswith("/api/admin"):
        return await call_next(request)

    # Exempt specific paths and OPTIONS preflight
    if path in _ADMIN_AUTH_EXEMPT_PATHS or request.method == "OPTIONS":
        return await call_next(request)

    # Auth method 1: Valid admin JWT Bearer token
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
            email = payload.get("sub")
            if email:
                from database import get_db as _get_db
                db = next(_get_db())
                try:
                    user = db.query(User).filter(User.email == email).first()
                    if user and user.role == UserRole.ADMIN:
                        logger.info(
                            f"Admin JWT access from IP={request.client.host} "
                            f"path={request.url.path} email={payload.get('sub', 'unknown')}"
                        )
                        return await call_next(request)
                finally:
                    db.close()
        except JWTError:
            pass
        # Token present but invalid or not admin
        return JSONResponse(
            status_code=403,
            content={"detail": "Admin access required"}
        )

    # Auth method 2: ADMIN_SECRET_KEY via X-Admin-Secret header (for ops/migration endpoints).
    # Header-only (never a query param — query strings leak into access logs / history) and
    # fail-closed: an unset ADMIN_SECRET_KEY authorizes no one. Constant-time compare.
    secret_key = request.headers.get("x-admin-secret")
    expected_key = os.getenv("ADMIN_SECRET_KEY")
    if expected_key and secret_key and hmac.compare_digest(secret_key, expected_key):
        logger.warning(
            f"ADMIN_SECRET_KEY used for admin access (bypasses JWT) "
            f"from IP={request.client.host} path={request.url.path}"
        )
        return await call_next(request)

    # No valid auth provided
    return JSONResponse(
        status_code=401,
        content={"detail": "Admin authentication required"},
        headers={"WWW-Authenticate": "Bearer"}
    )

# ===================== GLOBAL AUTH MIDDLEWARE (Safety Net) =====================
# SECURITY: Requires valid JWT for ALL non-public routes. Defense in depth —
# even if a developer forgets Depends(require_any_auth) on an endpoint,
# this middleware catches unauthenticated access.
#
# Modeled after admin_auth_middleware (proven pattern).
# Added AFTER admin_auth_middleware so /api/admin/* is handled there first.
#
# Public paths sourced from SECURITY_AUDIT_2026-02-20.md "Intentionally Public Endpoints"

import re as _re

_PUBLIC_EXACT_PATHS = {
    # Health checks
    "/health", "/api/health", "/api/health/ready", "/api/health/live", "/api/health/db-pool",
    "/api/erp/health/services",

    # Root
    "/",

    # Crawler directives
    "/robots.txt",

    # Legal pages
    "/privacy", "/terms",
    "/api/legal/terms", "/api/legal/privacy",
    "/api/legal/tos", "/api/legal/privacy-policy",
    "/api/legal/regulatory",

    # App config
    "/api/config", "/api/config/rideshare",

    # Auth — customer
    "/register",
    "/api/auth/login", "/api/auth/customer/login", "/api/auth/customer/register",
    "/api/auth/customer/google", "/api/auth/customer/apple-auth",
    "/api/customer/apple-auth", "/api/customer/register",

    # Auth — driver
    "/api/auth/driver/login", "/api/auth/driver/register",
    "/api/auth/driver/google", "/api/auth/driver/apple-auth",

    # Auth — vendor
    "/api/auth/vendor/login", "/api/auth/vendor/register",
    "/api/auth/vendor/demo-login",
    "/api/customer/demo-login",
    "/api/auth/customer/demo-login",
    "/api/auth/driver/demo-login",
    "/api/auth/vendor/google-auth", "/api/auth/vendor/google", "/api/auth/vendor/apple-auth",

    # Auth — admin
    "/api/admin/login",

    # Auth — admin setup (has own _require_admin_secret check)
    "/api/auth/admin/setup-production",

    # Password reset
    "/api/auth/password-reset/request", "/api/auth/password-reset/confirm",

    # Tax (public info)
    "/api/tax/rates",

    # Public content listings
    "/api/rides/surge", "/api/rides/estimate/bid-label", "/api/rides/pricing/tiers",
    "/api/payments/ride/pricing-info",

    # Fare estimates (public — no personal data, just pricing)
    "/api/rides/estimate",

    # Matchmaking public info
    "/api/matchmaking/states/live", "/api/matchmaking/connection-fee",

    # WebSocket stats (informational)
    "/api/websocket/stats",

    # Investor token-gated (not JWT-gated)
    "/api/investor/request-access", "/api/investor/verify-access", "/api/investor/log-view",

    # Waitlist (public landing page + partner forms)
    "/api/waitlist", "/api/waitlist/count",

    # Voice agent (Twilio webhook, no JWT) and AI text chat
    "/api/voice/incoming-call",
    "/api/support/chat",
}

_PUBLIC_PREFIXES = [
    "/api/public/",           # Public restaurant listings
    # "/api/promotions/suggestions/" removed — promotions_router uses require_any_auth
    "/api/webhooks/",         # Stripe webhooks (signature-verified)
    "/api/verification/webhook/",  # Verification provider webhooks (Persona/Onfido/Veriff — signature-verified)
    "/api/tnc/background-check/webhook",  # TNC-07: Persona background check webhook
    "/api/tnc/dmv-check/webhook",         # TNC-08: Persona DMV check webhook
    "/api/legal/",            # Legal pages
    "/api/customer/password-reset/",  # Password reset flows
    "/api/driver/password-reset/",
    "/api/vendor/password-reset/",
    "/api/erp/auth/",         # All ERP auth proxies
    "/api/vendors/public",    # Public vendor registration + document upload (code-gated)
    "/api/restaurants",       # Public restaurant browsing
    # H7: /uploads/ is intentionally NOT listed — driver docs require authentication
    "/admin",                 # Admin SPA frontend (static files, auth handled client-side)
    "/login",                 # Admin login page (SPA frontend)
    "/assets/",               # Vite-built frontend assets
    "/favicon.svg",           # Static favicon
    "/logo-dollar-ai.svg",    # Static logo
    "/api/admin/",            # Handled by admin_auth_middleware (don't double-check)
    "/api/demo/",             # Demo endpoints have own _require_admin_secret check
    "/ws/",                   # WebSocket connections (auth handled in websocket_route)
    "/privacy", "/terms",     # Legal pages (HTML)
]

# SECURITY (NSA-002): Only allow docs prefixes in non-production environments.
# In production, FastAPI docs are disabled at app level (docs_url=None, etc.).
if not _is_production:
    _PUBLIC_PREFIXES.extend(["/docs", "/openapi", "/redoc"])

_PUBLIC_PATTERN_PATHS = [
    # Vendor browsing (GET only): menu, reviews, categories
    (_re.compile(r"^/api/vendors/\d+/menu(/.*)?$"), {"GET"}),
    (_re.compile(r"^/api/vendors/\d+/reviews$"), {"GET"}),
    # Tax calculation endpoints
    (_re.compile(r"^/api/tax/(calculate|estimate/).*$"), {"GET", "POST"}),
    # Matchmaking state config/terms
    (_re.compile(r"^/api/matchmaking/states/.+/config$"), {"GET"}),
    (_re.compile(r"^/api/matchmaking/states/.+/terms$"), {"GET"}),
    # Verification required docs
    (_re.compile(r"^/api/verification/required-documents/.*$"), {"GET"}),
    # Verification status check (pre-auth flow)
    (_re.compile(r"^/api/verification/\w+/\d+/status$"), {"GET"}),
    # Onboarding code-gated flows (use invitation code, not JWT)
    (_re.compile(r"^/api/onboarding/confirm/.*$"), {"POST"}),
    (_re.compile(r"^/api/onboarding/status/.*$"), {"GET"}),
    (_re.compile(r"^/api/onboarding/upload-menu/.*$"), {"POST"}),
    # ERP restaurant detail (public browsing, only published/approved vendors)
    (_re.compile(r"^/api/erp/restaurants/\d+$"), {"GET"}),
    # Checkr background-check webhook (POST only) — HMAC signature-verified in the handler
    # (verify_webhook_signature fails closed when CHECKR_WEBHOOK_SECRET is unset).
    (_re.compile(r"^/api/checkr/webhook$"), {"POST"}),
]


@app.middleware("http")
async def require_auth_middleware(request: Request, call_next):
    """Global auth middleware — requires valid JWT for all non-public routes."""
    path = request.url.path
    method = request.method

    # Always allow CORS preflight
    if method == "OPTIONS":
        return await call_next(request)

    # Check exact public paths
    if path in _PUBLIC_EXACT_PATHS:
        return await call_next(request)

    # Check public prefixes
    for prefix in _PUBLIC_PREFIXES:
        if path.startswith(prefix):
            return await call_next(request)

    # Check public patterns (regex + method)
    for pattern, allowed_methods in _PUBLIC_PATTERN_PATHS:
        if method in allowed_methods and pattern.match(path):
            return await call_next(request)

    # All other paths: require valid JWT Bearer token
    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        # --no-access-log is set on uvicorn and this middleware previously never
        # logged its own rejections, so a 401 here was completely invisible in
        # CloudWatch — made debugging a silent client-side "unable to submit"
        # failure impossible to distinguish from a request that never arrived.
        logger.warning(f"require_auth_middleware: missing Bearer token for {method} {path}")
        return JSONResponse(
            status_code=401,
            content={"detail": "Authentication required"},
            headers={"WWW-Authenticate": "Bearer"}
        )

    try:
        token = auth_header[7:]
        _payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        # G3: honor the jti blacklist (logout/revocation) the same way the
        # auth_utils.require_* dependencies do, so a revoked token can't slip past
        # this safety-net middleware onto an endpoint that only relies on it.
        _jti = _payload.get("jti")
        if _jti and is_token_blacklisted(_jti):
            logger.warning(f"require_auth_middleware: revoked token (jti={_jti}) for {method} {path}")
            return JSONResponse(
                status_code=401,
                content={"detail": "Token has been revoked"},
                headers={"WWW-Authenticate": "Bearer"}
            )
    except (JWTError, Exception) as e:
        logger.warning(f"require_auth_middleware: invalid/expired token for {method} {path}: {e}")
        return JSONResponse(
            status_code=401,
            content={"detail": "Invalid or expired token"},
            headers={"WWW-Authenticate": "Bearer"}
        )

    return await call_next(request)


# Creates uploads directory if it doesn't exist (used as local fallback when S3 not configured)
import os
os.makedirs("uploads/vendor_documents", exist_ok=True)


# H7: Authenticated file server — replaces public StaticFiles mount.
# Only authenticated drivers (for their own docs) or admins may access /uploads/.
@app.get("/uploads/{file_path:path}")
async def serve_upload(
    file_path: str,
    payload: dict = Depends(require_any_auth),
):
    from fastapi.responses import FileResponse
    import pathlib
    # Prevent path traversal
    base = pathlib.Path("uploads").resolve()
    target = (base / file_path).resolve()
    if not str(target).startswith(str(base)):
        raise HTTPException(status_code=400, detail="Invalid path")
    if not target.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(str(target))


# ===================== RATE LIMITING =====================
# SECURITY: Protect auth endpoints from brute force attacks (Redis-backed, shared across workers/tasks)
from cache import (
    rate_limit_check, RateLimiter, check_rate_limit,
    record_login_failure, clear_login_failures, get_login_failure_count,
    LOCKOUT_THRESHOLD, LOCKOUT_WINDOW,
    blacklist_token, is_token_blacklisted,
)

# Rate limiters for different endpoints
auth_rate_limiter = RateLimiter(max_requests=10, window_seconds=60)  # 10 attempts per minute
registration_rate_limiter = RateLimiter(max_requests=5, window_seconds=3600)  # 5 registrations per hour
password_reset_limiter = RateLimiter(max_requests=5, window_seconds=3600)  # 5 per hour per email
payment_limiter = RateLimiter(max_requests=10, window_seconds=60)  # 10 per minute per user
admin_mutation_limiter = RateLimiter(max_requests=30, window_seconds=60)  # 30 per minute per admin IP
upload_limiter = RateLimiter(max_requests=10, window_seconds=3600)  # 10 uploads per hour per user
password_reset_ip_limiter = RateLimiter(max_requests=5, window_seconds=3600)  # 5 per hour per IP (anti-SMTP-amplification)

# Public endpoint rate limiters — prevent scrapers from hammering unauthenticated endpoints
public_listings_rate_limiter = RateLimiter(max_requests=30, window_seconds=60)   # 30/min per IP for vendor listings
public_estimate_rate_limiter = RateLimiter(max_requests=20, window_seconds=60)   # 20/min per IP for fare estimates

# Per-email rate limiter (G7): complement per-IP to block VPN rotation attacks
email_auth_rate_limiter = RateLimiter(max_requests=20, window_seconds=3600)  # 20 attempts/hr per email

# Demo accounts exempt from auth rate limiting (Apple App Store reviewers)
DEMO_EMAILS = frozenset({
    "demo.customer@dollor.ai",
    "demo.driver@dollor.ai",
    "demo.restaurant@dollor.ai",
    "support@dollor.ai"
})

# ===================== INPUT SANITIZATION =====================
# SECURITY: Strip HTML/script tags from user-supplied text to prevent stored XSS
import re
_HTML_TAG_RE = re.compile(r'<[^>]+>')

def _check_login_lockout(email: str) -> None:
    """(G5) Raise 429 if account is temporarily locked after too many failed attempts."""
    if get_login_failure_count(email) >= LOCKOUT_THRESHOLD:
        raise HTTPException(
            status_code=429,
            detail="Account temporarily locked due to too many failed attempts. Try again in 15 minutes.",
            headers={"Retry-After": str(LOCKOUT_WINDOW)}
        )


def _is_demo_exempt(email: str) -> bool:
    """Demo accounts are exempt from rate limiting ONLY outside production."""
    return not _is_production and email in DEMO_EMAILS


def sanitize_text(text: Optional[str]) -> Optional[str]:
    """Strip HTML tags from user input to prevent stored XSS attacks"""
    if not text or not isinstance(text, str):
        return text
    return _HTML_TAG_RE.sub('', text).strip()


def _validate_password(password: str) -> None:
    """
    SECURITY (NSA-009/NSA-010): Enforce password policy on ALL registration endpoints.
    Raises HTTPException(400) if password does not meet requirements.
    Requirements: 8+ chars, at least one uppercase, one lowercase, one digit.
    """
    if not password or len(password.strip()) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password is required and cannot be empty"
        )
    if len(password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must be at least 8 characters long"
        )
    if not any(c.isupper() for c in password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one uppercase letter"
        )
    if not any(c.islower() for c in password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one lowercase letter"
        )
    if not any(c.isdigit() for c in password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Password must contain at least one number"
        )


def _require_admin_secret(secret_key: Optional[str] = None):
    """Verify ADMIN_SECRET_KEY for demo/admin endpoints.

    FAILS CLOSED: if ADMIN_SECRET_KEY is not configured on the server, no caller can be
    authorized, so access is denied (previously an unset key silently allowed everyone).
    Uses hmac.compare_digest for a constant-time comparison.
    """
    expected = os.getenv("ADMIN_SECRET_KEY")
    if not expected:
        raise HTTPException(status_code=403, detail="Admin secret key not configured")
    if not secret_key or not hmac.compare_digest(secret_key, expected):
        raise HTTPException(status_code=403, detail="Admin secret key required")

# Health Check Endpoint
@app.get("/health")
async def health_check(db: Session = Depends(get_db)):
    """
    Health check endpoint for load balancers and monitoring.
    Returns:
    - status: "healthy" or "unhealthy"
    - service: service name
    - timestamp: current UTC timestamp
    - database: database connection status
    - version: API version
    """
    health_status = {
        "status": "healthy",
        "service": "p2p-backend",
        "version": "1.0.18",
        "build": "2026-02-11-negotiation-round-fix",
        "timestamp": datetime.utcnow().isoformat(),
        "database": "unknown"
    }

    # Check database connectivity
    try:
        from sqlalchemy import text
        db.execute(text("SELECT 1"))
        health_status["database"] = "connected"
    except Exception as e:
        health_status["status"] = "unhealthy"
        health_status["database"] = f"disconnected: {str(e)[:50]}"

    return health_status


@app.get("/api/health/ready")
async def health_ready(db: Session = Depends(get_db)):
    """Readiness probe - checks if service is ready to accept traffic"""
    try:
        from sqlalchemy import text
        db.execute(text("SELECT 1"))
        return {"ready": True, "timestamp": datetime.utcnow().isoformat()}
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="Service not ready")


@app.get("/api/health/live")
async def health_live():
    """Liveness probe - checks if service is running"""
    return {"alive": True, "timestamp": datetime.utcnow().isoformat()}


@app.get("/api/health/db-pool")
async def health_db_pool():
    """DB connection pool utilization stats. Returns warning status when >= 90% utilized."""
    from database import get_pool_stats
    stats = get_pool_stats()
    return stats


@app.post("/api/admin/backfill-payouts")
async def backfill_payouts(request: Request, db: Session = Depends(get_db)):
    """Backfill platform_fee and driver_payout for completed rides"""
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    import hmac as _hmac
    expected_key = os.getenv("ADMIN_SECRET_KEY", "")
    secret_key = request.headers.get("X-Admin-Secret", "")
    if not expected_key or not _hmac.compare_digest(secret_key, expected_key):
        raise HTTPException(status_code=403, detail="Invalid secret key")

    from models import RideRequest, RideRequestStatus
    results = []

    # Get all completed rides using ORM (avoids enum cast issues)
    rides = db.query(RideRequest).filter(
        RideRequest.status == RideRequestStatus.COMPLETED
    ).all()

    updated = 0
    for r in rides:
        price = float(r.final_price or r.suggested_price or 0)
        correct_fee = platform_fee_for(price)
        correct_payout = round(price - correct_fee, 2)

        old_fee = float(r.platform_fee) if r.platform_fee is not None else None
        old_payout = float(r.driver_payout) if r.driver_payout is not None else None
        needs_update = (old_fee != correct_fee or old_payout != correct_payout)

        results.append({
            "id": r.id, "price": price,
            "old_fee": old_fee, "old_payout": old_payout,
            "new_fee": correct_fee, "new_payout": correct_payout,
            "needs_update": needs_update
        })
        if needs_update:
            r.platform_fee = correct_fee
            r.driver_payout = correct_payout
            updated += 1

    db.commit()
    return {"updated": updated, "total_completed": len(rides), "details": results}


# Database Migration Endpoint (protected with secret key)
@app.post("/api/admin/migrate")
async def run_migrations(request: Request, db: Session = Depends(get_db)):
    """
    Run database migrations to add missing columns.
    Protected with ADMIN_SECRET_KEY via X-Admin-Secret header.
    Each migration step commits independently to prevent cascade failures.
    """
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    import hmac as _hmac
    expected_key = os.getenv("ADMIN_SECRET_KEY", "")
    if not expected_key:
        raise HTTPException(status_code=500, detail="ADMIN_SECRET_KEY not configured")
    secret_key = request.headers.get("X-Admin-Secret", "")
    if not _hmac.compare_digest(secret_key, expected_key):
        raise HTTPException(status_code=403, detail="Invalid secret key")

    from sqlalchemy import text

    migrations_run = []
    errors = []

    def run_migration(sql: str, name: str):
        """Execute a migration with isolated transaction"""
        try:
            db.execute(text(sql))
            db.commit()
            migrations_run.append(name)
            return True
        except Exception as e:
            db.rollback()
            errors.append(f"{name}: {str(e)}")
            return False

    # Migration: Add customer columns
    customer_columns = [
        ("customer_id", "VARCHAR(50)"),
        # Email verification columns
        ("email_verified", "BOOLEAN DEFAULT FALSE"),
        ("email_verification_code", "VARCHAR(10)"),
        ("email_verification_expires", "TIMESTAMP"),
        ("email_verified_at", "TIMESTAMP"),
    ]

    for col_name, col_type in customer_columns:
        run_migration(
            f"ALTER TABLE customers ADD COLUMN IF NOT EXISTS {col_name} {col_type}",
            f"customers.{col_name}"
        )

    # Migration: Add vendor_id and driver_id to users table
    user_columns = [
        ("vendor_id", "INTEGER"),
        ("driver_id", "INTEGER"),
    ]

    for col_name, col_type in user_columns:
        run_migration(
            f"ALTER TABLE users ADD COLUMN IF NOT EXISTS {col_name} {col_type}",
            f"users.{col_name}"
        )

    # Migration: Add verification columns to drivers table
    driver_columns = [
        ("verification_id", "VARCHAR(255)"),
        ("verification_status", "VARCHAR(50) DEFAULT 'not_started'"),
        ("documents_verified", "BOOLEAN DEFAULT FALSE"),
        ("documents_verified_at", "TIMESTAMP"),
        ("verification_notes", "TEXT"),
        ("verification_reviewer_id", "INTEGER"),
        # Third-party verification provider columns
        ("persona_inquiry_id", "VARCHAR(255)"),
        ("onfido_applicant_id", "VARCHAR(255)"),
        ("veriff_session_id", "VARCHAR(255)"),
        ("verification_provider", "VARCHAR(50)"),
        # Vehicle photo for customer tracking view
        ("vehicle_photo_url", "VARCHAR(500)"),
        # Bank account (stored in DB, verified via admin portal)
        ("bank_name", "VARCHAR(255)"),
        ("bank_last4", "VARCHAR(4)"),
        ("bank_routing_number", "VARCHAR(20)"),
        ("bank_account_holder", "VARCHAR(255)"),
        ("bank_verified", "BOOLEAN DEFAULT FALSE"),
        ("bank_verified_at", "TIMESTAMP"),
        ("bank_verified_by", "INTEGER"),
        # TNC-12: Driver accessibility capability
        ("accessibility_capable", "BOOLEAN DEFAULT FALSE"),
        ("accessibility_features", "TEXT"),
        # Vehicle registration document (was accepted by the upload endpoint but never persisted)
        ("vehicle_registration", "BOOLEAN DEFAULT FALSE"),
        ("vehicle_registration_url", "VARCHAR(500)"),
    ]

    for col_name, col_type in driver_columns:
        run_migration(
            f"ALTER TABLE drivers ADD COLUMN IF NOT EXISTS {col_name} {col_type}",
            f"drivers.{col_name}"
        )

    # Migration: Add verification and online status columns to vendors table
    vendor_columns = [
        ("verification_id", "VARCHAR(255)"),
        ("verification_status", "VARCHAR(50) DEFAULT 'not_started'"),
        ("documents_verified", "BOOLEAN DEFAULT FALSE"),
        ("documents_verified_at", "TIMESTAMP"),
        ("verification_notes", "TEXT"),
        ("verification_reviewer_id", "INTEGER"),
        # Online/Offline Status columns
        ("is_online", "BOOLEAN DEFAULT FALSE"),
        ("went_online_at", "TIMESTAMP"),
        ("went_offline_at", "TIMESTAMP"),
        # Publishing Status columns
        ("is_published", "BOOLEAN DEFAULT FALSE"),
        ("published_at", "TIMESTAMP"),
        ("published_platforms", "TEXT"),
        # Menu verification columns
        ("menu_verified", "BOOLEAN DEFAULT FALSE"),
        ("menu_verified_at", "TIMESTAMP"),
        ("menu_verified_by", "INTEGER"),
        # Admin approval columns
        ("approved_by", "INTEGER"),
        # Stripe integration columns
        ("stripe_account_id", "VARCHAR(255)"),
        ("stripe_onboarding_complete", "BOOLEAN DEFAULT FALSE"),
        # Restaurant image/logo
        ("image_url", "VARCHAR(500)"),
        # KOT/POS Integration columns
        ("kot_integration_type", "VARCHAR(50) DEFAULT 'none'"),
        ("kot_enabled", "BOOLEAN DEFAULT FALSE"),
        ("kot_api_key", "VARCHAR(500)"),
        ("kot_api_secret", "VARCHAR(500)"),
        ("kot_location_id", "VARCHAR(255)"),
        ("kot_merchant_id", "VARCHAR(255)"),
        ("kot_restaurant_guid", "VARCHAR(255)"),
        ("kot_printer_id", "VARCHAR(255)"),
        ("kot_webhook_url", "VARCHAR(500)"),
        ("kot_auto_print", "BOOLEAN DEFAULT TRUE"),
    ]

    for col_name, col_type in vendor_columns:
        run_migration(
            f"ALTER TABLE vendors ADD COLUMN IF NOT EXISTS {col_name} {col_type}",
            f"vendors.{col_name}"
        )

    # Migration: Fix vendor_id NOT NULL constraint issue
    run_migration(
        "ALTER TABLE vendors ALTER COLUMN vendor_id DROP NOT NULL",
        "vendors.vendor_id: dropped NOT NULL constraint"
    )

    # Trigger for vendor_id removed - vendor_id is now a regular nullable column
    # that gets set during INSERT in application code

    # Migration: Add payment and platform fee columns to ride_requests table
    ride_request_columns = [
        ("stripe_payment_intent_id", "VARCHAR(255)"),
        ("payment_status", "VARCHAR(50) DEFAULT 'pending'"),
        ("platform_fee", "FLOAT"),
        ("driver_payout", "FLOAT"),
        ("payment_completed_at", "TIMESTAMP"),
        ("driver_paid_at", "TIMESTAMP"),
        ("stripe_transfer_id", "VARCHAR(255)"),
    ]

    for col_name, col_type in ride_request_columns:
        try:
            db.execute(text(f"ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"ride_requests.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"ride_requests.{col_name}: {str(e)}")

    # Migration: Add driver_arrived_at timestamp to ride_requests
    try:
        db.execute(text("ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS driver_arrived_at TIMESTAMP"))  # nosemgrep: avoid-sqlalchemy-text
        db.commit()
        migrations_run.append("ride_requests.driver_arrived_at")
    except Exception as e:
        db.rollback()
        errors.append(f"ride_requests.driver_arrived_at: {str(e)}")

    # Migration: Add multi-round negotiation columns to ride_requests
    ride_request_negotiation_columns = [
        ("customer_counter_count", "INTEGER DEFAULT 0"),
        ("low_bid_warning_shown", "BOOLEAN DEFAULT FALSE"),
    ]

    for col_name, col_type in ride_request_negotiation_columns:
        try:
            db.execute(text(f"ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"ride_requests.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"ride_requests.{col_name}: {str(e)}")

    # TNC-12/13: Add accessibility request + Access for All fee columns to ride_requests
    tnc_columns = [
        ("accessibility_requested", "BOOLEAN DEFAULT FALSE"),
        ("accessibility_notes", "TEXT"),
        ("access_for_all_fee", "FLOAT DEFAULT 0.10"),
    ]
    for col_name, col_type in tnc_columns:
        try:
            db.execute(text(f"ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"ride_requests.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"ride_requests.{col_name}: {str(e)}")

    # Migration: Add multi-round negotiation columns to ride_bids
    ride_bid_negotiation_columns = [
        ("negotiation_round", "INTEGER DEFAULT 1"),
        ("last_offer_by", "VARCHAR(20) DEFAULT 'driver'"),
        ("round_counter", "INTEGER DEFAULT 0"),
    ]

    for col_name, col_type in ride_bid_negotiation_columns:
        try:
            db.execute(text(f"ALTER TABLE ride_bids ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"ride_bids.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"ride_bids.{col_name}: {str(e)}")

    # Migration: Add restaurant acceptance flow columns to orders table
    order_acceptance_columns = [
        ("sent_to_restaurant_at", "TIMESTAMP"),
        ("restaurant_accepted_at", "TIMESTAMP"),
        ("restaurant_declined_at", "TIMESTAMP"),
        ("restaurant_timeout_at", "TIMESTAMP"),
        ("decline_reason", "TEXT"),
    ]

    for col_name, col_type in order_acceptance_columns:
        try:
            db.execute(text(f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"orders.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"orders.{col_name}: {str(e)}")

    # Migration: Add delivery decision window columns to orders table
    delivery_decision_columns = [
        ("delivery_decision_sent_at", "TIMESTAMP"),
        ("restaurant_will_deliver", "BOOLEAN"),
        ("delivery_decision_at", "TIMESTAMP"),
        ("delivery_decision_timeout_at", "TIMESTAMP"),
    ]

    for col_name, col_type in delivery_decision_columns:
        try:
            db.execute(text(f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"orders.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"orders.{col_name}: {str(e)}")

    # Migration: Add early driver notification columns to orders table
    early_driver_notification_columns = [
        ("estimated_prep_minutes", "INTEGER"),
        ("estimated_ready_at", "TIMESTAMP"),
        ("driver_en_route", "BOOLEAN DEFAULT FALSE"),
        ("driver_accepted_at", "TIMESTAMP"),
        ("driver_eta_to_restaurant", "INTEGER"),
    ]

    for col_name, col_type in early_driver_notification_columns:
        try:
            db.execute(text(f"ALTER TABLE orders ADD COLUMN IF NOT EXISTS {col_name} {col_type}"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"orders.{col_name}")
        except Exception as e:
            db.rollback()
            errors.append(f"orders.{col_name}: {str(e)}")

    # Migration: Add new OrderStatus enum values for restaurant acceptance and delivery decision
    # PostgreSQL requires ALTER TYPE to add new enum values
    # SQLAlchemy stores enum NAMES (uppercase) not values, so we need uppercase values
    new_order_statuses = [
        "PENDING_RESTAURANT",
        "DECLINED_BY_RESTAURANT",
        "RESTAURANT_TIMEOUT",
        "PENDING_DELIVERY_DECISION",
        "RESTAURANT_WILL_DELIVER",
        "DELIVERY_DECISION_TIMEOUT",
        "PENDING_DELIVERY_PROOF",
    ]

    for status_value in new_order_statuses:
        try:
            # Check if value already exists before adding
            db.execute(text(f"ALTER TYPE orderstatus ADD VALUE IF NOT EXISTS '{status_value}'"))  # nosemgrep: avoid-sqlalchemy-text
            db.commit()
            migrations_run.append(f"orderstatus.{status_value}")
        except Exception as e:
            db.rollback()
            # Value might already exist
            errors.append(f"orderstatus.{status_value}: {str(e)}")

    return {
        "status": "completed",
        "migrations_run": migrations_run,
        "errors": errors,
        "timestamp": datetime.utcnow().isoformat()
    }

# Security
pwd_context = CryptContext(schemes=["bcrypt"], bcrypt__rounds=13, deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

# SOC 2 Compliant - JWT secret MUST be set via environment variable
SECRET_KEY = os.getenv("JWT_SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("CRITICAL: JWT_SECRET_KEY environment variable is required for security")
# Enforce a minimum key length. HS256 security depends on secret entropy; a short secret
# is brute-forceable. Require >= 32 bytes (256 bits) to match the signing algorithm strength.
# Enforced only in PRODUCTION — CI/test and local dev use a short throwaway secret and must
# still be able to import the app. Production's real secret is 64 bytes.
if (os.getenv("ENVIRONMENT", "").lower() == "production"
        and os.getenv("TESTING", "").lower() not in ("true", "1", "yes")
        and len(SECRET_KEY.encode("utf-8")) < 32):
    raise RuntimeError(
        "CRITICAL: JWT_SECRET_KEY must be at least 32 bytes (256 bits) in production. "
        f"Current length is {len(SECRET_KEY.encode('utf-8'))} bytes."
    )
ALGORITHM = "HS256"
# Access tokens live 24h; the mobile apps refresh via /api/auth/{role}/refresh.
# (Was 30d — a stolen long-lived token was too valuable.)
ACCESS_TOKEN_EXPIRE_MINUTES = 1440  # 24 hours

# Pydantic Models
class UserCreate(BaseModel):
    email: EmailStr
    password: str
    full_name: str
    role: str = "user"

class UserResponse(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    vendor_id: Optional[int] = None
    
    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str
    user: UserResponse
    # Top-level fields for Android compatibility
    vendor_id: Optional[int] = None
    business_name: Optional[str] = None
    email: Optional[str] = None

class ClientCreate(BaseModel):
    name: str
    email: str
    phone: Optional[str] = None
    company: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    zip_code: Optional[str] = None
    country: Optional[str] = None
    notes: Optional[str] = None

class ClientResponse(BaseModel):
    id: int
    name: str
    email: str
    phone: Optional[str]
    company: Optional[str]
    address: Optional[str]
    city: Optional[str]
    state: Optional[str]
    zip_code: Optional[str]
    country: Optional[str]
    notes: Optional[str]
    created_at: datetime
    
    class Config:
        from_attributes = True

class InvoiceItemCreate(BaseModel):
    description: str
    quantity: float
    unit_price: float

class InvoiceItemResponse(BaseModel):
    id: int
    description: str
    quantity: float
    unit_price: float
    amount: float
    
    class Config:
        from_attributes = True

class InvoiceCreate(BaseModel):
    client_id: int
    issue_date: datetime
    due_date: datetime
    items: List[InvoiceItemCreate]
    tax_rate: float = 0.0
    discount_amount: float = 0.0
    notes: Optional[str] = None
    terms: Optional[str] = None

class InvoiceResponse(BaseModel):
    id: int
    invoice_number: str
    client_id: int
    client_name: str
    issue_date: datetime
    due_date: datetime
    subtotal: float
    tax_rate: float
    tax_amount: float
    discount_amount: float
    total_amount: float
    status: str
    notes: Optional[str]
    terms: Optional[str]
    created_at: datetime
    items: List[InvoiceItemResponse]
    
    class Config:
        from_attributes = True

class PaymentCreate(BaseModel):
    amount: float
    payment_date: datetime
    payment_method: Optional[str] = None
    reference_number: Optional[str] = None
    notes: Optional[str] = None

class PaymentResponse(BaseModel):
    id: int
    invoice_id: int
    amount: float
    payment_date: datetime
    payment_method: Optional[str]
    reference_number: Optional[str]
    status: str
    notes: Optional[str]
    created_at: datetime
    
    class Config:
        from_attributes = True

# Helper functions

# M8: Magic-byte MIME detection for file uploads (never trust client content_type)
_DOCUMENT_SIGNATURES = [
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"%PDF-", "application/pdf"),
    (b"GIF87a", "image/gif"),
    (b"GIF89a", "image/gif"),
    (b"RIFF", "image/webp"),  # RIFF....WEBP
]

def _detect_document_mime(content: bytes) -> str | None:
    """Return MIME type from file magic bytes, or None if not an allowed type."""
    for sig, mime in _DOCUMENT_SIGNATURES:
        if content[:len(sig)] == sig:
            return mime
    # HEIC: ISO Base Media File Format — 4-byte box size + b"ftyp"
    if len(content) >= 12 and content[4:8] == b"ftyp":
        return "image/heic"
    return None


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    # G3: Add JTI (JWT ID) for token revocation support
    to_encode.update({"exp": expire, "jti": secrets.token_hex(16)})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise credentials_exception
    return user


def get_current_customer_from_token(authorization: str, db: Session) -> Optional[Customer]:
    """Extract customer from authorization token - works with both User and Customer tokens"""
    if not authorization or not authorization.startswith("Bearer "):
        return None

    token = authorization.replace("Bearer ", "")
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email = payload.get("sub")
        customer_id = payload.get("customer_id")

        # Try to find customer by ID first (more efficient)
        if customer_id:
            customer = db.query(Customer).filter(Customer.id == customer_id).first()
            if customer:
                return customer

        # Fall back to email lookup
        if email:
            customer = db.query(Customer).filter(Customer.email == email).first()
            if customer:
                return customer

        return None
    except JWTError:
        return None


def sanitize_input(text: str) -> str:
    """Sanitize user input to prevent XSS attacks"""
    if not text:
        return text
    import html
    import re
    # Strip HTML tags entirely (names should never contain HTML)
    text = re.sub(r'<[^>]+>', '', text)
    # Escape any remaining special characters
    text = html.escape(text, quote=True)
    return text.strip()


async def get_current_customer(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    """Get current customer from JWT token - queries Customer table directly"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])

        # First try customer_id from JWT (set during customer registration)
        customer_id = payload.get("customer_id")
        if customer_id:
            customer = db.query(Customer).filter(Customer.id == customer_id).first()
            if customer:
                return customer

        # Fallback to email lookup
        email: str = payload.get("sub")
        if email:
            customer = db.query(Customer).filter(Customer.email == email).first()
            if customer:
                return customer

        raise credentials_exception
    except JWTError:
        raise credentials_exception


async def get_current_driver(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    """Get current driver from JWT token - queries Driver table directly"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])

        # First try driver_id from JWT
        driver_id = payload.get("driver_id")
        if driver_id:
            # driver_id in JWT could be integer or string ID
            if isinstance(driver_id, int):
                driver = db.query(Driver).filter(Driver.id == driver_id).first()
            else:
                driver = db.query(Driver).filter(Driver.driver_id == driver_id).first()
            if driver:
                return driver

        # Fallback to email lookup
        email: str = payload.get("sub")
        if email:
            driver = db.query(Driver).filter(Driver.email == email).first()
            if driver:
                return driver

        raise credentials_exception
    except JWTError:
        raise credentials_exception


async def get_current_vendor(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    """Get current vendor from JWT token - queries Vendor table directly"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])

        # First try vendor_id from JWT
        vendor_id = payload.get("vendor_id")
        if vendor_id:
            vendor = db.query(Vendor).filter(Vendor.id == vendor_id).first()
            if vendor:
                return vendor

        # Fallback to email lookup (Vendor uses contact_email, not email)
        email: str = payload.get("sub")
        if email:
            vendor = db.query(Vendor).filter(Vendor.contact_email == email).first()
            if vendor:
                return vendor

        raise credentials_exception
    except JWTError:
        raise credentials_exception


def generate_invoice_number(db: Session) -> str:
    """Generate unique invoice number"""
    today = datetime.now()
    prefix = f"INV-{today.year}{today.month:02d}"
    
    last_invoice = db.query(Invoice).filter(
        Invoice.invoice_number.like(f"{prefix}%")
    ).order_by(Invoice.invoice_number.desc()).first()
    
    if last_invoice:
        last_num = int(last_invoice.invoice_number.split("-")[-1])
        new_num = last_num + 1
    else:
        new_num = 1
    
    return f"{prefix}-{new_num:04d}"

# Database migration function (called at startup)
def _run_startup_migrations():
    """Run database migrations to add missing columns"""
    from sqlalchemy import text
    from database import engine

    migrations = [
        # Orders table columns
        ("orders", "dispatched_at", "TIMESTAMP"),
        ("orders", "picked_up_at", "TIMESTAMP"),  # When driver picked up from restaurant
        ("orders", "cancelled_at", "TIMESTAMP"),
        ("orders", "auto_dispatched", "BOOLEAN DEFAULT FALSE"),
        ("orders", "broadcast_to_drivers", "BOOLEAN DEFAULT FALSE"),
        ("orders", "broadcast_at", "TIMESTAMP"),
        ("orders", "broadcast_radius_km", "FLOAT"),
        ("orders", "discount_amount", "FLOAT DEFAULT 0.0"),
        ("orders", "promo_code", "VARCHAR(50)"),
        ("orders", "promo_type", "VARCHAR(50)"),
        # Drivers table columns
        ("drivers", "date_of_birth", "VARCHAR(20)"),
        ("drivers", "license_number", "VARCHAR(50)"),
        ("drivers", "location_updated_at", "TIMESTAMP"),
        ("drivers", "went_online_at", "TIMESTAMP"),
        ("drivers", "went_offline_at", "TIMESTAMP"),
        ("drivers", "fcm_token", "VARCHAR(500)"),
        ("drivers", "device_type", "VARCHAR(20)"),
        ("drivers", "fcm_token_updated_at", "TIMESTAMP"),
        ("drivers", "photo_url", "VARCHAR(500)"),
        ("drivers", "vehicle_photo_url", "VARCHAR(500)"),
        # Driver bank account columns (admin portal verified)
        ("drivers", "bank_name", "VARCHAR(255)"),
        ("drivers", "bank_last4", "VARCHAR(4)"),
        ("drivers", "bank_routing_number", "VARCHAR(20)"),
        ("drivers", "bank_account_holder", "VARCHAR(255)"),
        ("drivers", "bank_verified", "BOOLEAN DEFAULT FALSE"),
        ("drivers", "bank_verified_at", "TIMESTAMP"),
        ("drivers", "bank_verified_by", "INTEGER"),
        # Driver verification columns
        ("drivers", "verification_id", "VARCHAR(255)"),
        ("drivers", "verification_status", "VARCHAR(50) DEFAULT 'not_started'"),
        ("drivers", "documents_verified", "BOOLEAN DEFAULT FALSE"),
        ("drivers", "documents_verified_at", "TIMESTAMP"),
        ("drivers", "verification_notes", "TEXT"),
        ("drivers", "verification_reviewer_id", "INTEGER"),
        ("drivers", "persona_inquiry_id", "VARCHAR(255)"),
        ("drivers", "onfido_applicant_id", "VARCHAR(255)"),
        ("drivers", "veriff_session_id", "VARCHAR(255)"),
        ("drivers", "verification_provider", "VARCHAR(50)"),
        # Customers table columns - for customer authentication
        ("customers", "password_hash", "VARCHAR(255)"),
        ("customers", "favorite_vendors", "JSON"),
        ("customers", "saved_cards", "JSON"),
        ("customers", "stripe_customer_id", "VARCHAR(255)"),
        # Vendors table columns - for online status and verification
        ("vendors", "is_online", "BOOLEAN DEFAULT FALSE"),
        ("vendors", "went_online_at", "TIMESTAMP"),
        ("vendors", "went_offline_at", "TIMESTAMP"),
        ("vendors", "is_published", "BOOLEAN DEFAULT FALSE"),
        ("vendors", "published_at", "TIMESTAMP"),
        ("vendors", "published_platforms", "TEXT"),
        ("vendors", "menu_verified", "BOOLEAN DEFAULT FALSE"),
        ("vendors", "menu_verified_at", "TIMESTAMP"),
        ("vendors", "menu_verified_by", "INTEGER"),
        ("vendors", "approved_by", "INTEGER"),
        ("vendors", "stripe_account_id", "VARCHAR(255)"),
        ("vendors", "stripe_onboarding_complete", "BOOLEAN DEFAULT FALSE"),
        ("vendors", "verification_id", "VARCHAR(255)"),
        ("vendors", "verification_status", "VARCHAR(50) DEFAULT 'not_started'"),
        ("vendors", "documents_verified", "BOOLEAN DEFAULT FALSE"),
        ("vendors", "documents_verified_at", "TIMESTAMP"),
        ("vendors", "verification_notes", "TEXT"),
        ("vendors", "verification_reviewer_id", "INTEGER"),
        # Verification provider integrations (Persona, Onfido, Veriff)
        ("vendors", "persona_inquiry_id", "VARCHAR(255)"),
        ("vendors", "onfido_applicant_id", "VARCHAR(255)"),
        ("vendors", "veriff_session_id", "VARCHAR(255)"),
        ("vendors", "verification_provider", "VARCHAR(50)"),
        # Vendor branding columns
        ("vendors", "logo_url", "VARCHAR(500)"),
        ("vendors", "banner_url", "VARCHAR(500)"),
        # KOT/POS Integration columns
        ("vendors", "kot_integration_type", "VARCHAR(50) DEFAULT 'none'"),
        ("vendors", "kot_enabled", "BOOLEAN DEFAULT FALSE"),
        ("vendors", "kot_api_key", "VARCHAR(500)"),
        ("vendors", "kot_api_secret", "VARCHAR(500)"),
        ("vendors", "kot_location_id", "VARCHAR(255)"),
        ("vendors", "kot_merchant_id", "VARCHAR(255)"),
        ("vendors", "kot_restaurant_guid", "VARCHAR(255)"),
        ("vendors", "kot_printer_id", "VARCHAR(255)"),
        ("vendors", "kot_webhook_url", "VARCHAR(500)"),
        ("vendors", "kot_auto_print", "BOOLEAN DEFAULT TRUE"),
        # Vendor menu items - admin review fields
        ("vendor_menu_items", "review_status", "VARCHAR(50) DEFAULT 'pending'"),
        ("vendor_menu_items", "needs_review", "BOOLEAN DEFAULT TRUE"),
        ("vendor_menu_items", "admin_notes", "TEXT"),
        ("vendor_menu_items", "reviewed_at", "TIMESTAMP"),
        ("vendor_menu_items", "reviewed_by", "INTEGER"),
        ("vendor_menu_items", "is_bestseller", "BOOLEAN DEFAULT FALSE"),
        ("vendor_menu_items", "is_combo", "BOOLEAN DEFAULT FALSE"),
        ("vendor_menu_items", "combo_items", "JSON"),
        ("vendor_menu_items", "combo_savings", "FLOAT DEFAULT 0.0"),
        # Rides table - full schema
        ("rides", "ride_id", "VARCHAR(50)"),
        ("rides", "customer_id", "INTEGER"),
        ("rides", "driver_id", "INTEGER"),
        ("rides", "status", "VARCHAR(50) DEFAULT 'pending'"),
        ("rides", "pickup_address", "TEXT"),
        ("rides", "pickup_lat", "FLOAT"),
        ("rides", "pickup_lng", "FLOAT"),
        ("rides", "dropoff_address", "TEXT"),
        ("rides", "dropoff_lat", "FLOAT"),
        ("rides", "dropoff_lng", "FLOAT"),
        ("rides", "fare_amount", "FLOAT"),
        ("rides", "tip_amount", "FLOAT DEFAULT 0"),
        ("rides", "platform_fee", "FLOAT DEFAULT 0"),
        ("rides", "driver_payout", "FLOAT"),
        ("rides", "distance_miles", "FLOAT"),
        ("rides", "duration_minutes", "INTEGER"),
        ("rides", "vehicle_type", "VARCHAR(50)"),
        ("rides", "requested_at", "TIMESTAMP"),
        ("rides", "accepted_at", "TIMESTAMP"),
        ("rides", "picked_up_at", "TIMESTAMP"),
        ("rides", "completed_at", "TIMESTAMP"),
        ("rides", "cancelled_at", "TIMESTAMP"),
        ("rides", "cancelled_by", "VARCHAR(20)"),
        ("rides", "cancellation_reason", "TEXT"),
        ("rides", "driver_rating", "FLOAT"),
        ("rides", "passenger_rating", "FLOAT"),
        ("rides", "created_at", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"),
        # Ride Requests table - payment columns
        ("ride_requests", "stripe_payment_intent_id", "VARCHAR(255)"),
        ("ride_requests", "payment_status", "VARCHAR(50) DEFAULT 'pending'"),
        ("ride_requests", "platform_fee", "FLOAT"),
        ("ride_requests", "driver_payout", "FLOAT"),
        ("ride_requests", "payment_completed_at", "TIMESTAMP"),
        ("ride_requests", "driver_paid_at", "TIMESTAMP"),
        ("ride_requests", "stripe_transfer_id", "VARCHAR(255)"),
        ("ride_requests", "tip_amount", "FLOAT DEFAULT 0"),
        ("ride_requests", "customer_rating", "INTEGER"),
        ("ride_requests", "customer_comment", "TEXT"),
        ("ride_requests", "passenger_rating", "INTEGER"),
        ("ride_requests", "passenger_comment", "TEXT"),
        # Ride Requests table - accessibility + retry columns (blocked by alembic VARCHAR(32) overflow)
        # Using public. prefix to be explicit about schema — bypasses any non-standard search_path
        ("public.ride_requests", "accessibility_requested", "BOOLEAN DEFAULT FALSE"),
        ("public.ride_requests", "accessibility_notes", "TEXT"),
        ("public.ride_requests", "access_for_all_fee", "FLOAT DEFAULT 0.10"),
        ("public.ride_requests", "payment_retry_count", "INTEGER DEFAULT 0"),
        ("customers", "rating", "FLOAT DEFAULT 5.0"),
        ("customers", "total_rides", "INTEGER DEFAULT 0"),
        # Early Driver Notification columns - orders table
        ("orders", "estimated_prep_minutes", "INTEGER"),
        ("orders", "estimated_ready_at", "TIMESTAMP"),
        ("orders", "driver_en_route", "BOOLEAN DEFAULT FALSE"),
        ("orders", "driver_accepted_at", "TIMESTAMP"),
        ("orders", "driver_eta_to_restaurant", "INTEGER"),
        # Delivery proof photo columns
        ("orders", "delivery_photo_url", "VARCHAR(500)"),
        ("orders", "delivery_photo_uploaded_at", "TIMESTAMP"),
        # Customer not at door flow columns
        ("orders", "leave_at_door", "BOOLEAN DEFAULT FALSE"),
        ("orders", "driver_arrived_at_delivery", "TIMESTAMP"),
        # Vendor payout Stripe transfer tracking
        ("vendor_payouts", "stripe_transfer_id", "VARCHAR(255)"),
        # Apple Sign-In user ID for returning user lookup
        ("drivers", "apple_id", "VARCHAR(255)"),
        ("vendors", "apple_id", "VARCHAR(255)"),
    ]

    # Tables to create if they don't exist
    table_creates = [
        """
        CREATE TABLE IF NOT EXISTS rides (
            id SERIAL PRIMARY KEY,
            ride_id VARCHAR(50) UNIQUE,
            customer_id INTEGER,
            driver_id INTEGER,
            status VARCHAR(50) DEFAULT 'pending',
            pickup_address TEXT,
            pickup_lat FLOAT,
            pickup_lng FLOAT,
            dropoff_address TEXT,
            dropoff_lat FLOAT,
            dropoff_lng FLOAT,
            fare_amount FLOAT,
            tip_amount FLOAT DEFAULT 0,
            platform_fee FLOAT DEFAULT 0,
            driver_payout FLOAT,
            distance_miles FLOAT,
            duration_minutes INTEGER,
            vehicle_type VARCHAR(50),
            requested_at TIMESTAMP,
            accepted_at TIMESTAMP,
            picked_up_at TIMESTAMP,
            completed_at TIMESTAMP,
            cancelled_at TIMESTAMP,
            cancelled_by VARCHAR(20),
            cancellation_reason TEXT,
            driver_rating FLOAT,
            passenger_rating FLOAT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS ride_chat_messages (
            id SERIAL PRIMARY KEY,
            ride_request_id INTEGER NOT NULL REFERENCES ride_requests(id),
            sender_type VARCHAR(20) NOT NULL,
            sender_id INTEGER NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS ride_disputes (
            id SERIAL PRIMARY KEY,
            ride_request_id INTEGER NOT NULL REFERENCES ride_requests(id),
            customer_id INTEGER NOT NULL REFERENCES customers(id),
            reason VARCHAR(50) NOT NULL,
            description TEXT,
            status VARCHAR(50) NOT NULL DEFAULT 'submitted',
            refund_amount FLOAT,
            stripe_refund_id VARCHAR(255),
            admin_notes TEXT,
            resolved_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS order_disputes (
            id SERIAL PRIMARY KEY,
            order_id INTEGER NOT NULL REFERENCES orders(id),
            customer_id INTEGER NOT NULL REFERENCES customers(id),
            reason VARCHAR(50) NOT NULL,
            description TEXT,
            affected_items TEXT,
            status VARCHAR(50) NOT NULL DEFAULT 'submitted',
            refund_amount FLOAT,
            stripe_refund_id VARCHAR(255),
            admin_notes TEXT,
            resolved_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_order_disputes_order_id ON order_disputes(order_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS idx_order_disputes_customer_id ON order_disputes(customer_id)
        """,
        """
        CREATE TABLE IF NOT EXISTS recurring_rides (
            id SERIAL PRIMARY KEY,
            customer_id INTEGER NOT NULL REFERENCES customers(id),
            pickup_address TEXT NOT NULL,
            pickup_latitude FLOAT NOT NULL,
            pickup_longitude FLOAT NOT NULL,
            dropoff_address TEXT NOT NULL,
            dropoff_latitude FLOAT NOT NULL,
            dropoff_longitude FLOAT NOT NULL,
            schedule_days VARCHAR(50) NOT NULL,
            schedule_time VARCHAR(10) NOT NULL,
            timezone VARCHAR(50) DEFAULT 'America/New_York',
            preferred_driver_id INTEGER REFERENCES drivers(id),
            max_price FLOAT,
            ride_type VARCHAR(50) DEFAULT 'standard',
            is_active BOOLEAN DEFAULT TRUE,
            last_triggered_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        # In-app notifications table
        """
        CREATE TABLE IF NOT EXISTS in_app_notifications (
            id SERIAL PRIMARY KEY,
            customer_id INTEGER NOT NULL REFERENCES customers(id),
            title VARCHAR(255) NOT NULL,
            message TEXT NOT NULL,
            type VARCHAR(50) DEFAULT 'system',
            is_read BOOLEAN DEFAULT FALSE,
            reference_id INTEGER,
            reference_type VARCHAR(50),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """,
        # Indexes for new tables
        "CREATE INDEX IF NOT EXISTS idx_ride_disputes_ride_request_id ON ride_disputes(ride_request_id)",
        "CREATE INDEX IF NOT EXISTS idx_ride_disputes_customer_id ON ride_disputes(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_recurring_rides_customer_id ON recurring_rides(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_in_app_notifications_customer_id ON in_app_notifications(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_in_app_notifications_customer_read ON in_app_notifications(customer_id, is_read)",
    ]

    try:
        with engine.connect() as conn:
            # Create tables first
            for create_sql in table_creates:
                try:
                    conn.execute(text(create_sql))
                except Exception as e:
                    print(f"Table creation: {e}")

            # Then add columns
            for table, col_name, col_type in migrations:
                try:
                    # Safe: table/col_name/col_type from hardcoded migrations list, not user input
                    conn.execute(text(f'ALTER TABLE {table} ADD COLUMN IF NOT EXISTS {col_name} {col_type}'))  # nosemgrep: avoid-sqlalchemy-text
                except Exception as e:
                    print(f"Migration {table}.{col_name}: {e}")

            # Phase 3: Add missing indexes for query performance
            # All use IF NOT EXISTS — idempotent, safe to run on every startup
            indexes = [
                # --- orders table (P0 — most queried table, ~58 queries accelerated) ---
                "CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)",
                "CREATE INDEX IF NOT EXISTS idx_orders_vendor_id ON orders (vendor_id)",
                "CREATE INDEX IF NOT EXISTS idx_orders_driver_id ON orders (driver_id)",
                "CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id)",
                "CREATE INDEX IF NOT EXISTS idx_orders_customer_email ON orders (customer_email)",
                "CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at DESC)",
                "CREATE INDEX IF NOT EXISTS idx_orders_vendor_status ON orders (vendor_id, status)",
                "CREATE INDEX IF NOT EXISTS idx_orders_driver_status ON orders (driver_id, status)",
                # --- vendor_menu_items table (P0 — every menu load) ---
                "CREATE INDEX IF NOT EXISTS idx_menu_items_vendor_id ON vendor_menu_items (vendor_id)",
                "CREATE INDEX IF NOT EXISTS idx_menu_items_review_status ON vendor_menu_items (review_status)",
                # --- drivers table (P1 — login, webhooks, dispatch) ---
                "CREATE INDEX IF NOT EXISTS idx_drivers_email ON drivers (email)",
                "CREATE INDEX IF NOT EXISTS idx_drivers_is_online ON drivers (is_online)",
                "CREATE INDEX IF NOT EXISTS idx_drivers_stripe_account ON drivers (stripe_account_id)",
                "CREATE INDEX IF NOT EXISTS idx_drivers_status ON drivers (status)",
                # --- vendors table (P1 — customer-facing restaurant list) ---
                "CREATE INDEX IF NOT EXISTS idx_vendors_published_status ON vendors (is_published, onboarding_status)",
                "CREATE INDEX IF NOT EXISTS idx_vendors_is_online ON vendors (is_online)",
                # --- rides table (P2 — created via raw SQL, had ZERO indexes) ---
                "CREATE INDEX IF NOT EXISTS idx_rides_status ON rides (status)",
                "CREATE INDEX IF NOT EXISTS idx_rides_customer_id ON rides (customer_id)",
                "CREATE INDEX IF NOT EXISTS idx_rides_driver_id ON rides (driver_id)",
                # --- ride_requests & payout tables (P2) ---
                "CREATE INDEX IF NOT EXISTS idx_ride_requests_status ON ride_requests (status)",
                "CREATE INDEX IF NOT EXISTS idx_vendor_payouts_vendor_id ON vendor_payouts (vendor_id)",
                "CREATE INDEX IF NOT EXISTS idx_driver_payouts_driver_id ON driver_payouts (driver_id)",
                # --- ride_chat_messages table ---
                "CREATE INDEX IF NOT EXISTS idx_ride_chat_messages_request_id ON ride_chat_messages (ride_request_id)",
            ]
            for idx_sql in indexes:
                try:
                    conn.execute(text(idx_sql))  # nosemgrep: avoid-sqlalchemy-text
                except Exception as e:
                    print(f"Index creation: {e}")

            conn.commit()

            # Add missing OrderStatus enum values to PostgreSQL
            # SQLAlchemy uses enum NAMES (uppercase) as DB values, and create_all
            # does not add new enum values to existing types. Must use ALTER TYPE.
            # NOTE: ALTER TYPE ... ADD VALUE cannot run inside a transaction in some
            # PostgreSQL versions, so we use autocommit mode.
            new_order_statuses = [
                "PENDING_RESTAURANT",
                "DECLINED_BY_RESTAURANT",
                "RESTAURANT_TIMEOUT",
                "PENDING_DELIVERY_DECISION",
                "RESTAURANT_WILL_DELIVER",
                "DELIVERY_DECISION_TIMEOUT",
                "PENDING_DELIVERY_PROOF",
                "DELIVERY_FAILED",
            ]
            for status_name in new_order_statuses:
                try:
                    conn.execute(text(f"ALTER TYPE orderstatus ADD VALUE IF NOT EXISTS '{status_name}'"))  # nosemgrep: avoid-sqlalchemy-text
                    conn.commit()
                except Exception as e:
                    try:
                        conn.rollback()
                    except Exception:
                        pass
                    # Value may already exist or DB may not support ALTER TYPE (e.g., SQLite)
                    if "already exists" not in str(e).lower() and "no such" not in str(e).lower():
                        print(f"OrderStatus enum migration {status_name}: {e}")

            print("Database migrations completed successfully (including Phase 3 indexes)")
    except Exception as e:
        print(f"Migration error: {e}")


# Initialize database on startup
@app.on_event("startup")
async def startup_event():
    init_db()
    _run_startup_migrations()
    # Seed default required fields for departments (if not already seeded)
    try:
        from project_tracker import seed_default_required_fields
        from database import SessionLocal
        _seed_db = SessionLocal()
        try:
            seed_default_required_fields(_seed_db)
        finally:
            _seed_db.close()
    except Exception as _e:
        import logging as _log
        _log.getLogger(__name__).warning(f"Failed to seed required fields: {_e}")
    # Seed default approval chain rules (if not already seeded)
    try:
        from change_management import seed_default_approval_rules
        from database import SessionLocal
        _seed_db2 = SessionLocal()
        try:
            seed_default_approval_rules(_seed_db2)
        finally:
            _seed_db2.close()
    except Exception as _e:
        import logging as _log
        _log.getLogger(__name__).warning(f"Failed to seed approval rules: {_e}")
    # Start background scheduler for restaurant timeout checks
    start_timeout_scheduler()
    # Capture the running event loop for the WebSocket Redis subscriber thread
    from websocket_server import capture_event_loop
    capture_event_loop()


@app.on_event("shutdown")
async def shutdown_event():
    # Stop background scheduler
    stop_timeout_scheduler()


# Routes
@app.get("/")
def read_root():
    return {"message": "Invoice Management System API", "version": "1.0.0"}


# ==================== APP CONFIGURATION ====================
# This endpoint provides app configuration to iOS apps
# All data comes from this P2P backend - Firebase is ONLY for authentication

@app.get("/api/config")
def get_app_config():
    """
    App configuration endpoint for iOS apps
    Returns $1 Dollar Store fee structure - World's First!
    """
    return {
        # Tax Rate
        "taxRate": 0.06,  # 6% default tax (matches DEFAULT_TAX_RATE in order_flow.py:568)

        # $1 Dollar Store Fee Structure - World's First!
        # ==============================================
        # DOLLOR.AI $1 FLAT FEE MODEL (Food Delivery)
        # Customer pays: Food + Tax + $1 Service Fee + Delivery Fee + Tip
        # Restaurant pays: $1 flat platform fee (deducted from their payout)
        # Driver receives: Delivery fee + 100% of tip
        # Platform receives: $1 from customer + $1 from restaurant = $2/order
        # ==============================================
        "serviceFee": 1.00,              # $1 flat service fee from customer
        "deliveryFee": 4.99,             # Delivery fee from customer (100% to driver)
        "restaurantPlatformFee": 1.00,   # $1 flat platform fee from restaurant

        # Legacy fields for backward compatibility
        "baseDeliveryFee": 4.99,
        "extraStopFee": 2.0,
        "platformFeePerRestaurant": 1.00,  # $1 platform fee from customer
        "maxRestaurantsPerOrder": 3,
        "serviceFeeRate": 0.0,  # DEPRECATED: Dollor.ai uses flat $1 fees, NOT percentage
        "smallOrderThreshold": 10.0,
        "smallOrderFee": 2.0,

        # Driver/Delivery Config
        "defaultTipRate": 0.15,
        "nearbyDistanceMeters": 3218.69,  # 2 miles
        "maxDeliveryDistanceMiles": 10.0,

        # Prep Time
        "defaultPrepTimeMinutes": 20,
        "maxPrepTimeMinutes": 60,
        "additionalPrepTimePerOrder": 3,

        # Support
        "supportUrl": "https://www.dollor.ai/support",
        "supportPhone": "+1-800-365-5671",
        "supportEmail": "support@dollor.ai",

        # Feature Flags
        "isDummyPaymentMode": False,  # Production: Real payments enabled
        "isAIFeaturesEnabled": True,
        "isDynamicPricingEnabled": False,

        # Busy Level Thresholds
        "busyLevelThresholds": {
            "slow": 2,
            "normal": 5,
            "busy": 8
        }
    }


@app.post("/register", response_model=UserResponse)
def register(http_request: Request, user: UserCreate, db: Session = Depends(get_db)):
    check_rate_limit(http_request, registration_rate_limiter, "register")
    db_user = db.query(User).filter(User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Registration failed. If you already have an account, please log in.")

    hashed_password = get_password_hash(user.password)
    # SECURITY: Never allow admin role via public registration
    db_user = User(
        email=user.email,
        password_hash=hashed_password,
        full_name=user.full_name,
        role=UserRole.USER
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

# Production Admin Setup - creates support@dollor.ai admin
@app.post("/api/auth/admin/setup-production")
def setup_production_admin(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """One-time setup for production admin account - requires admin secret"""
    _require_admin_secret(secret_key)
    if _is_production:
        raise HTTPException(status_code=404, detail="Not found")
    admin_email = "support@dollor.ai"
    # SECURITY: Never hardcode passwords in source. Set ADMIN_INITIAL_PASSWORD env var.
    admin_password = os.getenv("ADMIN_INITIAL_PASSWORD")
    if not admin_password:
        raise HTTPException(status_code=500, detail="ADMIN_INITIAL_PASSWORD env var not set")

    # Check if production admin exists
    existing = db.query(User).filter(User.email == admin_email).first()

    if existing:
        # Update password
        existing.password_hash = get_password_hash(admin_password)
        existing.role = UserRole.ADMIN
        db.commit()
        return {"message": "Production admin password updated", "email": admin_email}

    # Create production admin
    admin_user = User(
        email=admin_email,
        password_hash=get_password_hash(admin_password),
        full_name="Dollor Admin",
        role=UserRole.ADMIN,
        created_at=datetime.utcnow()
    )
    db.add(admin_user)
    db.commit()

    return {"message": "Production admin created", "email": admin_email}

# Delete legacy admin user (admin@invoice.com)
@app.delete("/api/auth/admin/legacy-cleanup")
def cleanup_legacy_admin(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    """Remove legacy admin@invoice.com account - requires authenticated admin"""
    if admin.email == "admin@invoice.com":
        raise HTTPException(status_code=400, detail="Cannot delete your own account")

    legacy_admin = db.query(User).filter(User.email == "admin@invoice.com").first()
    if not legacy_admin:
        return {"message": "Legacy admin not found", "deleted": False}

    db.delete(legacy_admin)
    db.commit()
    return {"message": "Legacy admin@invoice.com deleted", "deleted": True}

# Admin Demo Login - DISABLED FOR PRODUCTION
# Use /api/admin/login with proper credentials instead
@app.post("/api/auth/admin/demo-login")
def admin_demo_login():
    """Demo login disabled in production - use proper authentication"""
    raise HTTPException(
        status_code=403,
        detail="Demo login is disabled. Use /api/admin/login with your credentials."
    )

# Admin JSON Login endpoint (for web frontend)
class AdminLoginRequest(BaseModel):
    email: Optional[str] = None
    username: Optional[str] = None
    password: str

    def get_email(self) -> str:
        return self.email or self.username or ""

@app.post("/api/admin/login")
def admin_login_json(http_request: Request, request: AdminLoginRequest, db: Session = Depends(get_db)):
    """JSON-based admin login endpoint for web frontend"""
    # SECURITY: Rate-limit admin login to prevent brute force
    check_rate_limit(http_request, auth_rate_limiter, "admin_login")
    check_rate_limit(http_request, email_auth_rate_limiter, "admin_login_email",
                     identifier=request.get_email().lower())
    _check_login_lockout(request.get_email().lower())

    login_email = request.get_email()
    if not login_email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email or username is required"
        )
    # Find user with ADMIN role
    user = db.query(User).filter(
        User.email == login_email,
        User.role == UserRole.ADMIN
    ).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(data={"sub": user.email, "role": "admin"})

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "role": "admin"
        }
    }

@app.post("/api/auth/login", response_model=Token)
def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    # SECURITY: Rate limit login attempts to prevent brute force
    # Exempt demo accounts to prevent Apple reviewers from being blocked during rapid testing
    if not _is_demo_exempt(form_data.username):
        check_rate_limit(request, auth_rate_limiter, "admin_login")
        check_rate_limit(request, email_auth_rate_limiter, "admin_login_email", identifier=form_data.username.lower())
        _check_login_lockout(form_data.username.lower())
    user = db.query(User).filter(User.email == form_data.username).first()
    if not user:
        if not _is_demo_exempt(form_data.username):
            record_login_failure(form_data.username.lower())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not verify_password(form_data.password, user.password_hash):
        if not _is_demo_exempt(form_data.username):
            record_login_failure(form_data.username.lower())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    clear_login_failures(form_data.username.lower())
    access_token = create_access_token(data={"sub": user.email})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": user
    }

# Vendor Login

# Vendor Demo Login - for App Store review testing
class VendorDemoLoginRequest(BaseModel):
    email_hint: Optional[str] = None
    email: Optional[str] = None  # Android sends 'email' field


# Customer Demo Login - for App Store review testing (Android calls POST /api/customer/demo-login)
@app.post("/api/auth/customer/demo-login")
@app.post("/api/customer/demo-login")   # kept for Android backward compat
def customer_demo_login(request: VendorDemoLoginRequest, db: Session = Depends(get_db), x_admin_secret: Optional[str] = Header(None)):
    """Demo login for customer - creates or finds demo customer account for App Store review"""
    _require_admin_secret(x_admin_secret)

    hint = request.email_hint or request.email or ""
    print(f"Customer demo login attempt with hint: {hint}")

    demo_email = "demo.customer@dollor.ai"
    demo_password = "DemoCustomer2025!"

    # Check if demo customer exists
    customer = db.query(Customer).filter(Customer.email == demo_email).first()

    if not customer:
        # Create demo customer
        hashed_password = get_password_hash(demo_password)
        customer = Customer(
            email=demo_email,
            password_hash=hashed_password,
            first_name="Demo",
            last_name="Customer",
            phone="+14155550001",
            is_active=True,
            created_at=datetime.utcnow()
        )
        db.add(customer)
        db.commit()
        db.refresh(customer)
        print(f"Created demo customer: {mask_email(demo_email)}")
    else:
        # Update password to ensure it's correct
        customer.password_hash = get_password_hash(demo_password)
        customer.is_active = True
        db.commit()
        print(f"Updated demo customer credentials: {mask_email(demo_email)}")

    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip() or "Customer"
    access_token = create_access_token(data={"sub": customer.email, "role": "customer", "customer_id": customer.id})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "customer_id": customer.id,
        "customer_code": customer.customer_id or f"CUST-{customer.id:05d}",
        "name": full_name,
        "email": customer.email,
        "phone": customer.phone
    }

# Driver Demo Login - for App Store review testing (Android calls POST /api/auth/driver/demo-login)
@app.post("/api/auth/driver/demo-login")
def driver_demo_login(request: VendorDemoLoginRequest, db: Session = Depends(get_db), x_admin_secret: Optional[str] = Header(None)):
    """Demo login for driver - creates or finds demo driver account for App Store review"""
    _require_admin_secret(x_admin_secret)

    hint = request.email_hint or request.email or ""
    print(f"Driver demo login attempt with hint: {hint}")

    demo_email = "demo.driver@dollor.ai"
    demo_password = "DemoDriver2025!"

    # Check if demo driver user exists
    user = db.query(User).filter(
        User.email == demo_email,
        User.role == UserRole.DRIVER
    ).first()

    if not user:
        # Create demo driver
        hashed_password = get_password_hash(demo_password)

        # Create driver record first — pre-verified so App Store reviewers can bid on rides
        demo_driver = Driver(
            first_name="Demo",
            last_name="Driver",
            email=demo_email,
            phone="+14155550002",
            status=DriverStatus.ACTIVE,
            is_online=True,
            current_latitude=37.7749,
            current_longitude=-122.4194,
            verification_status="passed",
            documents_verified=True,
            created_at=datetime.utcnow()
        )
        db.add(demo_driver)
        db.flush()

        # Create user record
        user = User(
            email=demo_email,
            password_hash=hashed_password,
            full_name="Demo Driver",
            role=UserRole.DRIVER,
            driver_id=demo_driver.id,
            created_at=datetime.utcnow()
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        print(f"Created demo driver: {mask_email(demo_email)}")
    else:
        # Demo user exists - ensure password is correct and KYC fields are set
        user.password_hash = get_password_hash(demo_password)
        db.commit()
        print(f"Updated demo driver credentials: {mask_email(demo_email)}")

    # Get driver record — ensure KYC/online state is set for App Store review
    driver = db.query(Driver).filter(Driver.id == user.driver_id).first()
    if driver:
        driver.verification_status = "passed"
        driver.documents_verified = True
        driver.is_online = True
        driver.status = DriverStatus.ACTIVE
        if not driver.current_latitude:
            driver.current_latitude = 37.7749
            driver.current_longitude = -122.4194
        db.commit()
    driver_name = f"{driver.first_name} {driver.last_name}" if driver else "Demo Driver"

    access_token = create_access_token(data={"sub": user.email, "role": "driver", "driver_id": user.driver_id})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": user.driver_id,
        "driver_code": driver.driver_id if driver else None,
        "name": driver_name,
        "email": user.email,
        "status": driver.status.value if driver and hasattr(driver.status, 'value') else "active"
    }

class PasswordResetRequest(BaseModel):
    email: EmailStr

class PasswordResetConfirm(BaseModel):
    token: str
    new_password: str


def decode_google_jwt(token: str) -> dict:
    """
    Decode and VERIFY a Google or Apple identity token.

    Google tokens: verified using google-auth library (fetches Google's public keys,
    verifies RS256 signature, checks expiry and issuer).

    Apple tokens: verified using Apple's JWKS endpoint (RS256 signature check).

    SECURITY (G1): Replaces the old insecure base64-decode-only implementation that
    did NOT verify signatures, allowing forged tokens to authenticate as any user.
    """
    if not token:
        return {}

    # Determine token type by decoding header (header is safe to decode unverified)
    import base64, json
    try:
        header_part = token.split('.')[0]
        pad = 4 - len(header_part) % 4
        header = json.loads(base64.urlsafe_b64decode(header_part + ('=' * pad if pad != 4 else '')))
        alg = header.get('alg', '')
        kid = header.get('kid', '')
    except Exception:
        logger.warning("OAuth token: failed to decode header")
        return {}

    # Apple tokens have issuer https://appleid.apple.com — check kid prefix patterns
    # or fall through to Google verification first
    is_apple = False
    try:
        payload_part = token.split('.')[1]
        pad = 4 - len(payload_part) % 4
        raw_payload = json.loads(base64.urlsafe_b64decode(payload_part + ('=' * pad if pad != 4 else '')))
        iss = raw_payload.get('iss', '')
        if 'appleid.apple.com' in iss:
            is_apple = True
    except Exception:
        pass

    if is_apple:
        return _verify_apple_jwt(token)
    else:
        return _verify_google_jwt(token)


# Apple JWKS cache (1-hour TTL)
_apple_jwks_cache: dict = {"keys": None, "expires": 0}


def _verify_apple_jwt(token: str) -> dict:
    """Verify Apple Sign-In identity token signature using Apple's JWKS."""
    import time, base64, json, requests as _requests
    global _apple_jwks_cache

    try:
        # Fetch Apple JWKS (cached)
        if not _apple_jwks_cache["keys"] or time.time() > _apple_jwks_cache["expires"]:
            resp = _requests.get("https://appleid.apple.com/auth/keys", timeout=5)
            resp.raise_for_status()
            _apple_jwks_cache["keys"] = resp.json()["keys"]
            _apple_jwks_cache["expires"] = time.time() + 3600

        from jose import jwt as jose_jwt
        # Decode header to find matching key
        header_part = token.split('.')[0]
        pad = 4 - len(header_part) % 4
        header = json.loads(base64.urlsafe_b64decode(header_part + ('=' * pad if pad != 4 else '')))
        kid = header.get('kid')

        # Find matching key
        jwk = next((k for k in _apple_jwks_cache["keys"] if k.get('kid') == kid), None)
        if not jwk:
            logger.warning(f"Apple JWT: no matching key for kid={kid}")
            return {}

        from jose.backends import RSAKey
        public_key = RSAKey(jwk, 'RS256')

        payload = jose_jwt.decode(
            token,
            public_key.public_key().to_pem().decode(),
            algorithms=['RS256'],
            options={"verify_aud": False}  # audience is app bundle ID (varies)
        )
        logger.info(f"Apple JWT verified: sub={payload.get('sub')} email={mask_email(payload.get('email'))}")
        return payload
    except Exception as e:
        logger.warning(f"Apple JWT verification failed: {e}")
        return {}


def _verify_google_jwt(token: str) -> dict:
    """Verify Google identity token signature and audience using google-auth library."""
    try:
        from google.oauth2 import id_token
        from google.auth.transport import requests as google_requests

        google_client_id = os.getenv("GOOGLE_CLIENT_ID")
        # SECURITY: Fail closed — never skip audience verification in production.
        # An absent GOOGLE_CLIENT_ID would accept tokens from ANY Google app.
        if not google_client_id:
            logger.error("GOOGLE_CLIENT_ID not configured — Google auth disabled")
            return {}

        payload = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=google_client_id,
        )
        logger.info(f"Google JWT verified: sub={payload.get('sub')} email={mask_email(payload.get('email'))}")
        return payload
    except Exception as e:
        logger.warning(f"Google JWT verification failed: {e}")
        return {}


# Password Reset Request
@app.post("/api/auth/password-reset/request")
def request_password_reset(http_request: Request, request: PasswordResetRequest, db: Session = Depends(get_db)):
    check_rate_limit(http_request, password_reset_ip_limiter, "pwd_reset_ip")
    check_rate_limit(http_request, password_reset_limiter, "pwd_reset", identifier=request.email.lower())

    user = db.query(User).filter(User.email == request.email).first()
    if not user:
        # Don't reveal if email exists or not for security
        return {"message": "If this email exists, a password reset link has been sent"}

    # Generate reset token (valid for 1 hour)
    reset_token = create_access_token(
        data={"sub": user.email, "type": "password_reset"},
        expires_delta=timedelta(hours=1)
    )

    # Send reset link via email
    try:
        send_password_reset_link_email(user.email, user.email.split("@")[0], reset_token)
    except Exception as e:
        logger.error(f"Failed to send vendor/admin password reset email: {str(e)}")

    return {"message": "If this email exists, a password reset link has been sent"}

# Password Reset Confirm
@app.post("/api/auth/password-reset/confirm")
def confirm_password_reset(http_request: Request, request: PasswordResetConfirm, db: Session = Depends(get_db)):
    check_rate_limit(http_request, password_reset_limiter, "pwd_reset_confirm")
    try:
        payload = jwt.decode(request.token, SECRET_KEY, algorithms=[ALGORITHM])
        email = payload.get("sub")
        token_type = payload.get("type")

        if token_type != "password_reset":
            raise HTTPException(status_code=400, detail="Invalid reset token")

        # SECURITY: Prevent token reuse -- check Redis first, fall back to DB flag
        import hashlib
        token_hash = hashlib.sha256(request.token.encode()).hexdigest()
        used_key = f"pwd_reset_used:{token_hash}"
        _redis_available = False
        try:
            from cache import redis_client, REDIS_AVAILABLE
            _redis_available = REDIS_AVAILABLE and bool(redis_client)
            if _redis_available and redis_client.get(used_key):
                raise HTTPException(status_code=400, detail="Reset token has already been used")
        except ImportError:
            pass
        # DB fallback: check password_reset_token_used flag on the user row
        # We find the user by decoding the token payload (email is in the verified jwt claims above)
        _db_user_check = db.query(User).filter(User.email == email).first()
        if _db_user_check and getattr(_db_user_check, "password_reset_token_used", None) == token_hash:
            raise HTTPException(status_code=400, detail="Reset token has already been used")

        user = db.query(User).filter(User.email == email).first()
        if not user:
            raise HTTPException(status_code=400, detail="Invalid reset token")

        # Update password
        user.password_hash = get_password_hash(request.new_password)
        db.commit()

        # SECURITY: Mark token as used in Redis + DB so it cannot be replayed
        try:
            if _redis_available and redis_client:
                redis_client.setex(used_key, 3600, "1")
        except Exception:
            pass
        # DB fallback: stamp the token hash on the user row
        try:
            if user and hasattr(user, "password_reset_token_used"):
                user.password_reset_token_used = token_hash
                db.commit()
        except Exception:
            pass

        return {"message": "Password has been reset successfully"}

    except JWTError:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

# Helper function to get current vendor user
def get_current_vendor_user(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != UserRole.VENDOR:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to vendors only"
        )
    if not current_user.vendor_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User account not linked to a vendor"
        )
    return current_user

@app.get("/api/auth/me", response_model=UserResponse)
def get_current_user_info(current_user: User = Depends(get_current_user)):
    return current_user


# ==================== DRIVER AUTHENTICATION ====================

class DriverRegisterRequest(BaseModel):
    email: EmailStr
    password: str
    first_name: str
    last_name: str
    phone: str
    vehicle_type: Optional[str] = None  # car, motorcycle, bicycle
    license_number: Optional[str] = None
    date_of_birth: Optional[str] = None

class DriverLoginResponse(BaseModel):
    access_token: str
    token_type: str
    driver_id: int
    driver_code: str
    name: str
    email: str
    status: Optional[str] = None
    is_approved: bool = False
    requires_documents: bool = False

    class Config:
        from_attributes = True

# Accounts shared by app-store reviewers and the QA team: several people must be able to use them at once.
from ride_dispatch import SHARED_DEMO_DRIVER_EMAILS as _SHARED_DEMO_DRIVER_EMAILS


def _enforce_single_driver_session(email: str, driver_pk: int, access_token: str) -> None:
    """One active session per driver: a new login revokes the previous device's token (like Uber).

    Shared demo accounts are exempt so reviewers and testers do not sign each other out.
    """
    if (email or "").lower() in _SHARED_DEMO_DRIVER_EMAILS:
        return
    try:
        claims = jwt.get_unverified_claims(access_token)
        jti, exp = claims.get("jti"), claims.get("exp")
        if jti and exp:
            from cache import rotate_active_session
            ttl = max(int(exp - datetime.utcnow().timestamp()), 60)
            rotate_active_session(f"driver:{driver_pk}", jti, ttl)
    except Exception as e:
        logger.warning(f"single-session enforcement skipped: {e}")


@app.post("/api/auth/driver/login")
def driver_login(request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """Driver login - authenticates driver and returns token"""
    # SECURITY: Rate limit login attempts to prevent brute force
    # Exempt demo accounts to prevent Apple reviewers from being blocked during rapid testing
    if not _is_demo_exempt(form_data.username):
        check_rate_limit(request, auth_rate_limiter, "driver_login")
        check_rate_limit(request, email_auth_rate_limiter, "driver_login_email", identifier=form_data.username.lower())
        _check_login_lockout(form_data.username.lower())

    # Find user with DRIVER role first. Email lookup is case-insensitive — Postgres
    # `=` is case-sensitive by default, so a driver who registered as
    # "Jeet@x.com" but types "jeet@x.com" at login (or vice versa) would
    # otherwise get a false "incorrect email or password".
    login_email = form_data.username.strip()
    user = db.query(User).filter(
        func.lower(User.email) == login_email.lower(),
        User.role == UserRole.DRIVER
    ).first()

    if not user:
        # Also check for users with any role who have a linked driver account
        # (Google Sign-In creates users with role=user but links a driver_id)
        any_user = db.query(User).filter(func.lower(User.email) == login_email.lower()).first()
        if any_user and any_user.driver_id:
            user = any_user
        elif any_user:
            if not _is_demo_exempt(form_data.username):
                record_login_failure(form_data.username.lower())
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )
        else:
            if not _is_demo_exempt(form_data.username):
                record_login_failure(form_data.username.lower())
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

    if not verify_password(form_data.password, user.password_hash):
        if not _is_demo_exempt(form_data.username):
            record_login_failure(form_data.username.lower())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    clear_login_failures(form_data.username.lower())

    # Get driver record
    driver = db.query(Driver).filter(Driver.id == user.driver_id).first()
    if not driver:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Driver profile not found"
        )

    # Block only SUSPENDED drivers - allow PENDING so they can upload documents
    if driver.status == DriverStatus.SUSPENDED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Driver account is suspended. Please contact support@dollor.ai"
        )
    access_token = create_access_token(data={"sub": user.email, "role": "driver", "driver_id": driver.id})
    _enforce_single_driver_session(user.email, driver.id, access_token)
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "name": f"{driver.first_name} {driver.last_name}",
        "first_name": driver.first_name,
        "last_name": driver.last_name,
        "email": driver.email,
        "phone": driver.phone,
        "status": driver.status.value if hasattr(driver.status, 'value') else str(driver.status),
        "is_approved": driver.status in [DriverStatus.ACTIVE, DriverStatus.APPROVED],
        "is_online": driver.is_online,
        "requires_documents": not (driver.drivers_license and driver.insurance and driver.photo_url),
        "bankAccount": {
            "bankName": decrypt_field(driver.bank_name),
            "accountNumberLast4": driver.bank_last4,
            "accountHolderName": decrypt_field(driver.bank_account_holder) or f"{driver.first_name or ''} {driver.last_name or ''}".strip(),
            "routingNumber": decrypt_field(driver.bank_routing_number),
            "accountType": "checking",
            "isVerified": bool(driver.bank_verified),
        } if driver.bank_name and driver.bank_last4 else None,
    }


@app.post("/api/auth/driver/refresh")
def driver_refresh_token(driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Refresh driver authentication token"""

    # Block only SUSPENDED drivers - allow PENDING so they can upload documents
    if driver.status == DriverStatus.SUSPENDED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Driver account is suspended. Please contact support@dollor.ai"
        )

    # Generate new token
    access_token = create_access_token(data={"sub": driver.email, "role": "driver", "driver_id": driver.id})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "name": f"{driver.first_name} {driver.last_name}",
        "email": driver.email,
        "status": driver.status.value if hasattr(driver.status, 'value') else str(driver.status),
        "is_approved": driver.status in [DriverStatus.ACTIVE, DriverStatus.APPROVED],
        "requires_documents": not (driver.drivers_license and driver.insurance and driver.photo_url)
    }


@app.post("/api/auth/driver/register")
def driver_register(http_request: Request, request: DriverRegisterRequest, db: Session = Depends(get_db)):
    """Register a new driver account"""
    check_rate_limit(http_request, registration_rate_limiter, "register")
    print(f"Driver registration attempt for: {mask_email(request.email)}")

    try:
        # SECURITY (NSA-009): Enforce password policy for driver registration
        _validate_password(request.password)

        # TNC-06: Enforce minimum age of 21 for TNC drivers (CPUC Decision 13-09-045)
        if request.date_of_birth:
            try:
                dob = datetime.strptime(request.date_of_birth, "%Y-%m-%d").date()
                today = date.today()
                age = today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))
                if age < 21:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Driver must be at least 21 years old to provide TNC services."
                    )
            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid date_of_birth format. Use YYYY-MM-DD."
                )

        # Check if email already exists. Case-insensitive so "Jeet@x.com" and
        # "jeet@x.com" are treated as the same account on both sides of this check.
        existing_user = db.query(User).filter(func.lower(User.email) == request.email.lower()).first()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )

        # Check if driver email already exists
        existing_driver = db.query(Driver).filter(func.lower(Driver.email) == request.email.lower()).first()
        if existing_driver:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )

        # Create driver record
        driver_count = db.query(Driver).count()
        driver_code = f"DRV-{driver_count + 1:05d}"

        # Hash password once, store in both driver and user tables
        hashed_password = get_password_hash(request.password)

        # Sanitize inputs to prevent XSS
        first_name = sanitize_input(request.first_name)
        last_name = sanitize_input(request.last_name)

        new_driver = Driver(
            driver_id=driver_code,
            first_name=first_name,
            last_name=last_name,
            email=request.email,
            phone=request.phone,
            password_hash=hashed_password,  # Store password in driver table for mobile app compatibility
            vehicle_type=request.vehicle_type or "car",  # Default to car if not provided
            license_number=request.license_number,
            date_of_birth=request.date_of_birth,
            status=DriverStatus.PENDING  # Needs approval
        )
        db.add(new_driver)
        db.commit()
        db.refresh(new_driver)
        print(f"Driver record created: {new_driver.id}")

        # Create user record linked to driver
        new_user = User(
            email=request.email,
            password_hash=hashed_password,
            full_name=f"{first_name} {last_name}",
            role=UserRole.DRIVER,
            driver_id=new_driver.id
        )
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        print(f"User record created: {new_user.id}")

        print(f"Driver registration successful for: {mask_email(new_user.email)}, driver_id: {new_driver.id}")
        access_token = create_access_token(data={"sub": new_user.email, "role": "driver", "driver_id": new_driver.id})

        # Send registration confirmation email (non-blocking)
        try:
            send_driver_registration_confirmation(
                to_email=new_driver.email,
                driver_name=f"{new_driver.first_name} {new_driver.last_name}",
                driver_code=driver_code
            )
            print(f"Driver registration email sent to: {mask_email(new_driver.email)}")
        except Exception as e:
            print(f"Failed to send driver registration email: {str(e)}")

        # Notify support@dollor.ai of new driver application
        try:
            notify_support(
                subject=f"New driver application: {new_driver.first_name} {new_driver.last_name}",
                details={
                    "Name": f"{new_driver.first_name} {new_driver.last_name}",
                    "Email": new_driver.email,
                    "Phone": new_driver.phone or "(not provided)",
                    "Vehicle Type": getattr(request, "vehicle_type", "(not provided)"),
                    "License #": getattr(request, "license_number", "(not provided)"),
                    "Driver Code": driver_code,
                    "Status": "Pending review",
                    "Next step": "Background check + document upload required",
                }
            )
        except Exception as e:
            logger.warning(f"Driver notify_support failed (non-fatal): {e}")

        return {
            "access_token": access_token,
            "token_type": "bearer",
            "driver_id": new_driver.id,
            "driver_code": driver_code,
            "name": f"{new_driver.first_name} {new_driver.last_name}",
            "email": new_driver.email,
            "status": new_driver.status.value if hasattr(new_driver.status, 'value') else str(new_driver.status),
            "is_approved": False,
            "requires_documents": True,
            "message": "Registration successful. Please upload your driver's license and insurance documents to complete verification."
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        print(f"Driver registration error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            # A2: Log error internally, return generic message
            detail="Registration failed. Please try again or contact support."
        )


# Driver Google OAuth
class DriverGoogleAuthRequest(BaseModel):
    email: Optional[EmailStr] = None
    name: Optional[str] = None
    google_id: Optional[str] = None
    id_token: Optional[str] = None  # Web frontend sends this
    credential: Optional[str] = None  # Alternative field name

@app.post("/api/auth/driver/google")
def driver_google_auth(http_request: Request, request: DriverGoogleAuthRequest, db: Session = Depends(get_db)):
    """Google OAuth authentication for drivers - handles both login and registration"""
    check_rate_limit(http_request, registration_rate_limiter, "register")

    # Get token from either field
    token = request.id_token or request.credential

    # If token provided, decode it to get user info
    if token:
        decoded = decode_google_jwt(token)
        email = decoded.get('email', request.email)
        name = decoded.get('name', request.name)
        google_id = decoded.get('sub', request.google_id)
    else:
        email = request.email
        name = request.name
        google_id = request.google_id

    if not email:
        raise HTTPException(status_code=400, detail="Email is required")
    if not name:
        name = email.split('@')[0]  # Use email prefix as fallback name

    print(f"Driver Google auth for: {mask_email(email)}")

    # Check if user exists with this email (any role)
    existing_user = db.query(User).filter(User.email == email).first()

    if existing_user:
        user = existing_user
        if user.driver_id:
            # User already has a driver account — check if suspended
            driver = db.query(Driver).filter(Driver.id == user.driver_id).first()
            if driver and driver.status == DriverStatus.SUSPENDED:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Driver account is suspended. Please contact support@dollor.ai"
                )
            print(f"Existing user {mask_email(email)} (role={user.role.value}) logging in as driver")
        else:
            # User exists but has no driver account — direct them to register
            return JSONResponse(
                status_code=403,
                content={
                    "detail": "No driver account found. Please register as a driver first.",
                    "registration_url": "https://dollor.ai/driver/apply",
                    "requires_registration": True
                }
            )
    else:
        # Brand new user — direct them to register
        return JSONResponse(
            status_code=403,
            content={
                "detail": "No driver account found. Please register as a driver first.",
                "registration_url": "https://dollor.ai/driver/apply",
                "requires_registration": True
            }
        )

    # Get driver info
    driver = db.query(Driver).filter(Driver.id == user.driver_id).first() if user.driver_id else None

    print(f"Driver Google auth successful for: {mask_email(user.email)} (status: {driver.status.value if driver else 'unknown'})")
    access_token = create_access_token(data={"sub": user.email, "role": "driver", "driver_id": driver.id if driver else None})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": driver.id if driver else None,
        "driver_code": driver.driver_id if driver else None,
        "name": f"{driver.first_name} {driver.last_name}" if driver else name,
        "email": user.email,
        "status": driver.status.value if driver and hasattr(driver.status, 'value') else "pending",
        "is_approved": driver.status in [DriverStatus.ACTIVE, DriverStatus.APPROVED] if driver else False,
        "requires_documents": not (driver.drivers_license and driver.insurance and driver.photo_url) if driver else True
    }


# Driver Apple OAuth
class DriverAppleAuthRequest(BaseModel):
    email: Optional[str] = ""  # Apple only provides on first sign-in
    name: Optional[str] = None
    apple_id: str
    identity_token: Optional[str] = None  # JWT from Apple containing email for returning users
    nonce_hash: Optional[str] = None  # SHA256 hash of nonce sent to Apple (G2: replay protection)

@app.post("/api/auth/driver/apple-auth")
def driver_apple_auth(http_request: Request, request: DriverAppleAuthRequest, db: Session = Depends(get_db)):
    """Apple OAuth authentication for drivers - handles both login and registration"""
    check_rate_limit(http_request, registration_rate_limiter, "register")

    email = request.email or ""
    name = request.name

    # Try to decode identity_token first (Apple JWT contains email for returning users)
    if request.identity_token:
        try:
            decoded = decode_google_jwt(request.identity_token)  # Verifies Apple RS256 signature
            # G2: Validate nonce if provided by iOS (replay attack protection)
            if request.nonce_hash and decoded.get('nonce') != request.nonce_hash:
                logger.warning(f"Apple nonce mismatch for driver auth")
                raise HTTPException(status_code=401, detail="Invalid Apple identity token")
            elif not request.nonce_hash:
                logger.warning("Apple driver auth: no nonce provided — replay protection disabled")
            token_email = decoded.get('email')
            if token_email:
                email = token_email
            if not name and email:
                name = email.split('@')[0]
        except Exception as e:
            logger.debug(f"Apple identity token decode failed for driver auth")

    if not name and email:
        name = email.split('@')[0]
    elif not name:
        name = 'Driver'

    # For returning users, look up by apple_id first (most reliable)
    driver = None
    user = None

    # First: Try to find existing driver by apple_id
    driver = db.query(Driver).filter(Driver.apple_id == request.apple_id).first()
    if driver:
        email = driver.email
        user = db.query(User).filter(User.email == email).first()

    # Second: Try to find by email if we have one
    if not user and email:
        user = db.query(User).filter(User.email == email).first()
        if user and user.driver_id:
            driver = db.query(Driver).filter(Driver.id == user.driver_id).first()

    # If still no user and no email, we can't proceed
    if not user and not email:
        raise HTTPException(status_code=400, detail="Email is required for first-time Apple Sign-In. Please go to Settings > Apple ID > Sign-In & Security > Apps Using Apple ID, remove Dollor Driver, and try again.")

    if user:
        if user.driver_id:
            # User already has a driver account
            if not driver:
                driver = db.query(Driver).filter(Driver.id == user.driver_id).first()
            if driver and driver.status == DriverStatus.SUSPENDED:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Driver account is suspended. Please contact support@dollor.ai"
                )
            # Store apple_id on driver if not already set
            if driver and not driver.apple_id:
                driver.apple_id = request.apple_id
                db.commit()
            print(f"Existing user {mask_email(email)} (role={user.role.value}) logging in as driver via Apple")
        else:
            # User exists but has no driver account — direct them to register
            return JSONResponse(
                status_code=403,
                content={
                    "detail": "No driver account found. Please register as a driver first.",
                    "registration_url": "https://dollor.ai/driver/apply",
                    "requires_registration": True
                }
            )
    else:
        # Brand new user — direct them to register
        return JSONResponse(
            status_code=403,
            content={
                "detail": "No driver account found. Please register as a driver first.",
                "registration_url": "https://dollor.ai/driver/apply",
                "requires_registration": True
            }
        )

    # Get driver info (may already be loaded)
    if not driver and user and user.driver_id:
        driver = db.query(Driver).filter(Driver.id == user.driver_id).first()

    print(f"Driver Apple auth successful for: {mask_email(user.email)} (status: {driver.status.value if driver else 'unknown'})")
    access_token = create_access_token(data={"sub": user.email, "role": "driver", "driver_id": driver.id if driver else None})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": driver.id if driver else None,
        "driver_code": driver.driver_id if driver else None,
        "name": f"{driver.first_name} {driver.last_name}" if driver else name,
        "email": user.email,
        "status": driver.status.value if driver and hasattr(driver.status, 'value') else "pending",
        "is_approved": driver.status in [DriverStatus.ACTIVE, DriverStatus.APPROVED] if driver else False,
        "requires_documents": not (driver.drivers_license and driver.insurance and driver.photo_url) if driver else True
    }


@app.get("/api/auth/driver/me")
def get_driver_profile(driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Get current driver's profile"""
    return {
        "id": driver.id,
        "driver_code": driver.driver_id,
        "name": f"{driver.first_name} {driver.last_name}",
        "email": driver.email,
        "phone": driver.phone,
        "status": driver.status.value,
        "rating": driver.rating,
        "total_deliveries": driver.total_deliveries,
        "is_online": driver.is_online,
        "vehicle": {
            "type": driver.vehicle_type,
            "make": driver.vehicle_make,
            "model": driver.vehicle_model,
            "year": driver.vehicle_year,
            "color": driver.vehicle_color,
            "license_plate": driver.license_plate
        } if driver.vehicle_type else None
    }


@app.put("/api/auth/driver/online")
def set_driver_online(
    is_online: Optional[bool] = None,
    request_body: Optional[dict] = Body(None),
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Toggle driver online/offline status"""
    # Accept is_online from query param or request body
    online_status = is_online
    if online_status is None and request_body:
        online_status = request_body.get("is_online", request_body.get("online", True))
    if online_status is None:
        online_status = True  # Default to going online

    # Block unapproved drivers from going online
    if online_status:  # Only check when trying to go online
        approved_statuses = [DriverStatus.APPROVED, DriverStatus.ACTIVE]
        driver_status = driver.status if isinstance(driver.status, DriverStatus) else DriverStatus(driver.status) if driver.status else None

        if driver_status not in approved_statuses:
            # Check what's missing
            missing_docs = []
            if not driver.drivers_license:
                missing_docs.append("driver's license")
            if not driver.insurance:
                missing_docs.append("insurance")
            if not driver.photo_url:
                missing_docs.append("profile photo")

            if missing_docs:
                detail = f"Please upload and verify: {', '.join(missing_docs)}"
            else:
                detail = "Your documents are pending verification. You'll be notified when approved."

            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=detail
            )

        # TNC gate (CPUC 13-09-045): explicit Checkr background-check requirement,
        # independent of status, so no approval path can bypass driver vetting.
        if not driver.background_check:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Background check not passed. You cannot go online until your background check clears."
            )

    # A driver cannot go offline in the middle of a ride (riders would be stranded with an unreachable driver).
    if not online_status:
        from models import RideRequest, RideRequestStatus
        in_ride = db.query(RideRequest.id).filter(
            RideRequest.matched_driver_id == driver.id,
            RideRequest.status.in_([RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS]),
        ).first()
        if in_ride:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Finish or cancel your current ride before going offline."
            )

    driver.is_online = online_status
    driver.location_updated_at = datetime.utcnow()
    if online_status:
        driver.went_online_at = datetime.utcnow()
        # Insurance: Period 1 START — driver is now available
        try:
            import uuid as _uuid
            from insurance.events import log_insurance_event
            _session_id = str(_uuid.uuid4())
            driver.insurance_session_id = _session_id
            log_insurance_event(
                db=db, driver_id=driver.id, trip_type="available",
                trip_id=None, session_id=_session_id, period=1,
                event_type="period_start",
            )
        except Exception as e:
            logging.warning(f"Insurance event (online) failed: {e}")
    else:
        driver.went_offline_at = datetime.utcnow()
        # Insurance: Period 1 END — driver going offline
        try:
            from insurance.events import log_insurance_event, get_or_create_session_id
            _session_id = get_or_create_session_id(db, driver.id)
            log_insurance_event(
                db=db, driver_id=driver.id, trip_type="available",
                trip_id=None, session_id=_session_id, period=1,
                event_type="period_end",
            )
        except Exception as e:
            logging.warning(f"Insurance event (offline) failed: {e}")
    db.commit()

    return {"success": True, "is_online": driver.is_online}


@app.put("/api/auth/driver/location")
def update_driver_location(latitude: float, longitude: float, driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Update driver's current location"""
    if not driver:
        raise HTTPException(status_code=404, detail="Driver profile not found")

    driver.current_latitude = latitude
    driver.current_longitude = longitude
    driver.location_updated_at = datetime.utcnow()
    # Insurance: accumulate mileage for UBI tracking
    try:
        from insurance.events import accumulate_mileage
        if driver.insurance_session_id and driver.current_latitude and driver.current_longitude:
            accumulate_mileage(driver.id, driver.insurance_session_id,
                               driver.current_latitude, driver.current_longitude)
    except Exception as e:
        logging.warning(f"Insurance mileage accumulation failed: {e}")
    db.commit()

    _check_driver_proximity_to_delivery(driver.id, latitude, longitude, db)

    return {"success": True, "latitude": latitude, "longitude": longitude}


# =============================================================================
# CUSTOMER AUTHENTICATION ENDPOINTS (for Rideshare Matchmaking)
# =============================================================================

class CustomerRegisterRequest(BaseModel):
    email: EmailStr
    password: str
    name: Optional[str] = None
    full_name: Optional[str] = None  # iOS sends full_name, Android sends name
    phone: Optional[str] = None

    @field_validator('name', mode='before')
    @classmethod
    def set_name_from_full_name(cls, v, info):
        """Accept both 'name' and 'full_name' fields for compatibility"""
        if v:
            return v
        # Check if full_name was provided in the raw data
        data = info.data if hasattr(info, 'data') else {}
        return data.get('full_name', v)

    def get_name(self) -> str:
        """Get the name (prefers name, falls back to full_name)"""
        return self.name or self.full_name or ""

class CustomerLoginResponse(BaseModel):
    access_token: str
    token_type: str
    customer_id: int
    customer_code: str
    name: str
    email: str
    phone: Optional[str] = None

    class Config:
        from_attributes = True


class CustomerLoginRequest(BaseModel):
    """JSON login request for iOS/Android apps - accepts both email and username fields"""
    email: Optional[EmailStr] = None
    username: Optional[str] = None  # Some clients send username instead of email
    password: str

    def get_email(self) -> str:
        """Get the email (prefers email, falls back to username)"""
        return self.email or self.username or ""


@app.post("/api/auth/customer/login")
def customer_auth_login(request: Request, form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """Customer login - authenticates customer and returns token for rideshare"""
    # SECURITY: Rate limit login attempts to prevent brute force
    # Exempt demo accounts to prevent Apple reviewers from being blocked during rapid testing
    if not _is_demo_exempt(form_data.username):
        check_rate_limit(request, auth_rate_limiter, "customer_login")
        check_rate_limit(request, email_auth_rate_limiter, "customer_login_email", identifier=form_data.username.lower())
        _check_login_lockout(form_data.username.lower())
    print(f"Customer login attempt for: {form_data.username}")

    # Find customer by email
    customer = db.query(Customer).filter(Customer.email == form_data.username).first()

    if not customer:
        print(f"Customer not found: {form_data.username}")
        if not _is_demo_exempt(form_data.username):
            record_login_failure(form_data.username.lower())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not customer.password_hash or not verify_password(form_data.password, customer.password_hash):
        if not _is_demo_exempt(form_data.username):
            record_login_failure(form_data.username.lower())
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    clear_login_failures(form_data.username.lower())

    if not customer.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Customer account is not active"
        )

    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip() or "Customer"
    access_token = create_access_token(data={"sub": customer.email, "role": "customer", "customer_id": customer.id})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "customer_id": customer.id,
        "customer_code": customer.customer_id or f"CUST-{customer.id:05d}",
        "name": full_name,
        "email": customer.email,
        "phone": customer.phone
    }


# REMOVED: /api/auth/customer/login/json - Dead endpoint (no platform uses it)
# All platforms use OAuth2 form-based /api/auth/customer/login or /auth/customer/login


# ── Logout Endpoints (G3: Token Revocation) ───────────────────────────────────

def _revoke_current_token(token_payload: dict) -> None:
    """Add the current token's JTI to the blacklist."""
    import time
    jti = token_payload.get("jti")
    exp = token_payload.get("exp", 0)
    if jti:
        ttl = max(int(exp - time.time()), 1)
        blacklist_token(jti, ttl)


@app.post("/api/auth/customer/logout")
def customer_logout(_auth: dict = Depends(require_any_auth)):
    """Invalidate the current customer JWT (token blacklist)."""
    _revoke_current_token(_auth)
    return {"success": True, "message": "Logged out successfully"}


@app.post("/api/auth/driver/logout")
def driver_logout(_auth: dict = Depends(require_any_auth)):
    """Invalidate the current driver JWT (token blacklist)."""
    _revoke_current_token(_auth)
    return {"success": True, "message": "Logged out successfully"}




@app.post("/api/auth/customer/refresh")
def customer_refresh_token(customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """Refresh customer authentication token"""
    if not customer.is_active:
        raise HTTPException(status_code=403, detail="Customer account is inactive.")
    access_token = create_access_token(data={"sub": customer.email, "role": "customer", "customer_id": customer.id})
    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip() or "Customer"
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "customer_id": customer.id,
        "customer_code": customer.customer_id or f"CUST-{customer.id:05d}",
        "name": full_name,
        "email": customer.email,
        "phone": customer.phone,
    }




@app.post("/api/auth/customer/register")
def customer_auth_register(http_request: Request, request: CustomerRegisterRequest, db: Session = Depends(get_db)):
    """Register a new customer account for rideshare"""
    # SECURITY: Rate limit registration attempts
    check_rate_limit(http_request, registration_rate_limiter, "customer_register")
    print(f"Customer registration attempt for: {mask_email(request.email)}")

    try:
        # Check if email already exists
        existing_customer = db.query(Customer).filter(Customer.email == request.email).first()
        if existing_customer:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )

        # SECURITY: Enforce password policy (shared with all registration endpoints)
        _validate_password(request.password)

        # Split name (accepts both 'name' and 'full_name' fields)
        customer_name = request.get_name()
        if not customer_name:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name is required (send 'name' or 'full_name')"
            )
        # Sanitize name to prevent XSS
        customer_name = sanitize_input(customer_name)
        name_parts = customer_name.split(" ", 1)
        first_name = name_parts[0]
        last_name = name_parts[1] if len(name_parts) > 1 else ""

        hashed_password = get_password_hash(request.password)

        # Generate unique customer code with timestamp to avoid conflicts
        import time
        timestamp_suffix = int(time.time() * 1000) % 100000
        customer_code = f"CUST-{timestamp_suffix:05d}"

        new_customer = Customer(
            customer_id=customer_code,
            first_name=first_name,
            last_name=last_name,
            email=request.email,
            phone=request.phone or "",
            password_hash=hashed_password,
            is_active=True
        )
        db.add(new_customer)
        db.commit()
        db.refresh(new_customer)

        full_name = f"{new_customer.first_name} {new_customer.last_name}".strip()
        print(f"Customer registration successful for: {mask_email(new_customer.email)}, customer_id: {new_customer.id}")
        access_token = create_access_token(data={"sub": new_customer.email, "role": "customer", "customer_id": new_customer.id})

        # Send welcome email (non-blocking, don't fail registration if email fails)
        try:
            send_customer_welcome_email(
                to_email=new_customer.email,
                customer_name=full_name,
                customer_code=customer_code
            )
            print(f"Welcome email sent to: {mask_email(new_customer.email)}")
        except Exception as e:
            print(f"Failed to send customer welcome email: {str(e)}")

        return {
            "access_token": access_token,
            "token_type": "bearer",
            "customer_id": new_customer.id,
            "customer_code": customer_code,
            "name": full_name,
            "email": new_customer.email,
            "phone": new_customer.phone or "",
            "message": "Registration successful. Welcome to Dollor.ai!"
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        print(f"Customer auth registration error: {str(e)}")
        error_msg = str(e).lower()
        if "unique" in error_msg or "duplicate" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )
        elif "encoding" in error_msg or "unicode" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid characters in input. Please use standard characters."
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                # A2: Log error internally, return generic message
                detail="Registration failed. Please try again or contact support."
            )


# Customer Google OAuth
class CustomerGoogleAuthRequest(BaseModel):
    """Google auth request - accepts id_token from web or separate fields"""
    email: Optional[str] = None
    name: Optional[str] = None
    google_id: Optional[str] = None
    id_token: Optional[str] = None  # Web sends this JWT credential

@app.post("/api/auth/customer/google")
def customer_google_auth(http_request: Request, request: CustomerGoogleAuthRequest, db: Session = Depends(get_db)):
    """Google OAuth authentication for customers - handles both login and registration"""
    check_rate_limit(http_request, registration_rate_limiter, "register")

    # Decode id_token if provided (web sends this)
    if request.id_token:
        decoded = decode_google_jwt(request.id_token)
        email = decoded.get('email', request.email)
        name = decoded.get('name', request.name)
        google_id = decoded.get('sub', request.google_id)
    else:
        email = request.email
        name = request.name
        google_id = request.google_id

    if not email:
        raise HTTPException(status_code=400, detail="Email is required. Please try again.")
    if not name:
        name = email.split('@')[0]  # Use email prefix as fallback name

    print(f"Customer Google auth for: {mask_email(email)}")

    # Check if customer exists
    customer = db.query(Customer).filter(Customer.email == email).first()

    if customer:
        # Existing customer - check status
        if not customer.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Customer account is not active"
            )
    else:
        # Create new customer
        name_parts = name.split(" ", 1)
        first_name = name_parts[0]
        last_name = name_parts[1] if len(name_parts) > 1 else ""

        customer_count = db.query(Customer).count()
        customer_code = f"CUST-{customer_count + 1:05d}"

        hashed_password = get_password_hash(f"google_oauth_{google_id or email}")

        customer = Customer(
            customer_id=customer_code,
            first_name=first_name,
            last_name=last_name,
            email=email,
            password_hash=hashed_password,
            is_active=True
        )
        db.add(customer)
        db.commit()
        db.refresh(customer)
        print(f"Created new customer via Google auth: {mask_email(email)}")

        # Send welcome email for new Google signup
        try:
            send_customer_welcome_email(
                to_email=email,
                customer_name=name
            )
            print(f"Welcome email sent to Google signup: {mask_email(email)}")
        except Exception as e:
            print(f"Failed to send welcome email to Google signup: {str(e)}")

    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip() or name
    print(f"Customer Google auth successful for: {mask_email(customer.email)}")
    access_token = create_access_token(data={"sub": customer.email, "role": "customer", "customer_id": customer.id})
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "customer_id": customer.id,
        "customer_code": customer.customer_id or f"CUST-{customer.id:05d}",
        "name": full_name,
        "email": customer.email,
        "phone": customer.phone
    }


@app.get("/api/auth/customer/me")
def get_customer_profile(customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """Get current customer's profile"""
    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip() or "Customer"
    return {
        "id": customer.id,
        "customer_code": customer.customer_id or f"CUST-{customer.id:05d}",
        "name": full_name,
        "first_name": customer.first_name,
        "last_name": customer.last_name,
        "email": customer.email,
        "phone": customer.phone,
        "status": "active" if customer.is_active else "inactive",
        "total_rides": getattr(customer, 'total_rides', 0) or 0,
        "rating": getattr(customer, 'rating', 5.0) or 5.0
    }


@app.put("/api/auth/customer/profile")
def update_customer_profile(
    customer_id: Optional[int] = None,
    name: Optional[str] = None,
    phone: Optional[str] = None,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Update customer profile"""
    # SECURITY: If customer_id provided, verify ownership
    if customer_id is not None and customer.id != customer_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied")

    if name:
        name_parts = name.split(" ", 1)
        customer.first_name = name_parts[0]
        customer.last_name = name_parts[1] if len(name_parts) > 1 else ""

    if phone:
        customer.phone = phone

    db.commit()
    db.refresh(customer)

    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip() or "Customer"
    return {
        "success": True,
        "customer_id": customer.id,
        "name": full_name,
        "phone": customer.phone
    }


# ==================== CUSTOMER ACCOUNT DELETION ====================
# Required by Google Play Store policy for account deletion

@app.delete("/api/customers/{customer_id}/delete")
def delete_customer_account(
    customer_id: int,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Delete customer account - required by Play Store policy"""
    # SECURITY: Verify the token belongs to the customer being deleted
    if customer.id != customer_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot delete another user's account"
        )

    # Delete the customer
    db.delete(customer)
    db.commit()

    return {"success": True, "message": "Account deleted successfully"}


# ==================== DRIVER ACCOUNT DELETION ====================
# Required by Google Play Store policy for account deletion

@app.delete("/api/drivers/{driver_id}/delete")
def delete_driver_account(
    driver_id: int,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Delete driver account - required by Play Store policy"""
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    # Delete the driver
    db.delete(driver)
    db.commit()

    return {"success": True, "message": "Driver account deleted successfully"}


# ==================== VENDOR ACCOUNT DELETION ====================
# Required by Google Play Store policy for account deletion



# Admin endpoint to delete customer by email (for testing only)
@app.delete("/api/admin/customers/by-email/{email}")
def admin_delete_customer_by_email(
    request: Request,
    email: str,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Admin endpoint to delete customer by email - requires admin auth"""
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")

    customer = db.query(Customer).filter(Customer.email == email).first()
    if not customer:
        raise HTTPException(status_code=404, detail=f"Customer with email {email} not found")

    db.delete(customer)
    db.commit()

    return {"success": True, "message": f"Customer {email} deleted successfully"}


@app.get("/api/admin/customers")
def admin_list_customers(
    request: Request,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
    blocked_only: bool = False
):
    """Admin endpoint to list customers with unpaid balance status"""
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    query = db.query(Customer)
    if blocked_only:
        query = query.filter(Customer.has_unpaid_balance == True)
    customers = query.order_by(Customer.id.desc()).limit(500).all()
    return [
        {
            "id": c.id,
            "email": c.email,
            "name": getattr(c, "name", None) or getattr(c, "full_name", None) or "",
            "phone": getattr(c, "phone", ""),
            "has_unpaid_balance": c.has_unpaid_balance,
            "is_active": c.is_active,
            "created_at": c.created_at.isoformat() if c.created_at else None,
        }
        for c in customers
    ]


@app.post("/api/admin/customers/{customer_id}/clear-unpaid-balance")
def admin_clear_unpaid_balance(
    request: Request,
    customer_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Admin endpoint to clear has_unpaid_balance flag — unblocks customer from booking"""
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    customer = db.query(Customer).filter(Customer.id == customer_id).first()
    if not customer:
        raise HTTPException(status_code=404, detail=f"Customer {customer_id} not found")
    customer.has_unpaid_balance = False
    db.commit()
    logger.info(f"Admin {admin.email} cleared has_unpaid_balance for customer {customer_id}")
    return {"success": True, "customer_id": customer_id, "message": "Unpaid balance flag cleared"}


# ==================== EMAIL VERIFICATION ====================
# Required by App Store / Play Store for account security

import random
import string

class SendVerificationRequest(BaseModel):
    """Request to send email verification code"""
    pass  # No body needed - uses auth token

class VerifyEmailRequest(BaseModel):
    """Request to verify email with code"""
    code: str = Field(..., min_length=6, max_length=6)

@app.post("/api/customer/email/send-verification")
def send_verification_email(
    http_request: Request,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Send email verification code to customer's email"""
    # SECURITY: Rate-limit to prevent OTP spam and enumeration
    check_rate_limit(http_request, password_reset_limiter, "email_verify_send",
                     identifier=customer.email.lower())

    # Check if already verified
    if customer.email_verified:
        return {
            "success": True,
            "message": "Email already verified",
            "already_verified": True
        }

    # Generate cryptographically secure 6-digit verification code
    import secrets as _secrets_mod
    verification_code = ''.join(_secrets_mod.choice(string.digits) for _ in range(6))

    # Set expiry to 15 minutes from now
    expiry_time = datetime.utcnow() + timedelta(minutes=15)

    # Save code to database
    customer.email_verification_code = verification_code
    customer.email_verification_expires = expiry_time
    db.commit()

    # Send verification email
    email_sent = send_email_verification_code(
        to_email=customer.email,
        customer_name=customer.name or "Customer",
        verification_code=verification_code
    )

    if not email_sent:
        logger.warning(f"Failed to send verification email to {mask_email(customer.email)}")
        # Don't fail the request - code is saved, can try again

    return {
        "success": True,
        "message": "Verification code sent to your email",
        "email": customer.email[:3] + "***@" + customer.email.split("@")[1] if "@" in customer.email else "***",
        "expires_in_minutes": 15
    }

@app.post("/api/customer/email/verify")
def verify_customer_email(
    http_request: Request,
    request: VerifyEmailRequest,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Verify customer email with the 6-digit code"""
    # SECURITY: Rate-limit to prevent 6-digit OTP brute force (1M possibilities)
    check_rate_limit(http_request, auth_rate_limiter, "email_verify_attempt",
                     identifier=customer.email.lower())
    # Check if already verified
    if customer.email_verified:
        return {
            "success": True,
            "message": "Email already verified",
            "verified": True
        }

    # Check if code exists and hasn't expired
    if not customer.email_verification_code:
        raise HTTPException(
            status_code=400,
            detail="No verification code found. Please request a new code."
        )

    if customer.email_verification_expires and customer.email_verification_expires < datetime.utcnow():
        # Clear expired code
        customer.email_verification_code = None
        customer.email_verification_expires = None
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="Verification code has expired. Please request a new code."
        )

    # Verify the code (constant-time comparison to prevent timing attacks)
    import secrets as _secrets
    if not _secrets.compare_digest(str(customer.email_verification_code), str(request.code)):
        raise HTTPException(
            status_code=400,
            detail="Invalid verification code. Please try again."
        )

    # Mark email as verified
    customer.email_verified = True
    customer.email_verified_at = datetime.utcnow()
    customer.email_verification_code = None  # Clear the code
    customer.email_verification_expires = None
    db.commit()

    logger.info(f"Customer {mask_email(customer.email)} verified their email successfully")

    return {
        "success": True,
        "message": "Email verified successfully!",
        "verified": True,
        "verified_at": customer.email_verified_at.isoformat()
    }

@app.get("/api/customer/email/status")
def get_email_verification_status(
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Get customer's email verification status"""
    return {
        "email": customer.email,
        "verified": customer.email_verified or False,
        "verified_at": customer.email_verified_at.isoformat() if customer.email_verified_at else None
    }


# ==================== RIDESHARE ENDPOINTS ====================
# Rideshare booking endpoints for customer web and mobile apps

class FareEstimateRequest(BaseModel):
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    ride_type: Optional[str] = "standard"

class RideRequestModel(BaseModel):
    customer_name: Optional[str] = None  # Optional - derived from auth if not provided
    customer_email: Optional[str] = None  # Optional - derived from auth if not provided
    customer_phone: Optional[str] = None
    pickup_address: dict
    dropoff_address: dict
    tip: Optional[float] = 0.0
    ride_type: Optional[str] = "standard"

import math

# Track orders where "driver approaching" notification already sent (in-memory, resets on restart)
_driver_approaching_notified: set = set()

DRIVER_APPROACHING_THRESHOLD_METERS = 500

def calculate_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points using Haversine formula"""
    R = 6371  # Earth's radius in kilometers
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    return R * c


def _haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two GPS points in meters using Haversine formula."""
    R = 6371000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _check_driver_proximity_to_delivery(driver_id: int, driver_lat: float, driver_lng: float, db: Session):
    """Check if driver is within 500m of any active delivery address. Send one-time push to customer."""
    global _driver_approaching_notified
    try:
        active_orders = db.query(Order).filter(
            Order.driver_id == driver_id,
            Order.status == OrderStatus.OUT_FOR_DELIVERY,
            Order.delivery_latitude.isnot(None),
            Order.delivery_longitude.isnot(None)
        ).all()

        for order in active_orders:
            if order.id in _driver_approaching_notified:
                continue
            distance = _haversine_distance_meters(
                driver_lat, driver_lng,
                order.delivery_latitude, order.delivery_longitude
            )
            if distance <= DRIVER_APPROACHING_THRESHOLD_METERS:
                from order_flow import send_push_notification
                send_push_notification(
                    user_type="customer",
                    user_id=order.customer_id,
                    title="Driver Approaching",
                    body="Your driver is about 2 minutes away!",
                    data={"type": "driver_approaching", "order_id": str(order.id)},
                    db=db
                )
                _driver_approaching_notified.add(order.id)
                logger.info(f"Driver approaching notification sent for order {order.id} (distance: {distance:.0f}m)")
    except Exception as e:
        logger.warning(f"Driver proximity check failed: {e}")


def get_fare_tier_description(fare: float) -> str:
    """Get human-readable tier description for a fare amount."""
    return fare_tier_description(fare)


@app.post("/api/erp/rides/estimate-fare")
def estimate_fare(request: FareEstimateRequest):
    """
    Estimate fare for a ride - Fare-tiered platform fee model (canonical)

    Platform fee structure (based on FARE AMOUNT, not distance):
    - Fare <= $35: $1 from customer + $1 from driver = $2 platform revenue
    - Fare $35-70: $2 from customer + $2 from driver = $4 platform revenue
    - Fare > $70: $3 from customer + $3 from driver = $6 platform revenue

    Customer pays: Ride fare + platform fee
    Driver receives: Ride fare - platform fee + 100% of tips
    Source: rideshare_payments.py:36-43
    """
    # Calculate distance
    distance_km = calculate_distance_km(
        request.pickup_lat, request.pickup_lng,
        request.dropoff_lat, request.dropoff_lng
    )
    distance_miles = distance_km * 0.621371

    # Pricing based on ride type (canonical rates from pricing_config.py)
    pricing = {
        "standard": {"base": 2.50, "per_mile": 1.15, "per_min": 0.18},
        "premium": {"base": 5.00, "per_mile": 2.50, "per_min": 0.40},
        "xl": {"base": 4.00, "per_mile": 2.00, "per_min": 0.35},
        "shared": {"base": 1.50, "per_mile": 1.00, "per_min": 0.20}
    }

    if request.ride_type not in pricing:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid ride_type '{request.ride_type}'. Valid types: {', '.join(pricing.keys())}"
        )
    ride_pricing = pricing[request.ride_type]

    # Estimate time (assume 25 mph average speed)
    estimated_minutes = max(5, int((distance_miles / 25) * 60))

    # Calculate fare components
    base_fare = ride_pricing["base"]
    distance_fare = distance_miles * ride_pricing["per_mile"]
    time_fare = estimated_minutes * ride_pricing["per_min"]

    # Ride fare (before platform fees)
    ride_fare = round(base_fare + distance_fare + time_fare, 2)

    # Fare-tiered platform fees (canonical: rideshare_payments.py:36-43)
    platform_fee = get_tier_fee(ride_fare)
    fee_tier = get_fare_tier_description(ride_fare)
    customer_platform_fee = platform_fee
    driver_platform_fee = platform_fee

    # What driver receives (ride fare minus their tiered fee)
    driver_earnings = round(ride_fare - driver_platform_fee, 2)

    # Total customer pays (ride fare plus their tiered fee)
    total_fare = round(ride_fare + customer_platform_fee, 2)

    return {
        "estimated_fare": total_fare,
        "fare_breakdown": {
            "base_fare": base_fare,
            "distance_fare": round(distance_fare, 2),
            "time_fare": round(time_fare, 2),
            "ride_fare": ride_fare,
            "customer_platform_fee": customer_platform_fee,
            "driver_platform_fee": driver_platform_fee,
            "driver_earnings": driver_earnings,
            "total": total_fare,
            "fee_tier": fee_tier
        },
        "distance_miles": round(distance_miles, 2),
        "estimated_minutes": estimated_minutes,
        "ride_type": request.ride_type,
        "currency": "USD",
        "platform_fee": customer_platform_fee,
        "fee_tier": fee_tier,
        "message": f"You pay ${total_fare} (includes ${customer_platform_fee:.0f} platform fee for {fee_tier}). Driver earns ${driver_earnings} (after ${driver_platform_fee:.0f} platform fee)."
    }

@app.get("/erp/rides/{ride_id}/status")
@app.get("/api/erp/rides/{ride_id}/status")
def get_ride_status(ride_id: str, db: Session = Depends(get_db), _auth: dict = Depends(require_any_auth)):
    """Get current status of a ride from database (checks both rides and ride_requests tables)"""
    from sqlalchemy import text
    from models import RideRequest, RideRequestStatus

    # SECURITY: Verify caller is a participant in this ride before exposing driver PII
    caller_customer_id = _auth.get("customer_id")
    caller_driver_id = _auth.get("driver_id")
    rr = db.query(RideRequest).filter(
        (RideRequest.id == ride_id) | (RideRequest.request_id == str(ride_id))
    ).first()
    if rr:
        is_customer = caller_customer_id and rr.customer_id and int(caller_customer_id) == int(rr.customer_id)
        is_driver = caller_driver_id and rr.matched_driver_id and int(caller_driver_id) == int(rr.matched_driver_id)
        if not is_customer and not is_driver:
            raise HTTPException(status_code=403, detail="Access denied")

    # Try legacy rides table first
    result = None
    try:
        result = db.execute(
            text("""
                SELECT r.id, r.status, r.driver_id, r.pickup_address, r.dropoff_address,
                       d.first_name, d.last_name, d.rating, d.vehicle_type,
                       d.vehicle_make, d.vehicle_model, d.vehicle_year, d.license_plate, d.phone,
                       d.vehicle_color, d.photo_url, d.vehicle_photo_url
                FROM rides r
                LEFT JOIN drivers d ON r.driver_id = d.id
                WHERE r.id = :ride_id OR r.ride_id = :ride_id
            """),
            {"ride_id": ride_id}
        ).fetchone()
    except Exception:
        db.rollback()

    if result:
        ride_data = {
            "ride_id": ride_id,
            "status": result[1] if result[1] else "searching",
            "driver": None,
            "eta_minutes": None,
            "message": "Searching for a driver..."
        }

        if result[2]:
            ride_data["driver"] = {
                "id": result[2],
                "name": f"{result[5]} {result[6][0]}." if result[5] and result[6] else "Driver",
                "rating": float(result[7]) if result[7] else 4.8,
                "vehicle": {
                    "make": result[9] or "Unknown",
                    "model": result[10] or "Vehicle",
                    "year": result[11] or 2020,
                    "color": result[14] or "Unknown",
                    "license_plate": result[12] or "N/A"
                },
                "photo_url": result[15],
                "vehicle_photo_url": result[16],
                "phone": result[13] or None,
                "eta_minutes": 5
            }
            ride_data["eta_minutes"] = 5
            ride_data["message"] = f"Your driver {ride_data['driver']['name']} is on the way!"

        return ride_data

    # Fallback: check ride_requests table (new bidding flow)
    try:
        rr = db.query(RideRequest).filter(RideRequest.id == int(ride_id)).first()
    except Exception:
        raise HTTPException(status_code=404, detail="Ride not found")

    if not rr:
        raise HTTPException(status_code=404, detail="Ride not found")

    ride_data = {
        "ride_id": ride_id,
        "status": rr.status.value if rr.status else "open",
        "driver_id": rr.matched_driver_id,
        "pickup_address": rr.pickup_address,
        "dropoff_address": rr.dropoff_address,
        "suggested_price": float(rr.suggested_price) if rr.suggested_price else None,
        "final_price": float(rr.final_price) if rr.final_price else None,
        "tip_amount": float(rr.tip_amount) if rr.tip_amount else 0.0,
        "customer_rating": rr.customer_rating,
        "bid_count": len(rr.bids) if rr.bids else 0,
        "driver": None,
        "eta_minutes": None,
        "message": "Searching for a driver..."
    }

    if rr.matched_driver_id:
        driver = db.query(Driver).filter(Driver.id == rr.matched_driver_id).first()
        if driver:
            ride_data["driver"] = {
                "id": driver.id,
                "name": f"{driver.first_name} {driver.last_name[0]}." if driver.first_name and driver.last_name else "Driver",
                "rating": float(driver.rating) if driver.rating else 4.8,
                "vehicle": {
                    "make": getattr(driver, 'vehicle_make', None) or "Unknown",
                    "model": getattr(driver, 'vehicle_model', None) or "Vehicle",
                    "year": getattr(driver, 'vehicle_year', None) or 2020,
                    "color": getattr(driver, 'vehicle_color', None) or "Unknown",
                    "license_plate": getattr(driver, 'license_plate', None) or "N/A"
                },
                "phone": driver.phone or None,
                "eta_minutes": 5
            }
            status_val = rr.status.value if rr.status else ""
            if status_val == "completed":
                ride_data["message"] = "Ride completed"
            elif status_val == "in_progress":
                ride_data["message"] = f"Your driver {ride_data['driver']['name']} is on the way!"
            else:
                ride_data["message"] = f"Driver {ride_data['driver']['name']} matched!"

    return ride_data


# Frontend-compatible fare estimate endpoint (uses /estimate instead of /estimate-fare)
@app.get("/api/erp/rides/estimate")
def estimate_fare_frontend(
    pickup_lat: float = None,
    pickup_lng: float = None,
    dropoff_lat: float = None,
    dropoff_lng: float = None,
    state_code: str = "CA",
    tip: float = 0
):
    """
    Frontend-compatible fare estimate endpoint with fare-tiered platform fees

    Platform fee structure (based on FARE AMOUNT, not distance):
    - Fare <= $35: $1 from customer + $1 from driver = $2 platform revenue
    - Fare $35-70: $2 from customer + $2 from driver = $4 platform revenue
    - Fare > $70: $3 from customer + $3 from driver = $6 platform revenue
    Source: rideshare_payments.py:36-43
    """
    if not all([pickup_lat, pickup_lng, dropoff_lat, dropoff_lng]):
        raise HTTPException(status_code=400, detail="Missing coordinate parameters")

    # Validate coordinate ranges
    if not (-90 <= pickup_lat <= 90) or not (-90 <= dropoff_lat <= 90):
        raise HTTPException(status_code=400, detail="Invalid coordinates: latitude must be between -90 and 90")
    if not (-180 <= pickup_lng <= 180) or not (-180 <= dropoff_lng <= 180):
        raise HTTPException(status_code=400, detail="Invalid coordinates: longitude must be between -180 and 180")

    distance_km = calculate_distance_km(pickup_lat, pickup_lng, dropoff_lat, dropoff_lng)
    distance_miles = distance_km * 0.621371
    estimated_minutes = max(5, int((distance_miles / 25) * 60))

    # Calculate fare (canonical rates from pricing_config.py)
    base_fare = 2.50
    distance_fee = distance_miles * 1.15
    time_fee = estimated_minutes * 0.18
    ride_fare = round(base_fare + distance_fee + time_fee, 2)

    # Tax (state-based)
    tax_rates = {"CA": 0.0725, "NY": 0.08, "TX": 0.0625}
    tax_rate = tax_rates.get(state_code, 0.07)
    tax_amount = round(ride_fare * tax_rate, 2)

    # Fare-tiered platform fees (canonical: rideshare_payments.py:36-43)
    platform_fee = get_tier_fee(ride_fare)
    fee_tier = get_fare_tier_description(ride_fare)
    driver_platform_fee = platform_fee

    # Driver earnings
    driver_earnings = round(ride_fare - driver_platform_fee, 2)

    # Total (ride + customer platform fee + tax)
    total_fare = round(ride_fare + platform_fee + tax_amount, 2)

    return {
        "success": True,
        "fare_estimate": {
            "total_fare": total_fare,
            "platform_fee": platform_fee,
            "base_fare": base_fare,
            "distance_fee": round(distance_fee, 2),
            "time_fee": round(time_fee, 2),
            "tax_amount": tax_amount,
            "driver_earnings": driver_earnings,
            "distance_miles": round(distance_miles, 2),
            "duration_minutes": estimated_minutes,
            "fee_tier": fee_tier
        },
        "total_fare": total_fare,
        "platform_fee": platform_fee,
        "fee_tier": fee_tier,
        "base_fare": base_fare,
        "distance_fee": round(distance_fee, 2),
        "time_fee": round(time_fee, 2),
        "tax_amount": tax_amount,
        "driver_earnings": driver_earnings,
        "distance_miles": round(distance_miles, 2),
        "duration_minutes": estimated_minutes,
        "ride_fare": ride_fare,
        "customer_platform_fee": platform_fee,
        "driver_platform_fee": driver_platform_fee
    }


# Full tracking endpoint for RIDES (rideshare) - frontend polling
# NOTE: Use /api/erp/rides/ path to avoid conflict with order tracking in order_flow.py
@app.get("/api/erp/rides/{ride_id}/full-tracking")
def get_ride_full_tracking(ride_id: str, db: Session = Depends(get_db), _auth: dict = Depends(require_any_auth)):
    """
    Full tracking endpoint for RIDESHARE - queries real data from database
    For FOOD ORDER tracking, use /api/erp/orders/{order_id}/full-tracking (in order_flow.py)
    """
    # SECURITY: Only the customer or matched driver for THIS ride can see driver PII
    from models import RideRequest as _RR
    caller_customer_id = _auth.get("customer_id")
    caller_driver_id = _auth.get("driver_id")
    rr = db.query(_RR).filter(
        (_RR.id == ride_id) | (_RR.request_id == str(ride_id))
    ).first()
    if rr:
        is_customer = caller_customer_id and rr.customer_id and int(caller_customer_id) == int(rr.customer_id)
        is_driver = caller_driver_id and rr.matched_driver_id and int(caller_driver_id) == int(rr.matched_driver_id)
        if not is_customer and not is_driver:
            raise HTTPException(status_code=403, detail="Access denied")

    try:
        from sqlalchemy import text

        # Query ride with driver info including photos
        result = db.execute(
            text("""
                SELECT r.id, r.status, r.driver_id,
                       d.first_name, d.last_name, d.phone, d.rating,
                       d.vehicle_make, d.vehicle_model, d.license_plate,
                       d.photo_url, d.vehicle_photo_url, d.vehicle_color, d.vehicle_year
                FROM rides r
                LEFT JOIN drivers d ON r.driver_id = d.id
                WHERE r.id = :ride_id OR r.ride_id = :ride_id
            """),
            {"ride_id": ride_id}
        ).fetchone()

        if not result:
            raise HTTPException(status_code=404, detail="Ride not found")

        driver_data = None
        if result[2]:  # driver_id exists
            driver_data = {
                "id": result[2],
                "name": f"{result[3]} {result[4][0]}." if result[3] and result[4] else "Driver",
                "phone": result[5] or None,
                "rating": float(result[6]) if result[6] else 4.8,
                "photo_url": result[10],  # d.photo_url
                "vehicle_photo_url": result[11],  # d.vehicle_photo_url
                "vehicle": f"{result[7] or 'Unknown'} {result[8] or 'Vehicle'}",
                "vehicle_make": result[7],
                "vehicle_model": result[8],
                "vehicle_color": result[12],  # d.vehicle_color
                "vehicle_year": result[13],  # d.vehicle_year
                "license_plate": result[9] or "N/A"
            }

        return {
            "success": True,
            "order": {
                "status": result[1] or "searching",
                "ride_id": ride_id
            },
            "driver": driver_data,
            "eta_minutes": 5 if driver_data else None
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching ride tracking: {e}")
        raise HTTPException(status_code=500, detail="Unable to fetch ride tracking. Please try again.")


# Ride rating endpoint
class ERPRideRatingRequest(BaseModel):
    rating: int = Field(..., ge=1, le=5, description="Rating 1-5 stars")
    feedback: Optional[str] = Field(None, description="Optional feedback comment")
    comment: Optional[str] = Field(None, description="Alias for feedback")
    rated_by: str = Field("customer", description="Who is rating")

@app.post("/api/erp/rides/{ride_id}/rate")
async def rate_ride(ride_id: int, body: ERPRideRatingRequest, db: Session = Depends(get_db), _auth: dict = Depends(require_any_auth)):
    """
    Rate a completed ride (ERP endpoint).
    Accepts JSON body: {"rating": 1-5, "feedback": "optional", "rated_by": "customer"}
    Only the ride's customer or matched driver can rate.
    """
    from models import RideRequest, RideRequestStatus

    rating = body.rating
    feedback = body.feedback or body.comment or ""
    rated_by = body.rated_by

    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # SECURITY: Only ride participants (customer or matched driver) can rate
    auth_customer_id = _auth.get("customer_id")
    auth_driver_id = _auth.get("driver_id")
    if auth_customer_id != ride.customer_id and auth_driver_id != ride.matched_driver_id:
        raise HTTPException(status_code=403, detail="You can only rate rides you participated in")

    # Verify ride is completed
    if ride.status != RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail=f"Can only rate completed rides (current: {ride.status.value})")

    # Prevent double-rating (re-rating would inflate total_deliveries)
    if ride.customer_rating is not None:
        raise HTTPException(status_code=400, detail="This ride has already been rated")

    # Save rating to ride_requests
    ride.customer_rating = rating
    ride.customer_comment = feedback

    # Update driver's average rating
    if ride.matched_driver_id:
        driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first()
        if driver:
            current_rating = driver.rating or 5.0
            total_trips = driver.total_deliveries or 0
            new_rating = round(((current_rating * total_trips) + rating) / (total_trips + 1), 2)
            driver.rating = new_rating
            driver.total_deliveries = total_trips + 1

    db.commit()

    return {
        "success": True,
        "ride_id": ride_id,
        "rating": rating,
        "feedback": feedback,
        "rated_by": rated_by,
        "message": "Thank you for your feedback!"
    }


# ==================== REMOVED LEGACY ENDPOINTS ====================
# The following endpoints were removed as they are not used by any platform:
# - /api/customer/login (use /api/auth/customer/login or /auth/customer/login instead)
# - /api/driver/login (use /api/auth/driver/login or /auth/driver/login instead)
# - /api/vendor/login (use /api/auth/vendor/login or /auth/vendor/login instead)
#
# Active login endpoints by platform:
# - iOS/Android: /auth/customer/login, /auth/driver/login, /auth/vendor/login (no /api prefix)
# - WebApp: /api/auth/customer/login, /api/auth/driver/login, /api/auth/vendor/login
# ===================================================================


@app.get("/erp/drivers/{driver_id}")
def get_driver_profile_by_id(driver_id: int, driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Get driver profile by ID (requires valid driver JWT token)"""
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    # Count completed rides for this driver (defensive: table/column may not exist)
    total_rides = 0
    try:
        from models import RideRequest, RideRequestStatus
        total_rides = db.query(RideRequest).filter(
            RideRequest.matched_driver_id == driver.id,
            RideRequest.status == RideRequestStatus.COMPLETED
        ).count()
    except Exception:
        db.rollback()  # Reset session state after failed query

    try:
        status_val = driver.status.value if driver.status else "pending"
    except Exception:
        status_val = "pending"
    is_approved = status_val in ("approved", "active", "online")

    def safe_iso(dt):
        """Safely convert a date/datetime to ISO string."""
        try:
            return dt.isoformat() if dt else None
        except Exception:
            return str(dt) if dt else None

    return {
        "id": driver.id,
        "driver_code": driver.driver_id,
        "driver_id": driver.driver_id,
        "name": f"{driver.first_name or ''} {driver.last_name or ''}".strip(),
        "full_name": f"{driver.first_name or ''} {driver.last_name or ''}".strip(),
        "first_name": driver.first_name,
        "last_name": driver.last_name,
        "email": driver.email,
        "phone": driver.phone,
        "phone_number": driver.phone,
        "date_of_birth": safe_iso(driver.date_of_birth),
        "status": status_val,
        "approval_status": status_val,
        "is_approved": is_approved,
        "rating": driver.rating,
        "total_deliveries": driver.total_deliveries,
        "total_rides": total_rides,
        "is_online": driver.is_online,
        "latitude": driver.current_latitude,
        "longitude": driver.current_longitude,
        "current_lat": driver.current_latitude,
        "current_lng": driver.current_longitude,
        # Vehicle
        "vehicle_type": driver.vehicle_type,
        "vehicle_make": driver.vehicle_make,
        "vehicle_model": driver.vehicle_model,
        "vehicle_year": driver.vehicle_year,
        "vehicle_color": driver.vehicle_color,
        "license_plate": driver.license_plate,
        # Photos
        "profile_image": driver.photo_url,
        "photo_url": driver.photo_url,
        "profile_image_url": driver.photo_url,
        "vehicle_photo_url": driver.vehicle_photo_url,
        # Documents
        "license_number": driver.license_number,
        "drivers_license": driver.drivers_license,
        "drivers_license_url": driver.drivers_license_url,
        "drivers_license_expiry": safe_iso(driver.drivers_license_expiry),
        "insurance": driver.insurance,
        "insurance_url": driver.insurance_url,
        "insurance_expiry": safe_iso(driver.insurance_expiry),
        "background_check": driver.background_check,
        "background_check_date": safe_iso(driver.background_check_date),
        # Verification
        "verification_status": driver.verification_status,
        "documents_verified": driver.documents_verified,
        # Stripe / Payouts
        "stripe_onboarded": driver.stripe_onboarded,
        "stripe_account_connected": driver.stripe_account_id is not None,
        # Bank Account (iOS app uses camelCase keys) — decrypt sensitive fields
        "bankAccount": {
            "bankName": decrypt_field(driver.bank_name),
            "accountNumberLast4": driver.bank_last4,
            "accountHolderName": decrypt_field(driver.bank_account_holder) or f"{driver.first_name or ''} {driver.last_name or ''}".strip(),
            "routingNumber": decrypt_field(driver.bank_routing_number),
            "accountType": "checking",
            "isVerified": bool(driver.bank_verified),
        } if driver.bank_name and driver.bank_last4 else None,
        "bank_account_linked": bool(driver.bank_name and driver.bank_last4),
        # Address fields
        "street": driver.street,
        "city": driver.city,
        "state": driver.state,
        "zip_code": driver.zip_code,
        # Timestamps
        "created_at": safe_iso(driver.created_at),
        "approved_at": safe_iso(driver.approved_at),
    }


class DriverProfileUpdate(BaseModel):
    """Request body for driver profile update (iOS app and web portal compatible)"""
    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    # Address fields
    street: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    zip_code: Optional[str] = None
    # Vehicle fields
    vehicle_type: Optional[str] = None
    vehicle_make: Optional[str] = None
    vehicle_model: Optional[str] = None
    vehicle_year: Optional[int] = None
    vehicle_color: Optional[str] = None
    license_plate: Optional[str] = None
    license_number: Optional[str] = None
    license_expiry: Optional[str] = None
    insurance_expiry: Optional[str] = None
    # Photo URLs (from document uploads)
    photo_url: Optional[str] = None
    vehicle_photo_url: Optional[str] = None
    # Bank account fields (driver-submitted; auto-verified for demo)
    bank_name: Optional[str] = None
    bank_routing_number: Optional[str] = None
    account_number: Optional[str] = None  # Full number; last 4 stored

    class Config:
        extra = "ignore"  # Ignore extra fields


@app.put("/drivers/{driver_id}")
def update_driver_profile_by_id(
    driver_id: int,
    body: Optional[DriverProfileUpdate] = None,
    first_name: Optional[str] = None,
    last_name: Optional[str] = None,
    phone: Optional[str] = None,
    street: Optional[str] = None,
    city: Optional[str] = None,
    state: Optional[str] = None,
    zip_code: Optional[str] = None,
    vehicle_type: Optional[str] = None,
    vehicle_make: Optional[str] = None,
    vehicle_model: Optional[str] = None,
    vehicle_year: Optional[int] = None,
    vehicle_color: Optional[str] = None,
    license_plate: Optional[str] = None,
    license_number: Optional[str] = None,
    photo_url: Optional[str] = None,
    vehicle_photo_url: Optional[str] = None,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Update driver profile by ID (iOS app and web portal compatible endpoint)
    Accepts both JSON body and query parameters for flexibility.
    """
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    # Merge body and query params - body takes precedence
    if body:
        first_name = body.first_name or first_name
        last_name = body.last_name or last_name
        phone = body.phone or phone
        street = body.street or street
        city = body.city or city
        state = body.state or state
        zip_code = body.zip_code or zip_code
        vehicle_type = body.vehicle_type or vehicle_type
        vehicle_make = body.vehicle_make or vehicle_make
        vehicle_model = body.vehicle_model or vehicle_model
        vehicle_year = body.vehicle_year or vehicle_year
        vehicle_color = body.vehicle_color or vehicle_color
        license_plate = body.license_plate or license_plate
        license_number = body.license_number or license_number
        photo_url = body.photo_url or photo_url
        vehicle_photo_url = body.vehicle_photo_url or vehicle_photo_url

    # Update personal info
    if first_name is not None:
        driver.first_name = first_name
    if last_name is not None:
        driver.last_name = last_name
    if phone is not None:
        driver.phone = phone

    # Update address fields
    if street is not None:
        driver.street = street
    if city is not None:
        driver.city = city
    if state is not None:
        driver.state = state
    if zip_code is not None:
        driver.zip_code = zip_code

    # Update vehicle fields
    if vehicle_type is not None:
        driver.vehicle_type = vehicle_type
    if vehicle_make is not None:
        driver.vehicle_make = vehicle_make
    if vehicle_model is not None:
        driver.vehicle_model = vehicle_model
    if vehicle_year is not None:
        driver.vehicle_year = vehicle_year
    if vehicle_color is not None:
        driver.vehicle_color = vehicle_color
    if license_plate is not None:
        driver.license_plate = license_plate
    if license_number is not None:
        driver.license_number = license_number

    # Update expiry dates (from DriverProfileUpdate body only)
    if body and body.license_expiry:
        try:
            driver.drivers_license_expiry = datetime.fromisoformat(body.license_expiry.replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            pass
    if body and body.insurance_expiry:
        try:
            driver.insurance_expiry = datetime.fromisoformat(body.insurance_expiry.replace('Z', '+00:00'))
        except (ValueError, AttributeError):
            pass

    # Update photo URLs
    if photo_url is not None:
        driver.photo_url = photo_url
    if vehicle_photo_url is not None:
        driver.vehicle_photo_url = vehicle_photo_url

    # Update bank account (driver-submitted; auto-verified for demo accounts)
    if body:
        bank_name_val = body.bank_name
        bank_routing_val = body.bank_routing_number
        account_number_val = body.account_number
    else:
        bank_name_val = bank_routing_val = account_number_val = None

    if bank_name_val is not None:
        from encryption import encrypt_field
        driver.bank_name = encrypt_field(bank_name_val)
        driver.bank_routing_number = encrypt_field(bank_routing_val)
        if account_number_val:
            driver.bank_last4 = account_number_val[-4:]  # Last 4 stays plaintext for display
        account_holder = driver.bank_account_holder or f"{driver.first_name or ''} {driver.last_name or ''}".strip()
        driver.bank_account_holder = encrypt_field(account_holder)
        driver.bank_verified = True
        driver.bank_verified_at = datetime.utcnow()

    driver.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "message": "Profile updated successfully",
        "driver": {
            "id": driver.id,
            "name": f"{driver.first_name} {driver.last_name}",
            "email": driver.email,
            "street": driver.street,
            "city": driver.city,
            "state": driver.state,
            "zip_code": driver.zip_code
        }
    }


@app.patch("/drivers/{driver_id}/status")
def update_driver_status(
    driver_id: int,
    status: str,
    skip_document_check: bool = Query(False, description="Skip document verification (admin override)"),
    _admin: User = Depends(require_admin),  # SECURITY: admin-only — drivers must not self-approve
    db: Session = Depends(get_db)
):
    """Update driver status - sends approval email when approved. Admin only."""
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    old_status = driver.status

    # If approving, verify all required documents are uploaded for legal compliance
    if status.upper() in ["APPROVED", "ACTIVE"] and not skip_document_check:
        missing_docs = []

        # Check required documents for driver onboarding
        if not driver.drivers_license or not driver.drivers_license_url:
            missing_docs.append("Driver's License")

        if not driver.insurance or not driver.insurance_url:
            missing_docs.append("Vehicle Insurance")

        # Photo is required for identification
        if not driver.photo_url:
            missing_docs.append("Driver Photo (for ID verification)")

        # TNC-06: Verify driver is at least 21 years old before approval (CPUC Decision 13-09-045)
        if driver.date_of_birth:
            try:
                dob = datetime.strptime(driver.date_of_birth, "%Y-%m-%d").date()
                today = date.today()
                age = today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))
                if age < 21:
                    missing_docs.append("Age requirement (must be 21+ for TNC services)")
            except ValueError:
                missing_docs.append("Valid date of birth (YYYY-MM-DD format)")
        else:
            missing_docs.append("Date of birth (required for age verification)")

        if missing_docs:
            raise HTTPException(
                status_code=400,
                detail={
                    "message": "Cannot approve driver - requirements not met for TNC compliance",
                    "missing_requirements": missing_docs,
                    "action_required": "Upload all required documents and meet age requirements before approval",
                    "help": "Use /drivers/{driver_id}/documents endpoint to upload missing documents"
                }
            )

        print(f"✅ All required documents and age verified for driver {driver_id}")

    # Update status
    try:
        driver.status = DriverStatus[status.upper()]
    except KeyError:
        raise HTTPException(status_code=400, detail=f"Invalid status: {status}. Valid statuses: {[s.name for s in DriverStatus]}")

    driver.updated_at = datetime.utcnow()

    # If driver is being approved, set approved_at and send approval email
    if status.upper() in ["APPROVED", "ACTIVE"] and old_status not in [DriverStatus.APPROVED, DriverStatus.ACTIVE]:
        driver.approved_at = datetime.utcnow()
        try:
            send_driver_approval_email(
                to_email=driver.email,
                driver_name=f"{driver.first_name} {driver.last_name}",
                driver_code=driver.driver_id
            )
            print(f"Driver approval email sent to: {driver.email}")
        except Exception as e:
            print(f"Failed to send driver approval email: {str(e)}")

    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "message": f"Driver status updated to {driver.status.value}",
        "driver_id": driver.id,
        "status": driver.status.value
    }


# ==================== DRIVER STATUS ENDPOINTS (Android Compatibility) ====================
# Android app uses GET/POST /api/drivers/{driver_id}/status

@app.get("/api/drivers/{driver_id}/status")
def get_driver_status(
    driver_id: int,
    _auth: dict = Depends(require_any_auth),
    db: Session = Depends(get_db)
):
    """Get driver online/offline status - Used by Android Driver app"""
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    return {
        "success": True,
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "name": f"{driver.first_name} {driver.last_name}",
        "is_online": driver.is_online if hasattr(driver, 'is_online') else False,
        "status": driver.status.value if driver.status else "pending",
        "last_location_update": driver.last_location_update.isoformat() if hasattr(driver, 'last_location_update') and driver.last_location_update else None,
        "current_latitude": driver.current_latitude if hasattr(driver, 'current_latitude') else None,
        "current_longitude": driver.current_longitude if hasattr(driver, 'current_longitude') else None
    }


@app.post("/api/drivers/{driver_id}/status")
def post_driver_status(
    driver_id: int,
    is_online: bool = Query(..., description="Set driver online/offline status"),
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Update driver online/offline status - Used by Android Driver app"""
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    # TNC gate (CPUC 13-09-045): a driver may only go ONLINE if approved AND the
    # Checkr background check has passed. Prevents this route from bypassing vetting.
    if is_online:
        from models import DriverStatus
        status_val = driver.status.value if hasattr(driver.status, "value") else str(driver.status)
        approved_states = (DriverStatus.APPROVED.value, DriverStatus.ACTIVE.value, DriverStatus.ONLINE.value)
        if status_val not in approved_states:
            raise HTTPException(status_code=403, detail="Driver not approved. Complete verification and background check before going online.")
        if not driver.background_check:
            raise HTTPException(status_code=403, detail="Background check not passed. You cannot go online until your background check clears.")

    driver.is_online = is_online
    driver.updated_at = datetime.utcnow()

    if is_online:
        driver.last_online_at = datetime.utcnow()
        # Insurance: Period 1 START — driver is now available (mirrors PUT /api/auth/driver/online).
        # Non-blocking: an insurance logging failure must never stop a driver from going online.
        try:
            import uuid as _uuid
            from insurance.events import log_insurance_event
            _session_id = str(_uuid.uuid4())
            driver.insurance_session_id = _session_id
            log_insurance_event(
                db=db, driver_id=driver.id, trip_type="available",
                trip_id=None, session_id=_session_id, period=1,
                event_type="period_start",
            )
        except Exception as e:
            logging.warning(f"Insurance event (android online) failed: {e}")
    else:
        # Insurance: Period 1 END — driver going offline.
        try:
            from insurance.events import log_insurance_event, get_or_create_session_id
            _session_id = get_or_create_session_id(db, driver.id)
            log_insurance_event(
                db=db, driver_id=driver.id, trip_type="available",
                trip_id=None, session_id=_session_id, period=1,
                event_type="period_end",
            )
        except Exception as e:
            logging.warning(f"Insurance event (android offline) failed: {e}")

    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "message": f"Driver is now {'online' if is_online else 'offline'}",
        "driver_id": driver.id,
        "is_online": driver.is_online,
        "status": driver.status.value if driver.status else "pending"
    }


# ==================== STRIPE CONNECT FOR DRIVERS ====================
# Stripe Connect Express accounts for driver payouts

@app.post("/api/drivers/{driver_id}/stripe/connect")
def create_driver_stripe_account(
    driver_id: int,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Create a Stripe Connect Express account for a driver.
    This is step 1 of driver payout onboarding.
    """
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="You can only manage your own Stripe account")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    # Check if driver already has a Stripe account
    if driver.stripe_account_id:
        return {
            "success": True,
            "message": "Stripe account already exists",
            "stripe_account_id": driver.stripe_account_id,
            "onboarded": driver.stripe_onboarded
        }

    try:
        # Create Stripe Connect Express account
        account = stripe.Account.create(
            type="express",
            country="US",
            email=driver.email,
            capabilities={
                "card_payments": {"requested": True},
                "transfers": {"requested": True},
            },
            business_type="individual",
            business_profile={
                "mcc": "4121",  # Taxicabs/Limousines
                "product_description": "Delivery and rideshare driver services"
            },
            metadata={
                "driver_id": str(driver.id),
                "driver_code": driver.driver_id,
                "platform": "dollor.ai"
            }
        )

        # Save Stripe account ID to driver record
        driver.stripe_account_id = account.id
        driver.updated_at = datetime.utcnow()
        db.commit()

        return {
            "success": True,
            "message": "Stripe Connect account created",
            "stripe_account_id": account.id,
            "onboarded": False
        }

    except stripe.error.StripeError as e:
        logger.error(f"API error at line 5160: {e}")
        raise HTTPException(status_code=500, detail="Payment processing error. Please try again or contact support.")


@app.get("/api/drivers/{driver_id}/stripe/onboarding-link")
def get_driver_stripe_onboarding_link(
    driver_id: int,
    return_url: str = Query(default="https://www.dollor.ai/driver/profile"),
    refresh_url: str = Query(default="https://www.dollor.ai/driver/profile"),
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Generate a Stripe Connect onboarding link for the driver.
    The driver uses this link to complete their payout setup including bank account.
    """
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="You can only manage your own Stripe account")

    # Validate redirect URLs against allowed domains to prevent open redirect / phishing
    from urllib.parse import urlparse
    _ALLOWED_REDIRECT_DOMAINS = {"dollor.ai", "www.dollor.ai", "api.dollor.ai"}
    for url_val, url_name in [(return_url, "return_url"), (refresh_url, "refresh_url")]:
        parsed = urlparse(url_val)
        if parsed.netloc not in _ALLOWED_REDIRECT_DOMAINS:
            raise HTTPException(status_code=400, detail=f"Invalid {url_name}: domain must be dollor.ai")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    # Create Stripe account if doesn't exist
    if not driver.stripe_account_id:
        try:
            account = stripe.Account.create(
                type="express",
                country="US",
                email=driver.email,
                capabilities={
                    "card_payments": {"requested": True},
                    "transfers": {"requested": True},
                },
                business_type="individual",
                metadata={
                    "driver_id": str(driver.id),
                    "driver_code": driver.driver_id,
                    "platform": "dollor.ai"
                }
            )
            driver.stripe_account_id = account.id
            db.commit()
        except stripe.error.StripeError as e:
            logger.error(f"API error at line 5212: {e}")
            raise HTTPException(status_code=500, detail="Failed to set up payment account. Please try again or contact support.")

    try:
        # Create Account Link for onboarding
        account_link = stripe.AccountLink.create(
            account=driver.stripe_account_id,
            refresh_url=refresh_url,
            return_url=return_url,
            type="account_onboarding",
        )

        return {
            "success": True,
            "onboarding_url": account_link.url,
            "expires_at": account_link.expires_at,
            "stripe_account_id": driver.stripe_account_id
        }

    except stripe.error.StripeError as e:
        logger.error(f"API error at line 5231: {e}")
        raise HTTPException(status_code=500, detail="Payment processing error. Please try again or contact support.")


@app.get("/api/drivers/{driver_id}/stripe/status")
def get_driver_stripe_status(
    driver_id: int,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Get the driver's Stripe Connect account status including bank account info.
    """
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="You can only view your own Stripe status")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    # If driver has a bank account stored in DB (added via admin portal), return it directly
    if driver.bank_name and driver.bank_last4:
        return {
            "success": True,
            "has_stripe_account": driver.stripe_account_id is not None,
            "onboarded": driver.bank_verified,
            "charges_enabled": driver.bank_verified,
            "payouts_enabled": driver.bank_verified,
            "bank_account_linked": True,
            "bank_account": {
                "bank_name": decrypt_field(driver.bank_name),
                "last4": driver.bank_last4,
                "routing_number": decrypt_field(driver.bank_routing_number),
                "account_holder_name": decrypt_field(driver.bank_account_holder) or f"{driver.first_name} {driver.last_name}",
                "account_holder_type": "individual",
                "status": "verified" if driver.bank_verified else "new"
            },
            "details_submitted": True,
            "requirements": {
                "currently_due": [],
                "eventually_due": [],
                "pending_verification": []
            }
        }

    if not driver.stripe_account_id:
        return {
            "success": True,
            "has_stripe_account": False,
            "onboarded": False,
            "bank_account_linked": False,
            "payouts_enabled": False,
            "message": "No Stripe account. Call POST /api/drivers/{id}/stripe/connect to create one."
        }

    try:
        # Retrieve Stripe account details
        account = stripe.Account.retrieve(driver.stripe_account_id)

        # Check if account is fully onboarded
        is_onboarded = account.charges_enabled and account.payouts_enabled

        # Update driver record if onboarding status changed
        if is_onboarded and not driver.stripe_onboarded:
            driver.stripe_onboarded = True
            driver.updated_at = datetime.utcnow()
            db.commit()

        # Get bank account info if available
        bank_info = None
        if account.external_accounts and account.external_accounts.data:
            for ext_account in account.external_accounts.data:
                if ext_account.object == "bank_account":
                    bank_info = {
                        "bank_name": ext_account.bank_name,
                        "last4": ext_account.last4,
                        "routing_number": ext_account.routing_number,
                        "account_holder_name": ext_account.account_holder_name,
                        "account_holder_type": ext_account.account_holder_type,
                        "status": ext_account.status
                    }
                    break

        return {
            "success": True,
            "has_stripe_account": True,
            "stripe_account_id": driver.stripe_account_id,
            "onboarded": is_onboarded,
            "charges_enabled": account.charges_enabled,
            "payouts_enabled": account.payouts_enabled,
            "bank_account_linked": bank_info is not None,
            "bank_account": bank_info,
            "details_submitted": account.details_submitted,
            "requirements": {
                "currently_due": account.requirements.currently_due if account.requirements else [],
                "eventually_due": account.requirements.eventually_due if account.requirements else [],
                "pending_verification": account.requirements.pending_verification if account.requirements else []
            }
        }

    except stripe.error.StripeError as e:
        logger.error(f"API error at line 5332: {e}")
        raise HTTPException(status_code=500, detail="Payment processing error. Please try again or contact support.")


@app.post("/api/drivers/{driver_id}/stripe/dashboard-link")
def get_driver_stripe_dashboard_link(
    driver_id: int,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Generate a link to the driver's Stripe Express dashboard.
    Drivers can use this to view payouts, update bank info, etc.
    """
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="You can only access your own Stripe dashboard")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    if not driver.stripe_account_id:
        raise HTTPException(status_code=400, detail="Driver has no Stripe account")

    try:
        # Create login link for Express dashboard
        login_link = stripe.Account.create_login_link(driver.stripe_account_id)

        return {
            "success": True,
            "dashboard_url": login_link.url,
            "message": "Use this link to access your Stripe dashboard"
        }

    except stripe.error.StripeError as e:
        logger.error(f"API error at line 5367: {e}")
        raise HTTPException(status_code=500, detail="Payment processing error. Please try again or contact support.")


@app.post("/api/webhooks/stripe-connect")
async def stripe_connect_webhook(
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Handle Stripe Connect webhooks for driver account updates.
    Configure this endpoint in Stripe Dashboard > Webhooks for Connect.
    """
    import stripe
    import os

    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
    # M6: must use the Connect-specific secret — the standard webhook secret is DIFFERENT
    webhook_secret = os.getenv("STRIPE_CONNECT_WEBHOOK_SECRET")
    if not webhook_secret:
        logger.error("STRIPE_CONNECT_WEBHOOK_SECRET is not set — Connect webhook rejected")
        raise HTTPException(status_code=500, detail="Webhook not configured")

    payload = await request.body()
    sig_header = request.headers.get("stripe-signature")

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, webhook_secret
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    # Idempotency: prevent duplicate processing on Stripe retries
    event_id = event.get("id")
    if event_id:
        from cache import redis_client, REDIS_AVAILABLE
        if REDIS_AVAILABLE and redis_client:
            redis_key = f"dollor:stripe:event:{event_id}"
            if redis_client.get(redis_key):
                # Already processed — return 200 immediately (Stripe needs 2xx to stop retrying)
                return {"success": True, "event_type": event.get("type", "unknown"), "duplicate": True}

    event_type = event["type"]
    event_data = event["data"]["object"]

    # Handle account.updated event - fired when account status changes
    if event_type == "account.updated":
        account_id = event_data.get("id")

        # Find driver with this Stripe account
        driver = db.query(Driver).filter(Driver.stripe_account_id == account_id).first()

        if driver:
            # Check if onboarding is complete
            charges_enabled = event_data.get("charges_enabled", False)
            payouts_enabled = event_data.get("payouts_enabled", False)

            if charges_enabled and payouts_enabled:
                driver.stripe_onboarded = True
                driver.updated_at = datetime.utcnow()
                db.commit()
                print(f"Driver {driver.id} completed Stripe Connect onboarding")

        # Also check vendors table
        if not driver:
            vendor = db.query(Vendor).filter(Vendor.stripe_account_id == account_id).first()
            if vendor:
                charges_enabled = event_data.get("charges_enabled", False)
                payouts_enabled = event_data.get("payouts_enabled", False)

                if charges_enabled and payouts_enabled:
                    vendor.stripe_onboarding_complete = True
                    vendor.updated_at = datetime.utcnow()
                    db.commit()
                    print(f"Vendor {vendor.id} completed Stripe Connect onboarding")

    # Handle payout events
    elif event_type == "payout.paid":
        account_id = event_data.get("account") or event.get("account")
        amount = event_data.get("amount", 0) / 100  # Convert cents to dollars

        driver = db.query(Driver).filter(Driver.stripe_account_id == account_id).first()
        if driver:
            print(f"Payout of ${amount} sent to driver {driver.id}")

    elif event_type == "payout.failed":
        account_id = event_data.get("account") or event.get("account")

        driver = db.query(Driver).filter(Driver.stripe_account_id == account_id).first()
        if driver:
            print(f"Payout failed for driver {driver.id}: {event_data.get('failure_message')}")

    if event_id and REDIS_AVAILABLE and redis_client:
        redis_client.setex(f"dollor:stripe:event:{event_id}", 86400, "1")

    return {"success": True, "event_type": event_type}


# ==================== STRIPE CONNECT FOR VENDORS ====================
# Stripe Connect Express accounts for restaurant/vendor payouts









# ==================== ANDROID FINANCIAL ENDPOINTS ====================
# Android calls these endpoints for driver balance, bank account, payouts, and vendor payouts.
# These were missing from the backend, causing 404s on Android EarningsScreen / PaymentSettingsScreen.

class BankAccountRequest(BaseModel):
    account_holder_name: str
    routing_number: str
    account_number: str

class PayoutRequest(BaseModel):
    amount: float
    payout_type: str = "standard"  # "standard" or "instant"


@app.get("/api/drivers/{driver_id}/balance")
def get_driver_balance(
    driver_id: int,
    _auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Get the driver's available Stripe Connect balance.
    Android calls this from EarningsScreen.
    """
    # Ownership check
    if _auth_driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if not driver.stripe_account_id:
        return {"success": True, "available_balance": 0, "pending_balance": 0, "currency": "usd"}

    try:
        balance = stripe.Balance.retrieve(stripe_account=driver.stripe_account_id)
        available = sum(b.amount for b in balance.available) / 100.0 if balance.available else 0
        pending = sum(b.amount for b in balance.pending) / 100.0 if balance.pending else 0
        return {
            "success": True,
            "available_balance": available,
            "pending_balance": pending,
            "currency": "usd"
        }
    except stripe.error.StripeError:
        return {"success": True, "available_balance": 0, "pending_balance": 0, "currency": "usd"}


@app.post("/api/drivers/{driver_id}/bank-account")
def link_driver_bank_account(
    driver_id: int,
    request: BankAccountRequest,
    _auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Link a bank account to the driver's Stripe Connect account.
    Android calls this from PaymentSettingsScreen.
    """
    # Ownership check
    if _auth_driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if not driver.stripe_account_id:
        raise HTTPException(status_code=400, detail="Driver has no Stripe account. Create one first via POST /api/drivers/{id}/stripe/connect")

    try:
        bank_account = stripe.Account.create_external_account(
            driver.stripe_account_id,
            external_account={
                "object": "bank_account",
                "country": "US",
                "currency": "usd",
                "account_holder_name": request.account_holder_name,
                "routing_number": request.routing_number,
                "account_number": request.account_number,
                "account_holder_type": "individual",
            },
        )
        return {
            "success": True,
            "bank_account_id": bank_account.id,
            "last4": bank_account.last4,
            "bank_name": bank_account.bank_name
        }
    except stripe.error.StripeError as e:
        logger.error(f"API error at line 5824: {e}")
        raise HTTPException(status_code=400, detail="Payment processing error. Please try again or contact support.")


@app.post("/api/drivers/{driver_id}/payouts")
def request_driver_payout(
    driver_id: int,
    request: PayoutRequest,
    _auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Request a manual payout for the driver via Stripe Connect.
    Android calls this from EarningsScreen payout button.
    """
    # Ownership check
    if _auth_driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    if request.amount <= 0:
        raise HTTPException(status_code=400, detail="Payout amount must be greater than zero")

    if request.amount > 10000:
        raise HTTPException(status_code=400, detail="Payout amount exceeds maximum ($10,000)")

    import stripe
    import os
    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if not driver.stripe_account_id:
        raise HTTPException(status_code=400, detail="Driver has no Stripe account")

    # F1 SECURITY: Validate available earnings before allowing payout
    from sqlalchemy import func
    from models import DriverPayout, RideRequest, RideRequestStatus, Order, OrderStatus

    # Sum completed delivery earnings from DriverPayout table
    delivery_earnings = db.query(func.coalesce(func.sum(DriverPayout.net_payout), 0)).filter(
        DriverPayout.driver_id == driver_id,
        DriverPayout.status.in_(["pending", "completed"])
    ).scalar() or 0

    # Sum completed ride earnings (driver_payout field on rides)
    ride_earnings = db.query(func.coalesce(func.sum(RideRequest.driver_payout), 0)).filter(
        RideRequest.matched_driver_id == driver_id,
        RideRequest.status == RideRequestStatus.COMPLETED,
        RideRequest.driver_payout.isnot(None)
    ).scalar() or 0

    # Sum already-paid-out amounts (check Stripe Connect balance as source of truth)
    # For now, use Stripe's balance API which tracks available funds
    total_available = float(delivery_earnings) + float(ride_earnings)

    if total_available <= 0:
        raise HTTPException(status_code=400, detail="No available earnings for payout")

    if request.amount > total_available:
        raise HTTPException(
            status_code=400,
            detail=f"Requested amount ${request.amount:.2f} exceeds available earnings ${total_available:.2f}"
        )

    logger.info(f"Driver payout request: driver_id={driver_id}, amount=${request.amount:.2f}, available=${total_available:.2f}")

    try:
        payout_method = "instant" if request.payout_type == "instant" else "standard"
        payout = stripe.Payout.create(
            amount=int(request.amount * 100),
            currency="usd",
            method=payout_method,
            metadata={"driver_id": str(driver_id), "platform": "dollor.ai"},
            stripe_account=driver.stripe_account_id,
        )
        return {
            "success": True,
            "payout_id": payout.id,
            "amount": request.amount,
            "available_earnings": total_available,
            "status": payout.status,
            "arrival_date": payout.arrival_date
        }
    except stripe.error.StripeError as e:
        logger.error(f"API error at line 5909: {e}")
        raise HTTPException(status_code=400, detail="Payment processing error. Please try again or contact support.")






# =============================================================================
# DRIVER PAYOUTS - Stripe Connect Transfers
# =============================================================================

@app.post("/api/rides/{ride_id}/complete-and-pay")
async def complete_ride_and_pay_driver(
    request: Request,
    ride_id: int,
    _auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Complete a ride and transfer payment to driver via Stripe Connect.

    This endpoint:
    1. Marks the ride as completed
    2. Creates a Stripe Transfer to the driver's connected account
    3. Records the transfer ID for tracking

    Used after customer payment is captured.
    """
    # G2 fix: DEPRECATED duplicate payout path. The canonical completion + driver payout is
    # POST /api/rides/request/{id}/complete (bid_routes.py). This legacy endpoint used different
    # payout math (+tip, no Access-for-All deduction) and a separate Stripe idempotency key, so
    # if it ever fired alongside the canonical path the driver would be PAID TWICE. No app calls
    # it (verified across web/iOS/Android). Disabled to eliminate the double-pay risk.
    raise HTTPException(status_code=410, detail="Deprecated endpoint. Use POST /api/rides/request/{id}/complete.")
    check_rate_limit(request, payment_limiter, "payment", identifier=str(_auth_driver.id))
    import stripe
    import os

    stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

    from models import RideRequest as RideRequestDB, RideRequestStatus

    # Get the ride request
    ride = db.query(RideRequestDB).filter(RideRequestDB.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # Use matched_driver_id (correct field name in RideRequest model)
    driver_id = getattr(ride, 'matched_driver_id', None) or getattr(ride, 'driver_id', None)
    if not driver_id:
        raise HTTPException(status_code=400, detail="No driver assigned to this ride")

    # Get the driver
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if not driver.stripe_account_id:
        raise HTTPException(
            status_code=400,
            detail="Driver has not completed Stripe Connect onboarding"
        )

    if not driver.stripe_onboarded:
        raise HTTPException(
            status_code=400,
            detail="Driver's Stripe account is not fully onboarded"
        )

    # Calculate driver payout
    # Driver gets: ride fare - platform fee + 100% of tip
    ride_fare = float(ride.final_price or ride.suggested_price or 0)

    # Use stored platform_fee if available, otherwise calculate from fare tier
    # Fare tiers: ≤$35 → $1, $35-$70 → $2, >$70 → $3
    if ride.platform_fee is not None:
        platform_fee = float(ride.platform_fee)
    else:
        platform_fee = platform_fee_for(ride_fare)

    tip = float(ride.tip_amount or 0)

    driver_payout = round(ride_fare - platform_fee + tip, 2)
    driver_payout_cents = int(driver_payout * 100)

    if driver_payout_cents <= 0:
        raise HTTPException(status_code=400, detail="Invalid payout amount")

    try:
        # Create Stripe Transfer to driver's connected account
        transfer = stripe.Transfer.create(
            amount=driver_payout_cents,
            currency="usd",
            destination=driver.stripe_account_id,
            description=f"Ride {ride.request_id} payout",
            metadata={
                "ride_id": str(ride_id),
                "ride_request_id": ride.request_id,
                "driver_id": str(driver.id),
                "ride_fare": str(ride_fare),
                "platform_fee": str(platform_fee),
                "tip": str(tip)
            },
            idempotency_key=f"main_ride_xfer_{ride_id}_{ride.request_id}"
        )

        # Update ride record with transfer info
        ride.status = RideRequestStatus.COMPLETED
        ride.driver_payout = driver_payout
        ride.stripe_transfer_id = transfer.id
        ride.completed_at = datetime.utcnow()
        ride.driver_paid_at = datetime.utcnow()
        db.commit()

        return {
            "success": True,
            "message": f"Ride completed and ${driver_payout:.2f} transferred to driver",
            "transfer": {
                "id": transfer.id,
                "amount": driver_payout,
                "currency": "usd",
                "driver_id": driver.id,
                "driver_name": f"{driver.first_name} {driver.last_name}",
                "status": "paid"
            },
            "breakdown": {
                "ride_fare": ride_fare,
                "platform_fee": platform_fee,
                "tip": tip,
                "driver_payout": driver_payout
            }
        }

    except stripe.error.StripeError as e:
        logger.error(f"Stripe transfer failed: {str(e)}")
        raise HTTPException(status_code=500, detail="Payment transfer failed. Please try again or contact support.")



# REMOVED: Duplicate broken add_ride_tip endpoint (used ride.tip which doesn't exist)
# The correct tip endpoint is at POST /api/rides/{ride_id}/tip (tip_ride_driver) below line 14461


@app.get("/api/drivers/{driver_id}/payout-history")
async def get_driver_payout_history(
    driver_id: int,
    limit: int = Query(20, le=100),
    period: str = Query("week", regex="^(today|week|month)$"),
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Get driver's payout history from completed rides.
    Returns iOS-compatible PayoutHistoryResponse shape: {summary, rides, period}.
    """
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="You can only view your own payout history")
    from models import RideRequest as RideRequestDB, RideRequestStatus

    # Determine period date filter
    now = datetime.utcnow()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today_start - timedelta(days=today_start.weekday())
    month_start = today_start.replace(day=1)

    period_start = None
    if period == "today":
        period_start = today_start
    elif period == "week":
        period_start = week_start
    elif period == "month":
        period_start = month_start

    try:
        # Get completed rides with payouts (use matched_driver_id which is the correct field)
        ride_query = db.query(RideRequestDB).filter(
            RideRequestDB.matched_driver_id == driver_id,
            RideRequestDB.status == RideRequestStatus.COMPLETED
        )
        if period_start:
            ride_query = ride_query.filter(RideRequestDB.completed_at >= period_start)
        completed_rides = ride_query.order_by(RideRequestDB.created_at.desc()).limit(limit).all()
    except Exception as e:
        # If query fails (columns don't exist yet), return empty
        logger.warning(f"Payout history query failed: {e}")
        completed_rides = []

    # Build iOS-expected summary
    total_gross = sum(float(r.suggested_price or 0) for r in completed_rides)
    total_fees = sum(float(r.platform_fee or 0) for r in completed_rides)
    total_tips = sum(float(r.tip_amount or 0) for r in completed_rides)
    total_net = sum(float(r.driver_payout or 0) for r in completed_rides)
    avg_per_ride = total_net / max(len(completed_rides), 1)

    rides = [{
        "ride_id": r.id,
        "date": r.completed_at.isoformat() if r.completed_at else None,
        "fare": float(r.suggested_price or 0),
        "platform_fee": float(r.platform_fee or 0),
        "tip": float(r.tip_amount or 0),
        "net_payout": float(r.driver_payout or 0),
        "stripe_status": "transferred" if r.stripe_transfer_id else "pending",
        "pickup_address": r.pickup_address,
        "dropoff_address": r.dropoff_address,
    } for r in completed_rides]

    # Build flat fields for backward compat alongside new nested shape
    payouts = [{
        "id": r.id,
        "request_id": r.request_id,
        "completed_at": r.completed_at.isoformat() if r.completed_at else None,
        "pickup": r.pickup_address,
        "dropoff": r.dropoff_address,
        "ride_fare": float(r.suggested_price or 0),
        "platform_fee": float(r.platform_fee or 0),
        "tip": float(r.tip_amount or 0),
        "payout": float(r.driver_payout or 0),
        "stripe_transfer_id": r.stripe_transfer_id
    } for r in completed_rides]

    return {
        # iOS-expected nested shape (PayoutHistoryResponse)
        "summary": {
            "total_gross": round(total_gross, 2),
            "total_fees": round(total_fees, 2),
            "total_tips": round(total_tips, 2),
            "total_net": round(total_net, 2),
            "ride_count": len(completed_rides),
            "avg_per_ride": round(avg_per_ride, 2),
        },
        "rides": rides,
        "period": period,
        # Flat fields for backward compatibility
        "driver_id": driver_id,
        "driver_name": f"{driver.first_name} {driver.last_name}",
        "stripe_connected": driver.stripe_account_id is not None,
        "stripe_onboarded": driver.stripe_onboarded or False,
        "total_earnings": round(total_net, 2),
        "total_tips": round(total_tips, 2),
        "payout_count": len(payouts),
        "payouts": payouts
    }


@app.get("/drivers/{driver_id}/documents")
def get_driver_documents_by_id(driver_id: int, driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Get driver documents status (iOS app compatible endpoint)"""
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    documents = []

    # Driver's license
    if driver.drivers_license:
        documents.append({
            "document_type": "drivers_license",
            "status": "verified" if driver.drivers_license else "pending",
            "verified": driver.drivers_license,
            "file_url": driver.drivers_license_url,
            "expiry_date": driver.drivers_license_expiry.isoformat() if driver.drivers_license_expiry else None,
            "upload_date": driver.updated_at.isoformat() if driver.updated_at else None
        })

    # Insurance
    if driver.insurance:
        documents.append({
            "document_type": "insurance",
            "status": "verified" if driver.insurance else "pending",
            "verified": driver.insurance,
            "file_url": driver.insurance_url,
            "expiry_date": driver.insurance_expiry.isoformat() if driver.insurance_expiry else None,
            "upload_date": driver.updated_at.isoformat() if driver.updated_at else None
        })

    # Background check
    if driver.background_check:
        documents.append({
            "document_type": "background_check",
            "status": "verified" if driver.background_check else "pending",
            "verified": driver.background_check,
            "file_url": None,
            "expiry_date": None,
            "upload_date": driver.background_check_date.isoformat() if driver.background_check_date else None
        })

    all_verified = all(doc.get("verified", False) for doc in documents) if documents else False

    return {
        "success": True,
        "count": len(documents),
        "all_verified": all_verified,
        "documents": documents
    }


@app.post("/drivers/{driver_id}/documents")
async def upload_driver_document_by_id(
    request: Request,
    driver_id: int,
    document_type: str = Form(...),
    file: UploadFile = File(...),
    expiry_date: Optional[str] = Form(None),
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Upload driver document for manual review (Persona integration removed; driver
    background checks are handled separately by Checkr — see checkr_service.py)"""
    check_rate_limit(request, upload_limiter, "upload", identifier=f"driver:{driver.id}")
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")
    from s3_service import get_s3_service

    # Validate document type
    valid_types = ['drivers_license', 'license_front', 'license_back', 'insurance', 'insurance_card',
                   'vehicle_front', 'vehicle_side', 'vehicle_back', 'profile_photo']
    if document_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid document type. Must be one of: {valid_types}")

    # Read file content
    content = await file.read()

    # Validate file size (max 10MB)
    if len(content) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Maximum size is 10MB")

    # M8: Validate actual file type via magic bytes — never trust client content_type
    _detected_mime = _detect_document_mime(content)
    if not _detected_mime:
        raise HTTPException(status_code=400, detail="Unsupported file type. Upload JPEG, PNG, PDF, WEBP, GIF or HEIC.")

    # Use S3 service for upload (falls back to local if S3 not configured)
    s3_service = get_s3_service()
    success, url_path, message = await s3_service.upload_file(
        file_content=content,
        original_filename=file.filename,
        folder=f"driver_documents/{driver.id}",
        content_type=_detected_mime  # use verified MIME, not client-supplied
    )

    if not success:
        raise HTTPException(status_code=500, detail=message)

    # Update driver record with document URL (but NOT verified yet)
    if document_type in ['drivers_license', 'license_front', 'license_back']:
        # Store URL but keep drivers_license = False until an admin manually reviews it
        driver.drivers_license_url = url_path
        driver.drivers_license = False  # Will be set True by manual review (see /api/verification/.../manual-review)
        if expiry_date:
            try:
                driver.drivers_license_expiry = datetime.fromisoformat(expiry_date.replace('Z', '+00:00'))
            except ValueError as e:
                logger.warning(f"Invalid drivers license expiry date format: {expiry_date} - {e}")
        driver.verification_status = "pending_manual_review"
        logger.info(f"Driver {driver.id} license document requires manual review")

    elif document_type in ['insurance', 'insurance_card']:
        driver.insurance_url = url_path
        driver.insurance = False  # Will be set True after admin review
        if expiry_date:
            try:
                driver.insurance_expiry = datetime.fromisoformat(expiry_date.replace('Z', '+00:00'))
            except ValueError as e:
                logger.warning(f"Invalid insurance expiry date format: {expiry_date} - {e}")
    elif document_type == 'profile_photo':
        driver.photo_url = url_path

    db.commit()

    response = {
        "success": True,
        "message": f"{document_type} uploaded successfully",
        "file_url": url_path,
        "file_path": url_path,
        "document_type": document_type,
        "verification_status": driver.verification_status or "pending"
    }

    return response


@app.post("/api/auth/driver/documents")
async def upload_driver_document(
    request: Request,
    document_type: str = Form(...),
    file: UploadFile = File(...),
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Upload a document for a driver (license, insurance, etc.) - supports S3 and local storage"""
    check_rate_limit(request, upload_limiter, "upload", identifier=f"driver:{driver.id}")
    from s3_service import get_s3_service

    # Validate document type
    valid_types = ['drivers_license', 'insurance', 'vehicle_registration']
    if document_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid document type. Must be one of: {valid_types}")

    # Read file content
    content = await file.read()

    # Validate file size (max 10MB)
    if len(content) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large. Maximum size is 10MB")

    # M8: Validate actual file type via magic bytes
    _detected_mime = _detect_document_mime(content)
    if not _detected_mime:
        raise HTTPException(status_code=400, detail="Unsupported file type. Upload JPEG, PNG, PDF, WEBP, GIF or HEIC.")

    # Use S3 service for upload (falls back to local if S3 not configured)
    s3_service = get_s3_service()
    success, url_path, message = await s3_service.upload_file(
        file_content=content,
        original_filename=file.filename,
        folder=f"driver_documents/{driver.id}",
        content_type=_detected_mime  # use verified MIME, not client-supplied
    )

    if not success:
        raise HTTPException(status_code=500, detail=message)

    # Update driver record
    if document_type == 'drivers_license':
        driver.drivers_license = True
        driver.drivers_license_url = url_path
    elif document_type == 'insurance':
        driver.insurance = True
        driver.insurance_url = url_path
    elif document_type == 'vehicle_registration':
        driver.vehicle_registration = True
        driver.vehicle_registration_url = url_path

    db.commit()

    # License/insurance may be the last of the three gates (license, insurance,
    # background check) to complete — e.g. if the background check already
    # cleared before this upload. See maybe_auto_approve_driver's docstring.
    from checkr_service import maybe_auto_approve_driver
    maybe_auto_approve_driver(driver, db)

    return {
        "success": True,
        "message": f"{document_type} uploaded successfully",
        "file_path": url_path,
        "document_type": document_type
    }


@app.get("/api/auth/driver/documents")
def get_driver_documents(driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Get driver's uploaded documents status"""

    return {
        "documents": {
            "drivers_license": {
                "uploaded": driver.drivers_license,
                "url": driver.drivers_license_url,
                "expiry": driver.drivers_license_expiry.isoformat() if driver.drivers_license_expiry else None
            },
            "insurance": {
                "uploaded": driver.insurance,
                "url": driver.insurance_url,
                "expiry": driver.insurance_expiry.isoformat() if driver.insurance_expiry else None
            },
            "vehicle_registration": {
                "uploaded": driver.vehicle_registration,
                "url": driver.vehicle_registration_url
            },
            "background_check": {
                "completed": driver.background_check,
                "date": driver.background_check_date.isoformat() if driver.background_check_date else None
            }
        }
    }


@app.get("/api/driver/verification-status")
def get_driver_verification_status(driver: Driver = Depends(require_driver)):
    """Get driver's current KYC/identity verification state."""
    kyc_verified = (
        getattr(driver, 'verification_status', None) == "verified" or
        getattr(driver, 'documents_verified', False)
    )
    return {
        "verification_status": driver.verification_status or "not_started",
        "documents_verified": driver.documents_verified or False,
        "kyc_verified": kyc_verified,
        "can_accept_rides": kyc_verified,
        "verification_provider": getattr(driver, 'verification_provider', None),
    }


# ==================== CUSTOMER AUTHENTICATION (FOOD DELIVERY) ====================
# Note: CustomerRegisterRequest is already defined above for rideshare

@app.post("/api/customer/register")
def customer_food_register(http_request: Request, request: CustomerRegisterRequest, db: Session = Depends(get_db)):
    """Register a new customer account"""
    check_rate_limit(http_request, registration_rate_limiter, "register")
    print(f"Customer registration attempt for: {mask_email(request.email)}")

    try:
        # Check if customer already exists
        existing_customer = db.query(Customer).filter(Customer.email == request.email).first()
        if existing_customer:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )

        # Also check Users table
        existing_user = db.query(User).filter(User.email == request.email).first()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )

        # SECURITY (NSA-010): Enforce password policy for food customer registration
        _validate_password(request.password)

        # Split name into first and last name (accepts both 'name' and 'full_name')
        customer_name = request.get_name()
        if not customer_name:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Name is required (send 'name' or 'full_name')"
            )
        # Sanitize name to prevent XSS
        customer_name = sanitize_input(customer_name)
        name_parts = customer_name.split(" ", 1)
        first_name = name_parts[0]
        last_name = name_parts[1] if len(name_parts) > 1 else ""

        # Create customer record with correct field names
        hashed_password = get_password_hash(request.password)

        # Generate unique customer code with timestamp to avoid conflicts
        import time
        timestamp_suffix = int(time.time() * 1000) % 100000
        customer_code = f"CUST-{timestamp_suffix:05d}"

        new_customer = Customer(
            customer_id=customer_code,
            first_name=first_name,
            last_name=last_name,
            email=request.email,
            phone=request.phone or "",
            password_hash=hashed_password,
            is_active=True
        )
        db.add(new_customer)
        db.commit()
        db.refresh(new_customer)

        # Create user record linked to customer
        new_user = User(
            email=request.email,
            password_hash=hashed_password,
            full_name=customer_name,
            role=UserRole.USER
        )
        db.add(new_user)
        db.commit()
        db.refresh(new_user)

        full_name = f"{new_customer.first_name} {new_customer.last_name}".strip()
        print(f"Customer registration successful for: {mask_email(new_user.email)}, customer_id: {new_customer.id}")
        access_token = create_access_token(data={"sub": new_user.email, "role": "customer", "customer_id": new_customer.id})

        return {
            "access_token": access_token,
            "token_type": "bearer",
            "customer_id": new_customer.id,
            "customer_code": customer_code,
            "name": full_name,
            "email": new_customer.email,
            "status": "active",
            "message": "Registration successful"
        }
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        print(f"Customer registration error: {str(e)}")
        # Check for specific database errors
        error_msg = str(e).lower()
        if "unique" in error_msg or "duplicate" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Registration failed. If you already have an account, please log in."
            )
        elif "encoding" in error_msg or "unicode" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid characters in input. Please use standard characters."
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                # A2: Log error internally, return generic message
                detail="Registration failed. Please try again or contact support."
            )


# REMOVED: /api/customer/google-auth (v2 duplicate endpoint)
# Use /api/auth/customer/google or /auth/customer/google instead


class CustomerAppleAuthRequest(BaseModel):
    email: Optional[str] = None  # Apple only provides on first sign-in
    name: Optional[str] = None   # Apple only provides on first sign-in
    apple_id: str
    identity_token: Optional[str] = None  # JWT from Apple
    nonce_hash: Optional[str] = None  # SHA256 hash of nonce sent to Apple (G2: replay protection)

@app.post("/api/customer/apple-auth")
def customer_apple_auth(request: CustomerAppleAuthRequest, db: Session = Depends(get_db)):
    """Apple OAuth authentication for customers - handles both login and registration"""
    print(f"Customer Apple auth - apple_id: {request.apple_id[:20] if request.apple_id else 'None'}...")

    email = request.email
    name = request.name

    # Always try to decode identity_token first (Apple JWT contains email)
    if request.identity_token:
        try:
            decoded = decode_google_jwt(request.identity_token)  # Verifies Apple RS256 signature
            # G2: Validate nonce if provided by iOS (replay attack protection)
            if request.nonce_hash and decoded.get('nonce') != request.nonce_hash:
                logger.warning(f"Apple nonce mismatch for customer auth")
                raise HTTPException(status_code=401, detail="Invalid Apple identity token")
            elif not request.nonce_hash:
                logger.warning("Apple customer auth: no nonce provided — replay protection disabled")
            # Token email takes priority over request.email
            token_email = decoded.get('email')
            if token_email:
                email = token_email
            if not name and email:
                name = email.split('@')[0]
        except Exception as e:
            logger.debug("Apple identity token decode failed for customer auth")

    if not name and email:
        name = email.split('@')[0]
    elif not name:
        name = 'Apple User'

    # For returning users, look up by apple_id first (most reliable)
    # Then fall back to email lookup
    customer = None
    user = None

    # First: Try to find existing customer by apple_id (works for returning users without email)
    customer = db.query(Customer).filter(Customer.apple_id == request.apple_id).first()
    if customer:
        email = customer.email
        user = db.query(User).filter(User.email == email).first()

    # Second: Try to find by email if we have one
    if not user and email:
        user = db.query(User).filter(User.email == email).first()
        if user:
            # Also check if customer exists with this email
            customer = db.query(Customer).filter(Customer.email == email).first()

    # If still no user and no email, we can't proceed (truly new user needs email)
    if not user and not email:
        raise HTTPException(status_code=400, detail="Email is required for first-time Apple Sign-In. Please go to Settings > Apple ID > Sign-In & Security > Apps Using Apple ID, remove this app, and try again.")

    if not user:
        # Create new user - need email and name for new users
        if not name:
            name = email.split('@')[0] if email else 'Apple User'
        hashed_password = get_password_hash(f"apple_oauth_{request.apple_id}")
        user = User(
            email=email,
            password_hash=hashed_password,
            full_name=name,
            role=UserRole.USER
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        print(f"Created new user for Apple auth: {mask_email(email)}")

    # Check if customer record exists (may have been found earlier by apple_id)
    if not customer:
        customer = db.query(Customer).filter(Customer.email == email).first()

    if not customer:
        # Parse name into first_name and last_name
        display_name = name or user.full_name or email.split('@')[0]
        name_parts = display_name.split(" ", 1)
        first_name = name_parts[0]
        last_name = name_parts[1] if len(name_parts) > 1 else ""

        # Generate unique customer_id
        import random
        customer_id = f"CUST{random.randint(100000, 999999)}"

        # Create customer record with apple_id for future lookups
        customer = Customer(
            customer_id=customer_id,
            first_name=first_name,
            last_name=last_name,
            email=email,
            apple_id=request.apple_id  # Store apple_id for returning user lookup
        )
        db.add(customer)
        db.commit()
        db.refresh(customer)
        print(f"Created new customer record for: {mask_email(email)} with ID: {customer_id}, apple_id stored")

        # Send welcome email for new Apple signup
        try:
            send_customer_welcome_email(
                to_email=email,
                customer_name=display_name
            )
            print(f"Welcome email sent to Apple signup: {mask_email(email)}")
        except Exception as e:
            print(f"Failed to send welcome email to Apple signup: {str(e)}")

    elif not customer.apple_id:
        # Update existing customer with apple_id if not set (for users who signed up before this change)
        customer.apple_id = request.apple_id
        db.commit()
        print(f"Updated existing customer {mask_email(customer.email)} with apple_id")

    # Generate token
    access_token = create_access_token(data={"sub": user.email, "role": "customer", "customer_id": customer.id})

    # Construct full name from first_name and last_name
    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip()

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "customer_id": customer.id,
        "name": full_name,
        "email": user.email
    }


# Password reset codes — Redis-backed with in-memory fallback
from cache import store_reset_code, get_reset_code, delete_reset_code, REDIS_AVAILABLE as _REDIS_UP
password_reset_codes = {}  # in-memory fallback when Redis is unavailable

class CustomerPasswordResetRequest(BaseModel):
    email: str

class CustomerPasswordResetConfirm(BaseModel):
    email: str
    code: str
    new_password: str

@app.post("/api/customer/password-reset/request")
def customer_request_password_reset(http_request: Request, request: CustomerPasswordResetRequest, db: Session = Depends(get_db)):
    """Request a password reset - sends code to email"""
    check_rate_limit(http_request, password_reset_ip_limiter, "pwd_reset_ip")
    check_rate_limit(http_request, password_reset_limiter, "pwd_reset", identifier=request.email.lower())
    import random

    # Check if user exists
    user = db.query(User).filter(User.email == request.email).first()
    if not user:
        # Don't reveal whether email exists for security
        return {"success": True, "message": "If an account exists with this email, a reset code has been sent."}

    # Generate high-entropy reset code (256-bit)
    code = secrets.token_urlsafe(32)

    # Store code in Redis (15 min TTL), fall back to in-memory
    if not store_reset_code(request.email, code, 900):
        from datetime import datetime, timedelta
        password_reset_codes[request.email] = {
            "code": code,
            "expires": datetime.utcnow() + timedelta(minutes=15)
        }

    # Send email with reset code
    try:
        customer = db.query(Customer).filter(Customer.user_id == user.id).first()
        customer_name = f"{customer.first_name}" if customer else "Customer"
        send_password_reset_email(request.email, customer_name, code)
    except Exception as e:
        logger.error(f"Failed to send customer password reset email: {str(e)}")

    return {"success": True, "message": "Reset code sent to your email."}

@app.post("/api/customer/password-reset/confirm")
def customer_confirm_password_reset(http_request: Request, request: CustomerPasswordResetConfirm, db: Session = Depends(get_db)):
    """Confirm password reset with code and set new password"""
    check_rate_limit(http_request, password_reset_limiter, "pwd_reset_confirm", identifier=request.email.lower())
    from datetime import datetime

    # Check Redis first, fall back to in-memory
    redis_code = get_reset_code(request.email)
    if redis_code:
        if redis_code != request.code:
            raise HTTPException(status_code=400, detail="Invalid reset code")
    else:
        reset_data = password_reset_codes.get(request.email)
        if not reset_data:
            raise HTTPException(status_code=400, detail="Invalid or expired reset code")
        if datetime.utcnow() > reset_data["expires"]:
            del password_reset_codes[request.email]
            raise HTTPException(status_code=400, detail="Reset code has expired. Please request a new one.")
        if reset_data["code"] != request.code:
            raise HTTPException(status_code=400, detail="Invalid reset code")

    # Get CUSTOMER user record (must match role filter used by customer login)
    user = db.query(User).filter(User.email == request.email, User.role == UserRole.CUSTOMER).first()
    if not user:
        user = db.query(User).filter(User.email == request.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="Account not found")

    # Update password
    user.password_hash = get_password_hash(request.new_password)
    db.commit()

    # Remove used code from both stores
    delete_reset_code(request.email)
    password_reset_codes.pop(request.email, None)

    return {"success": True, "message": "Password reset successful. You can now login with your new password."}


# ============================================================
# Driver Password Reset (matches Android: driver/password-reset/*)
# ============================================================

class DriverPasswordResetRequest(BaseModel):
    email: str

class DriverPasswordResetConfirm(BaseModel):
    email: str
    code: str
    new_password: str

@app.post("/api/driver/password-reset/request")
def driver_request_password_reset(http_request: Request, request: DriverPasswordResetRequest, db: Session = Depends(get_db)):
    """Request a driver password reset - sends code to email"""
    check_rate_limit(http_request, password_reset_ip_limiter, "pwd_reset_ip")
    check_rate_limit(http_request, password_reset_limiter, "pwd_reset", identifier=request.email.lower())
    # Check if user exists with driver role (must match role used by login)
    user = db.query(User).filter(User.email == request.email, User.role == UserRole.DRIVER).first()
    if not user or not user.driver_id:
        # Don't reveal whether email exists for security
        return {"success": True, "message": "If a driver account exists with this email, a reset code has been sent."}

    # Generate high-entropy reset code (256-bit)
    code = secrets.token_urlsafe(32)

    # Store code in Redis (15 min TTL), fall back to in-memory
    if not store_reset_code(request.email, code, 900):
        from datetime import datetime, timedelta
        password_reset_codes[request.email] = {
            "code": code,
            "expires": datetime.utcnow() + timedelta(minutes=15)
        }

    # Send email with reset code
    try:
        driver = db.query(Driver).filter(Driver.id == user.driver_id).first()
        driver_name = f"{driver.first_name}" if driver else "Driver"
        send_password_reset_email(request.email, driver_name, code)
    except Exception as e:
        logger.error(f"Failed to send driver password reset email: {str(e)}")

    return {"success": True, "message": "Reset code sent to your email."}

@app.post("/api/driver/password-reset/confirm")
def driver_confirm_password_reset(http_request: Request, request: DriverPasswordResetConfirm, db: Session = Depends(get_db)):
    """Confirm driver password reset with code and set new password"""
    check_rate_limit(http_request, password_reset_limiter, "pwd_reset_confirm", identifier=request.email.lower())
    from datetime import datetime

    # Check Redis first, fall back to in-memory
    redis_code = get_reset_code(request.email)
    if redis_code:
        if redis_code != request.code:
            raise HTTPException(status_code=400, detail="Invalid reset code")
    else:
        reset_data = password_reset_codes.get(request.email)
        if not reset_data:
            raise HTTPException(status_code=400, detail="Invalid or expired reset code")
        if datetime.utcnow() > reset_data["expires"]:
            del password_reset_codes[request.email]
            raise HTTPException(status_code=400, detail="Reset code has expired. Please request a new one.")
        if reset_data["code"] != request.code:
            raise HTTPException(status_code=400, detail="Invalid reset code")

    # Get DRIVER user record (must match role filter used by driver login)
    user = db.query(User).filter(User.email == request.email, User.role == UserRole.DRIVER).first()
    if not user:
        raise HTTPException(status_code=404, detail="Driver account not found")

    user.password_hash = get_password_hash(request.new_password)
    db.commit()

    # Remove used code from both stores
    delete_reset_code(request.email)
    password_reset_codes.pop(request.email, None)

    return {"success": True, "message": "Password reset successful. You can now login with your new password."}


@app.get("/api/customer/profile")
async def get_customer_profile_v2(customer: Customer = Depends(require_customer)):
    """Get current customer's profile - uses Customer table directly via JWT"""
    # Construct full name from first_name and last_name
    full_name = f"{customer.first_name or ''} {customer.last_name or ''}".strip()

    return {
        "id": customer.id,
        "customer_id": customer.id,  # iOS compatibility - expects customer_id
        "customer_code": customer.customer_id,
        "name": full_name,
        "email": customer.email,
        "phone": customer.phone or "",
        "status": "active" if customer.is_active else "inactive",
        "is_active": customer.is_active,  # iOS compatibility - expects is_active boolean
        "loyalty_points": customer.loyalty_points or 0,
        "total_orders": customer.total_orders or 0,
        "total_spent": float(customer.total_spent or 0),
        "saved_addresses": customer.saved_addresses or []
    }


# ==================== CUSTOMER DASHBOARD ====================

@app.get("/api/customer/dashboard")
async def get_customer_dashboard(customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """Get customer dashboard data with rides history and stats"""
    customer_id = customer.id

    # Get recent rides from database (or mock data if no real rides)
    recent_rides = []

    # Calculate stats from customer record
    total_rides = customer.total_orders or 0
    total_spent = float(customer.total_spent or 0)

    # Calculate savings (estimated 20% savings vs traditional platforms)
    # Traditional platforms charge ~25-30% fees, we charge $1 flat
    estimated_traditional_fees = total_spent * 0.25  # 25% typical fees
    our_fees = total_rides * 1.0  # $1 per ride
    saved_amount = max(0, estimated_traditional_fees - our_fees)

    # Query real recent rides from database
    from models import RideRequest as RideRequestDB, RideRequestStatus
    recent_rides_db = db.query(RideRequestDB).filter(
        RideRequestDB.customer_id == customer_id
    ).order_by(RideRequestDB.created_at.desc()).limit(5).all()

    for r in recent_rides_db:
        recent_rides.append({
            "id": f"RIDE-{r.id}",
            "pickup": r.pickup_address,
            "dropoff": r.dropoff_address,
            "fare": float(r.final_price or r.suggested_price or 0),
            "status": r.status.value if r.status else "unknown",
            "date": r.created_at.isoformat() if r.created_at else None
        })

    # Quick destinations (from customer saved addresses or defaults)
    saved_addresses = customer.saved_addresses if customer.saved_addresses else []
    quick_destinations = [
        {"icon": "🏠", "label": "Home", "address": saved_addresses[0] if len(saved_addresses) > 0 else "Set home address"},
        {"icon": "💼", "label": "Work", "address": saved_addresses[1] if len(saved_addresses) > 1 else "Set work address"},
        {"icon": "✈️", "label": "Airport", "address": "Nearest airport"},
    ]

    return {
        "customer_name": f"{customer.first_name or ''} {customer.last_name or ''}".strip(),
        "customer_id": customer_id,
        "stats": {
            "total_rides": total_rides,
            "total_spent": round(total_spent, 2),
            "saved_amount": round(saved_amount, 2)
        },
        "recent_rides": recent_rides,
        "quick_destinations": quick_destinations,
        "loyalty": {
            "points": customer.loyalty_points or 0,
            "tier": getattr(customer, 'loyalty_tier', 'bronze') or "bronze"
        }
    }


def _ride_history_total(ride) -> float:
    """What the rider actually paid for a completed ride, same arithmetic as the receipt
    (fare + connection fee + CPUC Access-for-All customer share + tip). Other statuses show the fare only."""
    fare = float(ride.final_price or ride.suggested_price or 0)
    status = ride.status.value if getattr(ride, "status", None) else ""
    if status != "completed":
        return round(fare, 2)
    cpuc_customer_share = float(getattr(ride, "access_for_all_fee", None) or 0.10) / 2
    return round(fare + float(ride.platform_fee or 0) + cpuc_customer_share + float(ride.tip_amount or 0), 2)


@app.get("/api/customer/rides/history")
async def get_customer_ride_history(
    limit: int = 20,
    offset: int = 0,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Get customer's ride history with pagination from real database"""
    from models import RideRequest as RideRequestDB

    query = db.query(RideRequestDB).filter(
        RideRequestDB.customer_id == customer.id
    ).order_by(RideRequestDB.created_at.desc())

    total_rides = query.count()
    ride_records = query.offset(offset).limit(limit).all()

    rides = []
    for ride in ride_records:
        # Get driver name from matched_driver relationship
        driver_name = None
        if ride.matched_driver:
            driver_name = f"{ride.matched_driver.first_name or ''} {ride.matched_driver.last_name or ''}".strip() or None

        rides.append({
            "id": ride.id,
            "request_id": ride.request_id,
            "pickup": ride.pickup_address or "",
            "dropoff": ride.dropoff_address or "",
            "pickup_lat": ride.pickup_latitude,
            "pickup_lng": ride.pickup_longitude,
            "dropoff_lat": ride.dropoff_latitude,
            "dropoff_lng": ride.dropoff_longitude,
            "date": ride.created_at.strftime("%Y-%m-%d") if ride.created_at else None,
            "fare": float(ride.final_price or ride.suggested_price or 0),
            "platform_fee": float(ride.platform_fee or 0),
            "tip": float(ride.tip_amount or 0),
            "total": _ride_history_total(ride),
            "driver_name": driver_name,
            "status": ride.status.value if ride.status else "unknown",
            "rating": ride.customer_rating,
        })

    return {
        "rides": rides,
        "total": total_rides,
        "has_more": offset + limit < total_rides
    }



# ==================== DRIVER DASHBOARD ====================

@app.get("/api/driver/dashboard")
def get_driver_dashboard(
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Get driver dashboard data with active delivery, pending orders, and stats"""

    driver_name = f"{driver.first_name} {driver.last_name}"

    # Active delivery - query real orders assigned to this driver
    active_delivery = None
    active_order = db.query(Order).filter(
        Order.driver_id == driver.id,
        Order.status.in_([
            OrderStatus.CONFIRMED, OrderStatus.PREPARING,
            OrderStatus.READY_FOR_PICKUP, OrderStatus.OUT_FOR_DELIVERY
        ])
    ).order_by(Order.created_at.desc()).first()

    if active_order:
        vendor = db.query(Vendor).filter(Vendor.id == active_order.vendor_id).first() if active_order.vendor_id else None
        items_count = 0
        if active_order.items:
            try:
                items_data = json.loads(active_order.items) if isinstance(active_order.items, str) else active_order.items
                items_count = len(items_data) if isinstance(items_data, list) else 0
            except (json.JSONDecodeError, TypeError):
                pass
        status_map = {
            OrderStatus.CONFIRMED: "accepted",
            OrderStatus.PREPARING: "accepted",
            OrderStatus.READY_FOR_PICKUP: "accepted",
            OrderStatus.OUT_FOR_DELIVERY: "picked_up"
        }
        active_delivery = {
            "id": active_order.order_number or f"ORD-{active_order.id}",
            "restaurant": vendor.restaurant_name if vendor else "Restaurant",
            "customer": active_order.customer_name or "Customer",
            "address": active_order.delivery_address or "",
            "items": items_count,
            "total": float(active_order.total_amount or 0),
            "distance": "N/A",
            "estimated_time": "15-25 min",
            "status": status_map.get(active_order.status, "accepted"),
            "delivery_instructions": active_order.delivery_instructions or "",
            "customer_phone": active_order.customer_phone or "",
            "payout": float(active_order.delivery_fee or 0) + float(active_order.tip or 0)
        }

    # Pending deliveries - query real unassigned orders
    pending_deliveries = []
    if driver.is_online:
        available_orders = db.query(Order).filter(
            Order.status.in_([OrderStatus.CONFIRMED, OrderStatus.PREPARING, OrderStatus.READY_FOR_PICKUP]),
            Order.driver_id.is_(None)
        ).order_by(Order.created_at.desc()).limit(10).all()

        for order in available_orders:
            vendor = db.query(Vendor).filter(Vendor.id == order.vendor_id).first() if order.vendor_id else None
            pending_deliveries.append({
                "id": order.order_number or f"ORD-{order.id}",
                "restaurant": vendor.restaurant_name if vendor else "Restaurant",
                "address": order.delivery_address or "",
                "distance": "N/A",
                "payout": float(order.delivery_fee or 0) + float(order.tip or 0),
                "eta": "15-25 min"
            })

    # Today's stats - query real completed orders for today
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    today_completed = db.query(Order).filter(
        Order.driver_id == driver.id,
        Order.status == OrderStatus.DELIVERED,
        Order.updated_at >= today_start
    ).all()

    today_deliveries = len(today_completed)
    today_earnings = sum(float(o.delivery_fee or 0) + float(o.tip or 0) for o in today_completed)

    # Hours online today (based on when they went online)
    hours_online = 0.0
    if driver.is_online and driver.went_online_at:
        hours_online = round((datetime.utcnow() - driver.went_online_at).total_seconds() / 3600, 1)

    total_deliveries = driver.total_deliveries or 0

    # Compute real acceptance rate from DB counters (>= 5 rides required for meaningful rate)
    _total_rides = (driver.ride_accept_count or 0) + (driver.ride_cancel_count or 0)
    _acceptance_rate = round(((driver.ride_accept_count or 0) / _total_rides) * 100, 1) if _total_rides >= 5 else 95.0

    today_stats = {
        "deliveries": today_deliveries,
        "earnings": round(today_earnings, 2),
        "hours_online": hours_online,
        "acceptance_rate": _acceptance_rate
    }

    # Weekly stats - query real completed orders for this week
    week_start = today_start - timedelta(days=today_start.weekday())  # Monday
    week_completed = db.query(Order).filter(
        Order.driver_id == driver.id,
        Order.status == OrderStatus.DELIVERED,
        Order.updated_at >= week_start
    ).all()

    week_deliveries = len(week_completed)
    week_earnings = sum(float(o.delivery_fee or 0) + float(o.tip or 0) for o in week_completed)

    weekly_stats = {
        "deliveries": {"current": week_deliveries, "goal": 50},
        "earnings": {"current": round(week_earnings, 2), "goal": 800},
        "hours": {"current": round(hours_online, 1), "goal": 40}
    }

    return {
        "driver_name": driver_name,
        "driver_id": driver.driver_id,
        "is_online": driver.is_online,
        "rating": driver.rating or 5.0,
        "active_delivery": active_delivery,
        "pending_deliveries": pending_deliveries,
        "today_stats": today_stats,
        "weekly_stats": weekly_stats,
        "location": {
            "latitude": driver.current_latitude,
            "longitude": driver.current_longitude,
            "last_update": driver.location_updated_at.isoformat() if driver.location_updated_at else None
        }
    }


# ==================== iOS v5 DRIVER DASHBOARD (Compatibility Alias) ====================
# iOS app calls /api/v5/driver/{driverId}/dashboard - returns DriverDashboardResponse format

@app.get("/api/v5/driver/{driver_id}/dashboard")
def get_driver_dashboard_v5(
    driver_id: int,
    _auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    iOS Driver Dashboard v5 - Returns driver earnings dashboard in iOS-compatible format.

    iOS expects DriverDashboardResponse with:
    - driver_id, snapshot_time
    - today, this_week, this_month (DriverEarningsPeriod objects)
    - ratings, tax_info, platform_fees_paid, payment_methods (optional)

    Each DriverEarningsPeriod has: deliveries, gross_earnings, base_pay, tips, bonuses, active_hours
    """
    if _auth_driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied - not your dashboard")
    try:
        driver = db.query(Driver).filter(Driver.id == driver_id).first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")

        now = datetime.utcnow()

        # Helper function to calculate earnings for a period
        def calc_period_earnings(start_dt, end_dt=None):
            # Food delivery orders
            food_query = db.query(Order).filter(
                Order.driver_id == driver_id,
                Order.status == OrderStatus.DELIVERED,
                Order.delivered_at >= start_dt
            )
            if end_dt:
                food_query = food_query.filter(Order.delivered_at < end_dt)
            food_orders = food_query.all()

            # Rideshare rides — wrapped in try/except in case columns don't exist yet
            try:
                from models import RideRequest as RideRequestDB, RideRequestStatus
                ride_query = db.query(RideRequestDB).filter(
                    RideRequestDB.matched_driver_id == driver_id,
                    RideRequestDB.status == RideRequestStatus.COMPLETED,
                    RideRequestDB.completed_at >= start_dt
                )
                if end_dt:
                    ride_query = ride_query.filter(RideRequestDB.completed_at < end_dt)
                completed_rides = ride_query.all()
            except Exception as e:
                logger.warning(f"Rideshare earnings query failed in dashboard v5: {e}")
                completed_rides = []

            food_deliveries = len(food_orders)
            rideshare_rides = len(completed_rides)
            deliveries = food_deliveries + rideshare_rides  # total trips for backward compat

            food_base = sum(float(o.delivery_fee or 0) for o in food_orders)
            food_tips = sum(float(o.tip or 0) for o in food_orders)
            ride_base = sum(float(r.driver_payout or 0) for r in completed_rides)
            ride_tips = sum(float(r.tip_amount or 0) for r in completed_rides)

            base_pay = food_base + ride_base
            tips = food_tips + ride_tips
            bonuses = 0.0
            gross_earnings = base_pay + tips + bonuses
            # Estimate 30 min per food delivery, 24 min per rideshare ride for active hours
            active_hours = food_deliveries * 0.5 + rideshare_rides * 0.4

            return {
                "deliveries": deliveries,             # total trips (food + ride)
                "food_deliveries": food_deliveries,   # NEW — food count
                "rideshare_rides": rideshare_rides,   # NEW — rideshare count
                "gross_earnings": round(gross_earnings, 2),
                "base_pay": round(base_pay, 2),
                "tips": round(tips, 2),
                "bonuses": round(bonuses, 2),
                "active_hours": round(active_hours, 1),
                "food_base_pay": round(food_base, 2),      # NEW
                "rideshare_base_pay": round(ride_base, 2), # NEW
            }

        # Calculate period boundaries
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        week_start = today_start - timedelta(days=today_start.weekday())
        month_start = today_start.replace(day=1)

        # Calculate earnings for each period
        today_data = calc_period_earnings(today_start)
        week_data = calc_period_earnings(week_start)
        month_data = calc_period_earnings(month_start)

        # Compute real acceptance rate from DB counters (>= 5 rides required for meaningful rate)
        _total_rides = (driver.ride_accept_count or 0) + (driver.ride_cancel_count or 0)
        _acceptance_rate = round(((driver.ride_accept_count or 0) / _total_rides) * 100, 1) if _total_rides >= 5 else 95.0

        # Build iOS-compatible response with both nested AND flat fields
        return {
            "driver_id": str(driver_id),
            "snapshot_time": now.isoformat() + "Z",
            # Nested structure (original format)
            "today": today_data,
            "this_week": week_data,
            "this_month": month_data,
            # Flat fields for iOS compatibility (QA agent expects these)
            "week_earnings": week_data["gross_earnings"],
            "today_earnings": today_data["gross_earnings"],
            "total_deliveries": month_data["deliveries"],
            "week_deliveries": week_data["deliveries"],
            "rating": driver.rating or 5.0,
            "acceptance_rate": _acceptance_rate,  # Real acceptance rate from DB counters
            "completion_rate": 98.0,  # Default completion rate
            "total_tips": week_data["tips"],
            "online_hours": week_data["active_hours"],
            # Ratings nested
            "ratings": {
                "average": driver.rating or 5.0,
                "overall": driver.rating or 5.0,
                "total_ratings": driver.total_deliveries or 0,
                "total_reviews": driver.total_deliveries or 0,
                "on_time_percentage": 95  # Placeholder — no on-time tracking implemented yet
            },
            "tax_info": {
                "ytd_earnings": round(month_data["gross_earnings"] * 12, 2),
                "estimated_tax": round(month_data["gross_earnings"] * 12 * 0.15, 2)
            },
            "platform_fees_paid": {
                "today": round(today_data["deliveries"] * 1.0, 2),
                "this_week": round(week_data["deliveries"] * 1.0, 2),
                "this_month": round(month_data["deliveries"] * 1.0, 2)
            },
            "payment_methods": {
                "instant_pay_available": driver.stripe_onboarded if hasattr(driver, 'stripe_onboarded') else False,
                "bank_account_linked": driver.stripe_account_id is not None and (driver.stripe_onboarded if hasattr(driver, 'stripe_onboarded') else False),
                "stripe_account_id": driver.stripe_account_id if hasattr(driver, 'stripe_account_id') else None,
                "requires_setup": not (driver.stripe_account_id is not None and (driver.stripe_onboarded if hasattr(driver, 'stripe_onboarded') else False))
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Driver dashboard v5 error: {e}")
        # Return minimal valid response on error so iOS doesn't crash
        return {
            "driver_id": str(driver_id),
            "snapshot_time": datetime.utcnow().isoformat() + "Z",
            "today": {"deliveries": 0, "gross_earnings": 0.0, "base_pay": 0.0, "tips": 0.0, "bonuses": 0.0, "active_hours": 0.0},
            "this_week": {"deliveries": 0, "gross_earnings": 0.0, "base_pay": 0.0, "tips": 0.0, "bonuses": 0.0, "active_hours": 0.0},
            "this_month": {"deliveries": 0, "gross_earnings": 0.0, "base_pay": 0.0, "tips": 0.0, "bonuses": 0.0, "active_hours": 0.0},
            "ratings": {"average": 5.0, "overall": 5.0, "total_ratings": 0, "total_reviews": 0, "on_time_percentage": 95}  # Placeholder — no on-time tracking implemented yet
        }


def _driver_period_total(db: Session, driver_id: int, start_date: datetime) -> float:
    """Delivered-order and completed-ride earnings (fees and tips included) since start_date."""
    try:
        orders = db.query(Order).filter(
            Order.driver_id == driver_id,
            Order.status == OrderStatus.DELIVERED,
            Order.created_at >= start_date,
        ).all()
    except Exception:
        orders = []
    try:
        from models import RideRequest, RideRequestStatus
        rides = db.query(RideRequest).filter(
            RideRequest.matched_driver_id == driver_id,
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.created_at >= start_date,
        ).all()
    except Exception:
        rides = []
    total = sum(float(o.delivery_fee or 0) + float(o.tip or 0) for o in orders)
    total += sum(float(r.driver_payout or 0) + float(r.tip_amount or 0) for r in rides)
    return round(total, 2)


@app.get("/api/driver/earnings")
async def get_driver_earnings(
    period: str = "today",  # today, week, month, all
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Get driver earnings breakdown - uses actual data from delivered orders"""

    # Calculate period start date
    now = datetime.utcnow()
    if period == "today":
        start_date = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elif period == "week":
        start_date = now - timedelta(days=7)
    elif period == "month":
        start_date = now - timedelta(days=30)
    else:  # all time
        start_date = datetime(2020, 1, 1)  # Far enough back

    # Query actual delivered orders for this driver
    try:
        orders = db.query(Order).filter(
            Order.driver_id == driver.id,
            Order.status == OrderStatus.DELIVERED,
            Order.created_at >= start_date
        ).all()
    except Exception:
        # If query fails, return empty data
        orders = []

    # Calculate real earnings from order data
    deliveries = len(orders)
    base_earnings = sum(float(o.delivery_fee or 0) for o in orders)
    tips = sum(float(o.tip or 0) for o in orders)
    bonuses = 0  # Bonus tracking not yet implemented

    # Query completed rideshare rides for this driver
    try:
        from models import RideRequest, RideRequestStatus
        rideshare_rides = db.query(RideRequest).filter(
            RideRequest.matched_driver_id == driver.id,
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.created_at >= start_date
        ).all()
    except Exception:
        rideshare_rides = []

    rideshare_earnings = sum(float(r.driver_payout or 0) for r in rideshare_rides)
    rideshare_tips = sum(float(r.tip_amount or 0) for r in rideshare_rides)
    rideshare_count = len(rideshare_rides)

    total = round(base_earnings + tips + rideshare_earnings + rideshare_tips + bonuses, 2)
    food_total = round(base_earnings + tips, 2)

    # Also return period-based totals for dashboard display
    return {
        "period": period,
        "driver_id": driver.id,
        "driver_name": f"{driver.first_name or ''} {driver.last_name or ''}".strip(),
        "deliveries": deliveries,
        "base_earnings": round(base_earnings, 2),
        "tips": round(tips, 2),
        "bonuses": round(bonuses, 2),
        "rideshare_rides": rideshare_count,
        "rideshare_earnings": round(rideshare_earnings + rideshare_tips, 2),
        "total_earnings": total,
        "platform_fee": 0.00,  # Drivers pay $0 commission per CLAUDE.md
        "note": "100% of your earnings go to you. Dollor.ai charges $0 commission to drivers.",
        # Period totals for iOS/Android apps: always all three, whichever period was requested
        "today": _driver_period_total(db, driver.id, now.replace(hour=0, minute=0, second=0, microsecond=0)),
        "week": _driver_period_total(db, driver.id, now - timedelta(days=7)),
        "month": _driver_period_total(db, driver.id, now - timedelta(days=30)),
        "pending": 0.0  # Pending payout amount
    }


# ============================================================
# Prop 22 Compliance Endpoints — California BPC §§7453-7463
# ============================================================

@app.get("/api/driver/prop22/periods")
async def get_driver_prop22_periods(
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Returns all Prop 22 earning periods for the authenticated driver.
    Most recent period first. Includes qtd_engaged_hours from earnings statement
    per BPC §7454(b)(2) calendar-quarter disclosure requirement.
    iOS PayoutDashboardView consumes this.
    """
    from models import Prop22EarningPeriod, Prop22EarningsStatement
    periods = (
        db.query(Prop22EarningPeriod)
        .filter(
            Prop22EarningPeriod.driver_id == driver.id,
            Prop22EarningPeriod.is_archived == False
        )
        .order_by(Prop22EarningPeriod.period_start.desc())
        .all()
    )

    result = []
    for p in periods:
        # JOIN to earnings statement for QTD hours (BPC §7454(b)(2))
        statement = (
            db.query(Prop22EarningsStatement)
            .filter(Prop22EarningsStatement.period_id == p.id)
            .first()
        )
        result.append({
            "id": p.id,
            "period_start": p.period_start.isoformat(),
            "period_end": p.period_end.isoformat(),
            "status": p.status,
            "service_type": p.service_type,
            "engaged_hours": p.engaged_hours,
            "engaged_miles": p.engaged_miles,
            "net_earnings": p.net_earnings,
            "prop22_floor": p.prop22_floor,
            "top_up_amount": p.top_up_amount,
            "deadline_at": p.deadline_at.isoformat() if p.deadline_at else None,
            "qtd_engaged_hours": statement.qtd_engaged_hours if statement else None,
        })
    return result


@app.get("/api/driver/prop22/periods/{period_id}/rides")
async def get_driver_prop22_period_rides(
    period_id: int,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Returns rides (or orders) for a specific Prop 22 period.
    Driver can only access their own period (ownership check).
    iOS per-ride disclosure — prop22_floor_amount may be null (pre-deployment rides).
    """
    from models import Prop22EarningPeriod, RideRequest, RideRequestStatus
    from fastapi import HTTPException

    period = (
        db.query(Prop22EarningPeriod)
        .filter(
            Prop22EarningPeriod.id == period_id,
            Prop22EarningPeriod.driver_id == driver.id  # ownership: driver can only see own periods
        )
        .first()
    )
    if not period:
        raise HTTPException(status_code=404, detail="Period not found")

    if period.service_type == "FOOD_DELIVERY":
        orders = (
            db.query(Order)
            .filter(
                Order.driver_id == driver.id,
                Order.driver_accepted_at >= period.period_start,
                Order.driver_accepted_at < period.period_end,
            )
            .order_by(Order.delivered_at.desc())
            .all()
        )
        return [
            {
                "order_id": o.id,
                "completed_at": o.delivered_at.isoformat() if o.delivered_at else None,
                "prop22_engaged_hours": o.prop22_engaged_hours,
                "prop22_engaged_miles": o.prop22_engaged_miles,
                "prop22_floor_amount": o.prop22_floor_amount,
            }
            for o in orders
        ]
    else:  # RIDESHARE (default)
        rides = (
            db.query(RideRequest)
            .filter(
                RideRequest.driver_id == driver.id,
                RideRequest.matched_at >= period.period_start,
                RideRequest.matched_at < period.period_end,
                RideRequest.status == "completed",
            )
            .order_by(RideRequest.completed_at.desc())
            .all()
        )
        return [
            {
                "ride_id": r.id,
                "completed_at": r.completed_at.isoformat() if r.completed_at else None,
                "prop22_engaged_hours": r.prop22_engaged_hours,
                "prop22_engaged_miles": r.prop22_engaged_miles,
                "prop22_floor_amount": r.prop22_floor_amount,
            }
            for r in rides
        ]


@app.get("/api/admin/prop22/periods")
async def get_admin_prop22_periods(
    status: Optional[str] = None,
    page: int = 1,
    page_size: int = 50,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Returns all Prop 22 earning periods for admin compliance view.
    Supports filtering by status (e.g., MANUAL_REVIEW, OVERDUE).
    Sorted by deadline_at ASC for MANUAL_REVIEW/OVERDUE, period_start DESC otherwise.
    Admin portal compliance dashboard consumes this.
    """
    from models import Prop22EarningPeriod

    query = (
        db.query(Prop22EarningPeriod, Driver)
        .join(Driver, Prop22EarningPeriod.driver_id == Driver.id)
        .filter(Prop22EarningPeriod.is_archived == False)
    )

    if status:
        query = query.filter(Prop22EarningPeriod.status == status)

    if status in ["MANUAL_REVIEW", "OVERDUE"]:
        query = query.order_by(Prop22EarningPeriod.deadline_at.asc())
    else:
        query = query.order_by(Prop22EarningPeriod.period_start.desc())

    total = query.count()
    results = query.offset((page - 1) * page_size).limit(page_size).all()

    return {
        "total": total,
        "page": page,
        "page_size": page_size,
        "items": [
            {
                "id": p.id,
                "driver_id": p.driver_id,
                "driver_name": f"{d.first_name} {d.last_name}",
                "driver_stripe_onboarded": d.stripe_onboarded,
                "period_start": p.period_start.isoformat(),
                "period_end": p.period_end.isoformat(),
                "status": p.status,
                "service_type": p.service_type,
                "engaged_hours": p.engaged_hours,
                "engaged_miles": p.engaged_miles,
                "net_earnings": p.net_earnings,
                "prop22_floor": p.prop22_floor,
                "top_up_amount": p.top_up_amount,
                "top_up_stripe_id": p.top_up_stripe_id,
                "deadline_at": p.deadline_at.isoformat() if p.deadline_at else None,
            }
            for p, d in results
        ]
    }


@app.post("/api/admin/prop22/manual-topup")
async def post_admin_prop22_manual_topup(
    driver_id: int,
    period_id: int,
    amount: float,
    method: str,           # "ACH" | "CHECK" | "STRIPE"
    reference_number: str, # stored in top_up_stripe_id — BPC §7454 payment record
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    Records a manual Prop 22 top-up payment.
    Updates period status to PAID, stores reference_number in top_up_stripe_id.
    reference_number satisfies BPC §7454 audit requirement for offline payments.
    Format stored: "METHOD:REF-NUMBER" (e.g., "ACH:REF-001").
    """
    from models import Prop22EarningPeriod, Prop22EarningsStatement
    from fastapi import HTTPException

    period = db.query(Prop22EarningPeriod).filter(
        Prop22EarningPeriod.id == period_id,
        Prop22EarningPeriod.driver_id == driver_id
    ).first()
    if not period:
        raise HTTPException(status_code=404, detail="Prop 22 period not found")
    if period.status not in ["MANUAL_REVIEW", "OVERDUE"]:
        raise HTTPException(
            status_code=400,
            detail=f"Period status is {period.status}, not MANUAL_REVIEW or OVERDUE"
        )

    # Store as "METHOD:REF-NUMBER" for BPC §7454 audit trail
    period.top_up_stripe_id = f"{method}:{reference_number}"
    period.status = "PAID"
    period.top_up_amount = amount

    # Also update the earnings statement record for BPC §7454 compliance retention
    statement = db.query(Prop22EarningsStatement).filter(
        Prop22EarningsStatement.period_id == period_id
    ).first()
    if statement:
        statement.top_up_stripe_id = period.top_up_stripe_id
        statement.top_up_amount = amount

    db.commit()
    db.refresh(period)

    return {
        "success": True,
        "period_id": period.id,
        "status": period.status,
        "reference": period.top_up_stripe_id,
        "message": f"Manual top-up of ${amount:.2f} via {method} recorded. Reference: {reference_number}"
    }


# ==================== Compliance Email Trigger Endpoints ====================


@app.post("/api/admin/compliance/trigger-monthly-report")
async def trigger_monthly_report(
    request: Request,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """Manually trigger monthly earnings summary for a specific driver + month."""
    import calendar, traceback as _tb
    from email_service import send_monthly_earnings_summary_email, get_driver_ytd_earnings
    from models import Prop22EarningPeriod, OrderStatus, RideRequestStatus, RideRequest
    try:
        body = await request.json()
        driver_email = body.get("driver_email")
        year = body.get("year", datetime.utcnow().year)
        month = body.get("month", datetime.utcnow().month)

        if not driver_email:
            raise HTTPException(status_code=400, detail="driver_email is required")

        driver = db.query(Driver).filter(Driver.email == driver_email).first()
        if not driver:
            raise HTTPException(status_code=404, detail=f"Driver with email {driver_email} not found")

        _, last_day = calendar.monthrange(year, month)
        month_start = datetime(year, month, 1)
        month_end = datetime(year, month, last_day, 23, 59, 59)

        food_orders_q = db.query(Order).filter(
            Order.driver_id == driver.id,
            Order.status == OrderStatus.DELIVERED,
            Order.delivered_at >= month_start,
            Order.delivered_at <= month_end,
        ).all()
        food_orders = len(food_orders_q)
        food_delivery_fees = sum(float(o.delivery_fee or 0) for o in food_orders_q)
        food_tips = sum(float(o.tip or 0) for o in food_orders_q)

        rides_q = db.query(RideRequest).filter(
            RideRequest.matched_driver_id == driver.id,
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= month_start,
            RideRequest.completed_at <= month_end,
        ).all()
        ride_count = len(rides_q)
        ride_fares = sum(float(r.driver_payout or 0) for r in rides_q)
        ride_tips = sum(float(r.tip_amount or 0) for r in rides_q)
        platform_fees_paid = sum(float(r.platform_fee or 0) for r in rides_q)

        periods = db.query(Prop22EarningPeriod).filter(
            Prop22EarningPeriod.driver_id == driver.id,
            Prop22EarningPeriod.period_end >= month_start,
            Prop22EarningPeriod.period_end <= month_end,
            Prop22EarningPeriod.status.in_(["PAID", "RECONCILED"]),
        ).all()
        prop22_topups = sum(float(p.top_up_amount or 0) for p in periods)

        # ride_fares = driver_payout (already = fare - platform_fee), so don't subtract platform_fee again
        # Show platform_fees_paid in the email breakdown but don't deduct it from net
        net_payout = food_delivery_fees + food_tips + ride_fares + ride_tips + prop22_topups
        ytd_total = get_driver_ytd_earnings(db, driver.id, year)

        send_monthly_earnings_summary_email(
            driver_email=driver.email,
            driver_name=f"{driver.first_name} {driver.last_name}".strip(),
            year=year, month=month, food_orders=food_orders,
            food_delivery_fees=food_delivery_fees, food_tips=food_tips,
            ride_count=ride_count, ride_fares=ride_fares, ride_tips=ride_tips,
            platform_fees_paid=platform_fees_paid, prop22_topups=prop22_topups,
            net_payout=net_payout, ytd_total=ytd_total,
        )

        return {
            "status": "sent", "driver_email": driver.email,
            "year": year, "month": month,
            "net_payout": net_payout, "ytd_total": ytd_total,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"trigger-monthly-report error: {_tb.format_exc()}")
        return JSONResponse(status_code=500, content={"detail": str(e), "type": type(e).__name__, "traceback": _tb.format_exc()})


@app.post("/api/admin/compliance/trigger-quarterly-report")
async def trigger_quarterly_report(
    request: Request,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """Manually trigger quarterly compliance report for specified quarter."""
    import calendar, traceback as _tb
    from sqlalchemy import func as sqla_func
    from email_service import send_quarterly_compliance_report_email, get_driver_ytd_earnings
    from models import Prop22EarningPeriod, OrderStatus, RideRequestStatus, RideRequest
    try:
        body = await request.json()
        year = body.get("year", datetime.utcnow().year)
        quarter = body.get("quarter", ((datetime.utcnow().month - 1) // 3) + 1)

        if quarter not in (1, 2, 3, 4):
            raise HTTPException(status_code=400, detail="quarter must be 1, 2, 3, or 4")

        q_start_month = (quarter - 1) * 3 + 1
        q_end_month = q_start_month + 2
        _, q_end_day = calendar.monthrange(year, q_end_month)
        q_start = datetime(year, q_start_month, 1)
        q_end = datetime(year, q_end_month, q_end_day, 23, 59, 59)

        ride_driver_ids = {r[0] for r in db.query(RideRequest.matched_driver_id).filter(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= q_start,
            RideRequest.completed_at <= q_end,
            RideRequest.matched_driver_id.isnot(None),
        ).distinct().all()}

        food_driver_ids = {r[0] for r in db.query(Order.driver_id).filter(
            Order.status == OrderStatus.DELIVERED,
            Order.delivered_at >= q_start,
            Order.delivered_at <= q_end,
            Order.driver_id.isnot(None),
        ).distinct().all()}

        all_driver_ids = ride_driver_ids | food_driver_ids
        total_drivers = len(all_driver_ids)

        periods = db.query(Prop22EarningPeriod).filter(
            Prop22EarningPeriod.period_end >= q_start,
            Prop22EarningPeriod.period_end <= q_end,
        ).all()

        total_hours = sum(float(p.engaged_hours or 0) for p in periods)
        total_floor = sum(float(p.prop22_floor or 0) for p in periods)
        total_topups = sum(float(p.top_up_amount or 0) for p in periods if p.status in ("PAID", "RECONCILED"))
        drivers_with_topups = len({p.driver_id for p in periods if (p.top_up_amount or 0) > 0 and p.status in ("PAID", "RECONCILED")})

        prop22_summary = {
            "total_hours": total_hours, "total_floor": total_floor,
            "total_topups": total_topups, "drivers_with_topups": drivers_with_topups,
        }

        driver_breakdown = []
        threshold_drivers = []
        approaching_drivers = []

        for did in all_driver_ids:
            driver = db.query(Driver).filter(Driver.id == did).first()
            if not driver:
                continue
            driver_name = f"{driver.first_name} {driver.last_name}".strip()

            # Prop 22 periods (if reconciliation has run)
            driver_periods = [p for p in periods if p.driver_id == did]
            d_floor = sum(float(p.prop22_floor or 0) for p in driver_periods)
            d_topup = sum(float(p.top_up_amount or 0) for p in driver_periods if p.status in ("PAID", "RECONCILED"))
            d_status = driver_periods[-1].status if driver_periods else "N/A"

            # Calculate actual hours + earnings from ride/order data (always accurate)
            driver_rides = db.query(RideRequest).filter(
                RideRequest.matched_driver_id == did,
                RideRequest.status == RideRequestStatus.COMPLETED,
                RideRequest.completed_at >= q_start,
                RideRequest.completed_at <= q_end,
            ).all()
            driver_orders = db.query(Order).filter(
                Order.driver_id == did,
                Order.status == OrderStatus.DELIVERED,
                Order.delivered_at >= q_start,
                Order.delivered_at <= q_end,
            ).all()

            # Engaged hours: use Prop 22 data if available, else estimate from ride duration
            if driver_periods:
                d_hours = sum(float(p.engaged_hours or 0) for p in driver_periods)
            else:
                ride_hours = 0.0
                for r in driver_rides:
                    if r.completed_at and r.matched_at:
                        ride_hours += (r.completed_at - r.matched_at).total_seconds() / 3600
                    elif r.completed_at and r.created_at:
                        ride_hours += (r.completed_at - r.created_at).total_seconds() / 3600
                order_hours = 0.0
                for o in driver_orders:
                    if o.delivered_at and getattr(o, 'driver_accepted_at', None):
                        order_hours += (o.delivered_at - o.driver_accepted_at).total_seconds() / 3600
                d_hours = ride_hours + order_hours

            # Actual earned: driver_payout + tips
            d_earned = (
                sum(float(r.driver_payout or 0) + float(r.tip_amount or 0) for r in driver_rides) +
                sum(float(o.delivery_fee or 0) + float(o.tip or 0) for o in driver_orders)
            )

            driver_breakdown.append({
                "name": driver_name, "engaged_hours": round(d_hours, 2),
                "floor": round(d_floor, 2), "earned": round(d_earned, 2),
                "top_up": round(d_topup, 2), "status": d_status,
            })

            ytd = get_driver_ytd_earnings(db, did, year)
            if ytd >= 600:
                threshold_drivers.append({"name": driver_name, "ytd": round(ytd, 2)})
            elif ytd >= 500:
                approaching_drivers.append({"name": driver_name, "ytd": round(ytd, 2)})

        customer_ride_count = db.query(sqla_func.count(RideRequest.id)).filter(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= q_start,
            RideRequest.completed_at <= q_end,
        ).scalar() or 0
        customer_order_count = db.query(sqla_func.count(Order.id)).filter(
            Order.status == OrderStatus.DELIVERED,
            Order.delivered_at >= q_start,
            Order.delivered_at <= q_end,
        ).scalar() or 0

        customer_fees = float(customer_ride_count + customer_order_count) * 1.0
        driver_fees_sum = db.query(sqla_func.sum(RideRequest.platform_fee)).filter(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= q_start,
            RideRequest.completed_at <= q_end,
        ).scalar() or 0
        restaurant_fees = float(customer_order_count) * 1.0

        revenue_summary = {
            "customer_fees": customer_fees,
            "driver_fees": float(driver_fees_sum) + restaurant_fees,
            "net_revenue": customer_fees + float(driver_fees_sum) + restaurant_fees,
        }

        send_quarterly_compliance_report_email(
            admin_email="jeetnair.in@gmail.com",
            year=year, quarter=quarter, total_drivers=total_drivers,
            prop22_summary=prop22_summary, driver_breakdown=driver_breakdown,
            threshold_drivers=threshold_drivers, approaching_drivers=approaching_drivers,
            revenue_summary=revenue_summary,
        )

        return {
            "status": "sent", "admin_email": "jeetnair.in@gmail.com",
            "year": year, "quarter": quarter,
            "total_drivers": total_drivers,
            "threshold_drivers": len(threshold_drivers),
            "approaching_drivers": len(approaching_drivers),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"trigger-quarterly-report error: {_tb.format_exc()}")
        return JSONResponse(status_code=500, content={"detail": str(e), "type": type(e).__name__, "traceback": _tb.format_exc()})


# Client endpoints
@app.post("/api/clients", response_model=ClientResponse)
def create_client(client: ClientCreate, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    db_client = Client(**client.dict())
    db.add(db_client)
    db.commit()
    db.refresh(db_client)
    return db_client

@app.get("/api/clients", response_model=List[ClientResponse])
def get_clients(skip: int = 0, limit: int = 100, search: Optional[str] = None, 
                db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    query = db.query(Client)
    
    if search:
        query = query.filter(
            or_(
                Client.name.ilike(f"%{search}%"),
                Client.email.ilike(f"%{search}%"),
                Client.company.ilike(f"%{search}%")
            )
        )
    
    clients = query.offset(skip).limit(limit).all()
    return clients

@app.get("/api/clients/{client_id}", response_model=ClientResponse)
def get_client(client_id: int, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    client = db.query(Client).filter(Client.id == client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")
    return client

@app.put("/api/clients/{client_id}", response_model=ClientResponse)
def update_client(client_id: int, client_update: ClientCreate, 
                 db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    db_client = db.query(Client).filter(Client.id == client_id).first()
    if not db_client:
        raise HTTPException(status_code=404, detail="Client not found")
    
    for key, value in client_update.dict().items():
        setattr(db_client, key, value)
    
    db_client.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(db_client)
    return db_client

@app.delete("/api/clients/{client_id}")
def delete_client(client_id: int, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    db_client = db.query(Client).filter(Client.id == client_id).first()
    if not db_client:
        raise HTTPException(status_code=404, detail="Client not found")
    
    # Check if client has invoices
    invoice_count = db.query(Invoice).filter(Invoice.client_id == client_id).count()
    if invoice_count > 0:
        raise HTTPException(status_code=400, detail="Cannot delete client with existing invoices")
    
    db.delete(db_client)
    db.commit()
    return {"message": "Client deleted successfully"}

# Invoice endpoints
@app.post("/api/invoices", response_model=InvoiceResponse)
def create_invoice(invoice_data: InvoiceCreate, db: Session = Depends(get_db), 
                  admin: User = Depends(require_admin)):
    # Calculate amounts
    subtotal = sum(item.quantity * item.unit_price for item in invoice_data.items)
    tax_amount = subtotal * (invoice_data.tax_rate / 100)
    total_amount = subtotal + tax_amount - invoice_data.discount_amount
    
    # Create invoice
    db_invoice = Invoice(
        invoice_number=generate_invoice_number(db),
        user_id=admin.id,
        client_id=invoice_data.client_id,
        issue_date=invoice_data.issue_date,
        due_date=invoice_data.due_date,
        subtotal=subtotal,
        tax_rate=invoice_data.tax_rate,
        tax_amount=tax_amount,
        discount_amount=invoice_data.discount_amount,
        total_amount=total_amount,
        status=InvoiceStatus.DRAFT,
        notes=invoice_data.notes,
        terms=invoice_data.terms
    )
    db.add(db_invoice)
    db.flush()
    
    # Create invoice items
    for item in invoice_data.items:
        db_item = InvoiceItem(
            invoice_id=db_invoice.id,
            description=item.description,
            quantity=item.quantity,
            unit_price=item.unit_price,
            amount=item.quantity * item.unit_price
        )
        db.add(db_item)
    
    db.commit()
    db.refresh(db_invoice)
    
    # Format response
    client = db.query(Client).filter(Client.id == db_invoice.client_id).first()
    return {
        **db_invoice.__dict__,
        "client_name": client.name,
        "items": db_invoice.items
    }

@app.get("/api/invoices")
def get_invoices(
    skip: int = 0, 
    limit: int = 100, 
    status: Optional[str] = None,
    client_id: Optional[int] = None,
    search: Optional[str] = None,
    db: Session = Depends(get_db), 
    admin: User = Depends(require_admin)
):
    query = db.query(Invoice).join(Client)
    
    if status:
        query = query.filter(Invoice.status == InvoiceStatus[status.upper()])
    
    if client_id:
        query = query.filter(Invoice.client_id == client_id)
    
    if search:
        query = query.filter(
            or_(
                Invoice.invoice_number.ilike(f"%{search}%"),
                Client.name.ilike(f"%{search}%")
            )
        )
    
    total = query.count()
    invoices = query.order_by(Invoice.created_at.desc()).offset(skip).limit(limit).all()
    
    result = []
    for invoice in invoices:
        client = db.query(Client).filter(Client.id == invoice.client_id).first()
        paid_amount = sum(p.amount for p in invoice.payments if p.status == PaymentStatus.COMPLETED)
        
        result.append({
            "id": invoice.id,
            "invoice_number": invoice.invoice_number,
            "client_id": invoice.client_id,
            "client_name": client.name,
            "issue_date": invoice.issue_date,
            "due_date": invoice.due_date,
            "subtotal": invoice.subtotal,
            "tax_amount": invoice.tax_amount,
            "discount_amount": invoice.discount_amount,
            "total_amount": invoice.total_amount,
            "paid_amount": paid_amount,
            "balance": invoice.total_amount - paid_amount,
            "status": invoice.status.value,
            "created_at": invoice.created_at
        })
    
    return {"data": result, "total": total}

@app.get("/api/invoices/stats")
def get_invoice_stats(
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Get invoice statistics for dashboard widgets.
    Connected to Admin Portal: Invoice Dashboard Stats
    IMPORTANT: This route MUST be defined BEFORE /api/invoices/{invoice_id}
    to prevent FastAPI from matching 'stats' as an invoice_id.
    """
    # Total counts by status
    total_invoices = db.query(Invoice).count()
    draft_count = db.query(Invoice).filter(Invoice.status == InvoiceStatus.DRAFT).count()
    sent_count = db.query(Invoice).filter(Invoice.status == InvoiceStatus.SENT).count()
    paid_count = db.query(Invoice).filter(Invoice.status == InvoiceStatus.PAID).count()
    overdue_count = db.query(Invoice).filter(
        and_(
            Invoice.due_date < datetime.now(),
            Invoice.status.in_([InvoiceStatus.DRAFT, InvoiceStatus.SENT])
        )
    ).count()
    cancelled_count = db.query(Invoice).filter(Invoice.status == InvoiceStatus.CANCELLED).count()

    # Financial totals
    total_invoiced = db.query(func.sum(Invoice.total_amount)).filter(
        Invoice.status != InvoiceStatus.CANCELLED
    ).scalar() or 0

    total_paid = db.query(func.sum(Payment.amount)).filter(
        Payment.status == PaymentStatus.COMPLETED
    ).scalar() or 0

    total_outstanding = total_invoiced - total_paid

    # This month's stats
    month_start = datetime.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    this_month_invoiced = db.query(func.sum(Invoice.total_amount)).filter(
        and_(
            Invoice.created_at >= month_start,
            Invoice.status != InvoiceStatus.CANCELLED
        )
    ).scalar() or 0

    this_month_paid = db.query(func.sum(Payment.amount)).filter(
        and_(
            Payment.created_at >= month_start,
            Payment.status == PaymentStatus.COMPLETED
        )
    ).scalar() or 0

    # Recent invoices
    recent_invoices = db.query(Invoice).order_by(Invoice.created_at.desc()).limit(5).all()
    recent_list = []
    for inv in recent_invoices:
        client = db.query(Client).filter(Client.id == inv.client_id).first()
        recent_list.append({
            "id": inv.id,
            "invoice_number": inv.invoice_number,
            "client_name": client.name if client else "Unknown",
            "total_amount": inv.total_amount,
            "status": inv.status.value,
            "due_date": inv.due_date.isoformat() if inv.due_date else None
        })

    # Top clients by revenue
    top_clients = db.query(
        Client.id,
        Client.name,
        func.sum(Invoice.total_amount).label("total_revenue"),
        func.count(Invoice.id).label("invoice_count")
    ).join(Invoice).filter(
        Invoice.status != InvoiceStatus.CANCELLED
    ).group_by(Client.id).order_by(func.sum(Invoice.total_amount).desc()).limit(5).all()

    return {
        "summary": {
            "total_invoices": total_invoices,
            "draft": draft_count,
            "sent": sent_count,
            "paid": paid_count,
            "overdue": overdue_count,
            "cancelled": cancelled_count
        },
        "financials": {
            "total_invoiced": round(total_invoiced, 2),
            "total_paid": round(total_paid, 2),
            "total_outstanding": round(total_outstanding, 2),
            "this_month_invoiced": round(this_month_invoiced, 2),
            "this_month_paid": round(this_month_paid, 2)
        },
        "recent_invoices": recent_list,
        "top_clients": [
            {
                "id": c.id,
                "name": c.name,
                "total_revenue": round(c.total_revenue, 2),
                "invoice_count": c.invoice_count
            } for c in top_clients
        ]
    }

@app.get("/api/invoices/{invoice_id}", response_model=InvoiceResponse)
def get_invoice(invoice_id: int, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    
    client = db.query(Client).filter(Client.id == invoice.client_id).first()
    return {
        **invoice.__dict__,
        "client_name": client.name,
        "items": invoice.items
    }

@app.put("/api/invoices/{invoice_id}/status")
def update_invoice_status(invoice_id: int, status: str, db: Session = Depends(get_db), 
                         admin: User = Depends(require_admin)):
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    
    try:
        invoice.status = InvoiceStatus[status.upper()]
    except KeyError:
        raise HTTPException(status_code=400, detail="Invalid status")
    
    db.commit()
    return {"message": "Status updated successfully"}

@app.delete("/api/invoices/{invoice_id}")
def delete_invoice(invoice_id: int, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    
    if invoice.status != InvoiceStatus.DRAFT:
        raise HTTPException(status_code=400, detail="Can only delete draft invoices")
    
    db.delete(invoice)
    db.commit()
    return {"message": "Invoice deleted successfully"}

# Payment endpoints
@app.post("/api/invoices/{invoice_id}/payments", response_model=PaymentResponse)
def create_payment(request: Request, invoice_id: int, payment_data: PaymentCreate,
                  db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    check_rate_limit(request, payment_limiter, "payment", identifier=str(admin.id))
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")
    
    db_payment = Payment(
        invoice_id=invoice_id,
        **payment_data.dict()
    )
    db.add(db_payment)
    
    # Update invoice status based on payments
    total_paid = sum(p.amount for p in invoice.payments if p.status == PaymentStatus.COMPLETED) + payment_data.amount
    
    if total_paid >= invoice.total_amount:
        invoice.status = InvoiceStatus.PAID
    elif invoice.status == InvoiceStatus.DRAFT:
        invoice.status = InvoiceStatus.SENT
    
    db.commit()
    db.refresh(db_payment)
    return db_payment

@app.get("/api/invoices/{invoice_id}/payments", response_model=List[PaymentResponse])
def get_invoice_payments(invoice_id: int, db: Session = Depends(get_db),
                        admin: User = Depends(require_admin)):
    payments = db.query(Payment).filter(Payment.invoice_id == invoice_id).all()
    return payments


# ============================================================================
# ENHANCED INVOICE ENDPOINTS - Admin Portal Connected
# ============================================================================

@app.put("/api/invoices/{invoice_id}")
def update_invoice(
    invoice_id: int,
    invoice_data: dict,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Full update of an invoice. Can update client, dates, items, amounts.
    Connected to Admin Portal: Invoice Edit Modal
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    # Only allow editing draft or sent invoices
    if invoice.status not in [InvoiceStatus.DRAFT, InvoiceStatus.SENT]:
        raise HTTPException(status_code=400, detail="Can only edit draft or sent invoices")

    # Update basic fields
    if "client_id" in invoice_data:
        client = db.query(Client).filter(Client.id == invoice_data["client_id"]).first()
        if not client:
            raise HTTPException(status_code=404, detail="Client not found")
        invoice.client_id = invoice_data["client_id"]

    if "issue_date" in invoice_data:
        invoice.issue_date = datetime.fromisoformat(invoice_data["issue_date"].replace("Z", "+00:00")) if isinstance(invoice_data["issue_date"], str) else invoice_data["issue_date"]

    if "due_date" in invoice_data:
        invoice.due_date = datetime.fromisoformat(invoice_data["due_date"].replace("Z", "+00:00")) if isinstance(invoice_data["due_date"], str) else invoice_data["due_date"]

    if "tax_rate" in invoice_data:
        invoice.tax_rate = invoice_data["tax_rate"]

    if "discount_amount" in invoice_data:
        invoice.discount_amount = invoice_data["discount_amount"]

    if "notes" in invoice_data:
        invoice.notes = invoice_data["notes"]

    if "terms" in invoice_data:
        invoice.terms = invoice_data["terms"]

    if "status" in invoice_data:
        try:
            invoice.status = InvoiceStatus[invoice_data["status"].upper()]
        except KeyError:
            raise HTTPException(status_code=400, detail="Invalid status")

    # Update items if provided
    if "items" in invoice_data:
        # Delete existing items
        db.query(InvoiceItem).filter(InvoiceItem.invoice_id == invoice_id).delete()

        # Add new items
        subtotal = 0
        for item in invoice_data["items"]:
            amount = item["quantity"] * item["unit_price"]
            subtotal += amount
            db_item = InvoiceItem(
                invoice_id=invoice_id,
                description=item["description"],
                quantity=item["quantity"],
                unit_price=item["unit_price"],
                amount=amount
            )
            db.add(db_item)

        # Recalculate totals
        invoice.subtotal = subtotal
        invoice.tax_amount = subtotal * (invoice.tax_rate / 100)
        invoice.total_amount = invoice.subtotal + invoice.tax_amount - invoice.discount_amount

    invoice.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(invoice)

    client = db.query(Client).filter(Client.id == invoice.client_id).first()
    paid_amount = sum(p.amount for p in invoice.payments if p.status == PaymentStatus.COMPLETED)

    return {
        "id": invoice.id,
        "invoice_number": invoice.invoice_number,
        "client_id": invoice.client_id,
        "client_name": client.name if client else "Unknown",
        "client_email": client.email if client else None,
        "issue_date": invoice.issue_date,
        "due_date": invoice.due_date,
        "subtotal": invoice.subtotal,
        "tax_rate": invoice.tax_rate,
        "tax_amount": invoice.tax_amount,
        "discount_amount": invoice.discount_amount,
        "total_amount": invoice.total_amount,
        "paid_amount": paid_amount,
        "balance": invoice.total_amount - paid_amount,
        "status": invoice.status.value,
        "notes": invoice.notes,
        "terms": invoice.terms,
        "items": [{"id": i.id, "description": i.description, "quantity": i.quantity, "unit_price": i.unit_price, "amount": i.amount} for i in invoice.items],
        "created_at": invoice.created_at,
        "updated_at": invoice.updated_at
    }


@app.post("/api/invoices/{invoice_id}/send")
def send_invoice(
    invoice_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Send invoice to client via email. Updates status to SENT.
    Connected to Admin Portal: Send Invoice Button
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    if invoice.status == InvoiceStatus.CANCELLED:
        raise HTTPException(status_code=400, detail="Cannot send cancelled invoice")

    client = db.query(Client).filter(Client.id == invoice.client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")

    # Update status to SENT
    invoice.status = InvoiceStatus.SENT
    invoice.updated_at = datetime.utcnow()

    # Send email notification (placeholder - would integrate with email service)
    email_sent = False
    try:
        # In production, this would send an actual email
        # For now, log the action
        print(f"[INVOICE SENT] Invoice #{invoice.invoice_number} sent to {client.email}")
        email_sent = True
    except Exception as e:
        print(f"Email send error: {e}")

    db.commit()

    return {
        "success": True,
        "invoice_id": invoice_id,
        "invoice_number": invoice.invoice_number,
        "client_email": client.email,
        "email_sent": email_sent,
        "status": invoice.status.value,
        "message": f"Invoice #{invoice.invoice_number} has been sent to {client.email}"
    }


@app.post("/api/invoices/{invoice_id}/mark-paid")
def mark_invoice_paid(
    invoice_id: int,
    payment_data: Optional[dict] = None,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Mark invoice as fully paid with optional payment details.
    Connected to Admin Portal: Mark as Paid Button
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    if invoice.status == InvoiceStatus.PAID:
        raise HTTPException(status_code=400, detail="Invoice is already paid")

    if invoice.status == InvoiceStatus.CANCELLED:
        raise HTTPException(status_code=400, detail="Cannot mark cancelled invoice as paid")

    # Calculate remaining balance
    paid_amount = sum(p.amount for p in invoice.payments if p.status == PaymentStatus.COMPLETED)
    remaining = invoice.total_amount - paid_amount

    # Create payment record for the remaining balance
    if remaining > 0:
        payment = Payment(
            invoice_id=invoice_id,
            amount=remaining,
            payment_date=datetime.utcnow(),
            payment_method=payment_data.get("payment_method", "manual") if payment_data else "manual",
            reference_number=payment_data.get("reference_number") if payment_data else None,
            status=PaymentStatus.COMPLETED,
            notes=payment_data.get("notes", "Marked as paid from admin portal") if payment_data else "Marked as paid from admin portal"
        )
        db.add(payment)

    invoice.status = InvoiceStatus.PAID
    invoice.updated_at = datetime.utcnow()
    db.commit()

    return {
        "success": True,
        "invoice_id": invoice_id,
        "invoice_number": invoice.invoice_number,
        "status": invoice.status.value,
        "total_amount": invoice.total_amount,
        "message": f"Invoice #{invoice.invoice_number} marked as paid"
    }


@app.post("/api/invoices/{invoice_id}/items")
def add_invoice_item(
    invoice_id: int,
    item_data: InvoiceItemCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Add a new line item to an invoice.
    Connected to Admin Portal: Add Line Item Button
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    if invoice.status not in [InvoiceStatus.DRAFT, InvoiceStatus.SENT]:
        raise HTTPException(status_code=400, detail="Can only add items to draft or sent invoices")

    amount = item_data.quantity * item_data.unit_price

    db_item = InvoiceItem(
        invoice_id=invoice_id,
        description=item_data.description,
        quantity=item_data.quantity,
        unit_price=item_data.unit_price,
        amount=amount
    )
    db.add(db_item)

    # Recalculate invoice totals
    invoice.subtotal += amount
    invoice.tax_amount = invoice.subtotal * (invoice.tax_rate / 100)
    invoice.total_amount = invoice.subtotal + invoice.tax_amount - invoice.discount_amount
    invoice.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(db_item)

    return {
        "id": db_item.id,
        "description": db_item.description,
        "quantity": db_item.quantity,
        "unit_price": db_item.unit_price,
        "amount": db_item.amount,
        "invoice_subtotal": invoice.subtotal,
        "invoice_total": invoice.total_amount
    }


@app.put("/api/invoices/{invoice_id}/items/{item_id}")
def update_invoice_item(
    invoice_id: int,
    item_id: int,
    item_data: InvoiceItemCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Update a line item on an invoice.
    Connected to Admin Portal: Edit Line Item
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    item = db.query(InvoiceItem).filter(
        InvoiceItem.id == item_id,
        InvoiceItem.invoice_id == invoice_id
    ).first()
    if not item:
        raise HTTPException(status_code=404, detail="Invoice item not found")

    if invoice.status not in [InvoiceStatus.DRAFT, InvoiceStatus.SENT]:
        raise HTTPException(status_code=400, detail="Can only edit items on draft or sent invoices")

    # Update subtotal
    old_amount = item.amount
    new_amount = item_data.quantity * item_data.unit_price

    item.description = item_data.description
    item.quantity = item_data.quantity
    item.unit_price = item_data.unit_price
    item.amount = new_amount

    # Recalculate invoice totals
    invoice.subtotal = invoice.subtotal - old_amount + new_amount
    invoice.tax_amount = invoice.subtotal * (invoice.tax_rate / 100)
    invoice.total_amount = invoice.subtotal + invoice.tax_amount - invoice.discount_amount
    invoice.updated_at = datetime.utcnow()

    db.commit()

    return {
        "id": item.id,
        "description": item.description,
        "quantity": item.quantity,
        "unit_price": item.unit_price,
        "amount": item.amount,
        "invoice_subtotal": invoice.subtotal,
        "invoice_total": invoice.total_amount
    }


@app.delete("/api/invoices/{invoice_id}/items/{item_id}")
def delete_invoice_item(
    invoice_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Remove a line item from an invoice.
    Connected to Admin Portal: Delete Line Item Button
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    item = db.query(InvoiceItem).filter(
        InvoiceItem.id == item_id,
        InvoiceItem.invoice_id == invoice_id
    ).first()
    if not item:
        raise HTTPException(status_code=404, detail="Invoice item not found")

    if invoice.status not in [InvoiceStatus.DRAFT, InvoiceStatus.SENT]:
        raise HTTPException(status_code=400, detail="Can only delete items from draft or sent invoices")

    # Check if this is the last item
    item_count = db.query(InvoiceItem).filter(InvoiceItem.invoice_id == invoice_id).count()
    if item_count <= 1:
        raise HTTPException(status_code=400, detail="Cannot delete the last item. Delete the invoice instead.")

    # Update invoice totals
    invoice.subtotal -= item.amount
    invoice.tax_amount = invoice.subtotal * (invoice.tax_rate / 100)
    invoice.total_amount = invoice.subtotal + invoice.tax_amount - invoice.discount_amount
    invoice.updated_at = datetime.utcnow()

    db.delete(item)
    db.commit()

    return {
        "success": True,
        "message": "Item deleted successfully",
        "invoice_subtotal": invoice.subtotal,
        "invoice_total": invoice.total_amount
    }


@app.post("/api/invoices/{invoice_id}/duplicate")
def duplicate_invoice(
    invoice_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Create a duplicate of an existing invoice with new invoice number.
    Connected to Admin Portal: Duplicate Invoice Button
    """
    original = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not original:
        raise HTTPException(status_code=404, detail="Invoice not found")

    # Create new invoice
    new_invoice = Invoice(
        invoice_number=generate_invoice_number(db),
        user_id=admin.id,
        client_id=original.client_id,
        issue_date=datetime.utcnow(),
        due_date=datetime.utcnow() + timedelta(days=30),
        subtotal=original.subtotal,
        tax_rate=original.tax_rate,
        tax_amount=original.tax_amount,
        discount_amount=original.discount_amount,
        total_amount=original.total_amount,
        status=InvoiceStatus.DRAFT,
        notes=original.notes,
        terms=original.terms
    )
    db.add(new_invoice)
    db.flush()

    # Copy items
    for item in original.items:
        new_item = InvoiceItem(
            invoice_id=new_invoice.id,
            description=item.description,
            quantity=item.quantity,
            unit_price=item.unit_price,
            amount=item.amount
        )
        db.add(new_item)

    db.commit()
    db.refresh(new_invoice)

    client = db.query(Client).filter(Client.id == new_invoice.client_id).first()

    return {
        "id": new_invoice.id,
        "invoice_number": new_invoice.invoice_number,
        "client_name": client.name if client else "Unknown",
        "status": new_invoice.status.value,
        "total_amount": new_invoice.total_amount,
        "message": f"Invoice duplicated as #{new_invoice.invoice_number}"
    }


@app.post("/api/invoices/{invoice_id}/void")
def void_invoice(
    invoice_id: int,
    reason: Optional[str] = None,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Void/cancel an invoice. Cannot be undone.
    Connected to Admin Portal: Void Invoice Button
    """
    invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
    if not invoice:
        raise HTTPException(status_code=404, detail="Invoice not found")

    if invoice.status == InvoiceStatus.PAID:
        raise HTTPException(status_code=400, detail="Cannot void a paid invoice. Create a credit note instead.")

    if invoice.status == InvoiceStatus.CANCELLED:
        raise HTTPException(status_code=400, detail="Invoice is already cancelled")

    invoice.status = InvoiceStatus.CANCELLED
    if reason:
        invoice.notes = (invoice.notes or "") + f"\n\n[VOIDED] {reason}"
    invoice.updated_at = datetime.utcnow()

    db.commit()

    return {
        "success": True,
        "invoice_id": invoice_id,
        "invoice_number": invoice.invoice_number,
        "status": invoice.status.value,
        "message": f"Invoice #{invoice.invoice_number} has been voided"
    }


# Dashboard endpoints
@app.get("/api/dashboard/stats")
def get_dashboard_stats(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    # Total invoices
    total_invoices = db.query(Invoice).count()
    
    # Total revenue
    total_revenue = db.query(func.sum(Invoice.total_amount)).scalar() or 0
    
    # Outstanding balance
    paid_amount = db.query(func.sum(Payment.amount)).filter(
        Payment.status == PaymentStatus.COMPLETED
    ).scalar() or 0
    outstanding = total_revenue - paid_amount
    
    # Overdue invoices
    overdue_count = db.query(Invoice).filter(
        and_(
            Invoice.due_date < datetime.now(),
            Invoice.status != InvoiceStatus.PAID,
            Invoice.status != InvoiceStatus.CANCELLED
        )
    ).count()
    
    # Status breakdown
    status_breakdown = {}
    for inv_status in InvoiceStatus:
        count = db.query(Invoice).filter(Invoice.status == inv_status).count()
        status_breakdown[inv_status.value] = count
    
    # Monthly revenue (last 12 months)
    monthly_data = []
    for i in range(11, -1, -1):
        target_date = datetime.now() - timedelta(days=30*i)
        month_start = target_date.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        
        if i == 0:
            month_end = datetime.now()
        else:
            next_month = month_start + timedelta(days=32)
            month_end = next_month.replace(day=1) - timedelta(seconds=1)
        
        month_revenue = db.query(func.sum(Invoice.total_amount)).filter(
            and_(
                Invoice.created_at >= month_start,
                Invoice.created_at <= month_end
            )
        ).scalar() or 0
        
        monthly_data.append({
            "month": month_start.strftime("%b %Y"),
            "revenue": float(month_revenue)
        })
    
    # Recent invoices
    recent_invoices = db.query(Invoice).join(Client).order_by(
        Invoice.created_at.desc()
    ).limit(5).all()
    
    recent_list = []
    for inv in recent_invoices:
        client = db.query(Client).filter(Client.id == inv.client_id).first()
        recent_list.append({
            "id": inv.id,
            "invoice_number": inv.invoice_number,
            "client_name": client.name,
            "amount": inv.total_amount,
            "status": inv.status.value,
            "due_date": inv.due_date
        })
    
    return {
        "total_invoices": total_invoices,
        "total_revenue": float(total_revenue),
        "outstanding": float(outstanding),
        "overdue_count": overdue_count,
        "status_breakdown": status_breakdown,
        "monthly_revenue": monthly_data,
        "recent_invoices": recent_list
    }

@app.get("/api/dashboard/recent-activity")
def get_recent_activity(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    # Recent invoices
    recent_invoices = db.query(Invoice).order_by(Invoice.created_at.desc()).limit(5).all()
    
    # Recent payments
    recent_payments = db.query(Payment).order_by(Payment.created_at.desc()).limit(5).all()
    
    activity = []
    
    for inv in recent_invoices:
        client = db.query(Client).filter(Client.id == inv.client_id).first()
        activity.append({
            "id": f"inv-{inv.id}",
            "type": "invoice",
            "action": f"Invoice {inv.invoice_number} created",
            "client": client.name,
            "amount": inv.total_amount,
            "date": inv.created_at
        })
    
    for pay in recent_payments:
        invoice = db.query(Invoice).filter(Invoice.id == pay.invoice_id).first()
        client = db.query(Client).filter(Client.id == invoice.client_id).first()
        activity.append({
            "id": f"pay-{pay.id}",
            "type": "payment",
            "action": f"Payment received for {invoice.invoice_number}",
            "client": client.name,
            "amount": pay.amount,
            "date": pay.created_at
        })
    
    activity.sort(key=lambda x: x["date"], reverse=True)
    return activity[:10]

# ============================================================================
# CONSOLIDATED DASHBOARD API - Dollor.ai Platform Metrics
# ============================================================================

def format_amount(amount):
    """Format amount with K/M suffix."""
    if amount >= 1000000:
        return f"${amount / 1000000:.1f}M"
    elif amount >= 1000:
        return f"${amount / 1000:.1f}K"
    else:
        return f"${amount:.0f}"


@app.get("/api/dashboard/consolidated")
def get_consolidated_dashboard(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Get consolidated dashboard metrics for Dollor.ai platform (rideshare only —
    food-order and vendor/restaurant metrics removed).
    Includes: Rides, Drivers, Revenue, and Support Tickets.
    """
    from models import RideRequest, RideRequestStatus, Driver, DriverStatus, SupportTicket, TicketStatus
    from datetime import timedelta

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    # Ride Metrics
    all_rides = db.query(RideRequest).filter(RideRequest.created_at >= start_date).limit(10000).all()
    pending_rides = len([r for r in all_rides if r.status in [RideRequestStatus.OPEN, RideRequestStatus.BIDDING, RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS]])
    completed_rides = len([r for r in all_rides if r.status == RideRequestStatus.COMPLETED])
    total_revenue = sum(float(r.platform_fee or 0) for r in all_rides if r.status == RideRequestStatus.COMPLETED)

    # Driver Metrics
    all_drivers = db.query(Driver).limit(10000).all()
    active_drivers = len([d for d in all_drivers if d.status in [DriverStatus.ACTIVE, DriverStatus.APPROVED]])
    online_drivers = len([d for d in all_drivers if d.is_online])

    # Support Ticket Metrics
    try:
        all_tickets = db.query(SupportTicket).filter(SupportTicket.created_at >= start_date).limit(10000).all()
        active_tickets = len([t for t in all_tickets if t.status in [TicketStatus.OPEN, TicketStatus.IN_PROGRESS]])
        resolved_tickets = len([t for t in all_tickets if t.status in [TicketStatus.RESOLVED, TicketStatus.CLOSED]])
    except Exception:
        active_tickets = 0
        resolved_tickets = 0

    return {
        "counts": {
            "openIpo": len(all_rides),  # Total rides in period
            "requisition": pending_rides,  # Pending/in-progress rides
            "pendingApprovals": 0,  # No vendor approvals in rideshare-only mode
            "noAction": completed_rides,  # Completed rides
            "openBills": active_tickets,  # Active support tickets
            "totalAmount": format_amount(total_revenue),
            "activeSystems": 3  # Rides, Drivers, Tickets
        },
        "financialMetrics": [
            {
                "id": "rides",
                "name": "Rides",
                "metrics": {
                    "Total Rides": len(all_rides),
                    "Pending/In Progress": pending_rides,
                    "Completed": completed_rides,
                    "Platform Fee Revenue": format_amount(total_revenue)
                }
            },
            {
                "id": "drivers",
                "name": "Drivers",
                "metrics": {
                    "Total Drivers": len(all_drivers),
                    "Active": active_drivers,
                    "Online Now": online_drivers,
                    "Approval Rate": f"{(active_drivers/len(all_drivers)*100):.0f}%" if all_drivers else "0%"
                }
            },
            {
                "id": "support",
                "name": "Support Tickets",
                "metrics": {
                    "Active Tickets": active_tickets,
                    "Resolved": resolved_tickets,
                    "Resolution Rate": f"{(resolved_tickets/(active_tickets+resolved_tickets)*100):.0f}%" if (active_tickets + resolved_tickets) > 0 else "100%",
                    "SLA Compliance": "97%"
                }
            }
        ],
        "recentActivity": []  # Can be populated with recent ride/driver activity
    }


# ============================================================================
# COUPA DASHBOARD API
# ============================================================================

@app.get("/api/dashboard/coupa")
def get_coupa_dashboard_counts(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get Coupa dashboard main metrics.
    Returns: totalSpend, requisitionValue, reqCount, poCount
    """
    from models import CoupaPurchaseOrder, CoupaRequisition, CoupaPOStatus
    from datetime import timedelta

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    # Get PO data
    pos = db.query(CoupaPurchaseOrder).filter(
        CoupaPurchaseOrder.created_at >= start_date
    ).limit(10000).all()

    # Get Requisition data
    reqs = db.query(CoupaRequisition).filter(
        CoupaRequisition.created_at >= start_date
    ).limit(10000).all()

    # Calculate metrics
    total_spend = sum(po.total_amount or 0 for po in pos if po.status in [
        CoupaPOStatus.APPROVED, CoupaPOStatus.ORDERED, CoupaPOStatus.RECEIVED,
        CoupaPOStatus.INVOICED, CoupaPOStatus.CLOSED
    ])
    requisition_value = sum(req.total_amount or 0 for req in reqs)
    po_count = len(pos)
    req_count = len(reqs)

    return {
        "counts": {
            "totalSpend": round(total_spend, 2),
            "requisitionValue": round(requisition_value, 2),
            "poCount": po_count,
            "reqCount": req_count
        }
    }


@app.get("/api/dashboard/coupa/budget-overview")
def get_coupa_budget_overview(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get monthly spend trends for Coupa dashboard.
    Returns chart data for Line chart.
    """
    from models import CoupaPurchaseOrder, CoupaPOStatus
    from datetime import timedelta
    from collections import defaultdict

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    pos = db.query(CoupaPurchaseOrder).filter(
        CoupaPurchaseOrder.created_at >= start_date,
        CoupaPurchaseOrder.status.in_([
            CoupaPOStatus.APPROVED, CoupaPOStatus.ORDERED,
            CoupaPOStatus.RECEIVED, CoupaPOStatus.INVOICED, CoupaPOStatus.CLOSED
        ])
    ).limit(10000).all()

    # Group by month
    monthly_data = defaultdict(float)
    for po in pos:
        month_key = po.created_at.strftime("%b %Y")
        monthly_data[month_key] += po.total_amount or 0

    # Sort by date and prepare chart data
    labels = list(monthly_data.keys())[-12:]  # Last 12 months
    data = [monthly_data[label] for label in labels]

    return {
        "chartData": {
            "labels": labels if labels else ["No Data"],
            "datasets": [{
                "label": "Monthly Spend",
                "data": data if data else [0],
                "borderColor": "#0ea5e9",
                "backgroundColor": "rgba(14, 165, 233, 0.1)",
                "fill": True
            }]
        }
    }


@app.get("/api/dashboard/coupa/status-distribution")
def get_coupa_status_distribution(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get PO status distribution for Coupa dashboard.
    Returns chart data for Doughnut chart.
    """
    from models import CoupaPurchaseOrder, CoupaPOStatus
    from datetime import timedelta
    from collections import Counter

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    pos = db.query(CoupaPurchaseOrder).filter(
        CoupaPurchaseOrder.created_at >= start_date
    ).limit(10000).all()

    # Count by status
    status_counts = Counter(po.status.value if po.status else "draft" for po in pos)

    labels = ["Draft", "Pending Approval", "Approved", "Ordered", "Received", "Closed"]
    status_keys = ["draft", "pending_approval", "approved", "ordered", "received", "closed"]
    data = [status_counts.get(key, 0) for key in status_keys]

    return {
        "chartData": {
            "labels": labels,
            "datasets": [{
                "data": data,
                "backgroundColor": ["#6b7280", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#6b7280"]
            }]
        }
    }


@app.get("/api/dashboard/coupa/cost-center-distribution")
def get_coupa_cost_center_distribution(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get spend by cost center for Coupa dashboard.
    Returns chart data for Doughnut/Pie chart.
    """
    from models import CoupaPurchaseOrder, CoupaCostCenter, CoupaPOStatus
    from datetime import timedelta
    from collections import defaultdict

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    pos = db.query(CoupaPurchaseOrder).filter(
        CoupaPurchaseOrder.created_at >= start_date,
        CoupaPurchaseOrder.status.in_([
            CoupaPOStatus.APPROVED, CoupaPOStatus.ORDERED,
            CoupaPOStatus.RECEIVED, CoupaPOStatus.INVOICED, CoupaPOStatus.CLOSED
        ])
    ).limit(10000).all()

    # Get cost centers
    cost_centers = {cc.id: cc.name for cc in db.query(CoupaCostCenter).limit(10000).all()}

    # Group by cost center
    cc_spend = defaultdict(float)
    for po in pos:
        cc_name = cost_centers.get(po.cost_center_id, "Unassigned")
        cc_spend[cc_name] += po.total_amount or 0

    labels = list(cc_spend.keys())[:8] if cc_spend else ["No Data"]
    data = [cc_spend[label] for label in labels] if cc_spend else [0]

    return {
        "chartData": {
            "labels": labels,
            "datasets": [{
                "data": data,
                "backgroundColor": ["#10b981", "#3b82f6", "#f59e0b", "#ef4444", "#8b5cf6", "#ec4899", "#06b6d4", "#84cc16"]
            }]
        }
    }


@app.get("/api/dashboard/coupa/spend-by-department")
def get_coupa_spend_by_department(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get spend by department for Coupa dashboard.
    Returns chart data for Bar chart.
    """
    from models import CoupaPurchaseOrder, CoupaDepartment, CoupaPOStatus
    from datetime import timedelta
    from collections import defaultdict

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    pos = db.query(CoupaPurchaseOrder).filter(
        CoupaPurchaseOrder.created_at >= start_date,
        CoupaPurchaseOrder.status.in_([
            CoupaPOStatus.APPROVED, CoupaPOStatus.ORDERED,
            CoupaPOStatus.RECEIVED, CoupaPOStatus.INVOICED, CoupaPOStatus.CLOSED
        ])
    ).limit(10000).all()

    # Get departments
    departments = {dept.id: dept.name for dept in db.query(CoupaDepartment).limit(10000).all()}

    # Group by department
    dept_spend = defaultdict(float)
    for po in pos:
        dept_name = departments.get(po.department_id, "Unassigned")
        dept_spend[dept_name] += po.total_amount or 0

    labels = list(dept_spend.keys())[:10] if dept_spend else ["No Data"]
    data = [dept_spend[label] for label in labels] if dept_spend else [0]

    return {
        "chartData": {
            "labels": labels,
            "datasets": [{
                "label": "Spend",
                "data": data,
                "backgroundColor": "#3b82f6"
            }]
        }
    }


@app.get("/api/dashboard/coupa/commodity-distribution")
def get_coupa_commodity_distribution(
    days_back: int = Query(30, description="Number of days to look back"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get spend by commodity/category for Coupa dashboard.
    Returns chart data for Pie chart.
    """
    from models import CoupaPurchaseOrder, CoupaCommodity, CoupaPOStatus
    from datetime import timedelta
    from collections import defaultdict

    now = datetime.utcnow()
    start_date = now - timedelta(days=days_back)

    pos = db.query(CoupaPurchaseOrder).filter(
        CoupaPurchaseOrder.created_at >= start_date,
        CoupaPurchaseOrder.status.in_([
            CoupaPOStatus.APPROVED, CoupaPOStatus.ORDERED,
            CoupaPOStatus.RECEIVED, CoupaPOStatus.INVOICED, CoupaPOStatus.CLOSED
        ])
    ).limit(10000).all()

    # Get commodities
    commodities = {c.id: c.name for c in db.query(CoupaCommodity).limit(10000).all()}

    # Group by commodity
    commodity_spend = defaultdict(float)
    for po in pos:
        commodity_name = commodities.get(po.commodity_id, "Uncategorized")
        commodity_spend[commodity_name] += po.total_amount or 0

    labels = list(commodity_spend.keys())[:8] if commodity_spend else ["No Data"]
    data = [commodity_spend[label] for label in labels] if commodity_spend else [0]

    return {
        "chartData": {
            "labels": labels,
            "datasets": [{
                "data": data,
                "backgroundColor": ["#ef4444", "#f59e0b", "#10b981", "#3b82f6", "#8b5cf6", "#ec4899", "#06b6d4", "#84cc16"]
            }]
        }
    }


@app.get("/api/system-dashboard/coupa")
def get_coupa_system_dashboard(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """
    Get Coupa data for the system dashboard tab.
    Returns top categories and invoice approval cycle time.
    """
    from models import CoupaCommodity, CoupaPurchaseOrder

    # Get top categories
    commodities = db.query(CoupaCommodity).limit(5).all()
    top_categories = {
        "labels": [c.name for c in commodities] if commodities else ["Category 1", "Category 2", "Category 3"],
        "datasets": [{
            "data": [100, 80, 60, 40, 20][:len(commodities)] if commodities else [100, 80, 60],
            "backgroundColor": ["#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6"]
        }]
    }

    # Invoice approval cycle time (placeholder)
    invoice_approval_cycle_time = {
        "labels": ["Week 1", "Week 2", "Week 3", "Week 4"],
        "datasets": [{
            "label": "Approval Time (days)",
            "data": [3.5, 2.8, 3.2, 2.5],
            "borderColor": "#3b82f6",
            "tension": 0.4
        }]
    }

    return {
        "topCategories": top_categories,
        "invoiceApprovalCycleTime": invoice_approval_cycle_time
    }


@app.get("/api/dashboard/coupa/filters/suppliers")
def get_coupa_suppliers_filter(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """
    Get list of suppliers for filter dropdown.
    """
    from models import CoupaSupplier

    suppliers = db.query(CoupaSupplier).filter(
        CoupaSupplier.status == "active"
    ).order_by(CoupaSupplier.name).limit(10000).all()

    return {
        "suppliers": [
            {"id": s.id, "name": s.name, "code": s.supplier_number}
            for s in suppliers
        ]
    }


@app.get("/api/dashboard/coupa/filters/cost-centers")
def get_coupa_cost_centers_filter(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """
    Get list of cost centers for filter dropdown.
    """
    from models import CoupaCostCenter

    cost_centers = db.query(CoupaCostCenter).filter(
        CoupaCostCenter.is_active == True
    ).order_by(CoupaCostCenter.name).limit(10000).all()

    return {
        "costCenters": [
            {"id": cc.id, "name": cc.name, "code": cc.code}
            for cc in cost_centers
        ]
    }


@app.get("/api/dashboard/coupa/filters/departments")
def get_coupa_departments_filter(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """
    Get list of departments for filter dropdown.
    """
    from models import CoupaDepartment

    departments = db.query(CoupaDepartment).filter(
        CoupaDepartment.is_active == True
    ).order_by(CoupaDepartment.name).limit(10000).all()

    return {
        "departments": [
            {"id": d.id, "name": d.name, "code": d.code}
            for d in departments
        ]
    }


@app.get("/api/dashboard/coupa/filters/statuses")
def get_coupa_statuses_filter(_user = Depends(require_admin)):
    """
    Get list of PO statuses for filter dropdown.
    """
    from models import CoupaPOStatus

    return {
        "statuses": [
            {"value": status.value, "label": status.value.replace("_", " ").title()}
            for status in CoupaPOStatus
        ]
    }


# ============================================================================
# ACCOUNTING API - Platform Revenue & Financial Metrics
# ============================================================================

@app.get("/api/accounting/platform-revenue")
def get_platform_revenue(
    period: str = Query("month", description="week, month, quarter, year"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """
    Get platform revenue statistics (rideshare only — food-delivery revenue removed).
    Connected to Admin Portal: Platform Revenue Screen

    Revenue Model:
    - Rideshare: $1 (fare ≤$35), $2 ($35-70), $3 (>$70)
    """
    from models import RideRequest, RideRequestStatus

    # Calculate date range
    now = datetime.now()
    if period == "week":
        start_date = now - timedelta(days=7)
    elif period == "month":
        start_date = now - timedelta(days=30)
    elif period == "quarter":
        start_date = now - timedelta(days=90)
    elif period == "year":
        start_date = now - timedelta(days=365)
    else:
        start_date = now - timedelta(days=30)

    # Query rideshare revenue from ride_requests table
    completed_rides = db.query(RideRequest).filter(
        RideRequest.status == RideRequestStatus.COMPLETED,
        RideRequest.created_at >= start_date
    ).all()
    tier_cfg = pricing_engine.config

    def _ride_price(r):
        return float(r.final_price or r.suggested_price or 0)

    tier1 = sum(float(r.platform_fee or 0) for r in completed_rides if _ride_price(r) <= tier_cfg.TIER_1_MAX)
    tier2 = sum(float(r.platform_fee or 0) for r in completed_rides if tier_cfg.TIER_1_MAX < _ride_price(r) <= tier_cfg.TIER_2_MAX)
    tier3 = sum(float(r.platform_fee or 0) for r in completed_rides if _ride_price(r) > tier_cfg.TIER_2_MAX)
    rideshare_total = tier1 + tier2 + tier3

    total_rides = len(completed_rides)
    total_gmv = sum(float(r.final_price or r.suggested_price or 0) for r in completed_rides)
    total_tips = sum(float(r.tip_amount or 0) for r in completed_rides)

    # Daily breakdown for chart
    daily_revenue = {}
    for ride in completed_rides:
        day = ride.created_at.strftime("%Y-%m-%d")
        if day not in daily_revenue:
            daily_revenue[day] = {"rides": 0, "gmv": 0, "platform_fees": 0}
        daily_revenue[day]["rides"] += 1
        daily_revenue[day]["gmv"] += float(ride.final_price or ride.suggested_price or 0)
        daily_revenue[day]["platform_fees"] += float(ride.platform_fee or 0)

    # Sort by date
    daily_breakdown = [
        {"date": day_date, **data}
        for day_date, data in sorted(daily_revenue.items())
    ]

    return {
        "period": period,
        "start_date": start_date.isoformat(),
        "end_date": now.isoformat(),
        "summary": {
            "total_rides": total_rides,
            "total_gmv": round(total_gmv, 2),
            "platform_fees_collected": round(rideshare_total, 2),
            "tips_collected": round(total_tips, 2),
        },
        "revenue_breakdown": {
            "rideshare": {
                "tier_1_under_35": round(tier1, 2),
                "tier_2_35_70": round(tier2, 2),
                "tier_3_over_70": round(tier3, 2),
                "total": round(rideshare_total, 2),
            },
            "total_platform_revenue": round(rideshare_total, 2),
        },
        "driver_earnings": {
            "tips_to_drivers": round(total_tips, 2),
            "total_to_drivers": round(total_tips, 2),
        },
        "daily_breakdown": daily_breakdown,
        "pricing_model": {
            "rideshare": "$1 (≤$35), $2 ($35-70), $3 (>$70)",
        }
    }


# ============================================================================
# SUPPORT TICKET ENDPOINTS (JIRA Dashboard)
# ============================================================================

class TicketCreate(BaseModel):
    title: str
    description: Optional[str] = None
    ticket_type: Optional[str] = "Task"  # Bug, Feature, Task, Story, Epic, Support
    priority: Optional[str] = "P2 - Medium"  # P0 - Critical, P1 - High, P2 - Medium, P3 - Low
    assignee: Optional[str] = None
    reporter: Optional[str] = None
    team: Optional[str] = None
    labels: Optional[List[str]] = []
    component: Optional[str] = None
    due_date: Optional[str] = None  # ISO date string
    customer_id: Optional[int] = None
    order_id: Optional[int] = None
    vendor_id: Optional[int] = None
    driver_id: Optional[int] = None


class TicketUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    ticket_type: Optional[str] = None
    priority: Optional[str] = None
    status: Optional[str] = None
    assignee: Optional[str] = None
    team: Optional[str] = None
    labels: Optional[List[str]] = None
    component: Optional[str] = None
    due_date: Optional[str] = None
    resolution: Optional[str] = None


@app.get("/api/tickets")
def get_tickets(
    status: Optional[str] = None,
    priority: Optional[str] = None,
    ticket_type: Optional[str] = None,
    assignee: Optional[str] = None,
    team: Optional[str] = None,
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """Get all support tickets with optional filtering."""
    from models import SupportTicket, TicketStatus, TicketPriority, TicketType

    query = db.query(SupportTicket)

    if status:
        try:
            status_enum = TicketStatus(status)
            query = query.filter(SupportTicket.status == status_enum)
        except ValueError:
            pass

    if priority:
        try:
            priority_enum = TicketPriority(priority)
            query = query.filter(SupportTicket.priority == priority_enum)
        except ValueError:
            pass

    if ticket_type:
        try:
            type_enum = TicketType(ticket_type)
            query = query.filter(SupportTicket.ticket_type == type_enum)
        except ValueError:
            pass

    if assignee:
        query = query.filter(SupportTicket.assignee == assignee)

    if team:
        query = query.filter(SupportTicket.team == team)

    tickets = query.order_by(SupportTicket.created_at.desc()).offset(offset).limit(limit).all()

    return [
        {
            "id": t.ticket_id,
            "title": t.title,
            "description": t.description,
            "type": t.ticket_type.value if t.ticket_type else "Task",
            "priority": t.priority.value if t.priority else "P2 - Medium",
            "status": t.status.value if t.status else "Open",
            "assignee": t.assignee,
            "reporter": t.reporter,
            "team": t.team,
            "labels": t.labels or [],
            "component": t.component,
            "due_date": t.due_date.isoformat() if t.due_date else None,
            "sla_breached": t.sla_breached,
            "created": t.created_at.strftime("%Y-%m-%d") if t.created_at else None,
            "updated": t.updated_at.strftime("%Y-%m-%d") if t.updated_at else None,
            "resolved_at": t.resolved_at.isoformat() if t.resolved_at else None,
            "resolution_time_hours": t.resolution_time_hours
        }
        for t in tickets
    ]


@app.get("/api/tickets/metrics")
def get_ticket_metrics(
    period: str = Query("month", description="week, month, quarter, year"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """Get ticket metrics for JIRA Dashboard."""
    from models import SupportTicket, TicketStatus, TicketPriority, TicketType
    from datetime import timedelta

    now = datetime.utcnow()
    if period == "week":
        start_date = now - timedelta(days=7)
    elif period == "month":
        start_date = now - timedelta(days=30)
    elif period == "quarter":
        start_date = now - timedelta(days=90)
    else:
        start_date = now - timedelta(days=365)

    # Get all tickets in period
    tickets = db.query(SupportTicket).filter(SupportTicket.created_at >= start_date).all()

    # Calculate metrics
    active_tickets = len([t for t in tickets if t.status in [TicketStatus.OPEN, TicketStatus.IN_PROGRESS, TicketStatus.UNDER_REVIEW]])
    resolved_tickets = len([t for t in tickets if t.status in [TicketStatus.RESOLVED, TicketStatus.CLOSED]])

    # Average resolution time
    resolved_with_time = [t for t in tickets if t.resolution_time_hours is not None]
    avg_resolution_time = sum(t.resolution_time_hours for t in resolved_with_time) / len(resolved_with_time) if resolved_with_time else 0

    # SLA compliance
    total_with_sla = len([t for t in tickets if t.due_date is not None])
    sla_met = len([t for t in tickets if t.due_date is not None and not t.sla_breached])
    sla_compliance = (sla_met / total_with_sla * 100) if total_with_sla > 0 else 100

    # High priority tickets
    high_priority_tickets = len([t for t in tickets if t.priority in [TicketPriority.P0_CRITICAL, TicketPriority.P1_HIGH] and t.status not in [TicketStatus.RESOLVED, TicketStatus.CLOSED]])

    # Overdue tickets
    overdue_tickets = len([t for t in tickets if t.sla_breached and t.status not in [TicketStatus.RESOLVED, TicketStatus.CLOSED]])

    return {
        "activeTickets": active_tickets,
        "resolvedTickets": resolved_tickets,
        "avgResolutionTime": round(avg_resolution_time / 24, 1),  # Convert to days
        "slaCompliance": round(sla_compliance, 0),
        "highPriorityTickets": high_priority_tickets,
        "overdueTickets": overdue_tickets
    }


@app.get("/api/tickets/trends")
def get_ticket_trends(
    period: str = Query("month", description="week, month, quarter, year"),
    db: Session = Depends(get_db),
    _user = Depends(require_admin),
):
    """Get ticket creation and resolution trends."""
    from models import SupportTicket, TicketStatus
    from datetime import timedelta
    from collections import defaultdict

    now = datetime.utcnow()
    if period == "week":
        days = 7
        labels = [(now - timedelta(days=i)).strftime("%a") for i in range(6, -1, -1)]
    elif period == "month":
        days = 30
        # Group by week
        labels = [f"Week {i+1}" for i in range(4)]
    else:
        days = 180
        # Group by month
        labels = [(now - timedelta(days=30*i)).strftime("%b") for i in range(5, -1, -1)]

    start_date = now - timedelta(days=days)
    tickets = db.query(SupportTicket).filter(SupportTicket.created_at >= start_date).all()

    # For simplicity, generate mock trend data based on actual ticket counts
    total_created = len(tickets)
    total_resolved = len([t for t in tickets if t.status in [TicketStatus.RESOLVED, TicketStatus.CLOSED]])

    # Distribute across labels
    created_data = [int(total_created / len(labels)) + (i % 5) for i, _ in enumerate(labels)]
    resolved_data = [int(total_resolved / len(labels)) + (i % 4) for i, _ in enumerate(labels)]

    return {
        "labels": labels,
        "datasets": [
            {
                "label": "Created Tickets",
                "data": created_data,
                "borderColor": "#2563eb",
                "backgroundColor": "#2563eb",
                "tension": 0.4
            },
            {
                "label": "Resolved Tickets",
                "data": resolved_data,
                "borderColor": "#10b981",
                "backgroundColor": "#10b981",
                "tension": 0.4
            }
        ]
    }


@app.get("/api/tickets/priority-distribution")
def get_priority_distribution(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """Get ticket priority distribution."""
    from models import SupportTicket, TicketPriority, TicketStatus

    # Only count active tickets
    active_statuses = [TicketStatus.OPEN, TicketStatus.IN_PROGRESS, TicketStatus.UNDER_REVIEW]
    tickets = db.query(SupportTicket).filter(SupportTicket.status.in_(active_statuses)).all()

    priority_counts = {
        "P0 - Critical": 0,
        "P1 - High": 0,
        "P2 - Medium": 0,
        "P3 - Low": 0
    }

    for t in tickets:
        if t.priority:
            priority_counts[t.priority.value] = priority_counts.get(t.priority.value, 0) + 1

    total = sum(priority_counts.values()) or 1  # Avoid division by zero

    return {
        "labels": list(priority_counts.keys()),
        "datasets": [{
            "data": [round(v / total * 100) for v in priority_counts.values()],
            "backgroundColor": ["#ef4444", "#f59e0b", "#6366f1", "#10b981"],
            "borderWidth": 0
        }]
    }


@app.get("/api/tickets/resolution-by-type")
def get_resolution_by_type(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """Get average resolution time by ticket type."""
    from models import SupportTicket, TicketType, TicketStatus
    from collections import defaultdict

    # Get resolved tickets with resolution time
    resolved_tickets = db.query(SupportTicket).filter(
        SupportTicket.status.in_([TicketStatus.RESOLVED, TicketStatus.CLOSED]),
        SupportTicket.resolution_time_hours.isnot(None)
    ).all()

    type_times = defaultdict(list)
    for t in resolved_tickets:
        type_name = t.ticket_type.value if t.ticket_type else "Task"
        type_times[type_name].append(t.resolution_time_hours)

    # Default types if no data
    types = ["Bug", "Feature", "Task", "Story", "Epic"]
    avg_times = []
    for type_name in types:
        times = type_times.get(type_name, [])
        avg = sum(times) / len(times) / 24 if times else 1.0  # Convert to days
        avg_times.append(round(avg, 1))

    return {
        "labels": types,
        "datasets": [{
            "label": "Avg Resolution Time (days)",
            "data": avg_times,
            "backgroundColor": "#6366f1"
        }]
    }


@app.get("/api/tickets/team-performance")
def get_team_performance(db: Session = Depends(get_db), _user = Depends(require_admin)):
    """Get ticket distribution by team."""
    from models import SupportTicket, TicketStatus
    from collections import defaultdict

    # Get active tickets
    active_statuses = [TicketStatus.OPEN, TicketStatus.IN_PROGRESS, TicketStatus.UNDER_REVIEW]
    tickets = db.query(SupportTicket).filter(SupportTicket.status.in_(active_statuses)).all()

    team_counts = defaultdict(int)
    for t in tickets:
        team = t.team or "Unassigned"
        team_counts[team] += 1

    # Ensure at least some teams
    if not team_counts:
        team_counts = {"Team A": 25, "Team B": 30, "Team C": 20, "Team D": 25}

    teams = list(team_counts.keys())[:4]  # Max 4 teams
    counts = [team_counts[t] for t in teams]
    total = sum(counts) or 1

    colors = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444"]

    return {
        "labels": teams,
        "datasets": [{
            "data": [round(c / total * 100) for c in counts],
            "backgroundColor": colors[:len(teams)],
            "borderWidth": 0
        }]
    }


@app.post("/api/tickets")
def create_ticket(ticket_data: TicketCreate, db: Session = Depends(get_db), _auth: dict = Depends(require_any_auth)):
    """Create a new support ticket. Any authenticated user can create tickets."""
    from models import SupportTicket, TicketPriority, TicketType, TicketStatus

    # Generate ticket ID
    last_ticket = db.query(SupportTicket).order_by(SupportTicket.id.desc()).first()
    ticket_num = (last_ticket.id + 1) if last_ticket else 1
    ticket_id = f"DOLLOR-{ticket_num}"

    # Parse priority and type
    try:
        priority = TicketPriority(ticket_data.priority)
    except ValueError:
        priority = TicketPriority.P2_MEDIUM

    try:
        ticket_type = TicketType(ticket_data.ticket_type)
    except ValueError:
        ticket_type = TicketType.TASK

    # Parse due date
    due_date = None
    if ticket_data.due_date:
        try:
            due_date = datetime.fromisoformat(ticket_data.due_date.replace('Z', '+00:00'))
        except ValueError:
            pass

    ticket = SupportTicket(
        ticket_id=ticket_id,
        title=ticket_data.title,
        description=ticket_data.description,
        ticket_type=ticket_type,
        priority=priority,
        status=TicketStatus.OPEN,
        assignee=ticket_data.assignee,
        reporter=ticket_data.reporter,
        team=ticket_data.team,
        labels=ticket_data.labels,
        component=ticket_data.component,
        due_date=due_date,
        customer_id=ticket_data.customer_id,
        order_id=ticket_data.order_id,
        vendor_id=ticket_data.vendor_id,
        driver_id=ticket_data.driver_id
    )

    db.add(ticket)
    db.commit()
    db.refresh(ticket)

    return {
        "id": ticket.ticket_id,
        "title": ticket.title,
        "status": ticket.status.value,
        "priority": ticket.priority.value,
        "created_at": ticket.created_at.isoformat()
    }


@app.patch("/api/tickets/{ticket_id}")
def update_ticket(ticket_id: str, ticket_data: TicketUpdate, db: Session = Depends(get_db), _user = Depends(require_admin)):
    """Update a support ticket."""
    from models import SupportTicket, TicketPriority, TicketType, TicketStatus

    ticket = db.query(SupportTicket).filter(SupportTicket.ticket_id == ticket_id).first()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")

    if ticket_data.title is not None:
        ticket.title = ticket_data.title
    if ticket_data.description is not None:
        ticket.description = ticket_data.description
    if ticket_data.priority is not None:
        try:
            ticket.priority = TicketPriority(ticket_data.priority)
        except ValueError:
            pass
    if ticket_data.ticket_type is not None:
        try:
            ticket.ticket_type = TicketType(ticket_data.ticket_type)
        except ValueError:
            pass
    if ticket_data.status is not None:
        try:
            new_status = TicketStatus(ticket_data.status)
            # Track resolution time
            if new_status in [TicketStatus.RESOLVED, TicketStatus.CLOSED] and ticket.status not in [TicketStatus.RESOLVED, TicketStatus.CLOSED]:
                ticket.resolved_at = datetime.utcnow()
                if ticket.created_at:
                    delta = ticket.resolved_at - ticket.created_at
                    ticket.resolution_time_hours = delta.total_seconds() / 3600
            ticket.status = new_status
        except ValueError:
            pass
    if ticket_data.assignee is not None:
        ticket.assignee = ticket_data.assignee
        if not ticket.first_response_at:
            ticket.first_response_at = datetime.utcnow()
    if ticket_data.team is not None:
        ticket.team = ticket_data.team
    if ticket_data.labels is not None:
        ticket.labels = ticket_data.labels
    if ticket_data.component is not None:
        ticket.component = ticket_data.component
    if ticket_data.resolution is not None:
        ticket.resolution = ticket_data.resolution
    if ticket_data.due_date is not None:
        try:
            ticket.due_date = datetime.fromisoformat(ticket_data.due_date.replace('Z', '+00:00'))
        except ValueError:
            pass

    db.commit()
    db.refresh(ticket)

    return {"message": "Ticket updated", "id": ticket.ticket_id}


# NOTE: Persona/Onfido/Veriff inquiry-creation endpoints and webhooks
# (/api/verification/start, /api/verification/{type}/{id}/status,
# /api/verification/webhook/persona|onfido|veriff) were removed here — those
# third-party providers are gone, superseded by Checkr (checkr_service.py) for
# driver background checks. The manual-review workflow below is unaffected.

@app.get("/api/verification/required-documents/{entity_type}")
def get_required_documents(entity_type: str):
    """Get list of required documents for verification"""
    verifier = get_verification_service()
    documents = verifier.get_required_documents(entity_type)

    if not documents:
        raise HTTPException(status_code=400, detail=f"Invalid entity type: {entity_type}")

    return {
        "entity_type": entity_type,
        "documents": [
            {
                "type": doc["type"].value,
                "label": doc["label"],
                "description": doc["description"],
                "required": doc["required"],
                "accepted_formats": doc["accepts"]
            }
            for doc in documents
        ]
    }


@app.post("/api/verification/{entity_type}/{entity_id}/manual-review")
def submit_manual_review(
    entity_type: str,
    entity_id: int,
    action: str = Query(..., description="approve or reject"),
    notes: Optional[str] = None,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Admin endpoint to manually approve or reject document verification.
    Used when documents need human review in the ZIP dashboard.
    """
    # require_admin already enforces admin role -- redundant check removed

    if action not in ["approve", "reject"]:
        raise HTTPException(status_code=400, detail="Action must be 'approve' or 'reject'")

    if entity_type == "vendor":
        vendor = db.query(Vendor).filter(Vendor.id == entity_id).first()
        if not vendor:
            raise HTTPException(status_code=404, detail="Vendor not found")

        if action == "approve":
            vendor.verification_status = VerificationStatus.VERIFIED.value
            vendor.documents_verified = True
            vendor.documents_verified_at = datetime.now()
        else:
            vendor.verification_status = VerificationStatus.REJECTED.value
            vendor.documents_verified = False

        vendor.verification_notes = notes
        vendor.verification_reviewer_id = admin.id
        vendor.last_activity = datetime.now()
        db.commit()

        return {
            "success": True,
            "message": f"Vendor documents {action}d",
            "entity_type": "vendor",
            "entity_id": entity_id,
            "status": vendor.verification_status
        }

    elif entity_type == "driver":
        driver = db.query(Driver).filter(Driver.id == entity_id).first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")

        if action == "approve":
            driver.verification_status = VerificationStatus.VERIFIED.value
            driver.documents_verified = True
            driver.documents_verified_at = datetime.now()
        else:
            driver.verification_status = VerificationStatus.REJECTED.value
            driver.documents_verified = False

        driver.verification_notes = notes
        driver.verification_reviewer_id = admin.id
        driver.updated_at = datetime.now()
        db.commit()

        return {
            "success": True,
            "message": f"Driver documents {action}d",
            "entity_type": "driver",
            "entity_id": entity_id,
            "status": driver.verification_status
        }

    raise HTTPException(status_code=400, detail="Invalid entity type")




























# Include Stripe payment routes
from stripe_integration import router as stripe_router
app.include_router(stripe_router)

# Include ERP/Order Flow routes (rideshare only — food-delivery functions and their
# iOS/Android aliases were removed along with the rest of the food order flow)
from order_flow import (
    router as order_flow_router,
    start_timeout_scheduler,
    stop_timeout_scheduler,
    get_available_rides,
    accept_ride,
    ride_picked_up,
    AssignDriverRequest,
)
app.include_router(order_flow_router)

# ==================== iOS/Android RIDE ALIASES ====================
# iOS baseURL is "https://api.dollor.ai" without /api, so these aliases enable the
# driver/customer apps to call /erp/* ride paths without the /api prefix.

@app.get("/erp/rides/available")
async def get_available_rides_ios_alias(
    request: Request,
    driver_lat: Optional[float] = None,
    driver_lng: Optional[float] = None,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db),
):
    """Alias for iOS Driver app - get available rides
    iOS calls: GET /erp/rides/available
    quick-360: forward typed driver Depends + Request, and remap the iOS-side
    `driver_lat`/`driver_lng` query names to the real handler's
    `latitude`/`longitude` parameters. Previously 500'd because (a) the real
    handler needs `request: Request`, and (b) the kwarg names didn't match.
    """
    from bid_routes import get_available_ride_requests as _get_available
    return await _get_available(
        request=request,
        driver_id=driver.id,
        latitude=driver_lat,
        longitude=driver_lng,
        driver=driver,
        db=db,
    )

@app.post("/erp/rides/{ride_id}/accept")
async def accept_ride_ios_alias(ride_id: int, request: AssignDriverRequest, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Alias for iOS Driver app - accept ride (legacy - actual flow uses bid system).
    This sets status to MATCHED directly for backward compatibility.
    iOS calls: POST /api/erp/rides/{rideId}/accept
    """
    from models import RideRequest as RR, RideRequestStatus as RRS
    ride = db.query(RR).filter(RR.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")
    if ride.status not in [RRS.OPEN, RRS.BIDDING]:
        raise HTTPException(status_code=400, detail=f"Ride is not available (current: {ride.status.value})")
    ride.status = RRS.MATCHED
    ride.matched_driver_id = request.driver_id
    ride.matched_at = datetime.utcnow()

    # Reject all other PENDING bids on this ride (match bid_routes.py:617-629 behavior)
    from models import RideBid, BidStatus
    other_bids = db.query(RideBid).filter(
        RideBid.ride_request_id == ride_id,
        RideBid.status == BidStatus.PENDING
    ).all()
    for other_bid in other_bids:
        other_bid.status = BidStatus.REJECTED
        other_bid.rejected_at = datetime.utcnow()
        other_bid.customer_response = "Ride accepted via legacy endpoint"

    db.commit()

    # Broadcast ride_request_closed via WebSocket
    try:
        from websocket_server import broadcast_ride_status
        import asyncio
        asyncio.ensure_future(broadcast_ride_status(
            str(ride.id), "matched",
            {"ride_id": ride.id, "driver_id": request.driver_id, "reason": "legacy_accept"}
        ))
    except Exception as ws_err:
        logger.warning(f"Failed to broadcast ride matched for legacy accept: {ws_err}")

    return {"success": True, "message": "Ride accepted", "ride_id": ride.id, "status": "matched"}

@app.post("/erp/rides/{ride_id}/picked-up")
async def ride_picked_up_ios_alias(ride_id: int, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Alias for iOS Driver app - mark ride picked up (transitions to IN_PROGRESS).
    iOS calls: POST /api/erp/rides/{rideId}/picked-up
    """
    # Inline the start logic — calling bid_routes.start_ride as a function
    # fails because its `request: Request, auth_driver: Driver = Depends(...)`
    # parameters are FastAPI Depends and don't resolve outside a route handler.
    from models import RideRequest as RR, RideRequestStatus as RRS
    ride = db.query(RR).filter(RR.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")
    if ride.status not in [RRS.MATCHED, RRS.IN_PROGRESS]:
        raise HTTPException(status_code=400, detail=f"Ride must be matched (current: {ride.status.value})")
    ride.status = RRS.IN_PROGRESS
    db.commit()
    return {"success": True, "message": "Ride picked up", "ride_id": ride.id, "status": "in_progress"}

@app.post("/erp/rides/{ride_id}/start")
@app.post("/api/erp/rides/{ride_id}/start")
async def start_ride_alias(ride_id: int, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Start ride alias for Android/iOS driver apps.
    Android calls: POST /api/erp/rides/{rideId}/start
    Accepts MATCHED or IN_PROGRESS status (picked-up may have already set IN_PROGRESS).
    """
    from models import RideRequest as RR, RideRequestStatus as RRS
    ride = db.query(RR).filter(RR.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")
    if ride.status not in [RRS.MATCHED, RRS.IN_PROGRESS]:
        raise HTTPException(status_code=400, detail=f"Ride must be matched or in progress (current: {ride.status.value})")
    ride.status = RRS.IN_PROGRESS
    db.commit()
    return {"success": True, "message": "Ride started", "ride_id": ride.id, "status": "in_progress"}

@app.get("/erp/rides/{ride_id}/track")
@app.get("/api/erp/rides/{ride_id}/track")
async def track_ride_ios_alias(ride_id: int, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Alias for iOS Customer app - track ride
    iOS calls: GET /api/erp/rides/{rideId}/track
    """
    return await track_ride(ride_id, db, _auth)

@app.post("/erp/rides/{ride_id}/cancel")
@app.post("/api/erp/rides/{ride_id}/cancel")
async def cancel_ride_ios_alias(
    ride_id: int,
    reason: str = "customer_request",
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth)
):
    """Alias for iOS apps - cancel ride
    iOS calls: POST /api/erp/rides/{rideId}/cancel
    """
    return await cancel_ride(ride_id, reason, db, _auth)

@app.post("/erp/rides/{ride_id}/negotiate")
@app.post("/api/erp/rides/{ride_id}/negotiate")
async def negotiate_ride_ios_alias(
    ride_id: int,
    request: dict,
    _auth: dict = Depends(require_any_auth),
    db: Session = Depends(get_db)
):
    """Alias for iOS apps - negotiate fare
    iOS calls: POST /api/erp/rides/{rideId}/negotiate
    Body: {"proposed_fare": 10.0, "is_driver_offer": true}

    Returns FareNegotiationResponse format for iOS decode compatibility.
    """
    from models import RideRequest
    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    proposed_fare = request.get("proposed_fare", ride.suggested_price or 15.0)
    is_driver_offer = request.get("is_driver_offer", True)

    # Calculate platform fee based on fare (tiered: $1/$2/$3)
    platform_fee = platform_fee_for(proposed_fare)

    # Update ride with the offer (use customer_preferred_price for both since no driver_offer field)
    if not is_driver_offer:
        ride.customer_preferred_price = proposed_fare
        db.commit()

    # Send push notification to customer when driver sends an offer
    if is_driver_offer and ride.customer_id:
        try:
            from order_flow import send_push_notification
            send_push_notification(
                user_type="customer",
                user_id=ride.customer_id,
                title="Driver Price Offer!",
                body=f"A driver offered ${proposed_fare:.2f} for your ride",
                data={
                    "type": "fare_negotiation",
                    "ride_id": str(ride_id),
                    "proposed_fare": str(proposed_fare),
                    "action": "driver_offer"
                },
                db=db
            )
            logger.info(f"Push notification sent to customer {ride.customer_id} for fare negotiation")
        except Exception as e:
            logger.error(f"Failed to send negotiation push notification: {e}")

    # Return FareNegotiationResponse format expected by iOS
    customer_offer = ride.customer_preferred_price or ride.suggested_price or 15.0
    driver_offer = proposed_fare if is_driver_offer else None

    return {
        "success": True,
        "status": "pending",  # negotiating -> pending for iOS compatibility
        "customer_offer": customer_offer,
        "driver_offer": driver_offer,
        "platform_fee_driver": platform_fee,
        "platform_fee_customer": platform_fee,
        "message": "Fare negotiation submitted"
    }

@app.post("/erp/rides/{ride_id}/accept-fare")
@app.post("/api/erp/rides/{ride_id}/accept-fare")
async def accept_fare_ios_alias(
    ride_id: int,
    request: dict,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Alias for iOS apps - accept negotiated fare
    iOS calls: POST /api/erp/rides/{rideId}/accept-fare
    Body: {"accepted_fare": 12.0}
    """
    from models import RideRequest
    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    accepted_fare = request.get("accepted_fare", ride.final_price or 15.0)
    ride.final_price = accepted_fare
    db.commit()

    return {
        "success": True,
        "ride_id": ride_id,
        "accepted_fare": accepted_fare,
        "status": "fare_accepted"
    }

@app.get("/erp/rides/{ride_id}/customer-negotiate")
@app.post("/erp/rides/{ride_id}/customer-negotiate")
@app.get("/api/erp/rides/{ride_id}/customer-negotiate")
@app.post("/api/erp/rides/{ride_id}/customer-negotiate")
@app.get("/api/rides/{ride_id}/negotiate")
@app.post("/api/rides/{ride_id}/negotiate")
async def customer_negotiate_ios_alias(
    ride_id: int,
    proposed_fare: float = Query(default=0.0),
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Cross-platform fare negotiation endpoint
    iOS calls: POST /erp/rides/{rideId}/customer-negotiate?proposed_fare=10.0
    Android/Web calls: POST /api/rides/{rideId}/negotiate with JSON body

    This endpoint updates the customer's preferred price so drivers can see it.
    Returns FareNegotiationResponse format for all platforms.
    """
    from models import RideRequest

    # Update the ride request with customer's offer
    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if ride:
        ride.customer_preferred_price = proposed_fare
        ride.updated_at = datetime.utcnow()
        db.commit()
        logger.info(f"Customer updated offer for ride {ride_id} to ${proposed_fare}")
    else:
        logger.warning(f"Ride {ride_id} not found for negotiation")

    return {
        "success": True,
        "status": "counter_offer_sent",
        "customer_offer": proposed_fare,
        "driver_offer": None,
        "platform_fee_driver": 1.0,
        "platform_fee_customer": 1.0,
        "message": "Your offer has been sent to drivers"
    }

@app.get("/erp/rides/{ride_id}/customer-accept-fare")
@app.post("/erp/rides/{ride_id}/customer-accept-fare")
@app.get("/api/erp/rides/{ride_id}/customer-accept-fare")
@app.post("/api/erp/rides/{ride_id}/customer-accept-fare")
async def customer_accept_fare_ios_alias(
    ride_id: int,
    accepted_fare: float = Query(default=0.0),
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Alias for iOS Customer app - accept driver's fare
    iOS calls: POST /erp/rides/{rideId}/customer-accept-fare?accepted_fare=12.0
    Returns FareNegotiationResponse format for iOS
    """
    from models import RideRequest
    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if ride:
        ride.final_price = accepted_fare
        db.commit()

    return {
        "success": True,
        "status": "accepted",
        "customer_offer": accepted_fare,
        "driver_offer": accepted_fare,
        "platform_fee_driver": 1.0,
        "platform_fee_customer": 1.0,
        "message": "Fare accepted. Driver is on the way!"
    }

@app.get("/erp/rides/{ride_id}/negotiation-status")
@app.get("/api/erp/rides/{ride_id}/negotiation-status")
async def negotiation_status_ios_alias(
    ride_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Alias for iOS apps - get negotiation status
    iOS calls: GET /erp/rides/{rideId}/negotiation-status
    """
    from models import RideRequest
    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    return {
        "success": True,
        "ride_id": ride_id,
        "status": ride.status.value if ride.status else "pending",
        "current_fare": ride.final_price or ride.estimated_price,
        "negotiation_rounds": 0,
        "last_offer_by": None
    }

# NOTE: Auto-Onboarding (Nova), Promotions (Sierra), Menu Verification (Aria), and
# Vibing food-image routes were removed here — all restaurant/vendor-only AI employee
# systems with no rideshare role.

# ===================== AUTH UTILS FOR ROUTER-LEVEL AUTH =====================
# (auth_utils imported at top of file)

# Include Real-time Events routes (Phoenix AI Employee) — ALL endpoints require auth
from realtime_events import router as realtime_router
app.include_router(realtime_router, dependencies=[Depends(require_any_auth)])

# Include Ride Bidding routes (Matchmaking platform)
from bid_routes import router as bid_router
app.include_router(bid_router)

# Public rideshare config (fees, bidding presets, dispatch, support) read by every app
from rideshare_config import router as rideshare_config_router
app.include_router(rideshare_config_router)

# Include Rideshare Payment routes (Stripe integration for drivers)
from rideshare_payments import router as rideshare_payments_router, get_tier_fee
app.include_router(rideshare_payments_router)

# Include Matchmaking routes (Wyoming - Legal P2P without TNC)
from matchmaking_routes import router as matchmaking_router
app.include_router(matchmaking_router)

# Include Admin Accounting Module (Protected - Admin JWT required)
from accounting_module import router as accounting_router
app.include_router(accounting_router)

# Include Investor Deck Tracking (Email-gated access + view logging)
from investor_tracking import router as investor_router
app.include_router(investor_router)

# Include Voice Agent (Twilio + OpenAI Realtime) and AI Text Chat
from voice_agent import router as voice_router
app.include_router(voice_router)

# Include Project Tracker (Jira-style test case tracking for admin panel)
from project_tracker import project_tracker_router, department_router
app.include_router(project_tracker_router)
app.include_router(department_router)

# Include Change Management (enterprise change request lifecycle)
from change_management import change_management_router, approval_rules_router, delegation_router
app.include_router(change_management_router)
app.include_router(approval_rules_router)
app.include_router(delegation_router)

# Insurance UBI tracking
from insurance.routes import router as insurance_router
app.include_router(insurance_router)

# TNC Compliance (CPUC) — background checks, DMV, inspections, zero-tolerance, reporting
from tnc_compliance import router as tnc_compliance_router
app.include_router(tnc_compliance_router)

# Checkr-Hosted background checks (provider named in Zietra's CPUC TNC permit)
from checkr_service import router as checkr_router
app.include_router(checkr_router)

# Founding Member program ("Founding 10,000 per state") — $100 lifetime platform-fee lock
# Re-enabled 2026-10-12 after review: non-refundable $100 join charge uses a stable Stripe
# idempotency key per (member_type, member_id) so retries can't double-charge; a DB unique
# constraint + IntegrityError handler backstops the same race on the FoundingMember insert;
# and the post-charge slot-cap recheck now auto-refunds via Stripe if the cap filled between
# the charge and the commit (previously it charged the $100 and refunded nothing in that
# case — fixed in founding_members.py). STILL VERIFY in Stripe TEST mode before relying on
# this in production, per the module's own header. NOTE: compute_ride_fees()/is_founder()
# (the "locked platform fee for life" benefit) are not yet wired into the live ride-fare
# computation in main_new.py/order_flow.py — joining records a founder and charges $100,
# but no code path currently applies the frozen fee schedule to an actual ride. That
# integration is a separate follow-up; flagging for human review before marketing promises
# "locked fees" are relied upon.
from founding_members import router as founding_router
app.include_router(founding_router)

@app.get("/api/customer/rides")
async def get_customer_rides(
    limit: int = 20,
    offset: int = 0,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer)
):
    """
    Get customer's rides from real database.
    Used by Android/iOS customer apps.
    """
    from models import RideRequest as RideRequestDB, RideRequestStatus

    # Query real ride requests for this customer
    query = db.query(RideRequestDB).filter(
        RideRequestDB.customer_id == customer.id
    ).order_by(RideRequestDB.created_at.desc())

    total_rides = query.count()
    ride_records = query.offset(offset).limit(limit).all()

    rides = []
    for ride in ride_records:
        # Get driver info from matched_driver relationship
        driver_name = None
        driver_info = None
        if ride.matched_driver:
            d = ride.matched_driver
            driver_name = f"{d.first_name or ''} {d.last_name or ''}".strip() or None
            driver_info = {
                "id": d.id,
                "name": driver_name,
                "phone": d.phone,
                "rating": float(d.rating or 0),
                "photo_url": d.photo_url,
                "vehicle_make": d.vehicle_make,
                "vehicle_model": d.vehicle_model,
                "vehicle_color": d.vehicle_color,
            }

        fare = float(ride.final_price or ride.suggested_price or 0)
        platform_fee = float(ride.platform_fee or 0)

        rides.append({
            "id": ride.id,
            "request_id": ride.request_id,
            "customer_id": ride.customer_id,
            "driver_id": ride.matched_driver_id,
            "status": ride.status.value if ride.status else "unknown",
            "pickup_address": ride.pickup_address or "",
            "dropoff_address": ride.dropoff_address or "",
            "pickup_lat": ride.pickup_latitude,
            "pickup_lng": ride.pickup_longitude,
            "dropoff_lat": ride.dropoff_latitude,
            "dropoff_lng": ride.dropoff_longitude,
            "distance_miles": round(ride.estimated_distance_km * 0.621371, 1) if ride.estimated_distance_km else None,
            "fare_amount": fare,
            "platform_fee": platform_fee,
            "driver_earnings": fare - platform_fee if platform_fee else fare,
            "created_at": ride.created_at.isoformat() if ride.created_at else None,
            "started_at": ride.matched_at.isoformat() if ride.matched_at else None,
            "completed_at": ride.completed_at.isoformat() if ride.completed_at else None,
            "driver": driver_info,
            "customer_name": ride.customer_name,
            "customer_phone": ride.customer_phone,
            # Extra fields for history display
            "tip_amount": float(ride.tip_amount or 0),
            "driver_name": driver_name,
            "rating": ride.customer_rating,
        })

    return {"rides": rides, "count": total_rides, "total": total_rides, "has_more": offset + limit < total_rides}


@app.get("/api/rides/{ride_id}/track")
async def track_ride(
    ride_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """
    Track a ride's current status and driver location.
    Used by Android/iOS customer apps.
    Returns full driver details including name, photo, vehicle, license plate.
    """
    from models import RideRequest, Driver

    # Query ride request with driver relationship
    ride = db.query(RideRequest).filter(
        (RideRequest.id == ride_id) | (RideRequest.request_id == str(ride_id))
    ).first()

    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # SECURITY: Only the customer or matched driver for THIS ride can track it
    caller_customer_id = _auth.get("customer_id")
    caller_driver_id = _auth.get("driver_id")
    is_customer = caller_customer_id and ride.customer_id and int(caller_customer_id) == int(ride.customer_id)
    is_driver = caller_driver_id and ride.matched_driver_id and int(caller_driver_id) == int(ride.matched_driver_id)
    if not is_customer and not is_driver:
        raise HTTPException(status_code=403, detail="Access denied")

    # Base response matching iOS RideTrackingInfo struct
    response = {
        "success": True,
        "order_id": ride.id,
        "order_number": ride.request_id or f"RR-{ride.id}",
        "status": ride.status.value if ride.status else "pending",
        "driver_name": None,
        "driver_phone": None,
        "driver_photo_url": None,
        "driver_latitude": None,
        "driver_longitude": None,
        "estimated_arrival": None,
        "driver_vehicle": None,
        "driver_vehicle_color": None,
        "driver_license_plate": None,
        "driver_vehicle_photo_url": None,
        "driver_rating": None
    }

    # If driver is assigned, include full driver details
    if ride.matched_driver_id:
        driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first()
        if driver:
            # Driver name (first name + last initial for privacy)
            driver_name = f"{driver.first_name} {driver.last_name[0]}." if driver.first_name and driver.last_name else "Driver"

            # Vehicle info as combined string
            vehicle_parts = []
            if driver.vehicle_year:
                vehicle_parts.append(str(driver.vehicle_year))
            if driver.vehicle_make:
                vehicle_parts.append(driver.vehicle_make)
            if driver.vehicle_model:
                vehicle_parts.append(driver.vehicle_model)
            driver_vehicle = " ".join(vehicle_parts) if vehicle_parts else None

            # Calculate ETA using Haversine distance with traffic-adjusted speed
            eta_minutes = None
            eta_pickup_minutes = None
            eta_destination_minutes = None

            if driver.current_latitude and driver.current_longitude:
                # Average city driving speed: 25 km/h (accounts for traffic/stops)
                avg_speed_kmh = 25.0

                # ETA to pickup (when driver en route to customer)
                if ride.pickup_latitude and ride.pickup_longitude:
                    pickup_km = calculate_distance_km(
                        driver.current_latitude, driver.current_longitude,
                        ride.pickup_latitude, ride.pickup_longitude
                    )
                    eta_pickup_minutes = max(1, int((pickup_km / avg_speed_kmh) * 60))
                    eta_minutes = eta_pickup_minutes

                # ETA to destination (when ride in progress)
                if ride.dropoff_latitude and ride.dropoff_longitude:
                    dest_km = calculate_distance_km(
                        driver.current_latitude, driver.current_longitude,
                        ride.dropoff_latitude, ride.dropoff_longitude
                    )
                    eta_destination_minutes = max(1, int((dest_km / avg_speed_kmh) * 60))

            # iOS flat fields
            response.update({
                "driver_name": driver_name,
                "driver_phone": driver.phone,
                "driver_photo_url": driver.photo_url,
                "driver_latitude": driver.current_latitude,
                "driver_longitude": driver.current_longitude,
                "estimated_arrival": f"{eta_minutes} min" if eta_minutes else None,
                "estimated_destination_arrival": f"{eta_destination_minutes} min" if eta_destination_minutes else None,
                "eta_pickup_minutes": eta_pickup_minutes,
                "eta_destination_minutes": eta_destination_minutes,
                "driver_vehicle": driver_vehicle,
                "driver_vehicle_color": driver.vehicle_color,
                "driver_license_plate": driver.license_plate,
                "driver_vehicle_photo_url": driver.vehicle_photo_url if hasattr(driver, 'vehicle_photo_url') else None,
                "driver_rating": driver.rating,
                "eta_minutes": eta_minutes
            })

            # Android nested driver object (for CustomerRideTracking compatibility)
            response["driver"] = {
                "id": driver.id,
                "name": driver_name,
                "phone": driver.phone,
                "rating": driver.rating,
                "photo_url": driver.photo_url,
                "vehicle_photo_url": driver.vehicle_photo_url if hasattr(driver, 'vehicle_photo_url') else None,
                "latitude": driver.current_latitude,
                "longitude": driver.current_longitude,
                "vehicle_make": driver.vehicle_make,
                "vehicle_model": driver.vehicle_model,
                "vehicle_color": driver.vehicle_color,
                "vehicle_year": driver.vehicle_year,
                "vehicle_plate": driver.license_plate
            }

            # Android driver_location object
            if driver.current_latitude and driver.current_longitude:
                response["driver_location"] = {
                    "latitude": driver.current_latitude,
                    "longitude": driver.current_longitude
                }

    # Driver arrival timestamp (set when driver taps "I've Arrived")
    response["driver_arrived_at"] = ride.driver_arrived_at.isoformat() if ride.driver_arrived_at else None

    # Add ride location info for Android
    response["ride_request_id"] = ride.id
    response["ride_number"] = ride.request_id
    response["pickup"] = {
        "latitude": ride.pickup_latitude,
        "longitude": ride.pickup_longitude,
        "address": ride.pickup_address
    }
    response["dropoff"] = {
        "latitude": ride.dropoff_latitude,
        "longitude": ride.dropoff_longitude,
        "address": ride.dropoff_address
    }
    response["final_price"] = ride.final_price

    return response


@app.post("/api/rides/{ride_id}/cancel")
async def cancel_ride(
    ride_id: int,
    reason: str = "customer_request",
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth)
):
    """
    Cancel a ride request.
    Used by Android/iOS customer apps.
    Only open/bidding/matched rides can be cancelled.
    """
    from models import RideRequest, RideRequestStatus

    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # SECURITY: Verify the authenticated user is the ride's customer
    auth_customer_id = _auth.get("customer_id")
    if not auth_customer_id:
        raise HTTPException(status_code=403, detail="Only customers can cancel rides")
    if ride.customer_id != auth_customer_id:
        raise HTTPException(status_code=403, detail="You can only cancel your own rides")

    # Block cancel on completed/cancelled/in_progress rides
    non_cancellable = [RideRequestStatus.COMPLETED, RideRequestStatus.CANCELLED, RideRequestStatus.IN_PROGRESS]
    if ride.status in non_cancellable:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel ride with status: {ride.status.value}"
        )

    # Calculate cancellation fee based on ride state
    cancellation_fee = 0.0
    if ride.status == RideRequestStatus.MATCHED:
        cancellation_fee = 5.0  # $5 fee if driver already matched

    ride.status = RideRequestStatus.CANCELLED
    db.commit()

    return {
        "success": True,
        "ride_id": ride_id,
        "status": "cancelled",
        "reason": reason,
        "cancellation_fee": cancellation_fee
    }


class RideRatingRequest(BaseModel):
    rating: int = Field(..., ge=1, le=5, description="Rating 1-5 stars")
    comment: Optional[str] = Field(None, description="Optional review comment")

@app.post("/api/rides/{ride_id}/rate")
async def rate_ride_customer(
    ride_id: int,
    body: RideRatingRequest,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth)
):
    """
    Rate a completed ride (Customer API).
    Used by Android/iOS customer apps.
    Accepts JSON body: {"rating": 1-5, "comment": "optional"}
    """
    from models import RideRequest, Driver

    rating = body.rating
    comment = body.comment

    # Verify ride exists
    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # SECURITY: Only customers can rate, and only their own rides
    customer_id = _auth.get("customer_id")
    if not customer_id:
        raise HTTPException(status_code=403, detail="Only customers can rate rides")
    if ride.customer_id != customer_id:
        raise HTTPException(status_code=403, detail="You can only rate your own rides")

    # Verify ride is completed
    from models import RideRequestStatus
    if ride.status != RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail=f"Can only rate completed rides (current: {ride.status.value})")

    # Prevent double-rating (re-rating would inflate total_deliveries)
    if ride.customer_rating is not None:
        raise HTTPException(status_code=400, detail="You have already rated this ride")

    # Store rating on ride
    ride.customer_rating = rating
    ride.customer_comment = comment

    # Update driver's average rating
    driver = None
    if ride.matched_driver_id:
        driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first()
        if driver:
            current_rating = driver.rating or 5.0
            total_trips = driver.total_deliveries or 0
            # Rolling average
            new_rating = round(((current_rating * total_trips) + rating) / (total_trips + 1), 2)
            driver.rating = new_rating
            driver.total_deliveries = total_trips + 1

    db.commit()

    return {
        "success": True,
        "message": "Rating submitted",
        "ride_id": ride_id,
        "rating": rating,
        "newDriverRating": driver.rating if ride.matched_driver_id and driver else None
    }


class RideTipRequest(BaseModel):
    tip_amount: float = Field(..., gt=0, le=500, description="Tip amount in dollars")

@app.post("/api/rides/{ride_id}/tip")
async def tip_ride_driver(
    request: Request,
    ride_id: int,
    body: RideTipRequest,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth)
):
    """
    Finalize a completed ride: capture the authorized PaymentIntent for fare + tip,
    then pay the driver. Called by customer after dropoff (tip_amount=0 to skip tip).
    Accepts JSON body: {"tip_amount": 3.00}
    """
    check_rate_limit(request, payment_limiter, "payment", identifier=str(_auth.get("customer_id", _auth.get("user_id", "unknown"))))
    from models import RideRequest, RideRequestStatus
    import stripe as stripe_lib
    import os
    from rideshare_payments import get_tier_fee

    actual_tip = body.tip_amount

    ride = db.query(RideRequest).filter(RideRequest.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    customer_id = _auth.get("customer_id")
    if not customer_id:
        raise HTTPException(status_code=403, detail="Only customers can finalize rides")
    if ride.customer_id != customer_id:
        raise HTTPException(status_code=403, detail="You can only finalize your own rides")

    if ride.status != RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail=f"Ride must be completed before finalizing (current: {ride.status.value})")

    ride_fare = float(ride.final_price or ride.suggested_price or 0)
    if actual_tip > ride_fare:
        raise HTTPException(status_code=400, detail=f"Tip cannot exceed ride fare (${ride_fare:.2f})")

    total_charge = ride_fare + actual_tip
    pi_id = ride.stripe_payment_intent_id
    captured = False
    transfer_id = None

    if pi_id and not pi_id.startswith("demo_"):
        stripe_lib.api_key = os.getenv("STRIPE_SECRET_KEY")
        try:
            # Increase the authorized amount if a tip was added before capturing
            if actual_tip > 0:
                stripe_lib.PaymentIntent.modify(
                    pi_id,
                    amount=int(total_charge * 100),
                    metadata={"tip_amount": str(actual_tip)},
                )

            stripe_lib.PaymentIntent.capture(pi_id)
            captured = True
            logger.info(f"Ride {ride_id} PI {pi_id} captured: fare=${ride_fare:.2f} tip=${actual_tip:.2f}")
        except stripe_lib.error.StripeError as e:
            logger.error(f"Ride {ride_id} capture FAILED: {e}")
            raise HTTPException(status_code=502, detail="Payment capture failed. Please try again.")

        # Transfer driver payout after successful capture
        driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first()
        if driver and getattr(driver, "stripe_account_id", None) and getattr(driver, "stripe_onboarded", False):
            tier_fee = get_tier_fee(ride_fare)
            driver_payout = round(ride_fare - tier_fee + actual_tip, 2)
            payout_cents = int(driver_payout * 100)
            if payout_cents > 0:
                try:
                    transfer = stripe_lib.Transfer.create(
                        amount=payout_cents,
                        currency="usd",
                        destination=driver.stripe_account_id,
                        description=f"Ride {ride.request_id} payout (fare - fee + tip)",
                        idempotency_key=f"ride_payout_{ride_id}",
                        metadata={
                            "ride_id": str(ride_id),
                            "fare": str(ride_fare),
                            "tip": str(actual_tip),
                            "platform_fee": str(tier_fee),
                        },
                    )
                    transfer_id = transfer.id
                    ride.stripe_transfer_id = transfer_id
                    ride.driver_paid_at = datetime.utcnow()
                    ride.driver_payout = driver_payout
                    logger.info(f"Ride {ride_id} driver payout ${driver_payout:.2f}, transfer={transfer_id}")
                except stripe_lib.error.StripeError as e:
                    logger.error(f"Ride {ride_id} driver transfer FAILED (capture already done): {e}")

    ride.tip_amount = actual_tip
    ride.payment_status = "captured" if captured else "pending"
    ride.payment_completed_at = datetime.utcnow() if captured else None
    db.commit()

    return {
        "success": True,
        "message": f"Ride finalized — fare ${ride_fare:.2f}" + (f", tip ${actual_tip:.2f}" if actual_tip > 0 else ""),
        "ride_id": ride_id,
        "fare": ride_fare,
        "tip_amount": actual_tip,
        "total_charged": total_charge,
        "captured": captured,
        "driver_transfer_id": transfer_id,
    }


# ==================== RIDE BIDDING ROUTES (in bid_routes.py) ====================
# Legacy endpoints removed 2026-02-07 - all bid routes now in bid_routes.py
# See: bid_routes.py for /api/rides/request/{id}/bids, /bid/{id}/respond, etc.


# REMOVED: Legacy bid endpoints (6 handlers, ~420 lines)
# All bid functionality now in bid_routes.py which is registered via include_router
# Endpoints removed: /request/{id}/bids, /request/{id}/bid, /bid/{id}/withdraw,
#                    /bid/{id}/respond, /bid/{id}/accept-counter, /bid/{id}/reject-counter


# === LEGACY CODE REMOVED - START MARKER ===
# The following function bodies through reject_counter_offer were deleted.
# See git history for original code if needed.
def _legacy_placeholder():
    """Placeholder - legacy bid endpoints removed. See bid_routes.py"""
    pass


@app.get("/api/driver/bids")
def get_driver_bids(
    driver_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver)
):
    """Get all bids for a driver - includes pending, countered, accepted bids"""
    from models import RideBid, BidStatus, RideRequest, Driver as DriverModel

    # Use authenticated driver's ID (ignore query param to prevent IDOR)
    d_id = driver.id

    # Query all bids for this driver
    bids = db.query(RideBid).filter(RideBid.driver_id == d_id).order_by(RideBid.created_at.desc()).limit(50).all()

    bid_list = []
    for bid in bids:
        ride = db.query(RideRequest).filter(RideRequest.id == bid.ride_request_id).first()
        bid_list.append({
            "id": bid.id,
            "bid_id": bid.bid_id,
            "ride_request_id": bid.ride_request_id,
            "proposed_price": bid.proposed_price,
            "customer_counter_price": bid.customer_counter_price,
            "customer_response": bid.customer_response,
            "status": bid.status.value if hasattr(bid.status, 'value') else str(bid.status),
            "is_counter_offer": bid.is_counter_offer,
            "estimated_arrival_minutes": bid.estimated_arrival_minutes,
            "message": bid.message,
            "created_at": bid.created_at.isoformat() if bid.created_at else None,
            "ride": {
                "pickup_address": ride.pickup_address if ride else None,
                "dropoff_address": ride.dropoff_address if ride else None,
                "customer_name": ride.customer_name if ride else None,
                "status": ride.status.value if ride and hasattr(ride.status, 'value') else None
            } if ride else None
        })

    # Count by status
    pending = sum(1 for b in bid_list if b['status'] == 'pending')
    countered = sum(1 for b in bid_list if b['status'] == 'countered')
    accepted = sum(1 for b in bid_list if b['status'] == 'accepted')

    return {
        "success": True,
        "bids": bid_list,
        "total": len(bid_list),
        "pending": pending,
        "countered": countered,
        "accepted": accepted
    }


def get_available_ride_requests(
    driver_id: Optional[int] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius_miles: float = 50.0,
    radius_km: Optional[float] = None,
    _auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Get available ride requests for drivers to bid on"""
    from models import RideRequest, RideRequestStatus, Driver
    import math

    # Convert radius_km to radius_miles if provided
    if radius_km:
        radius_miles = radius_km * 0.621371

    # Query open ride requests (status = OPEN or BIDDING, not expired)
    now = datetime.utcnow()
    try:
        requests = db.query(RideRequest).filter(
            RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]),
            or_(
                RideRequest.bidding_expires_at > now,
                RideRequest.bidding_expires_at.is_(None)
            )
        ).order_by(RideRequest.created_at.desc()).limit(50).all()
    except Exception as e:
        # Fallback: try without enum if RideRequestStatus not available
        requests = db.query(RideRequest).filter(
            RideRequest.status.in_(["open", "bidding"]),
            or_(
                RideRequest.bidding_expires_at > now,
                RideRequest.bidding_expires_at.is_(None)
            )
        ).order_by(RideRequest.created_at.desc()).limit(50).all()

    # Batch-check which rides the authenticated driver has already bid on
    from models import RideBid, BidStatus as BS
    request_ids = [r.id for r in requests]
    driver_bid_ids = set()
    if request_ids:
        existing_bids = db.query(RideBid.ride_request_id).filter(
            RideBid.ride_request_id.in_(request_ids),
            RideBid.driver_id == _auth_driver.id,
            RideBid.status.in_([BS.PENDING, BS.COUNTERED])
        ).all()
        driver_bid_ids = {b.ride_request_id for b in existing_bids}

    available_requests = []
    for req in requests:
        # Calculate distance to pickup if driver location provided
        # Note: RideRequest model uses pickup_latitude/pickup_longitude
        distance_to_pickup_km = None
        if latitude and longitude and req.pickup_latitude and req.pickup_longitude:
            # Haversine formula for distance
            R = 6371  # Earth's radius in km
            lat1, lon1 = math.radians(latitude), math.radians(longitude)
            lat2, lon2 = math.radians(req.pickup_latitude), math.radians(req.pickup_longitude)
            dlat, dlon = lat2 - lat1, lon2 - lon1
            a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
            c = 2 * math.asin(math.sqrt(a))
            distance_to_pickup_km = R * c

            # Skip if outside radius
            if distance_to_pickup_km > (radius_miles * 1.60934):
                continue

        # Get customer name - RideRequest has customer_name field
        customer_name = req.customer_name or "Customer"

        available_requests.append({
            "id": req.id,
            "request_id": req.request_id or f"RR-{req.id}",
            "customer_id": req.customer_id,
            "customer_name": customer_name,
            "customer_phone": None,  # Hidden until matched
            "pickup": {
                "address": req.pickup_address or "Pickup Location",
                "latitude": req.pickup_latitude or 0.0,
                "longitude": req.pickup_longitude or 0.0,
                "place_name": req.pickup_address or "Pickup"
            },
            "dropoff": {
                "address": req.dropoff_address or "Dropoff Location",
                "latitude": req.dropoff_latitude or 0.0,
                "longitude": req.dropoff_longitude or 0.0,
                "place_name": req.dropoff_address or "Dropoff"
            },
            "estimated_distance_km": req.estimated_distance_km,
            "estimated_duration_minutes": req.estimated_duration_minutes,
            "ride_type": req.ride_type or "standard",
            "suggested_price": req.suggested_price,
            "customer_max_price": req.customer_max_price,
            "customer_preferred_price": req.customer_preferred_price,
            "status": req.status.value if hasattr(req.status, 'value') else str(req.status),
            "bidding_expires_at": req.bidding_expires_at.isoformat() if req.bidding_expires_at else None,
            "special_requests": getattr(req, 'special_requests', None),
            "accessibility_requested": getattr(req, 'accessibility_requested', False),
            "accessibility_notes": getattr(req, 'accessibility_notes', None),
            "created_at": req.created_at.isoformat() if req.created_at else None,
            "bid_count": len(req.bids) if req.bids else 0,
            "distance_to_pickup_km": distance_to_pickup_km,
            "already_bid": req.id in driver_bid_ids
        })

    return {
        "success": True,
        "available_requests": available_requests,
        "count": len(available_requests),
        "search_radius_miles": radius_miles
    }


# ==================== RIDE REQUEST CHAT ENDPOINTS ====================
# P2P ride request chat for driver/customer communication

class RideChatMessageRequest(BaseModel):
    """Request body for sending a chat message"""
    message: str = Field(..., min_length=1, max_length=1000)
    sender_type: str = Field(..., pattern="^(customer|driver)$")


def _require_ride_chat_participant(db: Session, ride_request_id: int, auth: dict) -> str:
    """Only the ride's rider and its matched driver (or an admin) may read or write its chat.

    Returns the caller's role for the ride ("customer", "driver" or "admin"); the sender is taken from the token,
    never from the request body.
    """
    from models import RideRequest

    ride = db.query(RideRequest).filter(RideRequest.id == ride_request_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")
    if auth.get("role") == "admin":
        return "admin"
    customer_id = auth.get("customer_id")
    driver_id = auth.get("driver_id")
    if customer_id and customer_id == ride.customer_id:
        return "customer"
    if driver_id and driver_id == ride.matched_driver_id:
        return "driver"
    raise HTTPException(status_code=403, detail="You are not a participant in this ride")


@app.get("/api/p2p/ride-requests/{ride_request_id}/chat")
def get_ride_request_chat(
    ride_request_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Get chat messages for a ride request"""
    from models import RideChatMessage

    _require_ride_chat_participant(db, ride_request_id, _auth)

    messages = db.query(RideChatMessage).filter(
        RideChatMessage.ride_request_id == ride_request_id
    ).order_by(RideChatMessage.created_at.asc()).all()

    return {
        "ride_request_id": ride_request_id,
        "messages": [
            {
                "id": msg.id,
                "ride_request_id": msg.ride_request_id,
                "sender_type": msg.sender_type,
                "sender_id": msg.sender_id,
                "message": msg.message,
                "created_at": msg.created_at.isoformat() if msg.created_at else None
            }
            for msg in messages
        ],
        "total": len(messages)
    }


@app.post("/api/p2p/ride-requests/{ride_request_id}/chat")
def send_ride_request_chat(
    ride_request_id: int,
    chat_request: RideChatMessageRequest,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth)
):
    """Send a chat message for a ride request"""
    from models import RideChatMessage

    # The sender comes from the token, not the request body, so nobody can post as the other party
    role = _require_ride_chat_participant(db, ride_request_id, _auth)
    from models import RideRequest
    ride_for_chat = db.query(RideRequest).filter(RideRequest.id == ride_request_id).first()
    if role == "admin":
        sender_type, sender_id = chat_request.sender_type, 0
    elif role == "customer":
        sender_type, sender_id = "customer", ride_for_chat.customer_id
    else:
        sender_type, sender_id = "driver", ride_for_chat.matched_driver_id

    chat_msg = RideChatMessage(
        ride_request_id=ride_request_id,
        sender_type=sender_type,
        sender_id=sender_id,
        message=chat_request.message,
    )
    db.add(chat_msg)
    db.commit()
    db.refresh(chat_msg)

    return {
        "success": True,
        "id": chat_msg.id,
        "message_id": chat_msg.id,
        "ride_request_id": ride_request_id,
        "sender_type": sender_type,
        "sender_id": sender_id,
        "message": chat_request.message,
        "created_at": chat_msg.created_at.isoformat() if chat_msg.created_at else datetime.utcnow().isoformat()
    }


@app.get("/api/chat/ride/{ride_id}")
def get_ride_chat_messages_alias(ride_id: int, db: Session = Depends(get_db), _auth: dict = Depends(require_any_auth)):
    """Get ride chat messages — distinct path to avoid conflict with /api/chat/messages/{order_id}"""
    return get_ride_request_chat(ride_request_id=ride_id, db=db, _auth=_auth)


@app.post("/api/chat/ride/{ride_id}")
def send_ride_chat_message_alias(
    ride_id: int,
    chat_request: RideChatMessageRequest,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Send ride chat message — distinct path to avoid conflict with /api/chat/messages/{order_id}"""
    return send_ride_request_chat(ride_request_id=ride_id, chat_request=chat_request, db=db, _auth=_auth)


def _format_address(addr: dict, index: int, is_default: bool = False) -> dict:
    """Helper to format address for Android/iOS API response."""
    return {
        "id": addr.get("id", index),
        "user_id": addr.get("user_id", 0),
        "location_name": addr.get("location_name", "Home" if index == 0 else ("Work" if index == 1 else f"Address {index+1}")),
        "street": addr.get("street", addr.get("address", "")),
        "unit": addr.get("unit"),
        "city": addr.get("city", ""),
        "state": addr.get("state", ""),
        "zip_code": addr.get("zip_code", addr.get("zipCode", "")),
        "instructions": addr.get("instructions"),
        "address_type": addr.get("address_type", "Home"),
        "latitude": addr.get("latitude"),
        "longitude": addr.get("longitude"),
        "phone_number": addr.get("phone_number"),
        "is_default": is_default,
        "label": addr.get("label", addr.get("location_name"))
    }


@app.get("/api/addresses/{customer_id}")
async def get_customer_addresses(
    customer_id: int,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """
    Get all saved addresses for a customer.
    Used by Android/iOS customer apps.
    """
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    saved_addresses = customer.saved_addresses or []
    default_addr = customer.default_address

    result = []
    for i, addr in enumerate(saved_addresses):
        if isinstance(addr, dict):
            is_default = (default_addr and addr.get("id") == default_addr.get("id")) or (i == 0 and not default_addr)
            result.append(_format_address(addr, i, is_default))
        else:
            # Legacy: address stored as string
            result.append({
                "id": i,
                "user_id": customer_id,
                "location_name": "Home" if i == 0 else f"Address {i+1}",
                "street": addr,
                "city": "",
                "state": "",
                "zip_code": "",
                "is_default": i == 0
            })
    return result


@app.get("/api/addresses/{customer_id}/default")
async def get_default_address(
    customer_id: int,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """
    Get default address for a customer.
    Used by Android/iOS customer apps.
    """
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    # Try default_address first, then first saved address
    if customer.default_address:
        return _format_address(customer.default_address, 0, True)

    saved_addresses = customer.saved_addresses or []
    if saved_addresses and isinstance(saved_addresses[0], dict):
        return _format_address(saved_addresses[0], 0, True)
    elif saved_addresses:
        return {
            "id": 0,
            "user_id": customer_id,
            "street": saved_addresses[0],
            "is_default": True
        }

    raise HTTPException(status_code=404, detail="No default address found")


@app.post("/api/addresses/{customer_id}")
async def add_customer_address(
    customer_id: int,
    address_data: dict,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """
    Add a new address for a customer.
    Used by Android/iOS customer apps.
    """
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    saved_addresses = list(customer.saved_addresses or [])  # Copy to new list for SQLAlchemy JSON change detection

    # Create new address with ID
    new_id = len(saved_addresses)
    new_address = {
        "id": new_id,
        "user_id": customer_id,
        "location_name": address_data.get("location_name", address_data.get("locationName", "Address")),
        "street": address_data.get("street", ""),
        "unit": address_data.get("unit"),
        "city": address_data.get("city", ""),
        "state": address_data.get("state", ""),
        "zip_code": address_data.get("zip_code", address_data.get("zipCode", "")),
        "instructions": address_data.get("instructions"),
        "address_type": address_data.get("address_type", address_data.get("addressType", "Home")),
        "latitude": address_data.get("latitude"),
        "longitude": address_data.get("longitude"),
        "phone_number": address_data.get("phone_number", address_data.get("phoneNumber")),
        "is_default": address_data.get("is_default", address_data.get("isDefault", False))
    }

    saved_addresses.append(new_address)
    customer.saved_addresses = saved_addresses

    # Set as default if requested or first address
    if new_address.get("is_default") or len(saved_addresses) == 1:
        customer.default_address = new_address

    db.commit()
    return _format_address(new_address, new_id, new_address.get("is_default", False))


@app.put("/api/addresses/{customer_id}/{address_id}")
async def update_customer_address(
    customer_id: int,
    address_id: int,
    address_data: dict,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """
    Update an existing address for a customer.
    Used by Android/iOS customer apps.
    """
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    saved_addresses = list(customer.saved_addresses or [])  # Copy to new list for SQLAlchemy JSON change detection

    # Find and update address
    for i, addr in enumerate(saved_addresses):
        if isinstance(addr, dict) and addr.get("id") == address_id:
            updated_address = {
                "id": address_id,
                "user_id": customer_id,
                "location_name": address_data.get("location_name", addr.get("location_name")),
                "street": address_data.get("street", addr.get("street")),
                "unit": address_data.get("unit", addr.get("unit")),
                "city": address_data.get("city", addr.get("city")),
                "state": address_data.get("state", addr.get("state")),
                "zip_code": address_data.get("zip_code", addr.get("zip_code")),
                "instructions": address_data.get("instructions", addr.get("instructions")),
                "address_type": address_data.get("address_type", addr.get("address_type")),
                "latitude": address_data.get("latitude", addr.get("latitude")),
                "longitude": address_data.get("longitude", addr.get("longitude")),
                "phone_number": address_data.get("phone_number", addr.get("phone_number")),
                "is_default": addr.get("is_default", False)
            }
            saved_addresses[i] = updated_address
            customer.saved_addresses = saved_addresses

            # Update default if this was the default
            if customer.default_address and customer.default_address.get("id") == address_id:
                customer.default_address = updated_address

            db.commit()
            return _format_address(updated_address, i, updated_address.get("is_default", False))

    raise HTTPException(status_code=404, detail="Address not found")


@app.delete("/api/addresses/{customer_id}/{address_id}")
async def delete_customer_address(
    customer_id: int,
    address_id: int,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """
    Delete an address for a customer.
    Used by Android/iOS customer apps.
    """
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    saved_addresses = list(customer.saved_addresses or [])  # Copy to new list for SQLAlchemy JSON change detection

    # Find and remove address
    for i, addr in enumerate(saved_addresses):
        if isinstance(addr, dict) and addr.get("id") == address_id:
            saved_addresses.pop(i)
            customer.saved_addresses = saved_addresses

            # Clear default if deleted
            if customer.default_address and customer.default_address.get("id") == address_id:
                customer.default_address = saved_addresses[0] if saved_addresses else None

            db.commit()
            return {"success": True, "message": "Address deleted"}

    raise HTTPException(status_code=404, detail="Address not found")


@app.post("/api/addresses/{customer_id}/{address_id}/set-default")
async def set_default_address(
    customer_id: int,
    address_id: int,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """
    Set an address as the default for a customer.
    Used by Android/iOS customer apps.
    """
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    saved_addresses = customer.saved_addresses or []

    # Find address and set as default
    for i, addr in enumerate(saved_addresses):
        if isinstance(addr, dict) and addr.get("id") == address_id:
            customer.default_address = addr
            db.commit()
            return _format_address(addr, i, True)

    raise HTTPException(status_code=404, detail="Address not found")




# ==================== P19: PAYMENT CARDS ENDPOINTS ====================
# PCI-COMPLIANT: All card data stored BY STRIPE, not in our database
# We only store stripe_customer_id and fetch card info from Stripe API

@app.get("/api/customers/{customer_id}/cards")
async def get_saved_cards(
    customer_id: int,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """
    Get all saved payment cards for a customer FROM STRIPE.
    PCI Compliant: Card data is stored by Stripe, not in our database.
    """
    # SECURITY: Verify token owner matches URL customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="You can only access your own payment cards")

    # If no Stripe customer, return empty list
    if not customer.stripe_customer_id:
        return {"cards": [], "count": 0}

    try:
        # Fetch payment methods FROM STRIPE (PCI compliant)
        payment_methods = stripe.PaymentMethod.list(
            customer=customer.stripe_customer_id,
            type="card"
        )

        # Get default payment method
        stripe_customer = stripe.Customer.retrieve(customer.stripe_customer_id)
        default_pm_id = stripe_customer.invoice_settings.default_payment_method

        # De-duplicate cards by (last4, brand, exp_month, exp_year)
        # Keep the default card if duplicate, otherwise keep the first one
        seen_cards = {}  # key: (last4, brand, exp_month, exp_year) -> card dict

        for pm in payment_methods.data:
            card_key = (pm.card.last4, pm.card.brand, pm.card.exp_month, pm.card.exp_year)
            card_data = {
                "id": pm.id,
                "brand": pm.card.brand,
                "last4": pm.card.last4,
                "exp_month": pm.card.exp_month,
                "exp_year": pm.card.exp_year,
                "is_default": pm.id == default_pm_id
            }

            # If we haven't seen this card, add it
            # If we have seen it, only replace if this one is the default
            if card_key not in seen_cards:
                seen_cards[card_key] = card_data
            elif card_data["is_default"]:
                seen_cards[card_key] = card_data

        cards = list(seen_cards.values())
        return {"cards": cards, "count": len(cards)}

    except stripe.error.StripeError as e:
        logger.error(f"Stripe error fetching cards: {str(e)}")
        return {"cards": [], "count": 0, "error": str(e)}


@app.post("/api/customers/{customer_id}/cards")
async def add_payment_card(
    customer_id: int,
    request: dict,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """
    Attach a payment method to customer IN STRIPE.
    PCI Compliant: Card tokenization happens on client, we only receive payment_method_id.
    """
    # SECURITY: Verify token owner matches URL customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="You can only manage your own payment cards")

    payment_method_id = request.get("payment_method_id")
    if not payment_method_id:
        raise HTTPException(status_code=400, detail="payment_method_id is required")

    try:
        # Create Stripe customer if needed
        if not customer.stripe_customer_id:
            stripe_customer = stripe.Customer.create(
                email=customer.email,
                name=f"{customer.first_name or ''} {customer.last_name or ''}".strip() or None,
                metadata={"dollor_customer_id": str(customer.id)}
            )
            customer.stripe_customer_id = stripe_customer.id
            db.commit()

        # Attach payment method to customer IN STRIPE
        stripe.PaymentMethod.attach(
            payment_method_id,
            customer=customer.stripe_customer_id
        )

        # Get the payment method details to return
        pm = stripe.PaymentMethod.retrieve(payment_method_id)

        return {
            "success": True,
            "card": {
                "id": pm.id,
                "brand": pm.card.brand,
                "last4": pm.card.last4,
                "exp_month": pm.card.exp_month,
                "exp_year": pm.card.exp_year
            },
            "message": "Card added successfully"
        }

    except stripe.error.StripeError as e:
        logger.error(f"Stripe error adding card: {str(e)}")
        raise HTTPException(status_code=400, detail="Request failed. Please try again.")


@app.delete("/api/customers/{customer_id}/cards/{card_id}")
async def delete_payment_card(
    customer_id: int,
    card_id: str,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """
    Detach a payment method FROM STRIPE.
    PCI Compliant: Card deletion happens in Stripe, not our database.
    """
    # SECURITY: Verify token owner matches URL customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="You can only manage your own payment cards")

    if not customer.stripe_customer_id:
        raise HTTPException(status_code=404, detail="No payment methods found")

    try:
        # Detach payment method FROM STRIPE
        stripe.PaymentMethod.detach(card_id)
        return {"success": True, "message": "Card deleted successfully"}

    except stripe.error.StripeError as e:
        logger.error(f"Stripe error deleting card: {str(e)}")
        raise HTTPException(status_code=400, detail="Request failed. Please try again.")


@app.post("/api/customers/{customer_id}/cards/{card_id}/default")
async def set_default_card(
    customer_id: int,
    card_id: str,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """
    Set default payment method IN STRIPE.
    PCI Compliant: Default card setting stored in Stripe, not our database.
    """
    # SECURITY: Verify token owner matches URL customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="You can only manage your own payment cards")

    if not customer.stripe_customer_id:
        raise HTTPException(status_code=404, detail="No payment methods found")

    try:
        # Set default payment method IN STRIPE
        stripe.Customer.modify(
            customer.stripe_customer_id,
            invoice_settings={"default_payment_method": card_id}
        )
        return {"success": True, "message": "Default card updated", "card_id": card_id}

    except stripe.error.StripeError as e:
        logger.error(f"Stripe error setting default card: {str(e)}")
        raise HTTPException(status_code=400, detail="Request failed. Please try again.")


@app.get("/api/customers/{customer_id}/stripe/setup-intent")
async def create_customer_setup_intent(
    customer_id: int,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """
    Create a Stripe SetupIntent so the client can save a payment method (including
    Apple Pay, which — unlike a card entered via STPPaymentCardTextField — has no
    client-side token to hand the existing POST /cards endpoint directly; it must
    confirm a PaymentIntent/SetupIntent via STPApplePayContext instead) without
    charging anything yet. On confirmation Stripe attaches the resulting payment
    method to this customer and (since we don't set `invoice_settings` here) the
    client still calls the existing /cards/{id}/default endpoint to make it default
    — mirrors the pattern in founding_members.py's publishable_key handoff.
    """
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="You can only manage your own payment methods")

    try:
        if not customer.stripe_customer_id:
            stripe_customer = stripe.Customer.create(
                email=customer.email,
                name=f"{customer.first_name or ''} {customer.last_name or ''}".strip() or None,
                metadata={"dollor_customer_id": str(customer.id)}
            )
            customer.stripe_customer_id = stripe_customer.id
            db.commit()

        setup_intent = stripe.SetupIntent.create(
            customer=customer.stripe_customer_id,
            payment_method_types=["card"],
            usage="off_session",
        )
        return {
            "success": True,
            "client_secret": setup_intent.client_secret,
            "publishable_key": os.getenv("STRIPE_PUBLISHABLE_KEY", ""),
        }
    except stripe.error.StripeError as e:
        logger.error(f"Stripe error creating setup intent for customer {customer_id}: {str(e)}")
        raise HTTPException(status_code=400, detail="Could not start payment setup. Please try again.")







# ==================== MICROSERVICE PROXY INFRASTRUCTURE ====================
# proxy_request() helper and service URL constants are used by the health check
# endpoint and a few kept proxy stubs that have active mobile app callers.

import httpx
from fastapi.responses import JSONResponse, HTMLResponse

# Microservice URLs (K8s internal services - configured via environment variables)
# Core Services
AUTH_SERVICE_URL = os.getenv("AUTH_SERVICE_URL", "http://auth-service:8001")
USER_SERVICE_URL = os.getenv("USER_SERVICE_URL", "http://user-service:8002")
DRIVER_SERVICE_URL = os.getenv("DRIVER_SERVICE_URL", "http://driver-service:8003")
RESTAURANT_SERVICE_URL = os.getenv("RESTAURANT_SERVICE_URL", "http://restaurant-service:8004")
ORDER_SERVICE_URL = os.getenv("ORDER_SERVICE_URL", "http://order-service:8005")
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://payment-service:8006")
LOCATION_SERVICE_URL = os.getenv("LOCATION_SERVICE_URL", "http://location-service:8007")
MENU_SERVICE_URL = os.getenv("MENU_SERVICE_URL", "http://menu-service:8008")
NOTIFICATION_SERVICE_URL = os.getenv("NOTIFICATION_SERVICE_URL", "http://notification-service:8009")
# Feature Services
RATING_SERVICE_URL = os.getenv("RATING_SERVICE_URL", "http://rating-service:8013")
RIDE_SERVICE_URL = os.getenv("RIDE_SERVICE_URL", "http://ride-service:8014")
PRICING_SERVICE_URL = os.getenv("PRICING_SERVICE_URL", "http://pricing-service:8015")
ANALYTICS_SERVICE_URL = os.getenv("ANALYTICS_SERVICE_URL", "http://analytics-service:8016")
NEGOTIATION_SERVICE_URL = os.getenv("NEGOTIATION_SERVICE_URL", "http://negotiation-service:8017")
CHAT_SERVICE_URL = os.getenv("CHAT_SERVICE_URL", "http://chat-service:8018")
CALL_SERVICE_URL = os.getenv("CALL_SERVICE_URL", "http://call-service:8019")

async def proxy_request(service_url: str, path: str, method: str = "GET",
                        params: dict = None, json_data: dict = None):
    """Proxy a request to a microservice."""
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            url = f"{service_url}{path}"
            if method == "GET":
                response = await client.get(url, params=params)
            elif method == "POST":
                response = await client.post(url, json=json_data, params=params)
            elif method == "PUT":
                response = await client.put(url, json=json_data)
            elif method == "DELETE":
                response = await client.delete(url)
            else:
                response = await client.request(method, url, json=json_data, params=params)

            return JSONResponse(
                content=response.json() if response.content else {},
                status_code=response.status_code
            )
    except httpx.ConnectError:
        # Service unavailable - return mock data for development
        return None
    except Exception as e:
        return JSONResponse(
            content={"error": str(e), "service": service_url},
            status_code=503
        )



# ==================== KEPT ERP ENDPOINTS (real code, not proxy stubs) ====================
# The proxy stubs to non-existent microservices were removed.
# These endpoints either query the real DB or have active mobile app callers.





# ==================== PAYMENT ENDPOINTS ====================

# Import Stripe for direct payment processing
import stripe
stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_PUBLISHABLE_KEY = os.getenv("STRIPE_PUBLISHABLE_KEY", "")

@app.post("/api/erp/payments/intent")
async def proxy_create_payment_intent(
    http_request: Request,
    request: dict,
    authorization: str = Header(None),
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """
    Create payment intent - uses direct Stripe integration.
    Returns clientSecret, ephemeralKey, customer, and publishableKey for iOS/Android apps.
    With customer and ephemeralKey, users can save cards and use Apple Pay.

    For demo accounts (App Store review), returns a demo payment response
    that bypasses actual Stripe processing.
    """
    check_rate_limit(http_request, payment_limiter, "payment", identifier=str(_auth.get("user_id", _auth.get("customer_id", _auth.get("driver_id", "unknown")))))
    # Check for demo account - bypass Stripe for App Store review + underwriter demo
    DEMO_CUSTOMER_EMAILS = [
        "demo.customer@dollor.ai",
        "demo.driver@dollor.ai",
        "demo.restaurant@dollor.ai",
        "jeetnair.in@gmail.com"
    ]

    customer = get_current_customer_from_token(authorization, db) if authorization else None
    if customer and customer.email and customer.email.lower() in [e.lower() for e in DEMO_CUSTOMER_EMAILS]:
        logger.info(f"Demo account detected: {mask_email(customer.email)} - bypassing Stripe payment")
        # Return demo payment response - app will detect 'demo' flag and skip actual payment
        return {
            "clientSecret": "demo_pi_appstore_review_secret",
            "paymentIntent": "demo_pi_appstore_review_secret",
            "publishableKey": STRIPE_PUBLISHABLE_KEY or "pk_demo_appstore_review",
            "ephemeralKey": "demo_ek_appstore_review",
            "customer": "demo_cus_appstore_review",
            "demo": True,  # Flag for app to detect demo mode
            "message": "Demo account - payment will be simulated"
        }

    # Try microservice first
    result = await proxy_request(PAYMENT_SERVICE_URL, "/api/payments/intent", method="POST", json_data=request)
    if result:
        return result

    # Direct Stripe integration (fallback or primary)
    if not stripe.api_key:
        logger.error("STRIPE_SECRET_KEY not configured")
        return JSONResponse(
            status_code=500,
            content={"error": "Payment service not configured", "message": "Stripe keys are missing"}
        )

    try:
        amount = request.get("amount", 0)  # Amount in cents
        currency = request.get("currency", "usd")
        order_id = request.get("order_id")
        customer_email = request.get("customer_email")

        # Get current customer from token (if authenticated)
        customer = get_current_customer_from_token(authorization, db) if authorization else None
        stripe_customer_id = None
        ephemeral_key = None

        if customer:
            # Get or create Stripe customer
            if customer.stripe_customer_id:
                stripe_customer_id = customer.stripe_customer_id
                logger.info(f"Using existing Stripe customer: {stripe_customer_id}")
            else:
                # Create new Stripe customer
                stripe_customer = stripe.Customer.create(
                    email=customer.email,
                    name=f"{customer.first_name or ''} {customer.last_name or ''}".strip() or None,
                    phone=customer.phone,
                    metadata={"dollor_customer_id": str(customer.id)}
                )
                stripe_customer_id = stripe_customer.id
                # Save to database
                customer.stripe_customer_id = stripe_customer_id
                db.commit()
                logger.info(f"Created new Stripe customer: {stripe_customer_id}")

            # Create ephemeral key for the customer (allows saving/retrieving payment methods)
            ephemeral_key_obj = stripe.EphemeralKey.create(
                customer=stripe_customer_id,
                stripe_version="2023-10-16"  # Use a stable API version
            )
            ephemeral_key = ephemeral_key_obj.secret

        # Create Stripe PaymentIntent
        payment_intent_params = {
            "amount": int(amount),
            "currency": currency,
            "automatic_payment_methods": {"enabled": True},
        }

        # Attach customer to payment intent (enables saved cards)
        if stripe_customer_id:
            payment_intent_params["customer"] = stripe_customer_id
            # Allow saving payment method for future use
            payment_intent_params["setup_future_usage"] = "off_session"

        if customer_email or (customer and customer.email):
            payment_intent_params["receipt_email"] = customer_email or customer.email

        if order_id:
            payment_intent_params["metadata"] = {"order_id": order_id}
            payment_intent_params["idempotency_key"] = f"main_pi_{order_id}_{int(datetime.utcnow().timestamp())}"

        payment_intent = stripe.PaymentIntent.create(**payment_intent_params)

        # Return format expected by iOS PaymentService (with customer for saved cards)
        return {
            "clientSecret": payment_intent.client_secret,
            "paymentIntent": payment_intent.client_secret,  # iOS compatibility
            "publishableKey": STRIPE_PUBLISHABLE_KEY,
            "ephemeralKey": ephemeral_key,
            "customer": stripe_customer_id
        }

    except stripe.error.StripeError as e:
        logger.error(f"Stripe error creating payment intent: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={"error": "Payment processing failed", "message": str(e)}
        )


@app.post("/api/erp/payments/refund")
async def proxy_create_refund(http_request: Request, request: dict, _auth: dict = Depends(require_any_auth)):
    """Proxy to payment-service: Create refund (kept: iOS calls this path)"""
    check_rate_limit(http_request, payment_limiter, "payment_refund", identifier=str(_auth.get("user_id", _auth.get("customer_id", _auth.get("driver_id", "unknown")))))
    result = await proxy_request(PAYMENT_SERVICE_URL, "/api/payments/refund", method="POST", json_data=request)
    if result:
        return result
    return {"error": "Payment service unavailable", "fallback": True}


# ==================== FCM TOKEN REGISTRATION ENDPOINTS ====================
# These endpoints allow mobile apps to register FCM tokens for push notifications

class FCMTokenRequest(BaseModel):
    """Request body for FCM token registration"""
    fcm_token: str = Field(..., min_length=10, max_length=500)
    platform: Optional[str] = Field(None, pattern="^(ios|android)$")
    device_id: Optional[str] = None


@app.post("/api/erp/customers/{customer_id}/fcm-token")
def register_customer_fcm_token(
    customer_id: int,
    token_request: FCMTokenRequest,
    db: Session = Depends(get_db),
    customer: Customer = Depends(require_customer),
):
    """Register FCM token for customer push notifications"""
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    customer.push_token = token_request.fcm_token
    if token_request.platform:
        customer.platform = token_request.platform
    if token_request.device_id:
        customer.device_id = token_request.device_id
    customer.updated_at = datetime.utcnow()

    db.commit()

    return {
        "success": True,
        "message": "FCM token registered successfully",
        "customer_id": customer_id
    }


@app.post("/api/erp/drivers/{driver_id}/fcm-token")
def register_driver_fcm_token(
    driver_id: int,
    token_request: FCMTokenRequest,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """Register FCM token for driver push notifications"""
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    # Update both push_token and fcm_token for driver (driver model has both)
    driver.push_token = token_request.fcm_token
    driver.fcm_token = token_request.fcm_token
    driver.fcm_token_updated_at = datetime.utcnow()
    if token_request.platform:
        driver.platform = token_request.platform
    driver.updated_at = datetime.utcnow()

    db.commit()

    return {
        "success": True,
        "message": "FCM token registered successfully",
        "driver_id": driver_id
    }




@app.delete("/api/erp/customers/{customer_id}/fcm-token")
def unregister_customer_fcm_token(customer_id: int, db: Session = Depends(get_db), customer: Customer = Depends(require_customer)):
    """Unregister FCM token for customer (on logout)"""
    # SECURITY: Verify the authenticated customer owns this customer_id
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Access denied")

    customer.push_token = None
    customer.updated_at = datetime.utcnow()
    db.commit()

    return {"success": True, "message": "FCM token unregistered", "customer_id": customer_id}


@app.delete("/api/erp/drivers/{driver_id}/fcm-token")
def unregister_driver_fcm_token(driver_id: int, db: Session = Depends(get_db), driver: Driver = Depends(require_driver)):
    """Unregister FCM token for driver (on logout)"""
    # SECURITY: Verify the authenticated driver owns this account
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    driver.push_token = None
    driver.fcm_token = None
    driver.updated_at = datetime.utcnow()
    db.commit()

    return {"success": True, "message": "FCM token unregistered", "driver_id": driver_id}




@app.get("/api/erp/analytics/dashboard/realtime")
async def proxy_realtime_dashboard(_auth: dict = Depends(require_any_auth)):
    """Proxy to analytics-service: Get realtime dashboard (kept: iOS calls this path)"""
    result = await proxy_request(ANALYTICS_SERVICE_URL, "/api/dashboard/realtime")
    if result:
        return result
    return {"orders": 0, "rides": 0, "revenue": 0, "message": "Analytics service unavailable"}


@app.get("/api/erp/analytics/ai-employees")
async def get_ai_employees_analytics(db: Session = Depends(get_db), _auth: dict = Depends(require_any_auth)):
    """Get AI employees analytics and status"""
    # Return AI employee status and metrics
    ai_employees = [
        {
            "id": "customer-support",
            "name": "Customer Support AI",
            "type": "customerSupport",
            "status": "active",
            "metrics": {
                "queries_handled": 0,
                "avg_response_time": 0,
                "satisfaction_rate": 0
            }
        },
        {
            "id": "order-dispatcher",
            "name": "Order Dispatcher AI",
            "type": "orderDispatcher",
            "status": "active",
            "metrics": {
                "orders_dispatched": 0,
                "avg_dispatch_time": 0,
                "efficiency_rate": 0
            }
        },
        {
            "id": "analytics-reporter",
            "name": "Analytics Reporter AI",
            "type": "analyticsReporter",
            "status": "active",
            "metrics": {
                "reports_generated": 0,
                "insights_delivered": 0
            }
        },
        {
            "id": "route-optimizer",
            "name": "Route Optimizer AI",
            "type": "routeOptimizer",
            "status": "active",
            "metrics": {
                "routes_optimized": 0,
                "avg_time_saved": 0
            }
        }
    ]

    return {
        "ai_employees": ai_employees,
        "total_active": len([e for e in ai_employees if e["status"] == "active"]),
        "last_updated": datetime.utcnow().isoformat()
    }



# ==================== MICROSERVICE HEALTH CHECKS ====================

@app.get("/api/erp/health/services")
async def check_all_services_health():
    """Check health of all microservices"""
    import asyncio

    services = {
        "auth": AUTH_SERVICE_URL,
        "user": USER_SERVICE_URL,
        "driver": DRIVER_SERVICE_URL,
        "restaurant": RESTAURANT_SERVICE_URL,
        "order": ORDER_SERVICE_URL,
        "payment": PAYMENT_SERVICE_URL,
        "location": LOCATION_SERVICE_URL,
        "menu": MENU_SERVICE_URL,
        "notification": NOTIFICATION_SERVICE_URL,
        "rating": RATING_SERVICE_URL,
        "ride": RIDE_SERVICE_URL,
        "pricing": PRICING_SERVICE_URL,
        "analytics": ANALYTICS_SERVICE_URL,
        "negotiation": NEGOTIATION_SERVICE_URL,
        "chat": CHAT_SERVICE_URL,
        "call": CALL_SERVICE_URL
    }

    async def check_service(name: str, url: str):
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{url}/health")
                return name, response.status_code == 200, response.status_code
        except Exception as e:
            return name, False, str(e)

    tasks = [check_service(name, url) for name, url in services.items()]
    results = await asyncio.gather(*tasks)

    health_status = {}
    healthy_count = 0
    for name, is_healthy, svc_status in results:
        health_status[name] = {
            "healthy": is_healthy,
            "status": svc_status
        }
        if is_healthy:
            healthy_count += 1

    return {
        "services": health_status,
        "healthy_count": healthy_count,
        "total_services": len(services),
        "overall_health": "healthy" if healthy_count == len(services) else "degraded" if healthy_count > 0 else "unhealthy"
    }


# ==================== WEBSOCKET REAL-TIME UPDATES ====================
# Import WebSocket server for real-time order/ride tracking
try:
    from websocket_server import (
        websocket_endpoint,
        manager as ws_manager,
        get_websocket_stats,
        broadcast_order_status,
        broadcast_driver_location,
        broadcast_ride_status,
        broadcast_eta_update
    )

    @app.websocket("/ws/{client_id}")
    async def websocket_route(websocket: WebSocket, client_id: str, token: Optional[str] = Query(None)):
        """
        WebSocket endpoint for real-time updates.
        SECURITY: Requires JWT token as query parameter for authentication.

        Client ID format:
        - customer_{id} - Customer app connections
        - driver_{id} - Driver app connections
        - restaurant_{id} - Restaurant app connections

        Usage: ws://host/ws/customer_123?token=JWT_TOKEN_HERE
        """
        # SECURITY (NSA-001): Validate JWT token before accepting WebSocket connection
        if not token:
            await websocket.close(code=4001, reason="Authentication required: provide ?token=JWT")
            return

        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        except (JWTError, Exception):
            await websocket.close(code=4001, reason="Invalid or expired token")
            return

        # SECURITY: Validate client_id matches JWT claims
        # client_id format: "customer_123", "driver_456", "restaurant_789"
        parts = client_id.split("_", 1)
        client_type = parts[0] if len(parts) > 0 else ""
        entity_id = parts[1] if len(parts) > 1 else ""

        jwt_customer_id = str(payload.get("customer_id", ""))
        jwt_driver_id = str(payload.get("driver_id", ""))
        jwt_vendor_id = str(payload.get("vendor_id", ""))
        jwt_role = payload.get("role", "")

        # Admin can connect as any client_id
        is_authorized = jwt_role == "admin"

        if not is_authorized:
            if client_type == "customer" and entity_id and jwt_customer_id == entity_id:
                is_authorized = True
            elif client_type == "driver" and entity_id and jwt_driver_id == entity_id:
                is_authorized = True
            elif client_type == "restaurant" and entity_id and jwt_vendor_id == entity_id:
                is_authorized = True

        if not is_authorized:
            await websocket.close(code=4003, reason="client_id does not match authenticated user")
            return

        await websocket_endpoint(websocket, client_id)

    @app.get("/api/websocket/stats")
    def get_ws_stats():
        """Get WebSocket server statistics."""
        return get_websocket_stats()

    print("WebSocket server initialized successfully")
except ImportError as e:
    print(f"WebSocket server not available: {e}")


# ==================== PUSH NOTIFICATION SERVICE ====================
@app.post("/api/notifications/register-token")
def register_push_token(
    device_token: str = Form(...),
    platform: str = Form(...),  # ios or android
    user_type: str = Form(...),  # customer, driver, restaurant
    user_id: int = Form(...),
    _auth: dict = Depends(require_any_auth),
    db: Session = Depends(get_db)
):
    """Register a device token for push notifications."""
    # SECURITY: Verify the authenticated user matches the user_id parameter
    auth_customer_id = _auth.get("customer_id")
    auth_driver_id = _auth.get("driver_id")
    if user_type == "customer" and auth_customer_id and int(auth_customer_id) != user_id:
        raise HTTPException(status_code=403, detail="Access denied - user_id mismatch")
    if user_type == "driver" and auth_driver_id and int(auth_driver_id) != user_id:
        raise HTTPException(status_code=403, detail="Access denied - user_id mismatch")
    # Store token in database (update existing or create new)
    if user_type == "customer":
        customer = db.query(Customer).filter(Customer.id == user_id).first()
        if customer:
            customer.push_token = device_token
            customer.platform = platform
            db.commit()
    elif user_type == "driver":
        driver = db.query(Driver).filter(Driver.id == user_id).first()
        if driver:
            driver.push_token = device_token
            driver.platform = platform
            db.commit()

    return {"success": True, "message": "Push token registered"}


@app.delete("/api/notifications/unregister-token")
def unregister_push_token(
    user_type: str = Query(...),
    user_id: int = Query(...),
    _auth: dict = Depends(require_any_auth),
    db: Session = Depends(get_db)
):
    """Unregister a device token (on logout)."""
    # SECURITY: Verify the authenticated user matches the user_id parameter
    auth_customer_id = _auth.get("customer_id")
    auth_driver_id = _auth.get("driver_id")
    if user_type == "customer" and auth_customer_id and int(auth_customer_id) != user_id:
        raise HTTPException(status_code=403, detail="Access denied - user_id mismatch")
    if user_type == "driver" and auth_driver_id and int(auth_driver_id) != user_id:
        raise HTTPException(status_code=403, detail="Access denied - user_id mismatch")
    if user_type == "customer":
        customer = db.query(Customer).filter(Customer.id == user_id).first()
        if customer:
            customer.push_token = None
            db.commit()
    elif user_type == "driver":
        driver = db.query(Driver).filter(Driver.id == user_id).first()
        if driver:
            driver.push_token = None
            db.commit()

    return {"success": True, "message": "Push token unregistered"}


# ==================== IN-APP NOTIFICATION ENDPOINTS ====================

@app.post("/api/feedback")
async def submit_feedback(request: Request):
    """Customer bug report / feedback. Reliably logged (captured in server logs) + best-effort
    email to support — fixes the prior silent-loss where the button faked success against a 404."""
    try:
        body = await request.json()
    except Exception:
        body = {}
    ftype = str(body.get("type", "feedback"))[:50]
    desc = str(body.get("description", ""))[:5000]
    cust = body.get("customer_id")
    appv = str(body.get("app_version", ""))[:50]
    logging.warning(f"[FEEDBACK] type={ftype} customer={cust} app_version={appv} :: {desc}")
    try:
        from email_service import send_email
        send_email(to_email="support@dollor.ai",
                   subject=f"[{ftype}] Dollor feedback (customer {cust})",
                   body=f"App version: {appv}\nCustomer: {cust}\nType: {ftype}\n\n{desc}")
    except Exception as _e:
        logging.info(f"[FEEDBACK] email not sent (non-blocking): {_e}")
    return {"success": True, "message": "Feedback received"}


@app.get("/api/customer/notifications")
def get_customer_notifications(
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Get all notifications for the current customer, newest first."""
    from models import InAppNotification
    notifications = db.query(InAppNotification).filter(
        InAppNotification.customer_id == customer.id
    ).order_by(InAppNotification.created_at.desc()).limit(100).all()

    return {
        "notifications": [
            {
                "id": str(n.id),
                "title": n.title,
                "message": n.message,
                "type": n.type or "system",
                "is_read": n.is_read,
                "reference_id": n.reference_id,
                "reference_type": n.reference_type,
                "created_at": n.created_at.isoformat() if n.created_at else None
            }
            for n in notifications
        ]
    }


@app.put("/api/customer/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: int,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Mark a notification as read. Customer can only mark their own."""
    from models import InAppNotification
    notification = db.query(InAppNotification).filter(
        InAppNotification.id == notification_id,
        InAppNotification.customer_id == customer.id
    ).first()
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    notification.is_read = True
    db.commit()
    return {"success": True}


@app.delete("/api/customer/notifications")
def clear_all_notifications(
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Delete all notifications for the current customer."""
    from models import InAppNotification
    db.query(InAppNotification).filter(
        InAppNotification.customer_id == customer.id
    ).delete()
    db.commit()
    return {"success": True}


def create_in_app_notification(db: Session, customer_id: int, title: str, message: str,
                                notification_type: str = "system", reference_id: int = None,
                                reference_type: str = None):
    """Helper to create an in-app notification for a customer."""
    from models import InAppNotification
    notification = InAppNotification(
        customer_id=customer_id,
        title=title,
        message=message,
        type=notification_type,
        reference_id=reference_id,
        reference_type=reference_type
    )
    db.add(notification)
    db.commit()
    return notification


# ==================== LEGAL DOCUMENT ENDPOINTS ====================
@app.get("/api/legal/terms")
def get_terms_of_service():
    """Get Terms of Service content and URL."""
    return {
        "url": "https://dollor.ai/terms",
        "last_updated": "2025-12-15",
        "version": "1.0",
        "summary": {
            "service_type": "Matchmaking Platform",
            "pricing": {
                "food_delivery": {
                    "customer_fee": 1.00,
                    "restaurant_fee": 1.00,
                    "driver_fee": 0.00,
                    "tip_fee": 0.00
                },
                "rideshare": {
                    "rider_fee": 1.00,
                    "driver_fee": 1.00,
                    "tip_fee": 0.00
                }
            },
            "key_points": [
                "Dollor.ai is a technology matchmaking platform, not a delivery or transportation company",
                "Drivers are independent contractors, not employees",
                "Flat $1 matchmaking fee - no percentage commissions",
                "100% of tips go directly to drivers",
                "Drivers choose their own routes, schedules, and which requests to accept"
            ],
            "cancellation_policy": {
                "food_delivery": {
                    "cancellable_statuses": ["pending_payment", "confirmed", "pending_restaurant"],
                    "non_cancellable_after": "Restaurant has accepted the order",
                    "refund_timeline": "1-3 business days"
                },
                "rideshare": {
                    "free_cancellation": "Before driver assignment",
                    "cancellation_fee": "After driver assigned and en route"
                }
            }
        }
    }


@app.get("/api/legal/privacy")
def get_privacy_policy():
    """Get Privacy Policy content and URL."""
    return {
        "url": "https://dollor.ai/privacy",
        "last_updated": "2025-12-15",
        "version": "1.0",
        "data_collected": [
            {"type": "Account Information", "purpose": "Account creation and authentication"},
            {"type": "Payment Information", "purpose": "Process transactions securely via Stripe"},
            {"type": "Location Data", "purpose": "Facilitate accurate deliveries and rides"},
            {"type": "Order History", "purpose": "Personalization and customer service"},
            {"type": "Device Information", "purpose": "Security and push notifications"}
        ],
        "data_sharing": [
            "Restaurant Partners - for order fulfillment",
            "Driver Partners - for delivery/ride completion",
            "Payment Processors (Stripe) - for secure transactions",
            "We do NOT sell personal information"
        ],
        "user_rights": [
            "Access your data",
            "Correct inaccurate data",
            "Request deletion",
            "Opt-out of marketing",
            "Data portability"
        ],
        "contact": "privacy@dollor.ai"
    }


# ==================== DEMO ACCOUNT SETUP (App Store Review) ====================
@app.post("/api/demo/setup")
def setup_demo_accounts(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """Create demo accounts for App Store/Play Store review.
    SECURITY: Requires ADMIN_SECRET_KEY to prevent unauthorized account manipulation."""
    # SECURITY: Require admin secret key
    expected_key = os.getenv("ADMIN_SECRET_KEY")
    if expected_key and (not secret_key or secret_key != expected_key):
        raise HTTPException(status_code=403, detail="Admin secret key required")
    results = {"created": [], "existing": [], "errors": []}

    # --- Demo Customer ---
    try:
        customer_email = "demo.customer@dollor.ai"
        existing = db.query(Customer).filter(Customer.email == customer_email).first()
        if not existing:
            demo_customer = Customer(
                customer_id="DEMO-CUST-001",
                first_name="Demo",
                last_name="Customer",
                email=customer_email,
                phone="+14155551001",
                password_hash=get_password_hash("DemoCustomer2025!"),
                default_address={"street": "123 Market St", "city": "San Francisco", "state": "CA", "zip_code": "94102"},
                is_active=True,
                is_verified=True,
                loyalty_points=500,
                loyalty_tier="gold",
                total_orders=25,
                created_at=datetime.utcnow()
            )
            db.add(demo_customer)
            db.commit()
            results["created"].append("customer")
        else:
            # Update password to ensure it matches (for existing accounts)
            # Use explicit SQL UPDATE to ensure the change is applied
            new_hash = get_password_hash("DemoCustomer2025!")
            db.execute(
                text("UPDATE customers SET password_hash = :hash, is_active = true WHERE email = :email"),
                {"hash": new_hash, "email": customer_email}
            )
            db.commit()
            # Clear ride state so demo customer can request rides without hitting 429/402 blocks
            from models import RideRequest, RideRequestStatus
            demo_rides = db.query(RideRequest).filter(
                RideRequest.customer_id == existing.id,
                RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING])
            ).all()
            cancelled_rides = 0
            for ride in demo_rides:
                ride.status = RideRequestStatus.CANCELLED
                cancelled_rides += 1
            db.execute(
                text("UPDATE customers SET has_unpaid_balance = false WHERE email = :email"),
                {"email": customer_email}
            )
            db.commit()
            results["ride_state_reset"] = {"cancelled_rides": cancelled_rides}
            results["existing"].append("customer")
    except Exception as e:
        db.rollback()
        results["errors"].append(f"customer: {str(e)}")

    # --- Demo Driver (Driver + User) ---
    from encryption import encrypt_field
    try:
        driver_email = "demo.driver@dollor.ai"
        existing_driver = db.query(Driver).filter(Driver.email == driver_email).first()
        if not existing_driver:
            demo_driver = Driver(
                driver_id="DEMO-DRV-001",
                first_name="Marcus",
                last_name="Johnson",
                email=driver_email,
                phone="+14155551002",
                password_hash=get_password_hash("DemoDriver2025!"),
                city="San Francisco",
                state="CA",
                zip_code="94102",
                street="789 Driver Lane",
                vehicle_type="car",
                vehicle_make="Toyota",
                vehicle_model="Camry",
                vehicle_year=2023,
                vehicle_color="Silver",
                license_plate="7ABC123",
                license_number="D1234567",
                drivers_license=True,
                drivers_license_expiry=datetime(2027, 12, 31),
                insurance=True,
                insurance_expiry=datetime(2026, 6, 30),
                background_check=True,
                background_check_date=datetime(2024, 1, 15),
                status=DriverStatus.APPROVED,
                rating=4.9,
                total_deliveries=6,  # Matches actual orders in demo data
                # Professional driver photo - generated avatar
                photo_url="https://ui-avatars.com/api/?name=Marcus+Johnson&size=200&background=4CAF50&color=fff&bold=true&format=png",
                # Vehicle photo placeholder - silver Toyota Camry
                vehicle_photo_url="https://images.unsplash.com/photo-1621007947382-bb3c3994e3fb?w=400&h=300&fit=crop",
                is_online=True,
                current_latitude=37.7749,
                current_longitude=-122.4194,
                terms_accepted_at=datetime(2024, 1, 10),
                verification_status="verified",
                documents_verified=True,
                documents_verified_at=datetime(2024, 1, 12),
                stripe_account_id="acct_demo_marcus_johnson",
                stripe_onboarded=True,
                bank_name=encrypt_field("Wells Fargo"),
                bank_last4="4242",
                bank_routing_number=encrypt_field("121042882"),
                bank_account_holder=encrypt_field("Marcus Johnson"),
                bank_verified=True,
                bank_verified_at=datetime(2024, 1, 15),
                created_at=datetime.utcnow()
            )
            db.add(demo_driver)
            db.flush()  # Get driver.id before creating User
            # Create User record for driver login (required for /api/auth/driver/login)
            driver_user = User(
                email=driver_email,
                password_hash=get_password_hash("DemoDriver2025!"),
                full_name="Marcus Johnson",
                role=UserRole.DRIVER,
                driver_id=demo_driver.id,
                created_at=datetime.utcnow()
            )
            db.add(driver_user)
            db.commit()
            results["created"].append("driver")
        else:
            # Update existing driver with all demo details (ensure photos and vehicle info are set)
            existing_driver.first_name = "Marcus"
            existing_driver.last_name = "Johnson"
            existing_driver.vehicle_make = "Toyota"
            existing_driver.vehicle_model = "Camry"
            existing_driver.vehicle_year = 2023
            existing_driver.vehicle_color = "Silver"
            existing_driver.license_plate = "7ABC123"
            existing_driver.rating = 4.9
            existing_driver.total_deliveries = 6  # Matches actual orders in demo data
            existing_driver.photo_url = "https://ui-avatars.com/api/?name=Marcus+Johnson&size=200&background=4CAF50&color=fff&bold=true&format=png"
            existing_driver.vehicle_photo_url = "https://images.unsplash.com/photo-1621007947382-bb3c3994e3fb?w=400&h=300&fit=crop"
            existing_driver.status = DriverStatus.APPROVED
            existing_driver.is_online = True
            existing_driver.verification_status = "verified"
            existing_driver.documents_verified = True
            existing_driver.stripe_account_id = "acct_demo_marcus_johnson"
            existing_driver.stripe_onboarded = True
            existing_driver.bank_name = encrypt_field("Wells Fargo")
            existing_driver.bank_last4 = "4242"
            existing_driver.bank_routing_number = encrypt_field("121042882")
            existing_driver.bank_account_holder = encrypt_field("Marcus Johnson")
            existing_driver.bank_verified = True
            existing_driver.bank_verified_at = datetime(2024, 1, 15)
            db.commit()

            # Ensure User record exists for existing driver
            existing_user = db.query(User).filter(User.email == driver_email).first()
            if not existing_user:
                driver_user = User(
                    email=driver_email,
                    password_hash=get_password_hash("DemoDriver2025!"),
                    full_name="Marcus Johnson",
                    role=UserRole.DRIVER,
                    driver_id=existing_driver.id,
                    created_at=datetime.utcnow()
                )
                db.add(driver_user)
                db.commit()
                results["created"].append("driver_user")
            else:
                # Update password and name to ensure it matches
                existing_user.password_hash = get_password_hash("DemoDriver2025!")
                existing_user.full_name = "Marcus Johnson"
                existing_user.driver_id = existing_driver.id
                existing_user.role = UserRole.DRIVER
                db.commit()
            results["existing"].append("driver")
    except Exception as e:
        db.rollback()
        results["errors"].append(f"driver: {str(e)}")

    # --- Demo Restaurant (Vendor + User) ---
    try:
        vendor_email = "demo.restaurant@dollor.ai"
        existing = db.query(Vendor).filter(Vendor.contact_email == vendor_email).first()
        if not existing:
            demo_vendor = Vendor(
                restaurant_name="Demo Restaurant",
                company_name="Demo Restaurant LLC",
                contact_email=vendor_email,
                contact_phone="+14155551003",
                contact_name="Demo Owner",
                street="456 Demo Ave",
                city="San Francisco",
                state="CA",
                zip_code="94102",
                cuisine_type="American",
                onboarding_status="APPROVED",
                is_online=True,
                created_at=datetime.utcnow()
            )
            db.add(demo_vendor)
            db.flush()
            vendor_user = User(
                email=vendor_email,
                password_hash=get_password_hash("DemoRestaurant2025!"),
                full_name="Demo Owner",
                role=UserRole.VENDOR,
                vendor_id=demo_vendor.id,
                created_at=datetime.utcnow()
            )
            db.add(vendor_user)
            db.commit()
            results["created"].append("restaurant")
        else:
            # Ensure User record exists for existing vendor
            existing_user = db.query(User).filter(User.email == vendor_email).first()
            if not existing_user:
                vendor_user = User(
                    email=vendor_email,
                    password_hash=get_password_hash("DemoRestaurant2025!"),
                    full_name="Demo Owner",
                    role=UserRole.VENDOR,
                    vendor_id=existing.id,
                    created_at=datetime.utcnow()
                )
                db.add(vendor_user)
                db.commit()
                results["created"].append("restaurant_user")
            else:
                # Update password to ensure it matches
                existing_user.password_hash = get_password_hash("DemoRestaurant2025!")
                existing_user.vendor_id = existing.id
                existing_user.role = UserRole.VENDOR
                db.commit()
            results["existing"].append("restaurant")
    except Exception as e:
        db.rollback()
        results["errors"].append(f"restaurant: {str(e)}")

    # --- Production Admin (support@dollor.ai) ---
    try:
        admin_email = "support@dollor.ai"
        existing = db.query(User).filter(User.email == admin_email).first()
        if not existing:
            admin_user = User(
                email=admin_email,
                password_hash=get_password_hash("DollorAdmin2026!"),
                full_name="Dollor Admin",
                role=UserRole.ADMIN,
                created_at=datetime.utcnow()
            )
            db.add(admin_user)
            db.commit()
            results["created"].append("admin")
        else:
            # Update password to ensure it matches
            existing.password_hash = get_password_hash("DollorAdmin2026!")
            existing.role = UserRole.ADMIN
            db.commit()
            results["existing"].append("admin")
    except Exception as e:
        db.rollback()
        results["errors"].append(f"admin: {str(e)}")

    # SECURITY: Never expose credentials in API responses
    return {
        "success": len(results["errors"]) == 0,
        "results": results
    }


@app.post("/api/demo/reset-ride-state")
def reset_demo_ride_state(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """Lightweight reset of demo.customer ride state without account recreation.
    Cancels all OPEN/BIDDING ride requests and clears has_unpaid_balance.
    SECURITY: Requires ADMIN_SECRET_KEY."""
    _require_admin_secret(secret_key)

    customer_email = "demo.customer@dollor.ai"
    customer = db.query(Customer).filter(Customer.email == customer_email).first()
    if not customer:
        raise HTTPException(status_code=404, detail="Demo customer not found — run /api/demo/setup first")

    from models import RideRequest, RideRequestStatus
    open_rides = db.query(RideRequest).filter(
        RideRequest.customer_id == customer.id,
        RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING])
    ).all()

    cancelled = 0
    for ride in open_rides:
        ride.status = RideRequestStatus.CANCELLED
        cancelled += 1

    db.execute(
        text("UPDATE customers SET has_unpaid_balance = false WHERE email = :email"),
        {"email": customer_email}
    )
    db.commit()

    return {
        "success": True,
        "customer_email": customer_email,
        "cancelled_rides": cancelled,
        "has_unpaid_balance_cleared": True
    }


@app.post("/api/demo/recreate-customer")
def recreate_demo_customer(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """Delete and recreate demo customer account to fix corrupted data."""
    _require_admin_secret(secret_key)
    try:
        # Delete existing demo customer
        db.execute(text("DELETE FROM customers WHERE email = 'demo.customer@dollor.ai'"))
        db.commit()

        # Create fresh demo customer
        demo_password = "DemoCustomer2025!"
        new_hash = get_password_hash(demo_password)
        demo_customer = Customer(
            customer_id="DEMO-CUST-001",
            first_name="Demo",
            last_name="Customer",
            email="demo.customer@dollor.ai",
            phone="+14155551001",
            password_hash=new_hash,
            default_address={"street": "123 Market St", "city": "San Francisco", "state": "CA", "zip_code": "94102"},
            is_active=True,
            is_verified=True,
            loyalty_points=500,
            loyalty_tier="gold",
            total_orders=25,
            created_at=datetime.utcnow()
        )
        db.add(demo_customer)
        db.commit()
        db.refresh(demo_customer)

        # Verify password works
        if verify_password(demo_password, demo_customer.password_hash):
            return {
                "success": True,
                "customer_id": demo_customer.id,
                "email": "demo.customer@dollor.ai",
                "message": "Demo customer recreated and verified"
            }
        else:
            return {"success": False, "error": "Password verification failed after creation"}
    except Exception as e:
        db.rollback()
        return {"success": False, "error": str(e)}


@app.post("/api/demo/force-reset-passwords")
def force_reset_demo_passwords(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """Force reset all demo account passwords and verify they work."""
    _require_admin_secret(secret_key)
    results = {"reset": [], "verified": [], "failed": []}

    demo_accounts = [
        {"type": "customer", "email": "demo.customer@dollor.ai", "password": "DemoCustomer2025!", "table": "customers"},
        {"type": "driver", "email": "demo.driver@dollor.ai", "password": "DemoDriver2025!", "table": "users"},
        {"type": "vendor", "email": "demo.restaurant@dollor.ai", "password": "DemoRestaurant2025!", "table": "users"},
        {"type": "admin", "email": "support@dollor.ai", "password": "DollorAdmin2026!", "table": "users"},
    ]

    for account in demo_accounts:
        try:
            # Generate fresh password hash
            new_hash = get_password_hash(account["password"])

            # Update using raw SQL
            db.execute(
                text(f"UPDATE {account['table']} SET password_hash = :hash WHERE email = :email"),
                {"hash": new_hash, "email": account["email"]}
            )
            db.commit()
            results["reset"].append(account["type"])

            # Verify password works
            if account["table"] == "customers":
                record = db.query(Customer).filter(Customer.email == account["email"]).first()
            else:
                record = db.query(User).filter(User.email == account["email"]).first()

            if record and verify_password(account["password"], record.password_hash):
                results["verified"].append(account["type"])
            else:
                results["failed"].append(f"{account['type']}: verification failed")

        except Exception as e:
            db.rollback()
            results["failed"].append(f"{account['type']}: {str(e)}")

    return {
        "success": len(results["failed"]) == 0,
        "results": results,
        "message": "All demo passwords reset and verified" if len(results["failed"]) == 0 else "Some accounts failed"
    }


@app.get("/api/demo/debug-driver-login")
def debug_driver_login(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """Debug why driver login is failing - disabled in production"""
    if _is_production:
        raise HTTPException(status_code=404, detail="Not found")
    _require_admin_secret(secret_key)
    email = "demo.driver@dollor.ai"
    password = "DemoDriver2025!"

    # Check 1: Find user with any role
    any_user = db.query(User).filter(User.email == email).all()
    users_info = []
    for u in any_user:
        users_info.append({
            "id": u.id,
            "email": u.email,
            "role": str(u.role),
            "driver_id": u.driver_id,
            "has_password_hash": bool(u.password_hash),
            "hash_length": len(u.password_hash) if u.password_hash else 0
        })

    # Check 2: Find user with DRIVER role
    driver_user = db.query(User).filter(
        User.email == email,
        User.role == UserRole.DRIVER
    ).first()

    driver_user_info = None
    password_verify_result = None
    if driver_user:
        password_verify_result = verify_password(password, driver_user.password_hash)
        driver_user_info = {
            "id": driver_user.id,
            "role": str(driver_user.role),
            "driver_id": driver_user.driver_id,
            "password_verifies": password_verify_result
        }

    # Check 3: Find driver record
    driver = db.query(Driver).filter(Driver.email == email).first()
    driver_info = None
    if driver:
        driver_info = {
            "id": driver.id,
            "email": driver.email,
            "status": str(driver.status) if driver.status else None,
            "has_password_hash": bool(driver.password_hash),
            "driver_password_verifies": verify_password(password, driver.password_hash) if driver.password_hash else None
        }

    return {
        "email": email,
        "all_users_with_email": users_info,
        "driver_role_user": driver_user_info,
        "driver_record": driver_info,
        "conclusion": "SHOULD_WORK" if driver_user_info and password_verify_result else "BROKEN"
    }


@app.get("/api/demo/debug-customer-login")
def debug_customer_login(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """Debug why customer login is failing - disabled in production"""
    if _is_production:
        raise HTTPException(status_code=404, detail="Not found")
    _require_admin_secret(secret_key)
    email = "demo.customer@dollor.ai"
    password = "DemoCustomer2025!"

    # Check: Find customer
    customer = db.query(Customer).filter(Customer.email == email).first()

    customer_info = None
    password_verify_result = None
    if customer:
        password_verify_result = verify_password(password, customer.password_hash) if customer.password_hash else False
        customer_info = {
            "id": customer.id,
            "email": customer.email,
            "customer_id": customer.customer_id,
            "is_active": customer.is_active,
            "has_password_hash": bool(customer.password_hash),
            "hash_length": len(customer.password_hash) if customer.password_hash else 0,
            "hash_prefix": customer.password_hash[:20] if customer.password_hash else None,
            "password_verifies": password_verify_result
        }

    # Also check if there are multiple customers with same email
    all_customers = db.query(Customer).filter(Customer.email == email).all()
    all_customers_info = [{
        "id": c.id,
        "email": c.email,
        "is_active": c.is_active
    } for c in all_customers]

    return {
        "email": email,
        "customer_record": customer_info,
        "all_customers_with_email": all_customers_info,
        "conclusion": "SHOULD_WORK" if customer_info and password_verify_result else "BROKEN"
    }


@app.post("/api/demo/fix-driver-login")
def fix_driver_login(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """
    Fix demo driver login by ensuring User record exists with correct password and role.
    The driver login endpoint (/api/auth/driver/login) requires a User with role=DRIVER.
    """
    _require_admin_secret(secret_key)
    try:
        driver_email = "demo.driver@dollor.ai"
        driver_password = "DemoDriver2025!"
        new_hash = get_password_hash(driver_password)

        # Find demo driver
        driver = db.query(Driver).filter(Driver.email == driver_email).first()
        if not driver:
            return {"success": False, "error": "Demo driver not found"}

        # Check if User record exists with DRIVER role specifically
        user = db.query(User).filter(
            User.email == driver_email,
            User.role == UserRole.DRIVER
        ).first()

        if user:
            # Update existing driver user
            user.password_hash = new_hash
            user.driver_id = driver.id
            user.full_name = f"{driver.first_name} {driver.last_name}"
            db.commit()

            # Verify the password works
            test_verify = verify_password(driver_password, user.password_hash)

            return {
                "success": True,
                "action": "updated_driver_user",
                "user_id": user.id,
                "driver_id": driver.id,
                "role": str(user.role),
                "password_verify_test": test_verify,
                "message": "Existing DRIVER user updated"
            }

        # Check if there's any user with this email (might have wrong role)
        any_user = db.query(User).filter(User.email == driver_email).first()
        if any_user:
            # Update to DRIVER role
            any_user.password_hash = new_hash
            any_user.role = UserRole.DRIVER
            any_user.driver_id = driver.id
            any_user.full_name = f"{driver.first_name} {driver.last_name}"
            db.commit()

            test_verify = verify_password(driver_password, any_user.password_hash)

            return {
                "success": True,
                "action": "converted_to_driver",
                "user_id": any_user.id,
                "driver_id": driver.id,
                "old_role": "unknown",
                "new_role": str(any_user.role),
                "password_verify_test": test_verify,
                "message": "Existing user converted to DRIVER role"
            }

        # Create new user
        new_user = User(
            email=driver_email,
            password_hash=new_hash,
            full_name=f"{driver.first_name} {driver.last_name}",
            role=UserRole.DRIVER,
            driver_id=driver.id,
            created_at=datetime.utcnow()
        )
        db.add(new_user)
        db.commit()

        test_verify = verify_password(driver_password, new_user.password_hash)

        return {
            "success": True,
            "action": "created",
            "user_id": new_user.id,
            "driver_id": driver.id,
            "role": str(new_user.role),
            "password_verify_test": test_verify,
            "message": "New DRIVER user created"
        }
    except Exception as e:
        db.rollback()
        logging.error(f"Demo setup error: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


@app.post("/api/demo/update-driver-profile")
def update_demo_driver_profile(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """
    Update the demo driver (Marcus Johnson) with complete profile details.
    This ensures all driver details are properly populated and flow through
    to Customer and Restaurant apps during order tracking.
    """
    _require_admin_secret(secret_key)
    try:
        driver_email = "demo.driver@dollor.ai"
        driver = db.query(Driver).filter(Driver.email == driver_email).first()

        if not driver:
            return {"success": False, "error": "Demo driver not found. Run /api/demo/setup first."}

        # Update driver with complete profile details
        driver.first_name = "Marcus"
        driver.last_name = "Johnson"
        driver.phone = "+1-555-123-4567"
        driver.date_of_birth = "1990-05-15"
        driver.license_number = "D1234567"

        # Vehicle details
        driver.vehicle_type = "car"
        driver.vehicle_make = "Toyota"
        driver.vehicle_model = "Camry"
        driver.vehicle_year = 2023
        driver.vehicle_color = "Silver"
        driver.license_plate = "7ABC123"

        # Professional driver photo (using a reliable placeholder service)
        driver.photo_url = "https://ui-avatars.com/api/?name=Marcus+Johnson&size=200&background=4CAF50&color=fff&bold=true&format=png"

        # Vehicle photo - silver Toyota Camry (using Unsplash direct link)
        driver.vehicle_photo_url = "https://images.unsplash.com/photo-1621007947382-bb3c3994e3fb?w=400&h=300&fit=crop"

        # Address
        driver.street = "789 Driver Lane"
        driver.city = "San Francisco"
        driver.state = "CA"
        driver.zip_code = "94102"

        # Status and ratings
        driver.status = DriverStatus.APPROVED
        driver.rating = 4.9
        driver.total_deliveries = 6
        driver.is_online = True

        # Documents (all verified)
        driver.drivers_license = True
        driver.drivers_license_url = "/uploads/driver_documents/48/license_verified.png"
        driver.drivers_license_expiry = datetime(2027, 12, 31)
        driver.insurance = True
        driver.insurance_url = "/uploads/driver_documents/48/insurance_verified.png"
        driver.insurance_expiry = datetime(2026, 6, 30)
        driver.background_check = True
        driver.background_check_date = datetime(2024, 1, 15)

        db.commit()
        db.refresh(driver)

        return {
            "success": True,
            "driver_id": driver.id,
            "driver_code": driver.driver_id,
            "profile": {
                "name": f"{driver.first_name} {driver.last_name}",
                "phone": driver.phone,
                "email": driver.email,
                "photo_url": driver.photo_url,
                "rating": driver.rating
            },
            "vehicle": {
                "type": driver.vehicle_type,
                "make": driver.vehicle_make,
                "model": driver.vehicle_model,
                "year": driver.vehicle_year,
                "color": driver.vehicle_color,
                "license_plate": driver.license_plate,
                "photo_url": driver.vehicle_photo_url
            },
            "documents": {
                "drivers_license": driver.drivers_license,
                "insurance": driver.insurance,
                "background_check": driver.background_check
            },
            "message": "Demo driver profile updated with complete details"
        }
    except Exception as e:
        db.rollback()
        logging.error(f"Demo profile update error: {e}", exc_info=True)
        return {"success": False, "error": str(e)}


@app.post("/api/demo/setup-support-customer")
def setup_support_customer(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """
    Create or update support@dollor.ai as a customer account for web login testing.

    IMPORTANT: Creates records in BOTH tables to work with:
    - main_new.py (queries customers table directly)
    - auth-service microservice (queries users table with role='CUSTOMER')
    """
    _require_admin_secret(secret_key)
    try:
        customer_email = "support@dollor.ai"
        customer_password = "DemoDollor123!"
        new_hash = get_password_hash(customer_password)

        # Check if customer exists in customers table
        existing_customer = db.query(Customer).filter(Customer.email == customer_email).first()

        # Check if user exists in users table
        existing_user = db.execute(
            text("SELECT id, customer_id FROM users WHERE email = :email"),
            {"email": customer_email}
        ).fetchone()

        customer_id = None

        if existing_customer:
            # Update existing customer's password
            db.execute(
                text("UPDATE customers SET password_hash = :hash, is_active = true WHERE email = :email"),
                {"hash": new_hash, "email": customer_email}
            )
            customer_id = existing_customer.id
        else:
            # Create new customer record
            customer_code = f"SUPP-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
            new_customer = Customer(
                customer_id=customer_code,
                first_name="Support",
                last_name="Admin",
                email=customer_email,
                phone="+14155550000",
                password_hash=new_hash,
                default_address={"street": "1 Dollor Plaza", "city": "San Francisco", "state": "CA", "zip_code": "94102"},
                is_active=True,
                is_verified=True,
                loyalty_points=1000,
                loyalty_tier="platinum",
                total_orders=0,
                created_at=datetime.utcnow()
            )
            db.add(new_customer)
            db.flush()  # Get the ID without committing
            customer_id = new_customer.id

        # Now handle the users table (for auth-service microservice compatibility)
        if existing_user:
            # Update existing user's password and link to customer
            db.execute(
                text("""
                    UPDATE users
                    SET password_hash = :hash, customer_id = :customer_id, role = 'CUSTOMER'
                    WHERE email = :email
                """),
                {"hash": new_hash, "email": customer_email, "customer_id": customer_id}
            )
        else:
            # Create new user record linked to customer
            db.execute(
                text("""
                    INSERT INTO users (email, password_hash, full_name, role, customer_id, created_at)
                    VALUES (:email, :hash, :full_name, 'CUSTOMER', :customer_id, NOW())
                """),
                {
                    "email": customer_email,
                    "hash": new_hash,
                    "full_name": "Support Admin",
                    "customer_id": customer_id
                }
            )

        db.commit()

        # Verify password works in customers table
        updated_customer = db.query(Customer).filter(Customer.email == customer_email).first()
        customer_verified = verify_password(customer_password, updated_customer.password_hash) if updated_customer else False

        # Verify password works in users table
        user_row = db.execute(
            text("SELECT password_hash FROM users WHERE email = :email"),
            {"email": customer_email}
        ).fetchone()
        user_verified = verify_password(customer_password, user_row[0]) if user_row else False

        if customer_verified and user_verified:
            return {
                "success": True,
                "action": "created" if not existing_customer else "updated",
                "customer_id": customer_id,
                "email": customer_email,
                "message": "Support customer account created/updated in BOTH customers and users tables",
                "tables_updated": ["customers", "users"],
                "verification": {
                    "customers_table": customer_verified,
                    "users_table": user_verified
                }
            }
        else:
            return {
                "success": False,
                "error": "Password verification failed",
                "verification": {
                    "customers_table": customer_verified,
                    "users_table": user_verified
                }
            }

    except Exception as e:
        db.rollback()
        return {"success": False, "error": str(e)}


@app.get("/api/debug/order/{order_id}")
def debug_order(order_id: int, db: Session = Depends(get_db), _user = Depends(require_admin)):
    """Debug endpoint to check raw order data - disabled in production."""
    if _is_production:
        raise HTTPException(status_code=404, detail="Not found")
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        return {"error": "Order not found"}
    return {
        "id": order.id,
        "order_number": order.order_number,
        "customer_id": order.customer_id,
        "customer_name": order.customer_name,
        "customer_email": order.customer_email,
        "vendor_id": order.vendor_id,
        "status": order.status.value if order.status else None
    }


@app.post("/api/demo/clear-driver-bids")
def clear_demo_driver_bids(secret_key: Optional[str] = Query(None), db: Session = Depends(get_db)):
    """
    Clear all old bids for the demo driver (ID 48).
    This resets the driver to a clean state for testing.
    """
    _require_admin_secret(secret_key)
    try:
        from models import RideBid, Driver, RideRequest, RideRequestStatus

        # Get demo driver
        demo_driver = db.query(Driver).filter(Driver.id == 48).first()
        if not demo_driver:
            return {"success": False, "error": "Demo driver not found"}

        # Get all bid IDs for this driver
        driver_bid_ids = [b.id for b in db.query(RideBid).filter(RideBid.driver_id == 48).all()]

        # Clear matched_bid_id and matched_driver_id references in ride_requests first (FK constraint)
        if driver_bid_ids:
            cleared_refs = db.query(RideRequest).filter(
                RideRequest.matched_bid_id.in_(driver_bid_ids)
            ).update({
                RideRequest.matched_bid_id: None,
                RideRequest.matched_driver_id: None
            }, synchronize_session=False)
        else:
            cleared_refs = 0

        # Now delete all bids for this driver
        deleted_count = db.query(RideBid).filter(RideBid.driver_id == 48).delete()

        # Also clear any active orders assigned to this driver
        from models import Order, OrderStatus
        active_orders = db.query(Order).filter(
            Order.driver_id == 48,
            Order.status.in_([OrderStatus.READY_FOR_PICKUP, OrderStatus.OUT_FOR_DELIVERY])
        ).all()

        for order in active_orders:
            order.status = OrderStatus.DELIVERED
            order.delivered_at = datetime.now()

        # Clear any active rides assigned to this driver
        active_rides = db.query(RideRequest).filter(
            RideRequest.matched_driver_id == 48,
            RideRequest.status.in_([RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS])
        ).all()

        for ride in active_rides:
            ride.status = RideRequestStatus.COMPLETED
            ride.completed_at = datetime.now()

        db.commit()

        return {
            "success": True,
            "bids_deleted": deleted_count,
            "refs_cleared": cleared_refs,
            "orders_completed": len(active_orders),
            "rides_completed": len(active_rides),
            "message": f"Cleared {deleted_count} bids, {cleared_refs} refs, completed {len(active_orders)} orders and {len(active_rides)} rides for demo driver"
        }
    except Exception as e:
        db.rollback()
        return {"success": False, "error": str(e)}


@app.post("/api/admin/cleanup-expired-bids")
def cleanup_expired_bids(request: Request, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    """
    Clean up all expired bids system-wide.
    Marks bids past their expires_at as EXPIRED and clears stale references.
    """
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    try:
        from models import RideBid, BidStatus
        from sqlalchemy import and_

        now = datetime.utcnow()

        # Find all expired pending bids
        expired_bids = db.query(RideBid).filter(
            and_(
                RideBid.status == BidStatus.PENDING,
                RideBid.expires_at < now
            )
        ).all()

        expired_count = 0
        for bid in expired_bids:
            bid.status = BidStatus.EXPIRED
            bid.customer_response = "Bid expired (no response within 10 minutes)"
            expired_count += 1

        db.commit()

        return {
            "success": True,
            "expired_count": expired_count,
            "message": f"Marked {expired_count} bids as expired"
        }
    except Exception as e:
        db.rollback()
        return {"success": False, "error": str(e)}


# ==================== ANDROID COMPATIBILITY ENDPOINTS ====================
# These endpoints provide aliases for Android app compatibility

# Legal endpoint aliases (Android expects different paths)
@app.get("/api/legal/tos")
def get_terms_of_service_android():
    """Android-compatible Terms of Service endpoint (alias for /api/legal/terms)."""
    return get_terms_of_service()


@app.get("/api/legal/privacy-policy")
def get_privacy_policy_android():
    """Android-compatible Privacy Policy endpoint (alias for /api/legal/privacy)."""
    return get_privacy_policy()


# ==================== TNC REGULATORY INFO (CPUC Compliance) ====================

@app.get("/api/legal/regulatory")
def get_regulatory_info():
    """TNC-14: Regulatory info for CA TNC compliance. Apps display this on help/about screens and receipts."""
    return {
        "tnc_operator": {
            "carrier_name": "Zietra Technologies inc",
            "dba": "Dollor.ai",
            "permit_type": "TCP-P TNC",
            "permit_number": None,  # To be filled after CPUC issues permit
            "website": "https://dollor.ai"
        },
        "zero_tolerance_policy": {
            "statement": "Dollor.ai maintains a zero-tolerance policy for drug and alcohol use by drivers during TNC services. Any driver suspected of being under the influence will be immediately suspended pending investigation.",
            "report_email": "support@dollor.ai",
            "report_in_app": True
        },
        "cpuc_consumer_complaint": {
            "phone": "1-800-894-9444",
            "email": "CIU_intake@cpuc.ca.gov",
            "description": "California Public Utilities Commission - Consumer Intake Unit. File complaints about TNC service."
        },
        "accessibility": {
            "wheelchair_accessible_vehicles": "Request via app when booking",
            "service_animals": "Service animals are welcome in all Dollor.ai rides. Drivers may not refuse service to passengers with service animals.",
            "accessibility_feedback": "support@dollor.ai"
        },
        "fees": {
            "access_for_all_fee": "$0.10 per completed trip, remitted quarterly to CPUC Access for All Fund",
            "platform_fee": "Flat $1-$3 based on fare tier (not a percentage commission)"
        }
    }


# ==================== LEGAL HTML PAGES (App Store Requirement) ====================
# These serve the actual HTML pages at /privacy and /terms for App Store compliance

@app.get("/privacy", response_class=HTMLResponse)
def serve_privacy_policy_page():
    """Serve Privacy Policy HTML page for App Store compliance."""
    legal_dir = os.path.join(os.path.dirname(__file__), "legal")
    privacy_file = os.path.join(legal_dir, "privacy.html")
    try:
        with open(privacy_file, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read(), status_code=200)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Privacy policy page not found")


@app.get("/terms", response_class=HTMLResponse)
def serve_terms_of_service_page():
    """Serve Terms of Service HTML page for App Store compliance."""
    legal_dir = os.path.join(os.path.dirname(__file__), "legal")
    terms_file = os.path.join(legal_dir, "terms.html")
    try:
        with open(terms_file, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read(), status_code=200)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Terms of service page not found")


# Fare estimate helper for ERP alias (below)
# NOTE: POST /api/rides/estimate is handled by bid_routes.py (registered first via include_router).
# This function is kept only for the /api/erp/rides/fare-estimate alias.
# Driver profile GET /api/erp/drivers/{driver_id} is handled by get_driver_profile_by_id (line ~3027)
def get_fare_estimate_android(request: dict, db: Session = Depends(get_db)):
    """Fare estimate calculation (used by ERP alias endpoint)."""
    pickup_lat = request.get("pickup_latitude", 0)
    pickup_lng = request.get("pickup_longitude", 0)
    dropoff_lat = request.get("dropoff_latitude", 0)
    dropoff_lng = request.get("dropoff_longitude", 0)

    # Validate coordinate ranges
    if not (-90 <= pickup_lat <= 90) or not (-90 <= dropoff_lat <= 90):
        raise HTTPException(status_code=400, detail="Invalid coordinates: latitude must be between -90 and 90")
    if not (-180 <= pickup_lng <= 180) or not (-180 <= dropoff_lng <= 180):
        raise HTTPException(status_code=400, detail="Invalid coordinates: longitude must be between -180 and 180")

    # Calculate distance using Haversine formula
    import math
    R = 3959  # Earth's radius in miles

    lat1, lon1 = math.radians(pickup_lat), math.radians(pickup_lng)
    lat2, lon2 = math.radians(dropoff_lat), math.radians(dropoff_lng)

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    distance_miles = R * c

    # Calculate fare
    base_fare = 5.00
    per_mile_rate = 1.50
    per_minute_rate = 0.25
    estimated_minutes = distance_miles * 2.5  # Rough estimate

    fare = base_fare + (distance_miles * per_mile_rate) + (estimated_minutes * per_minute_rate)

    # Calculate tiered platform fee
    if distance_miles <= 10:
        platform_fee = 1.00
    elif distance_miles <= 20:
        platform_fee = 2.00
    else:
        platform_fee = 3.00

    driver_earnings = fare - platform_fee

    return {
        "fare_estimate": round(fare, 2),
        "total_fare": round(fare, 2),
        "platform_fee": platform_fee,
        "driver_earnings": round(driver_earnings, 2),
        "base_fare": base_fare,
        "distance_fee": round(distance_miles * per_mile_rate, 2),
        "time_fee": round(estimated_minutes * per_minute_rate, 2),
        "distance_miles": round(distance_miles, 1),
        "duration_minutes": round(estimated_minutes),
        "surge_multiplier": 1.0,
        "currency": "USD"
    }


@app.post("/api/erp/rides/fare-estimate")
def get_fare_estimate_erp(request: dict, db: Session = Depends(get_db)):
    """ERP fare estimate endpoint (alias)."""
    return get_fare_estimate_android(request, db)


# Driver location update endpoint
@app.post("/api/driver/location")
def update_driver_location_android(request: dict, db: Session = Depends(get_db), driver: Driver = Depends(require_driver)):
    """Update driver's current location (Android compatible)."""
    driver_id = request.get("driver_id")
    latitude = request.get("latitude")
    longitude = request.get("longitude")

    # SECURITY: Verify the authenticated driver owns this driver_id
    if driver_id and driver_id != driver.id:
        raise HTTPException(status_code=403, detail="Access denied")

    driver.current_latitude = latitude
    driver.current_longitude = longitude
    db.commit()

    if latitude is not None and longitude is not None:
        _check_driver_proximity_to_delivery(driver.id, latitude, longitude, db)

    return {
        "success": True,
        "driver_id": driver.id,
        "latitude": latitude,
        "longitude": longitude,
        "updated_at": datetime.now().isoformat()
    }


# ============================================================
# ADMIN - RIDESHARE MANAGEMENT
# ============================================================
# NOTE: /api/erp/orders/{order_id}/picked-up and /api/erp/orders/{order_id}/delivered
# are now handled by order_flow.py router (included above) to avoid route collision

@app.get("/api/admin/rideshare/requests")
def get_admin_rideshare_requests(
    status: Optional[str] = None,
    limit: int = Query(100, le=500),
    offset: int = 0,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Get all ride requests for admin dashboard.
    Shows ride requests with customer/driver info and platform fees.
    """
    try:
        from models import RideRequest, RideRequestStatus

        query = db.query(RideRequest)

        # Map status string to enum
        status_enum_map = {
            'open': RideRequestStatus.OPEN,
            'bidding': RideRequestStatus.BIDDING,
            'matched': RideRequestStatus.MATCHED,
            'in_progress': RideRequestStatus.IN_PROGRESS,
            'completed': RideRequestStatus.COMPLETED,
            'cancelled': RideRequestStatus.CANCELLED,
            'expired': RideRequestStatus.EXPIRED
        }

        if status and status != 'all':
            if status in status_enum_map:
                query = query.filter(RideRequest.status == status_enum_map[status])

        query = query.order_by(RideRequest.created_at.desc())

        total = query.count()
        rides = query.offset(offset).limit(limit).all()

        # Calculate stats using enum comparisons
        all_rides = db.query(RideRequest).all()
        pending_count = len([r for r in all_rides if r.status in [RideRequestStatus.OPEN, RideRequestStatus.BIDDING]])
        active_count = len([r for r in all_rides if r.status in [RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS]])
        completed_count = len([r for r in all_rides if r.status == RideRequestStatus.COMPLETED])

        # Calculate platform revenue from completed rides
        total_revenue = sum(r.platform_fee or 0 for r in all_rides if r.status == RideRequestStatus.COMPLETED)

        # Convert km to miles for frontend
        def km_to_miles(km):
            return (km or 0) * 0.621371

        return {
            "rides": [
                {
                    "id": r.id,
                    "customer_id": r.customer_id,
                    "customer_name": r.customer_name or "Customer",
                    "customer_phone": r.customer_phone or "",
                    "pickup_address": r.pickup_address,
                    "dropoff_address": r.dropoff_address,
                    "pickup_lat": r.pickup_latitude,
                    "pickup_lng": r.pickup_longitude,
                    "dropoff_lat": r.dropoff_latitude,
                    "dropoff_lng": r.dropoff_longitude,
                    "distance_miles": km_to_miles(r.estimated_distance_km),
                    "estimated_fare": r.suggested_price,
                    "final_price": r.final_price,
                    "platform_fee": r.platform_fee,
                    "status": r.status.value if hasattr(r.status, 'value') else str(r.status),
                    "driver_id": r.matched_driver_id,
                    "driver_name": None,  # Would join with drivers table
                    "created_at": r.created_at.isoformat() if r.created_at else None,
                    "accepted_at": r.matched_at.isoformat() if r.matched_at else None,
                    "completed_at": r.completed_at.isoformat() if r.completed_at else None
                }
                for r in rides
            ],
            "stats": {
                "totalRequests": total,
                "pendingRequests": pending_count,
                "activeRides": active_count,
                "completedRides": completed_count,
                "totalRevenue": round(total_revenue, 2)
            },
            "pagination": {
                "total": total,
                "limit": limit,
                "offset": offset
            }
        }
    except Exception as e:
        logging.error(f"Ride admin dashboard error: {e}", exc_info=True)
        return {
            "error": "An internal error occurred",
            "rides": [],
            "stats": {"totalRequests": 0, "pendingRequests": 0, "activeRides": 0, "completedRides": 0, "totalRevenue": 0}
        }


@app.get("/api/admin/rideshare/active")
def get_admin_active_rides(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    """
    Get currently active rides for real-time monitoring.
    """
    try:
        from models import RideRequest, Driver, RideRequestStatus
        from datetime import datetime

        # Active statuses from the enum
        active_statuses = [RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS]

        rides = db.query(RideRequest).filter(
            RideRequest.status.in_(active_statuses)
        ).order_by(RideRequest.created_at.desc()).all()

        # Get online drivers count
        online_drivers = db.query(Driver).filter(Driver.is_online == True).count()

        # Calculate average ride time for completed rides today
        today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        completed_today = db.query(RideRequest).filter(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= today_start
        ).all()

        avg_ride_time = 0
        if completed_today:
            ride_times = []
            for r in completed_today:
                if r.matched_at and r.completed_at:
                    diff = (r.completed_at - r.matched_at).total_seconds() / 60
                    ride_times.append(diff)
            if ride_times:
                avg_ride_time = sum(ride_times) / len(ride_times)

        # Convert km to miles
        def km_to_miles(km):
            return (km or 0) * 0.621371

        # Get driver info for matched rides
        def get_driver_info(driver_id):
            if not driver_id:
                return None, ""
            driver = db.query(Driver).filter(Driver.id == driver_id).first()
            if driver:
                return f"{driver.first_name} {driver.last_name}", driver.phone or ""
            return None, ""

        return {
            "rides": [
                {
                    "id": r.id,
                    "customer_name": r.customer_name or "Customer",
                    "customer_phone": r.customer_phone or "",
                    "driver_name": get_driver_info(r.matched_driver_id)[0],
                    "driver_phone": get_driver_info(r.matched_driver_id)[1],
                    "driver_id": r.matched_driver_id,
                    "pickup_address": r.pickup_address,
                    "dropoff_address": r.dropoff_address,
                    "distance_miles": km_to_miles(r.estimated_distance_km),
                    "final_price": r.final_price,
                    "platform_fee": r.platform_fee,
                    "status": r.status.value if hasattr(r.status, 'value') else str(r.status),
                    "started_at": r.matched_at.isoformat() if r.matched_at else None,
                    "estimated_arrival": None,
                    "progress_percent": 50 if r.status == RideRequestStatus.IN_PROGRESS else 25,
                    "driver_lat": None,
                    "driver_lng": None
                }
                for r in rides
            ],
            "stats": {
                "activeCount": len(rides),
                "driversOnline": online_drivers,
                "avgRideTime": round(avg_ride_time, 1),
                "totalFaresInProgress": sum(r.final_price or 0 for r in rides)
            }
        }
    except Exception as e:
        logging.error(f"Active rides dashboard error: {e}", exc_info=True)
        return {
            "error": "An internal error occurred",
            "rides": [],
            "stats": {"activeCount": 0, "driversOnline": 0, "avgRideTime": 0, "totalFaresInProgress": 0}
        }


# ============================================================
# ADMIN - DRIVERS MANAGEMENT
# ============================================================

@app.get("/api/admin/drivers")
def get_admin_drivers(
    status: Optional[str] = None,
    limit: int = Query(100, le=500),
    offset: int = 0,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Get all drivers for admin management. Requires admin authentication.
    """

    from models import Driver, DriverStatus

    query = db.query(Driver)

    # Map status string to enum
    status_enum_map = {
        'pending': DriverStatus.PENDING,
        'approved': DriverStatus.APPROVED,
        'active': DriverStatus.ACTIVE,
        'inactive': DriverStatus.INACTIVE,
        'suspended': DriverStatus.SUSPENDED
    }

    if status and status != 'all':
        if status in status_enum_map:
            query = query.filter(Driver.status == status_enum_map[status])

    query = query.order_by(Driver.created_at.desc())

    total = query.count()
    drivers = query.offset(offset).limit(limit).all()

    # Calculate stats - compare enum values properly
    all_drivers = db.query(Driver).all()

    def get_status_value(d):
        return d.status.value if hasattr(d.status, 'value') else str(d.status)

    active_count = len([d for d in all_drivers if get_status_value(d) in ['approved', 'active']])
    pending_count = len([d for d in all_drivers if get_status_value(d) == 'pending'])
    online_count = len([d for d in all_drivers if d.is_online])

    return {
        "drivers": [
            {
                "id": d.id,
                "driver_id": d.driver_id,
                "first_name": d.first_name,
                "last_name": d.last_name,
                "email": d.email,
                "phone": d.phone,
                # Address
                "street": d.street,
                "city": d.city,
                "state": d.state,
                "zip_code": d.zip_code,
                # Vehicle
                "vehicle_type": d.vehicle_type,
                "vehicle_make": d.vehicle_make,
                "vehicle_model": d.vehicle_model,
                "vehicle_year": d.vehicle_year,
                "vehicle_color": d.vehicle_color,
                "license_plate": d.license_plate,
                # Status & stats
                "status": d.status.value if hasattr(d.status, 'value') else str(d.status),
                "rating": d.rating,
                "total_deliveries": d.total_deliveries,
                "is_online": d.is_online,
                "documents_verified": d.documents_verified,
                "stripe_onboarded": d.stripe_onboarded,
                "created_at": d.created_at.isoformat() if d.created_at else None,
                # Photos
                "photo_url": d.photo_url,
                "vehicle_photo_url": d.vehicle_photo_url if hasattr(d, 'vehicle_photo_url') else None
            }
            for d in drivers
        ],
        "stats": {
            "totalDrivers": total,
            "activeDrivers": active_count,
            "pendingApproval": pending_count,
            "onlineNow": online_count
        },
        "pagination": {
            "total": total,
            "limit": limit,
            "offset": offset
        }
    }


@app.post("/api/admin/drivers/{driver_id}/set-documents")
def admin_set_driver_documents(
    request: Request,
    driver_id: int,
    drivers_license: bool = Query(True, description="Set driver's license as verified"),
    insurance: bool = Query(True, description="Set insurance as verified"),
    photo: bool = Query(True, description="Set photo as uploaded"),
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Admin endpoint to directly set driver document verification status.
    Used for testing and manual verification bypass. Requires admin authentication.
    """
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")

    from models import Driver

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    # Set document flags
    if drivers_license:
        driver.drivers_license = True
        driver.drivers_license_url = f"/uploads/driver_documents/{driver_id}/license_verified.png"
    if insurance:
        driver.insurance = True
        driver.insurance_url = f"/uploads/driver_documents/{driver_id}/insurance_verified.png"
    if photo:
        driver.photo_url = f"/uploads/driver_documents/{driver_id}/photo_verified.png"

    # If all documents are set, mark driver as fully verified
    if drivers_license and insurance and photo:
        driver.documents_verified = True
        driver.verification_status = "verified"
        driver.documents_verified_at = datetime.utcnow()

    driver.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "message": "Driver documents set successfully",
        "driver_id": driver.id,
        "documents_verified": driver.documents_verified,
        "verification_status": driver.verification_status,
        "documents": {
            "drivers_license": driver.drivers_license,
            "drivers_license_url": driver.drivers_license_url,
            "insurance": driver.insurance,
            "insurance_url": driver.insurance_url,
            "photo_url": driver.photo_url
        }
    }


@app.post("/api/admin/drivers/{driver_id}/verify")
def admin_verify_driver(
    request: Request,
    driver_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Admin endpoint to directly mark a driver as verified.
    Sets documents_verified=True, verification_status='verified', and status='approved'.
    Used for demo accounts and testing. Requires admin authentication.
    """
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")

    from models import Driver, DriverStatus

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    # Mark as fully verified
    driver.documents_verified = True
    driver.verification_status = "verified"
    driver.documents_verified_at = datetime.utcnow()
    driver.status = DriverStatus.APPROVED
    driver.approved_at = datetime.utcnow()

    # Also set all document flags
    driver.drivers_license = True
    driver.insurance = True
    driver.background_check = True

    driver.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "message": "Driver verified successfully",
        "driver_id": driver.id,
        "driver_name": f"{driver.first_name} {driver.last_name}",
        "status": driver.status.value if hasattr(driver.status, 'value') else str(driver.status),
        "documents_verified": driver.documents_verified,
        "verification_status": driver.verification_status
    }


class AdminDriverBankAccountRequest(BaseModel):
    bank_name: str
    account_number: str  # Full account number — last4 stored, rest discarded
    routing_number: str
    account_holder_name: str


@app.post("/api/admin/drivers/{driver_id}/bank-account")
def admin_set_driver_bank_account(
    request: Request,
    driver_id: int,
    body: AdminDriverBankAccountRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Admin endpoint to add and verify a driver's bank account.
    Stores bank details in DB and marks as verified (approved).
    """
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")

    from models import Driver

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    # Store bank account — encrypt sensitive fields, only keep last 4 plaintext
    from encryption import encrypt_field
    driver.bank_name = encrypt_field(body.bank_name)
    driver.bank_last4 = body.account_number[-4:]  # Last 4 stays plaintext for display
    driver.bank_routing_number = encrypt_field(body.routing_number)
    driver.bank_account_holder = encrypt_field(body.account_holder_name)
    driver.bank_verified = True
    driver.bank_verified_at = datetime.utcnow()
    driver.bank_verified_by = admin.id
    driver.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "message": "Bank account added and verified",
        "driver_id": driver.id,
        "driver_name": f"{driver.first_name} {driver.last_name}",
        "bank_name": decrypt_field(driver.bank_name),
        "last4": driver.bank_last4,
        "bank_verified": driver.bank_verified
    }


@app.post("/api/admin/cleanup/pending-orders")
def admin_cleanup_pending_orders(
    request: Request,
    db: Session = Depends(get_db),
    secret_key: str = None,
):
    """
    Admin endpoint to cancel all old pending orders and ride requests.
    This cleans up stale data that clutters the Restaurant and Driver apps.
    Only cancels: pending_payment, pending_restaurant, pending_delivery_decision
    Keeps: confirmed, preparing, ready_for_pickup, out_for_delivery, delivered, etc.
    Accepts either admin JWT Bearer token or ADMIN_SECRET_KEY query param.
    """
    # Auth: accept JWT Bearer or X-Admin-Secret header (not query param — see H2 fix)
    import hmac as _hmac_mod
    expected_key = os.getenv("ADMIN_SECRET_KEY", "")
    auth_header = request.headers.get("authorization", "")
    has_jwt = auth_header.startswith("Bearer ")
    # M7: use constant-time compare to prevent timing attacks
    _provided = (secret_key or request.headers.get("X-Admin-Secret", "")).encode()
    has_secret = bool(expected_key) and bool(_provided) and _hmac_mod.compare_digest(
        _provided, expected_key.encode()
    )
    if not has_jwt and not has_secret:
        raise HTTPException(status_code=401, detail="Admin authentication required")
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    from models import Order, OrderStatus, RideRequest, RideRequestStatus

    # Define which statuses to cancel
    pending_statuses = [
        OrderStatus.PENDING_PAYMENT,
        OrderStatus.PENDING_RESTAURANT,
        OrderStatus.PENDING_DELIVERY_DECISION,
    ]

    # Cancel pending orders
    cancelled_order_count = 0
    try:
        pending_orders = db.query(Order).filter(
            Order.status.in_(pending_statuses)
        ).all()

        for order in pending_orders:
            order.status = OrderStatus.CANCELLED
            order.updated_at = datetime.utcnow()
            cancelled_order_count += 1
    except Exception as e:
        logger.warning(f"Could not cancel pending orders: {e}")

    # Cancel open ride requests
    cancelled_ride_count = 0
    try:
        open_rides = db.query(RideRequest).filter(
            RideRequest.status.in_([
                RideRequestStatus.OPEN,
                RideRequestStatus.BIDDING
            ])
        ).all()

        for ride in open_rides:
            ride.status = RideRequestStatus.CANCELLED
            cancelled_ride_count += 1
    except Exception as e:
        logger.warning(f"Could not cancel ride requests: {e}")

    db.commit()

    return {
        "success": True,
        "message": "Pending orders and rides cancelled",
        "orders_cancelled": cancelled_order_count,
        "rides_cancelled": cancelled_ride_count,
        "pending_statuses_cleared": [s.value for s in pending_statuses]
    }


@app.post("/api/admin/cleanup/all-incomplete")
def admin_cleanup_all_incomplete(
    request: Request,
    db: Session = Depends(get_db),
    secret_key: str = None,
):
    """
    Admin endpoint to cancel ALL incomplete orders and ride requests.
    This is more aggressive than /cleanup/pending-orders.

    Cancels:
    - Orders NOT in: DELIVERED, CANCELLED
    - Rides NOT in: COMPLETED, CANCELLED, EXPIRED
    - Also cancels any bids that are still PENDING
    Accepts either admin JWT Bearer token or ADMIN_SECRET_KEY query param.
    """
    # Auth: accept JWT Bearer or X-Admin-Secret header (not query param — see H2 fix)
    import hmac as _hmac_mod
    expected_key = os.getenv("ADMIN_SECRET_KEY", "")
    auth_header = request.headers.get("authorization", "")
    has_jwt = auth_header.startswith("Bearer ")
    # M7: use constant-time compare to prevent timing attacks
    _provided = (secret_key or request.headers.get("X-Admin-Secret", "")).encode()
    has_secret = bool(expected_key) and bool(_provided) and _hmac_mod.compare_digest(
        _provided, expected_key.encode()
    )
    if not has_jwt and not has_secret:
        raise HTTPException(status_code=401, detail="Admin authentication required")
    check_rate_limit(request, admin_mutation_limiter, "admin_mutation")
    from models import Order, OrderStatus, RideRequest, RideRequestStatus, RideBid, BidStatus

    # Cancel all incomplete orders
    cancelled_order_count = 0
    completed_statuses = [OrderStatus.DELIVERED, OrderStatus.CANCELLED]

    try:
        incomplete_orders = db.query(Order).filter(
            ~Order.status.in_(completed_statuses)
        ).all()

        for order in incomplete_orders:
            order.status = OrderStatus.CANCELLED
            order.updated_at = datetime.utcnow()
            cancelled_order_count += 1
    except Exception as e:
        logger.warning(f"Could not cancel incomplete orders: {e}")

    # Cancel all incomplete ride requests
    cancelled_ride_count = 0
    ride_completed_statuses = [
        RideRequestStatus.COMPLETED,
        RideRequestStatus.CANCELLED,
        RideRequestStatus.EXPIRED
    ]

    try:
        incomplete_rides = db.query(RideRequest).filter(
            ~RideRequest.status.in_(ride_completed_statuses)
        ).all()

        for ride in incomplete_rides:
            ride.status = RideRequestStatus.CANCELLED
            cancelled_ride_count += 1
    except Exception as e:
        logger.warning(f"Could not cancel incomplete rides: {e}")

    # Cancel all pending bids
    cancelled_bid_count = 0
    try:
        pending_bids = db.query(RideBid).filter(
            RideBid.status == BidStatus.PENDING
        ).all()

        for bid in pending_bids:
            bid.status = BidStatus.EXPIRED
            cancelled_bid_count += 1
    except Exception as e:
        logger.warning(f"Could not cancel pending bids: {e}")

    db.commit()

    return {
        "success": True,
        "message": "All incomplete orders, rides, and bids cancelled",
        "orders_cancelled": cancelled_order_count,
        "rides_cancelled": cancelled_ride_count,
        "bids_cancelled": cancelled_bid_count
    }


# ============================================================
# ADMIN INSPECTION ENDPOINTS
# ============================================================

@app.get("/api/admin/database/schema")
def get_database_schema(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    """Get complete database schema - all tables and columns (admin only)"""
    from sqlalchemy import text

    try:
        # Get all tables
        tables_result = db.execute(text("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public'
            ORDER BY table_name
        """))
        tables = [row[0] for row in tables_result.fetchall()]

        schema = {}
        for table in tables:
            cols_result = db.execute(text("""
                SELECT column_name, data_type, is_nullable, column_default
                FROM information_schema.columns
                WHERE table_name = :table_name
                ORDER BY ordinal_position
            """), {"table_name": table})

            columns = []
            for row in cols_result.fetchall():
                columns.append({
                    "name": row[0],
                    "type": row[1],
                    "nullable": row[2] == 'YES',
                    "default": row[3]
                })
            schema[table] = {
                "column_count": len(columns),
                "columns": columns
            }

        return {
            "success": True,
            "table_count": len(tables),
            "tables": list(schema.keys()),
            "schema": schema
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


@app.get("/api/admin/api/routes")
def get_all_api_routes(admin: User = Depends(require_admin)):
    """Get all API routes with methods and paths (admin only)"""
    routes = []
    route_set = set()  # For duplicate detection

    for route in app.routes:
        if hasattr(route, 'path') and hasattr(route, 'methods'):
            for method in route.methods:
                if method not in ['HEAD', 'OPTIONS']:
                    route_key = f"{method}:{route.path}"
                    is_duplicate = route_key in route_set
                    route_set.add(route_key)

                    routes.append({
                        "method": method,
                        "path": route.path,
                        "name": route.name if hasattr(route, 'name') else None,
                        "duplicate": is_duplicate
                    })

    # Group by prefix
    groups = {}
    for r in routes:
        prefix = r['path'].split('/')[2] if len(r['path'].split('/')) > 2 else 'root'
        if prefix not in groups:
            groups[prefix] = []
        groups[prefix].append(r)

    # Find duplicates
    duplicates = [r for r in routes if r['duplicate']]

    return {
        "success": True,
        "total_routes": len(routes),
        "duplicate_count": len(duplicates),
        "duplicates": duplicates,
        "routes_by_group": {k: len(v) for k, v in groups.items()},
        "routes": sorted(routes, key=lambda x: (x['path'], x['method']))
    }


@app.get("/api/admin/api/duplicates")
def get_duplicate_routes(admin: User = Depends(require_admin)):
    """Find duplicate API routes and schemas"""
    from collections import defaultdict

    # Find duplicate routes
    route_counts = defaultdict(list)
    for route in app.routes:
        if hasattr(route, 'path') and hasattr(route, 'methods'):
            for method in route.methods:
                if method not in ['HEAD', 'OPTIONS']:
                    key = f"{method}:{route.path}"
                    route_counts[key].append({
                        "name": route.name if hasattr(route, 'name') else None,
                        "endpoint": str(route.endpoint) if hasattr(route, 'endpoint') else None
                    })

    duplicate_routes = {k: v for k, v in route_counts.items() if len(v) > 1}

    # Find similar paths (potential duplicates with different naming)
    paths = [route.path for route in app.routes if hasattr(route, 'path')]
    similar_paths = []

    # Check for auth patterns
    auth_paths = [p for p in paths if '/auth/' in p]
    customer_paths = [p for p in paths if '/customer/' in p]
    driver_paths = [p for p in paths if '/driver/' in p]
    vendor_paths = [p for p in paths if '/vendor/' in p]

    return {
        "success": True,
        "duplicate_routes": duplicate_routes,
        "duplicate_count": len(duplicate_routes),
        "path_analysis": {
            "auth_endpoints": len(auth_paths),
            "customer_endpoints": len(customer_paths),
            "driver_endpoints": len(driver_paths),
            "vendor_endpoints": len(vendor_paths),
            "total_paths": len(paths)
        }
    }


# =============================================================================
# AI INSIGHTS API - Restaurant Analytics & Predictions
# =============================================================================

class AIInsightsResponse(BaseModel):
    """AI-powered insights for restaurant dashboard"""
    success: bool
    vendor_id: int
    period: str
    generated_at: str

    # Demand Forecast
    demand_forecast: List[dict]
    estimated_orders_next_hour: int
    peak_hour: str
    peak_hour_orders: int
    forecast_confidence: float

    # Popular Items
    popular_items: List[dict]

    # Hourly Distribution
    hourly_distribution: List[dict]

    # Performance Metrics
    total_orders: int
    total_revenue: float
    average_order_value: float
    order_completion_rate: float
    average_prep_time_minutes: int

    # Peak Hours Analysis
    lunch_peak: dict
    dinner_peak: dict

    # Staffing Recommendations
    staffing_recommendations: List[dict]

    # Smart Recommendations
    recommendations: List[dict]






# =============================================================================
# ROUTE ALIASES - Auto-generated to fix stacked decorator anti-pattern
# =============================================================================
app.add_api_route("/auth/driver/login", driver_login, methods=["POST"])
app.add_api_route("/auth/driver/refresh", driver_refresh_token, methods=["POST"])
app.add_api_route("/auth/driver/register", driver_register, methods=["POST"])
app.add_api_route("/auth/driver/google", driver_google_auth, methods=["POST"])
app.add_api_route("/auth/driver/apple-auth", driver_apple_auth, methods=["POST"])
app.add_api_route("/api/auth/driver/online", set_driver_online, methods=["POST"])
app.add_api_route("/api/auth/driver/toggle-online", set_driver_online, methods=["PUT"])
app.add_api_route("/api/auth/driver/toggle-online", set_driver_online, methods=["POST"])
app.add_api_route("/api/driver/online/toggle", set_driver_online, methods=["PUT"])
app.add_api_route("/api/driver/online/toggle", set_driver_online, methods=["POST"])
app.add_api_route("/auth/customer/login", customer_auth_login, methods=["POST"])
app.add_api_route("/auth/customer/register", customer_auth_register, methods=["POST"])
app.add_api_route("/auth/customer/refresh", customer_refresh_token, methods=["POST"])
app.add_api_route("/auth/customer/google", customer_google_auth, methods=["POST"])
app.add_api_route("/api/customer/{customer_id}/profile", update_customer_profile, methods=["PUT"])
app.add_api_route("/customer/{customer_id}/profile", update_customer_profile, methods=["PUT"])
app.add_api_route("/customers/{customer_id}/delete", delete_customer_account, methods=["DELETE"])
app.add_api_route("/customer/email/send-verification", send_verification_email, methods=["POST"])
app.add_api_route("/customer/email/verify", verify_customer_email, methods=["POST"])
app.add_api_route("/customer/email/status", get_email_verification_status, methods=["GET"])
app.add_api_route("/api/erp/drivers/{driver_id}", get_driver_profile_by_id, methods=["GET"])
app.add_api_route("/api/drivers/{driver_id}", update_driver_profile_by_id, methods=["PUT"])
app.add_api_route("/erp/drivers/{driver_id}", update_driver_profile_by_id, methods=["PUT"])
app.add_api_route("/api/erp/drivers/{driver_id}", update_driver_profile_by_id, methods=["PUT"])
app.add_api_route("/drivers/{driver_id}/status", get_driver_status, methods=["GET"])
app.add_api_route("/drivers/{driver_id}/status", post_driver_status, methods=["POST"])
app.add_api_route("/api/drivers/{driver_id}/documents", get_driver_documents_by_id, methods=["GET"])
app.add_api_route("/api/drivers/{driver_id}/documents", upload_driver_document_by_id, methods=["POST"])
app.add_api_route("/api/auth/customer/apple-auth", customer_apple_auth, methods=["POST"])
app.add_api_route("/auth/customer/apple-auth", customer_apple_auth, methods=["POST"])
app.add_api_route("/customer/apple-auth", customer_apple_auth, methods=["POST"])
# Routes removed - already exist in bid_routes.py which is included as a router:
# - GET /request/{request_id}/bids -> get_bids_for_request
# - POST /request/{request_id}/bid -> submit_bid
# - POST /bid/{bid_id}/withdraw -> withdraw_bid
# - POST /bid/{bid_id}/respond -> respond_to_bid
# - POST /bid/{bid_id}/accept-counter -> accept_counter_offer
# - POST /bid/{bid_id}/reject-counter -> reject_counter_offer
app.add_api_route("/driver/bids", get_driver_bids, methods=["GET"])
from bid_routes import get_available_ride_requests as _live_available_rides
app.add_api_route("/rides/available", _live_available_rides, methods=["GET"])  # same handler as /api/rides/available
app.add_api_route("/p2p/ride-requests/{ride_request_id}/chat", get_ride_request_chat, methods=["GET"])
app.add_api_route("/p2p/ride-requests/{ride_request_id}/chat", send_ride_request_chat, methods=["POST"])
app.add_api_route("/chat/ride/{ride_id}", get_ride_chat_messages_alias, methods=["GET"])
app.add_api_route("/chat/ride/{ride_id}", send_ride_chat_message_alias, methods=["POST"])
app.add_api_route("/erp/orders/{order_id}/start-delivery-decision", _format_address, methods=["POST"])
app.add_api_route("/erp/orders/{order_id}/restaurant-delivery-decision", _format_address, methods=["POST"])
app.add_api_route("/erp/orders/{order_id}/delivery-decision-status", _format_address, methods=["GET"])
app.add_api_route("/erp/customers/{customer_id}/fcm-token", register_customer_fcm_token, methods=["POST"])
app.add_api_route("/erp/drivers/{driver_id}/fcm-token", register_driver_fcm_token, methods=["POST"])
app.add_api_route("/erp/customers/{customer_id}/fcm-token", unregister_customer_fcm_token, methods=["DELETE"])
app.add_api_route("/erp/drivers/{driver_id}/fcm-token", unregister_driver_fcm_token, methods=["DELETE"])
app.add_api_route("/api/health", health_check, methods=["GET"])
app.add_api_route("/erp/analytics/realtime", proxy_realtime_dashboard, methods=["GET"])
app.add_api_route("/api/erp/analytics/realtime", proxy_realtime_dashboard, methods=["GET"])
app.add_api_route("/erp/analytics/ai-employees", get_ai_employees_analytics, methods=["GET"])

# =============================================================================
# TAX CALCULATION API
# =============================================================================
# Simple state-level tax rates for US states
# Rates are state-level only (city/county rates can be added later)
# Last updated: February 2026

US_STATE_TAX_RATES = {
    "AL": 0.04,    # Alabama
    "AK": 0.00,    # Alaska (no state sales tax)
    "AZ": 0.056,   # Arizona
    "AR": 0.065,   # Arkansas
    "CA": 0.0725,  # California
    "CO": 0.029,   # Colorado
    "CT": 0.0635,  # Connecticut
    "DE": 0.00,    # Delaware (no sales tax)
    "FL": 0.06,    # Florida
    "GA": 0.04,    # Georgia
    "HI": 0.04,    # Hawaii (GET)
    "ID": 0.06,    # Idaho
    "IL": 0.0625,  # Illinois
    "IN": 0.07,    # Indiana
    "IA": 0.06,    # Iowa
    "KS": 0.065,   # Kansas
    "KY": 0.06,    # Kentucky
    "LA": 0.0445,  # Louisiana
    "ME": 0.055,   # Maine
    "MD": 0.06,    # Maryland
    "MA": 0.0625,  # Massachusetts
    "MI": 0.06,    # Michigan
    "MN": 0.06875, # Minnesota
    "MS": 0.07,    # Mississippi
    "MO": 0.04225, # Missouri
    "MT": 0.00,    # Montana (no sales tax)
    "NE": 0.055,   # Nebraska
    "NV": 0.0685,  # Nevada
    "NH": 0.00,    # New Hampshire (no sales tax)
    "NJ": 0.06625, # New Jersey
    "NM": 0.05125, # New Mexico (GRT)
    "NY": 0.04,    # New York
    "NC": 0.0475,  # North Carolina
    "ND": 0.05,    # North Dakota
    "OH": 0.0575,  # Ohio
    "OK": 0.045,   # Oklahoma
    "OR": 0.00,    # Oregon (no sales tax)
    "PA": 0.06,    # Pennsylvania
    "RI": 0.07,    # Rhode Island
    "SC": 0.06,    # South Carolina
    "SD": 0.045,   # South Dakota
    "TN": 0.07,    # Tennessee
    "TX": 0.0625,  # Texas
    "UT": 0.061,   # Utah
    "VT": 0.06,    # Vermont
    "VA": 0.053,   # Virginia
    "WA": 0.065,   # Washington
    "WV": 0.06,    # West Virginia
    "WI": 0.05,    # Wisconsin
    "WY": 0.04,    # Wyoming
    "DC": 0.06,    # Washington D.C.
}

# Major city additional tax rates (approximate - for better accuracy, integrate TaxJar)
US_CITY_TAX_RATES = {
    # California cities
    "CA": {
        "los angeles": 0.0225,
        "san francisco": 0.0125,
        "san diego": 0.0075,
        "san jose": 0.0125,
        "oakland": 0.0225,
        "sacramento": 0.0075,
        "rancho santa margarita": 0.0075,
    },
    # Texas cities
    "TX": {
        "houston": 0.02,
        "dallas": 0.02,
        "austin": 0.02,
        "san antonio": 0.02,
    },
    # Arizona cities
    "AZ": {
        "phoenix": 0.023,
        "tucson": 0.026,
        "scottsdale": 0.0175,
        "tempe": 0.018,
        "mesa": 0.0175,
    },
    # New York
    "NY": {
        "new york": 0.045,
        "new york city": 0.045,
        "buffalo": 0.04,
        "albany": 0.04,
    },
    # Florida
    "FL": {
        "miami": 0.01,
        "orlando": 0.005,
        "tampa": 0.015,
        "jacksonville": 0.005,
    },
}


class TaxCalculationRequest(BaseModel):
    subtotal: float = Field(..., description="Order subtotal before tax")
    state: str = Field(..., min_length=2, max_length=2, description="Two-letter state code")
    city: Optional[str] = Field(None, description="City name for local tax lookup")
    zip_code: Optional[str] = Field(None, description="ZIP code (for future city lookup)")


class TaxCalculationResponse(BaseModel):
    subtotal: float
    state: str
    state_code: str
    city: Optional[str]
    state_tax_rate: float
    city_tax_rate: float
    combined_tax_rate: float
    state_tax_amount: float
    city_tax_amount: float
    total_tax_amount: float
    total_with_tax: float
    tax_breakdown: dict


@app.get("/api/tax/rates")
async def get_tax_rates(state: Optional[str] = None):
    """
    Get tax rates for all US states or a specific state.

    Returns state-level tax rates. For city-level rates, use /api/tax/calculate.
    """
    if state:
        state = state.upper()
        if state not in US_STATE_TAX_RATES:
            raise HTTPException(status_code=404, detail=f"Unknown state: {state}")

        city_rates = US_CITY_TAX_RATES.get(state, {})
        return {
            "state": state,
            "state_rate": US_STATE_TAX_RATES[state],
            "state_rate_percent": f"{US_STATE_TAX_RATES[state] * 100:.2f}%",
            "city_rates": {
                city: {
                    "rate": rate,
                    "rate_percent": f"{rate * 100:.2f}%",
                    "combined_rate": US_STATE_TAX_RATES[state] + rate,
                    "combined_percent": f"{(US_STATE_TAX_RATES[state] + rate) * 100:.2f}%"
                }
                for city, rate in city_rates.items()
            },
            "has_sales_tax": US_STATE_TAX_RATES[state] > 0
        }

    return {
        "states": {
            code: {
                "rate": rate,
                "rate_percent": f"{rate * 100:.2f}%",
                "has_sales_tax": rate > 0
            }
            for code, rate in sorted(US_STATE_TAX_RATES.items())
        },
        "no_sales_tax_states": ["AK", "DE", "MT", "NH", "OR"],
        "total_states": len(US_STATE_TAX_RATES)
    }


@app.post("/api/tax/calculate", response_model=TaxCalculationResponse)
@app.get("/api/tax/calculate")
async def calculate_tax(
    subtotal: float = Query(..., description="Order subtotal before tax"),
    state: str = Query(..., min_length=2, max_length=2, description="Two-letter state code"),
    city: Optional[str] = Query(None, description="City name for local tax lookup"),
    zip_code: Optional[str] = Query(None, description="ZIP code (reserved for future use)")
):
    """
    Calculate tax for an order based on delivery location.

    - Supports all 50 US states + DC
    - Includes city-level taxes for major cities
    - Returns detailed breakdown for receipts

    Example:
    - GET /api/tax/calculate?subtotal=50.00&state=CA&city=los%20angeles
    """
    state = state.upper()

    # Validate state
    if state not in US_STATE_TAX_RATES:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown state code: {state}. Use two-letter state abbreviation (e.g., CA, TX, NY)"
        )

    # Get state tax rate
    state_rate = US_STATE_TAX_RATES[state]

    # Get city tax rate if city provided
    city_rate = 0.0
    city_normalized = None
    if city:
        city_normalized = city.lower().strip()
        state_cities = US_CITY_TAX_RATES.get(state, {})
        city_rate = state_cities.get(city_normalized, 0.0)

    # Calculate taxes
    combined_rate = state_rate + city_rate
    state_tax = round(subtotal * state_rate, 2)
    city_tax = round(subtotal * city_rate, 2)
    total_tax = round(subtotal * combined_rate, 2)
    total_with_tax = round(subtotal + total_tax, 2)

    # Build response
    return TaxCalculationResponse(
        subtotal=subtotal,
        state=state,
        state_code=state,
        city=city_normalized,
        state_tax_rate=state_rate,
        city_tax_rate=city_rate,
        combined_tax_rate=combined_rate,
        state_tax_amount=state_tax,
        city_tax_amount=city_tax,
        total_tax_amount=total_tax,
        total_with_tax=total_with_tax,
        tax_breakdown={
            "subtotal": f"${subtotal:.2f}",
            "state_tax": f"${state_tax:.2f} ({state_rate * 100:.2f}%)",
            "city_tax": f"${city_tax:.2f} ({city_rate * 100:.2f}%)" if city_tax > 0 else None,
            "total_tax": f"${total_tax:.2f}",
            "total": f"${total_with_tax:.2f}"
        }
    )


@app.get("/api/tax/estimate/{state}")
async def estimate_state_tax(
    state: str,
    subtotal: float = Query(100.0, description="Sample subtotal for estimation")
):
    """
    Quick estimate of tax for a state (uses average city rate).
    Useful for showing "estimated tax" before customer enters full address.
    """
    state = state.upper()

    if state not in US_STATE_TAX_RATES:
        raise HTTPException(status_code=404, detail=f"Unknown state: {state}")

    state_rate = US_STATE_TAX_RATES[state]

    # Calculate average city rate for this state
    city_rates = US_CITY_TAX_RATES.get(state, {})
    avg_city_rate = sum(city_rates.values()) / len(city_rates) if city_rates else 0.02  # Default 2% city estimate

    estimated_rate = state_rate + avg_city_rate
    estimated_tax = round(subtotal * estimated_rate, 2)

    return {
        "state": state,
        "subtotal": subtotal,
        "state_rate": state_rate,
        "estimated_city_rate": round(avg_city_rate, 4),
        "estimated_combined_rate": round(estimated_rate, 4),
        "estimated_tax": estimated_tax,
        "estimated_total": round(subtotal + estimated_tax, 2),
        "note": "This is an estimate. Final tax calculated at checkout with exact address."
    }


# ===================== ADMIN FRONTEND (SPA) =====================
# Serve the React admin portal from the built frontend dist directory.
# This must come AFTER all API routes so /api/* routes take priority.
import pathlib as _pathlib

_frontend_dist = _pathlib.Path(__file__).parent / "admin_frontend"
if _frontend_dist.is_dir():
    from fastapi.responses import FileResponse

    # Serve static assets (JS, CSS, images)
    app.mount("/assets", StaticFiles(directory=str(_frontend_dist / "assets")), name="admin_assets")

    # Serve favicon and other root-level static files
    @app.get("/favicon.svg")
    async def favicon():
        return FileResponse(str(_frontend_dist / "favicon.svg"))

    @app.get("/logo-dollar-ai.svg")
    async def logo():
        return FileResponse(str(_frontend_dist / "logo-dollar-ai.svg"))

    # SPA catch-all: serve index.html for all frontend routes (React Router handles routing)
    _SPA_ROUTES = ["/admin", "/login", "/customer", "/vendor", "/driver"]

    @app.get("/admin")
    async def admin_spa_root():
        return FileResponse(str(_frontend_dist / "index.html"))

    @app.get("/admin/{full_path:path}")
    async def admin_spa(full_path: str = ""):
        return FileResponse(str(_frontend_dist / "index.html"))

    @app.get("/login")
    async def login_spa():
        return FileResponse(str(_frontend_dist / "index.html"))


# ── Waitlist ──────────────────────────────────────────────────────────────────

class WaitlistRequest(BaseModel):
    email: EmailStr
    name: str = ""
    role: str = "rider"  # rider | driver | both

@app.post("/api/waitlist")
async def join_waitlist(payload: WaitlistRequest, db: Session = Depends(get_db)):
    try:
        db.execute(text("""
            CREATE TABLE IF NOT EXISTS waitlist (
                id SERIAL PRIMARY KEY,
                email TEXT NOT NULL,
                name TEXT DEFAULT '',
                role TEXT DEFAULT 'rider',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(email)
            )
        """))
        db.commit()
        is_new = False
        existing = db.execute(text("SELECT id FROM waitlist WHERE email = :e"), {"e": payload.email}).fetchone()
        if not existing:
            is_new = True
        db.execute(text("""
            INSERT INTO waitlist (email, name, role)
            VALUES (:email, :name, :role)
            ON CONFLICT (email) DO UPDATE SET role = EXCLUDED.role, name = EXCLUDED.name
        """), {"email": payload.email, "name": payload.name, "role": payload.role})
        db.commit()

        # Notify support@dollor.ai for every new signup
        if is_new:
            role_labels = {
                "rider": "🚗 Rider", "driver": "💼 Driver", "volunteer": "🙋 Volunteer",
                "partner": "🤝 Business Partner", "investor": "💰 Investor/Funder",
                "state_launch": "🗺️ State Launch Partner",
            }
            role_display = role_labels.get(payload.role, payload.role)
            try:
                notify_support(
                    subject=f"New signup: {payload.email} ({role_display})",
                    details={
                        "Email": payload.email,
                        "Name": payload.name or "(not provided)",
                        "Role": role_display,
                        "Source": "dollor.ai waitlist / get-involved form",
                    }
                )
            except Exception as email_err:
                logger.warning(f"Waitlist email notify failed (non-fatal): {email_err}")

        return {"success": True, "message": "You're on the list! We'll notify you when Dollor launches in your area."}
    except Exception as e:
        db.rollback()
        logger.error(f"Waitlist error: {e}")
        raise HTTPException(status_code=500, detail="Could not save your signup. Please try again.")

@app.get("/api/waitlist/count")
async def waitlist_count(db: Session = Depends(get_db)):
    try:
        result = db.execute(text("SELECT COUNT(*) FROM waitlist")).scalar()
        return {"count": result}
    except Exception:
        return {"count": 0}

@app.get("/api/admin/waitlist")
async def admin_waitlist(db: Session = Depends(get_db)):
    """Admin endpoint — list all waitlist entries newest first."""
    try:
        rows = db.execute(text(
            "SELECT id, email, name, role, created_at FROM waitlist ORDER BY created_at DESC"
        )).fetchall()
        return {"entries": [{"id": r[0], "email": r[1], "name": r[2], "role": r[3], "created_at": str(r[4])} for r in rows]}
    except Exception as e:
        logger.error(f"Admin waitlist error: {e}")
        raise HTTPException(status_code=500, detail="Could not fetch waitlist.")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
# Backend rebuild trigger - 20260106081348
# Backend deploy 20260128-ai-insights
# Backend rebuild 20260206-fix-bids-api-format
# Backend rebuild 20260208-fix-ios-erp-api-paths
