"""Tests for the Project Tracker admin API endpoints.

Validates stats, list (with sorting), export CSV, and update (with last_activity tracking).
"""
import os

# Set admin secret before importing app (admin middleware checks this)
os.environ.setdefault("ADMIN_SECRET_KEY", "test-admin-secret")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret")
os.environ.setdefault("DATABASE_URL", "postgresql://jeet@localhost:5432/dollor_dev")

import pytest
from fastapi.testclient import TestClient

from database import SessionLocal
from main_new import app
from project_tracker import ProjectCase

client = TestClient(app)
ADMIN_SECRET = os.environ.get("ADMIN_SECRET_KEY", "test-admin-secret")


@pytest.fixture(autouse=True)
def seeded_case(test_db):
    """Fresh schema (conftest test_db) plus one known case, so the list/update paths are exercised."""
    db = SessionLocal()
    try:
        if not db.query(ProjectCase).filter_by(case_id="TC-0001").first():
            db.add(ProjectCase(
                case_id="TC-0001", name="test_seeded", full_path="tests/test_seed.py::test_seeded",
                category="test_seed", test_type="unit", status="Open", priority="Medium", platform="backend",
            ))
            db.commit()
    finally:
        db.close()


def admin_get(path: str):
    """GET an admin URL, authenticating via the X-Admin-Secret header.

    The admin middleware no longer accepts the secret as a query param (query strings leak
    into access logs), so only the header form is valid.
    """
    return client.get(path, headers={"X-Admin-Secret": ADMIN_SECRET})


class TestAdminAuthRequired:
    def test_query_param_secret_is_rejected(self):
        """The secret in the URL must NOT authenticate (it would leak into logs)."""
        response = client.get(f"/api/admin/project-cases/stats?secret_key={ADMIN_SECRET}")
        assert response.status_code == 401

    def test_missing_secret_is_rejected(self):
        assert client.get("/api/admin/project-cases/stats").status_code == 401

    def test_wrong_header_secret_is_rejected(self):
        response = client.get("/api/admin/project-cases/stats", headers={"X-Admin-Secret": "nope"})
        assert response.status_code == 401


class TestProjectTrackerStats:
    def test_stats_endpoint(self):
        """GET /api/admin/project-cases/stats returns expected keys."""
        response = admin_get("/api/admin/project-cases/stats")
        assert response.status_code == 200, f"Stats returned {response.status_code}: {response.text}"
        data = response.json()
        assert "total" in data
        assert "by_status" in data
        assert "by_platform" in data
        assert "platforms" in data


class TestProjectTrackerList:
    def test_list_endpoint_fields(self):
        """GET /api/admin/project-cases/ returns items with all expected fields."""
        response = admin_get("/api/admin/project-cases/")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert "total" in data
        assert "page" in data
        assert "platforms" in data

        if data["items"]:
            item = data["items"][0]
            expected_fields = [
                "case_id", "name", "full_path", "category", "subcategory",
                "test_type", "status", "priority", "platform",
                "version_introduced", "build_number", "release_notes",
                "reason", "commit_ref", "dependencies", "impact_analysis",
                "last_activity", "created_at", "updated_at",
            ]
            for field in expected_fields:
                assert field in item, f"Missing field: {field}"

    def test_list_sorting(self):
        """GET /api/admin/project-cases/?sort_by=case_id&sort_order=desc returns 200."""
        response = admin_get("/api/admin/project-cases/?sort_by=case_id&sort_order=desc")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data


class TestProjectTrackerExport:
    def test_export_csv(self):
        """GET /api/admin/project-cases/export returns CSV content."""
        response = admin_get("/api/admin/project-cases/export")
        assert response.status_code == 200
        assert "text/csv" in response.headers.get("content-type", "")
        # Verify CSV has header row
        lines = response.text.strip().split("\n")
        assert len(lines) >= 1, "CSV should have at least a header row"
        assert "case_id" in lines[0]


class TestProjectTrackerUpdate:
    def test_update_case(self):
        """PUT /api/admin/project-cases/TC-0001 updates and returns last_activity."""
        response = client.put(
            "/api/admin/project-cases/TC-0001",
            json={"status": "Verified"},
            headers={"X-Admin-Secret": ADMIN_SECRET},
        )
        assert response.status_code == 200, f"Update returned {response.status_code}: {response.text}"
        data = response.json()
        assert data["status"] == "Verified"
        assert "last_activity" in data
        assert data["last_activity"] is not None
        assert "Updated status" in data["last_activity"]
