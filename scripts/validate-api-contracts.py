#!/usr/bin/env python3
"""
API Contract Validator — ensures iOS and Android API calls match backend OpenAPI routes.

Extracts paths from:
  1. FastAPI OpenAPI spec (via app.openapi() — no server needed)
  2. iOS P2PAPIService.swift (baseURL and direct URL patterns)
  3. Android DollorApiService.kt (Retrofit annotations)
  4. Android CustomerRideshareApiService.kt (OkHttp URL construction)
  5. Android dead-code services: ChatService, NegotiationService, CallService (excluded)

Usage:
    python scripts/validate-api-contracts.py                       # Full validation
    python scripts/validate-api-contracts.py --skip-android        # iOS only (for CI)
    python scripts/validate-api-contracts.py --android-repo /path  # Custom Android repo path
"""

import argparse
import os
import re
import sys
import tempfile
import warnings
from pathlib import Path

# ---------------------------------------------------------------------------
# Path param normalization: {ride_id}, {rideId}, {id} all become {}
# ---------------------------------------------------------------------------
PATH_PARAM_RE = re.compile(r"\{[^}]+\}")


def normalize_path(path: str) -> str:
    """Normalize a path by replacing all path params with {} and stripping query strings."""
    # Remove query strings
    path = path.split("?")[0]
    # Remove trailing slashes (except root)
    path = path.rstrip("/") if path != "/" else path
    # Replace path params
    return PATH_PARAM_RE.sub("{}", path)


# ---------------------------------------------------------------------------
# Dead-code exclusion prefixes
# ---------------------------------------------------------------------------
EXCLUDED_PREFIXES = [
    "/api/chat/",
    "/api/negotiations/",
    "/api/negotiations",
    "/api/call/",
    "/ws/chat/",
    "/ws/negotiation/",
]

# Exact paths excluded (iOS dead code calling nonexistent backend endpoints)
EXCLUDED_EXACT_PATHS = {
    # iOS calls /api/erp/orders/pending-restaurant-delivery but backend has
    # /api/erp/orders/pending-delivery-decision — aspirational name mismatch, never used
    "/api/erp/orders/pending-restaurant-delivery",
    # iOS P2PAPIService.sendChatMessage/fetchChatMessages (food-order chat) and assignDriver (ERP)
    # have no callers in the customer or driver app targets; the backend has no such routes.
    "/api/customer/orders/{}/chat",
    "/api/erp/orders/{}/assign-driver",
}


def is_excluded(path: str) -> bool:
    """Check if a path belongs to a dead-code aspirational service or known dead endpoint."""
    normalized = normalize_path(path)
    if normalized in EXCLUDED_EXACT_PATHS:
        return True
    for prefix in EXCLUDED_PREFIXES:
        if path.startswith(prefix) or normalized.startswith(prefix):
            return True
    return False


# ---------------------------------------------------------------------------
# 1. OpenAPI spec extraction
# ---------------------------------------------------------------------------
def extract_openapi_paths() -> set[str]:
    """Extract and normalize all paths from the FastAPI OpenAPI spec."""
    # Set env vars before importing
    os.environ.setdefault(
        "DATABASE_URL",
        "sqlite:///" + os.path.join(tempfile.gettempdir(), "validate-api-contracts.db"),
    )
    os.environ.setdefault("JWT_SECRET_KEY", "ci-test-key")
    os.environ.setdefault("ENVIRONMENT", "development")

    backend_dir = Path(__file__).resolve().parent.parent / "apps" / "web" / "p2p-platform" / "backend"
    sys.path.insert(0, str(backend_dir))

    # Suppress warnings during import (SQLAlchemy, deprecation, etc.)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        # Redirect stderr to suppress FastAPI startup noise
        old_stderr = sys.stderr
        sys.stderr = open(os.devnull, "w")
        try:
            from main_new import app
            spec = app.openapi()
        finally:
            sys.stderr.close()
            sys.stderr = old_stderr

    paths = set()
    for path_key in spec.get("paths", {}):
        paths.add(normalize_path(path_key))
    return paths


# ---------------------------------------------------------------------------
# 2. iOS path extraction from P2PAPIService.swift
# ---------------------------------------------------------------------------
# Pattern 1: \(baseURL)/path/... where baseURL = {p2pAPIBaseURL}/api
# Must match everything including \(var) interpolations up to closing quote
IOS_BASEURL_RE = re.compile(r'\\?\(baseURL\)/([^"]+?)(?=")')
# Pattern 2: \(AppConfig.shared.p2pAPIBaseURL)/api/path/...
IOS_DIRECT_RE = re.compile(r'p2pAPIBaseURL\)/api/([^"]+?)(?=")')
# Swift interpolation: \(variableName) -> {}
SWIFT_INTERP_RE = re.compile(r"\\\([^)]+\)")


def extract_ios_paths(repo_root: Path) -> set[str]:
    """Extract all API paths from P2PAPIService.swift."""
    swift_file = repo_root / "apps" / "ios" / "eatfair-ios-shared" / "Sources" / "EatFairShared" / "Services" / "P2PAPIService.swift"

    if not swift_file.exists():
        print(f"WARNING: iOS file not found: {swift_file}", file=sys.stderr)
        return set()

    content = swift_file.read_text(encoding="utf-8")
    paths = set()

    # Pattern 1: baseURL paths
    for match in IOS_BASEURL_RE.finditer(content):
        raw_path = match.group(1)
        # Replace Swift interpolation with {}
        clean_path = SWIFT_INTERP_RE.sub("{}", raw_path)
        full_path = f"/api/{clean_path}"
        paths.add(normalize_path(full_path))

    # Pattern 2: direct p2pAPIBaseURL paths
    for match in IOS_DIRECT_RE.finditer(content):
        raw_path = match.group(1)
        clean_path = SWIFT_INTERP_RE.sub("{}", raw_path)
        full_path = f"/api/{clean_path}"
        paths.add(normalize_path(full_path))

    return paths


# ---------------------------------------------------------------------------
# 3. Android Retrofit path extraction from DollorApiService.kt
# ---------------------------------------------------------------------------
RETROFIT_RE = re.compile(r'@(?:GET|POST|PUT|DELETE|PATCH)\("([^"]+)"\)')
KOTLIN_PARAM_RE = re.compile(r"\{[^}]+\}")


def extract_android_retrofit_paths(android_repo: Path) -> set[str]:
    """Extract all Retrofit annotation paths from DollorApiService.kt."""
    kt_file = android_repo / "shared" / "src" / "main" / "java" / "ai" / "dollor" / "shared" / "data" / "remote" / "DollorApiService.kt"

    if not kt_file.exists():
        print(f"WARNING: Android Retrofit file not found: {kt_file}", file=sys.stderr)
        return set()

    content = kt_file.read_text(encoding="utf-8")
    paths = set()

    for match in RETROFIT_RE.finditer(content):
        raw_path = match.group(1)
        # Retrofit base URL is {baseUrl}/api/, so prepend /api/
        full_path = f"/api/{raw_path}"
        paths.add(normalize_path(full_path))

    return paths


# ---------------------------------------------------------------------------
# 4. Android OkHttp path extraction from CustomerRideshareApiService.kt
# ---------------------------------------------------------------------------
OKHTTP_URL_RE = re.compile(r'\.url\("?\$(?:BASE_URL|baseUrl)/api/([^")\s]+)"?\)')
KOTLIN_STRING_INTERP_RE = re.compile(r"\$\{[^}]+\}|\$[a-zA-Z_][a-zA-Z0-9_]*")


def extract_android_okhttp_paths(file_path: Path) -> set[str]:
    """Extract OkHttp URL paths from a Kotlin file."""
    if not file_path.exists():
        print(f"WARNING: Android OkHttp file not found: {file_path}", file=sys.stderr)
        return set()

    content = file_path.read_text(encoding="utf-8")
    paths = set()

    for match in OKHTTP_URL_RE.finditer(content):
        raw_path = match.group(1)
        # Replace Kotlin string interpolation with {}
        clean_path = KOTLIN_STRING_INTERP_RE.sub("{}", raw_path)
        full_path = f"/api/{clean_path}"
        paths.add(normalize_path(full_path))

    return paths


# ---------------------------------------------------------------------------
# 5. Android dead-code services (excluded from failure)
# ---------------------------------------------------------------------------
def extract_android_deadcode_paths(android_repo: Path) -> set[str]:
    """Extract paths from aspirational dead-code services."""
    dead_services = ["ChatService.kt", "NegotiationService.kt", "CallService.kt"]
    base_dir = android_repo / "shared" / "src" / "main" / "java" / "ai" / "dollor" / "shared" / "data" / "remote"

    paths = set()
    for service_name in dead_services:
        service_file = base_dir / service_name
        if not service_file.exists():
            continue

        content = service_file.read_text(encoding="utf-8")

        # OkHttp pattern: .url("$baseUrl/api/...")
        for match in re.finditer(r'\.url\("?\$(?:BASE_URL|baseUrl)/api/([^")\s]+)"?\)', content):
            raw_path = match.group(1)
            clean_path = KOTLIN_STRING_INTERP_RE.sub("{}", raw_path)
            full_path = f"/api/{clean_path}"
            paths.add(normalize_path(full_path))

        # Also catch WebSocket URLs: .url("$wsUrl/ws/...")
        for match in re.finditer(r'\.url\("?\$(?:wsUrl|WS_URL)/ws/([^")\s]+)"?\)', content):
            raw_path = match.group(1)
            clean_path = KOTLIN_STRING_INTERP_RE.sub("{}", raw_path)
            full_path = f"/ws/{clean_path}"
            paths.add(normalize_path(full_path))

    return paths


# ---------------------------------------------------------------------------
# 6. Comparison and reporting
# ---------------------------------------------------------------------------
def validate_and_report(
    openapi_paths: set[str],
    ios_paths: set[str],
    android_retrofit_paths: set[str],
    android_okhttp_paths: set[str],
    android_deadcode_paths: set[str],
    skip_android: bool,
) -> int:
    """Compare client paths against OpenAPI spec and print report."""
    print("=" * 70)
    print("API Contract Validation Report")
    print("=" * 70)
    print()

    # Summary counts
    print(f"Backend paths (OpenAPI):          {len(openapi_paths)}")
    print(f"iOS client paths:                 {len(ios_paths)}")
    if not skip_android:
        print(f"Android Retrofit paths:           {len(android_retrofit_paths)}")
        print(f"Android OkHttp paths:             {len(android_okhttp_paths)}")
        print(f"Android dead-code paths:          {len(android_deadcode_paths)} (excluded)")
    print()

    # Collect all results
    results = []
    fail_count = 0
    pass_count = 0
    excluded_count = 0

    # Check iOS paths
    for path in sorted(ios_paths):
        if is_excluded(path):
            results.append(("iOS", path, "EXCLUDED"))
            excluded_count += 1
        elif path in openapi_paths:
            results.append(("iOS", path, "PASS"))
            pass_count += 1
        else:
            results.append(("iOS", path, "FAIL"))
            fail_count += 1

    if not skip_android:
        # Check Android Retrofit paths
        for path in sorted(android_retrofit_paths):
            if is_excluded(path):
                results.append(("Android-Retrofit", path, "EXCLUDED"))
                excluded_count += 1
            elif path in openapi_paths:
                results.append(("Android-Retrofit", path, "PASS"))
                pass_count += 1
            else:
                results.append(("Android-Retrofit", path, "FAIL"))
                fail_count += 1

        # Check Android OkHttp paths
        for path in sorted(android_okhttp_paths):
            if is_excluded(path):
                results.append(("Android-OkHttp", path, "EXCLUDED"))
                excluded_count += 1
            elif path in openapi_paths:
                results.append(("Android-OkHttp", path, "PASS"))
                pass_count += 1
            else:
                results.append(("Android-OkHttp", path, "FAIL"))
                fail_count += 1

        # Report dead-code paths
        for path in sorted(android_deadcode_paths):
            results.append(("Android-DeadCode", path, "EXCLUDED"))
            excluded_count += 1

    # Print report table
    print(f"{'Source':<20} {'Path':<55} {'Status':<10}")
    print("-" * 85)
    for source, path, status in results:
        print(f"{source:<20} {path:<55} {status:<10}")

    print()
    print("-" * 85)
    print(f"TOTAL:  {pass_count} PASS  |  {fail_count} FAIL  |  {excluded_count} EXCLUDED")
    print()

    if fail_count > 0:
        print("RESULT: FAIL")
        print()
        print("Failed paths (client calls endpoint not in backend OpenAPI spec):")
        for source, path, status in results:
            if status == "FAIL":
                print(f"  - [{source}] {path}")
        return 1
    else:
        print("RESULT: PASS")
        if excluded_count > 0:
            print(f"  ({excluded_count} dead-code endpoints excluded from validation)")
        return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate iOS and Android API calls against backend OpenAPI spec"
    )
    parser.add_argument(
        "--skip-android",
        action="store_true",
        help="Skip Android validation (for CI where android repo is not available)",
    )
    parser.add_argument(
        "--android-repo",
        type=str,
        default=None,
        help="Path to the Android sources (default: apps/android in this repository)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    android_repo = Path(args.android_repo) if args.android_repo else repo_root / "apps" / "android"

    # 1. Extract OpenAPI paths
    print("Extracting OpenAPI paths from FastAPI app...", flush=True)
    openapi_paths = extract_openapi_paths()

    # 2. Extract iOS paths
    print("Extracting iOS paths from P2PAPIService.swift...", flush=True)
    ios_paths = extract_ios_paths(repo_root)

    # 3-5. Extract Android paths (if not skipped)
    android_retrofit_paths: set[str] = set()
    android_okhttp_paths: set[str] = set()
    android_deadcode_paths: set[str] = set()

    if not args.skip_android:
        if not android_repo.exists():
            print(f"ERROR: Android repo not found at {android_repo}", file=sys.stderr)
            print("Use --skip-android or --android-repo to specify location", file=sys.stderr)
            return 1

        print("Extracting Android Retrofit paths from DollorApiService.kt...", flush=True)
        android_retrofit_paths = extract_android_retrofit_paths(android_repo)

        print("Extracting Android OkHttp paths from CustomerRideshareApiService.kt...", flush=True)
        okhttp_file = android_repo / "app" / "src" / "main" / "java" / "ai" / "dollor" / "customer" / "data" / "CustomerRideshareApiService.kt"
        android_okhttp_paths = extract_android_okhttp_paths(okhttp_file)

        print("Extracting Android dead-code service paths...", flush=True)
        android_deadcode_paths = extract_android_deadcode_paths(android_repo)

    print()

    # 6. Validate and report
    return validate_and_report(
        openapi_paths=openapi_paths,
        ios_paths=ios_paths,
        android_retrofit_paths=android_retrofit_paths,
        android_okhttp_paths=android_okhttp_paths,
        android_deadcode_paths=android_deadcode_paths,
        skip_android=args.skip_android,
    )


if __name__ == "__main__":
    sys.exit(main())
