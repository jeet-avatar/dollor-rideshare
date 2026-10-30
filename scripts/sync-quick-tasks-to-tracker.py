#!/usr/bin/env python3
"""
Sync all quick tasks from STATE.md into the Dollor.ai Project Tracker.

Parses the quick tasks table, classifies each by category/platform/department,
then calls POST /api/admin/project-cases/seed-quick-tasks.

Usage:
    python scripts/sync-quick-tasks-to-tracker.py --env staging
    python scripts/sync-quick-tasks-to-tracker.py --env production
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import urllib.error

# ==================== Configuration ====================

ENVS = {
    "staging": "https://d34u5ixl0bulv4.cloudfront.net",
    "production": "https://api.dollor.ai",
}

ADMIN_EMAIL = "support@dollor.ai"
ADMIN_PASSWORD = os.environ["DOLLOR_ADMIN_PASSWORD"]

STATE_MD_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    ".planning", "STATE.md",
)

# ==================== Classification Rules ====================

# Category keywords (checked in order, first match wins)
CATEGORY_RULES = [
    (r"(?i)\b(security|VAPT|SSL|pinning|vulnerability)\b", "security"),
    (r"(?i)\b(hotfix|HOTFIX)\b", "bug-fix"),
    (r"(?i)\b(fix|bug|broken|regression|crash|error|500|404|401)\b", "bug-fix"),
    (r"(?i)\b(audit|verify|verification|check|stress.test|smoke.test|recheck)\b", "audit"),
    (r"(?i)\b(deploy|rebuild|distribute|TestFlight|Firebase|CI.CD)\b", "deploy"),
    (r"(?i)\b(research|gap.analysis|investigate)\b", "research"),
    (r"(?i)\b(feature|add|implement|build|create|wire|expand)\b", "feature"),
    (r"(?i)\b(reconcile|standardize|refactor|clean|remove)\b", "refactor"),
    (r"(?i)\b(submit|submission|App Store)\b", "deploy"),
]

# Priority rules
PRIORITY_RULES = [
    (r"(?i)\b(security|VAPT|SSL|CRITICAL|hotfix)\b", "Critical"),
    (r"(?i)\b(fix|bug|broken|regression|500|404|error)\b", "High"),
    (r"(?i)\b(audit|verify|deploy|rebuild)\b", "Medium"),
    (r"(?i)\b(research|gap.analysis|docs)\b", "Low"),
]

# Platform detection
PLATFORM_RULES = [
    (r"(?i)\b(iOS|TestFlight|xcarchive|Swift|XCTest|Xcode)\b", "ios"),
    (r"(?i)\b(Android|Firebase|APK|Play Store|Kotlin|Gradle)\b", "android"),
    (r"(?i)\b(backend|API|endpoint|deploy|migration|model|FastAPI|backend)\b", "backend"),
    (r"(?i)\b(admin|frontend|portal|React|dashboard|sidebar)\b", "frontend"),
]


def classify_category(description: str) -> str:
    for pattern, category in CATEGORY_RULES:
        if re.search(pattern, description):
            return category
    return "feature"


def classify_priority(description: str) -> str:
    for pattern, priority in PRIORITY_RULES:
        if re.search(pattern, description):
            return priority
    return "Medium"


def classify_platform(description: str) -> str:
    matches = set()
    for pattern, platform in PLATFORM_RULES:
        if re.search(pattern, description):
            matches.add(platform)

    if len(matches) > 1:
        return "cross-platform"
    if len(matches) == 1:
        return matches.pop()
    return "backend"


def classify_department(category: str, platform: str, description: str) -> str:
    if category == "security":
        return "SEC"
    if category in ("audit", "verification") or re.search(r"(?i)\b(test coverage|E2E|QA)\b", description):
        return "QA"
    if category == "deploy":
        return "OPS"
    if category == "research" or re.search(r"(?i)\b(project tracker|tracker|documentation|docs)\b", description):
        return "PMO"
    return "ENG"


# ==================== STATE.md Parser ====================

def parse_state_md(filepath: str) -> list:
    """Parse the quick tasks table from STATE.md."""
    if not os.path.isfile(filepath):
        print(f"ERROR: STATE.md not found at {filepath}")
        sys.exit(1)

    with open(filepath, "r") as f:
        content = f.read()

    # Find the quick tasks table
    tasks = []
    # Match table rows: | # | Description | Date | Commit | Directory |
    # Example: | 55 | Fix broken links in Restaurant iOS app ... | 2026-03-02 | 1682b609 | [55-fix...](./quick/55-...) |
    row_re = re.compile(
        r"^\|\s*(\d+)\s*\|\s*(.+?)\s*\|\s*(\S+)\s*\|\s*(\S+)\s*\|\s*(.+?)\s*\|",
        re.MULTILINE,
    )

    for match in row_re.finditer(content):
        num = int(match.group(1))
        description = match.group(2).strip()
        date = match.group(3).strip()
        commit = match.group(4).strip()

        # Skip header/separator rows
        if description in ("Description", "---", ""):
            continue
        if date in ("Date", "---"):
            continue

        # Skip reserved entries
        if description.startswith("(reserved)"):
            continue

        # Clean date
        if date in ("--", "---", ""):
            date = None

        # Clean commit — normalize non-hash values
        if commit in ("(pending)", "(API-only)", "(none)", "(research)", "---", "--", ""):
            commit = ""

        tasks.append({
            "quick_num": num,
            "description": description,
            "date": date,
            "commit": commit,
            "category": classify_category(description),
            "platform": classify_platform(description),
            "department_code": classify_department(
                classify_category(description),
                classify_platform(description),
                description,
            ),
            "priority": classify_priority(description),
        })

    return tasks


# ==================== API Client ====================

def api_request(base_url: str, path: str, data=None, token=None):
    """Make an API request. Returns (status_code, response_body)."""
    url = f"{base_url}{path}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method="POST" if data else "GET")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else ""
        return e.code, error_body
    except urllib.error.URLError as e:
        return 0, str(e.reason)
    except Exception as e:
        return 0, str(e)


def admin_login(base_url: str) -> str:
    """Login as admin and return JWT token."""
    status, body = api_request(
        base_url,
        "/api/admin/login",
        data={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
    )
    if status != 200:
        print(f"ERROR: Admin login failed (HTTP {status}): {body}")
        sys.exit(1)

    if isinstance(body, dict):
        token = body.get("access_token") or body.get("token")
        if token:
            return token

    print(f"ERROR: No token in login response: {body}")
    sys.exit(1)


def seed_quick_tasks(base_url: str, token: str, tasks: list) -> dict:
    """Call the seed-quick-tasks endpoint."""
    url = f"{base_url}/api/admin/project-cases/seed-quick-tasks"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
    }
    body = json.dumps(tasks).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else ""
        print(f"ERROR: Seed request failed (HTTP {e.code}): {error_body}")
        return {"error": error_body, "status": e.code}
    except Exception as e:
        print(f"ERROR: Seed request failed: {e}")
        return {"error": str(e)}


# ==================== Main ====================

def main():
    parser = argparse.ArgumentParser(description="Sync quick tasks to project tracker")
    parser.add_argument(
        "--env",
        choices=["staging", "production"],
        default="production",
        help="Target environment (default: production)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and classify tasks without sending to API",
    )
    args = parser.parse_args()

    base_url = ENVS[args.env]

    # Parse STATE.md
    print(f"Parsing quick tasks from {STATE_MD_PATH}...")
    tasks = parse_state_md(STATE_MD_PATH)
    print(f"Found {len(tasks)} quick tasks")

    if not tasks:
        print("No tasks found. Check STATE.md format.")
        sys.exit(1)

    # Show classification summary
    categories = {}
    platforms = {}
    departments = {}
    for t in tasks:
        categories[t["category"]] = categories.get(t["category"], 0) + 1
        platforms[t["platform"]] = platforms.get(t["platform"], 0) + 1
        departments[t["department_code"]] = departments.get(t["department_code"], 0) + 1

    print(f"\nClassification summary:")
    print(f"  Categories: {dict(sorted(categories.items()))}")
    print(f"  Platforms:  {dict(sorted(platforms.items()))}")
    print(f"  Departments: {dict(sorted(departments.items()))}")

    if args.dry_run:
        print("\n--- DRY RUN: Tasks that would be synced ---")
        for t in tasks:
            print(f"  QT-{t['quick_num']:3d} | {t['category']:10s} | {t['platform']:14s} | {t['department_code']:4s} | {t['priority']:8s} | {t['description'][:60]}")
        print(f"\nTotal: {len(tasks)} tasks")
        return

    # Login
    print(f"\nLogging in to {args.env} ({base_url})...")
    token = admin_login(base_url)
    print("Login OK")

    # Send tasks in batches of 50
    batch_size = 50
    total_created = 0
    total_skipped = 0
    all_warnings = []

    for i in range(0, len(tasks), batch_size):
        batch = tasks[i : i + batch_size]
        print(f"Sending batch {i // batch_size + 1} ({len(batch)} tasks)...")
        result = seed_quick_tasks(base_url, token, batch)

        if "error" in result:
            print(f"  ERROR: {result}")
            continue

        total_created += result.get("created", 0)
        total_skipped += result.get("skipped", 0)
        if result.get("warnings"):
            all_warnings.extend(result["warnings"])
        print(f"  Created: {result.get('created', 0)}, Skipped: {result.get('skipped', 0)}")

    print(f"\n=== SYNC COMPLETE ({args.env}) ===")
    print(f"  Created: {total_created}")
    print(f"  Skipped: {total_skipped}")
    print(f"  Total:   {total_created + total_skipped}")

    if all_warnings:
        print(f"\n  Warnings ({len(all_warnings)}):")
        for w in all_warnings:
            print(f"    - {w}")


if __name__ == "__main__":
    main()
