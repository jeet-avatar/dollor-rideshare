#!/usr/bin/env python3
"""
Populate reason, commit_ref, dependencies, and impact_analysis for all ProjectCase rows.

Generates deterministic, human-readable values from each case's test name, platform,
test_type, and category. Idempotent -- safe to re-run (overwrites existing values).

Usage:
  cd apps/web/p2p-platform/backend
  DATABASE_URL=postgresql://<user>@<host>:5432/<db> \
    JWT_SECRET_KEY=test ADMIN_SECRET_KEY=test \
    python scripts/populate_case_reasons.py
"""

import sys
import os
import re
import subprocess

# Add backend root to path so imports work
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import func
from database import SessionLocal, init_db
from project_tracker import ProjectCase


# ==================== Word Mappings ====================

WORD_MAP = {
    "auth": "authentication",
    "api": "API",
    "e2e": "end-to-end",
    "ws": "WebSocket",
    "db": "database",
    "cfg": "configuration",
    "btn": "button",
    "msg": "message",
    "err": "error",
    "req": "request",
    "res": "response",
    "usr": "user",
    "pwd": "password",
    "txn": "transaction",
    "fmt": "format",
    "init": "initialization",
    "calc": "calculation",
    "val": "validation",
    "nav": "navigation",
    "img": "image",
    "del": "delete",
    "upd": "update",
    "str": "string",
}

PLATFORM_LABELS = {
    "backend": "Backend",
    "ios": "iOS",
    "android": "Android",
    "microservice": "Microservice",
    "frontend": "Frontend",
}

TEST_TYPE_LABELS = {
    "unit": "Unit",
    "e2e": "E2E",
    "integration": "Integration",
    "smoke": "Smoke",
    "api": "API",
    "other": "Test",
}

# ==================== Reason Generation ====================

# Regex to split on underscore or camelCase boundary
_SPLIT_RE = re.compile(r'(?<=[a-z])(?=[A-Z])|_')


def _generate_reason(name: str, platform: str, test_type: str, category: str) -> str:
    """Generate a human-readable reason from test name + metadata."""
    # Split on underscores and camelCase boundaries
    words = _SPLIT_RE.split(name)

    # Remove leading "test" / "Test" prefix
    if words and words[0].lower() == "test":
        words = words[1:]
    if not words:
        words = [name]

    # Apply word mappings (only exact standalone matches)
    mapped = []
    for w in words:
        lower = w.lower()
        if lower in WORD_MAP:
            mapped.append(WORD_MAP[lower])
        else:
            mapped.append(w.lower())

    # Capitalize first word, join
    if mapped:
        mapped[0] = mapped[0].capitalize() if mapped[0] != "API" else "API"
    description = " ".join(mapped)

    platform_label = PLATFORM_LABELS.get(platform or "backend", "Backend")
    type_label = TEST_TYPE_LABELS.get(test_type or "other", "Test")

    return f"{platform_label} {type_label}: {description} ({category})"


# ==================== Dependencies Generation ====================

def _generate_dependencies(category: str, platform: str) -> str:
    """Generate dependencies based on category and platform."""
    cat_lower = (category or "").lower()
    deps = None

    # Check category patterns (order matters -- first match wins)
    if any(kw in cat_lower for kw in ("payment", "stripe", "billing", "invoice", "payout")):
        deps = "auth, user-management"
    elif any(kw in cat_lower for kw in ("order", "delivery", "food")):
        deps = "auth, vendor-management, payment"
    elif any(kw in cat_lower for kw in ("ride", "rideshare", "fare", "bid")):
        deps = "auth, driver-management, payment"
    elif any(kw in cat_lower for kw in ("auth", "login", "register", "jwt")):
        deps = "database, user-model"
    elif any(kw in cat_lower for kw in ("driver",)):
        deps = "auth, vehicle-management"
    elif any(kw in cat_lower for kw in ("vendor", "restaurant", "menu")):
        deps = "auth, restaurant-management"
    elif any(kw in cat_lower for kw in ("admin", "dashboard")):
        deps = "auth, all-models"
    else:
        deps = "core-api"

    # For client platforms, prepend backend-api
    if platform in ("ios", "android"):
        deps = f"backend-api, {deps}"

    return deps


# ==================== Impact Analysis Generation ====================

def _generate_impact(test_type: str, category: str) -> str:
    """Generate impact analysis based on test_type and category."""
    cat = category or "unknown"

    impact_map = {
        "e2e": f"Breaking this test indicates regression in the {cat} user flow. Affects end-to-end functionality.",
        "unit": f"Breaking this test indicates a code-level regression in {cat}. Isolated impact.",
        "integration": f"Breaking this test indicates integration failure between {cat} components. May cascade.",
        "smoke": f"Breaking this test indicates critical system failure in {cat}. Immediate attention required.",
        "api": f"Breaking this test indicates API contract violation in {cat}. Client apps may break.",
    }

    return impact_map.get(test_type, f"Breaking this test indicates regression in {cat}. Investigate scope of change.")


# ==================== Main ====================

def main():
    # Get git HEAD short hash
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=10,
        )
        commit_ref = result.stdout.strip() or "unknown"
    except Exception:
        commit_ref = "unknown"

    print(f"Git HEAD: {commit_ref}")

    # Ensure tables exist
    init_db()

    db = SessionLocal()
    try:
        total = db.query(ProjectCase).count()
        print(f"Total cases in DB: {total}")

        if total == 0:
            print("No cases to populate. Run seed_project_cases.py first.")
            return

        # Fetch all cases
        all_cases = db.query(ProjectCase).all()

        # Process in batches of 500
        BATCH_SIZE = 500
        updated = 0
        samples = {}  # platform -> sample reason

        for i in range(0, len(all_cases), BATCH_SIZE):
            batch = all_cases[i:i + BATCH_SIZE]
            for case in batch:
                reason = _generate_reason(case.name, case.platform, case.test_type, case.category)
                deps = _generate_dependencies(case.category, case.platform)
                impact = _generate_impact(case.test_type, case.category)

                db.query(ProjectCase).filter(ProjectCase.id == case.id).update({
                    "reason": reason,
                    "commit_ref": commit_ref,
                    "dependencies": deps,
                    "impact_analysis": impact,
                })
                updated += 1

                # Collect samples (one per platform)
                plat = case.platform or "backend"
                if plat not in samples:
                    samples[plat] = reason

            db.commit()
            print(f"  Batch {i // BATCH_SIZE + 1}: updated {len(batch)} cases (total: {updated})")

        # Final summary
        print(f"\n{'=' * 60}")
        print(f"POPULATE COMPLETE")
        print(f"{'=' * 60}")
        print(f"Total updated: {updated}")
        print(f"Commit ref: {commit_ref}")
        print(f"\nSample reasons by platform:")
        for plat, sample in sorted(samples.items()):
            print(f"  {plat:15s}: {sample}")

        # Verify counts
        with_reason = db.query(ProjectCase).filter(ProjectCase.reason.isnot(None), ProjectCase.reason != '').count()
        with_commit = db.query(ProjectCase).filter(ProjectCase.commit_ref.isnot(None)).count()
        with_deps = db.query(ProjectCase).filter(ProjectCase.dependencies.isnot(None)).count()
        with_impact = db.query(ProjectCase).filter(ProjectCase.impact_analysis.isnot(None)).count()
        print(f"\nPopulated fields:")
        print(f"  reason:          {with_reason}/{total}")
        print(f"  commit_ref:      {with_commit}/{total}")
        print(f"  dependencies:    {with_deps}/{total}")
        print(f"  impact_analysis: {with_impact}/{total}")

        if with_reason == total and with_commit == total and with_deps == total and with_impact == total:
            print(f"\nAll {total} cases fully populated!")
        else:
            print(f"\nWARNING: Not all cases populated!")
            sys.exit(1)

    finally:
        db.close()


if __name__ == "__main__":
    main()
