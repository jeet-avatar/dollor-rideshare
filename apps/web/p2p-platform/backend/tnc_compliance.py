"""
TNC Compliance Module — California CPUC Requirements
=====================================================

Covers:
- TNC-07: Criminal background check via Persona Reports
- TNC-08: DMV driving record check via Persona Database Verifications
- TNC-09: 19-point vehicle inspection tracking
- TNC-10: Zero-tolerance drug/alcohol reporting + auto-suspension
- TNC-22: CPUC quarterly compliance reporting (PUCTRA + trip data)
- TNC-23: Anti-discrimination monitoring for driver ratings

Authority: CPUC Decision 13-09-045, Decision 19-06-033
"""

import os
import hmac
import hashlib
import httpx
import logging
from html import escape as html_escape
from datetime import datetime, date, timedelta
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Request, BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import and_, func, case, extract, or_
from pydantic import BaseModel, Field, field_validator
from enum import Enum

from database import get_db
from auth_utils import require_any_auth, require_driver, require_admin
from models import Driver, DriverStatus, RideRequest, RideRequestStatus, Customer
from cache import RateLimiter, check_rate_limit

logger = logging.getLogger("tnc_compliance")

router = APIRouter(prefix="/api/tnc", tags=["TNC Compliance"])

PERSONA_API_URL = "https://withpersona.com/api/v1"
PERSONA_API_KEY = os.getenv("PERSONA_API_KEY", "")
PERSONA_WEBHOOK_SECRET = os.getenv("PERSONA_WEBHOOK_SECRET", "")

# Rate limiter for zero-tolerance reports (prevent abuse)
zt_report_limiter = RateLimiter(max_requests=3, window_seconds=300)  # 3 reports per 5 min


def _sanitize(text: str) -> str:
    """Sanitize user input — strip HTML and limit length."""
    if not text:
        return ""
    return html_escape(text.strip())[:2000]


def _verify_persona_webhook(request_body: bytes, signature_header: str) -> bool:
    """Verify Persona webhook HMAC-SHA256 signature."""
    if not PERSONA_WEBHOOK_SECRET:
        logger.warning("PERSONA_WEBHOOK_SECRET not configured — skipping signature check")
        return True  # Allow in dev; in production, PERSONA_WEBHOOK_SECRET should always be set
    expected = hmac.new(
        PERSONA_WEBHOOK_SECRET.encode(),
        request_body,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(f"sha256={expected}", signature_header or "")

# Criminal convictions that permanently disqualify a TNC driver (CPUC Decision 13-09-045)
PERMANENT_DISQUALIFIERS = [
    "reckless_driving",
    "hit_and_run",
    "suspended_license",
    "revoked_license",
]

# Convictions within past 7 years that disqualify
SEVEN_YEAR_DISQUALIFIERS = [
    "dui",
    "driving_under_influence",
    "fraud",
    "sexual_offense",
    "motor_vehicle_felony",
    "property_damage",
    "theft",
    "violence",
    "terror",
]


# =============================================================================
# MODELS
# =============================================================================

class BackgroundCheckRequest(BaseModel):
    driver_id: int
    ssn_last4: Optional[str] = None  # For verification — full SSN sent to Persona only


class DMVCheckRequest(BaseModel):
    driver_id: int
    license_number: Optional[str] = None
    license_state: str = "CA"


class VehicleInspectionSubmit(BaseModel):
    driver_id: int
    inspection_date: str  # YYYY-MM-DD
    facility_name: str = Field(..., max_length=500)
    facility_bar_license: Optional[str] = Field(None, max_length=100)
    mileage_at_inspection: Optional[int] = Field(None, ge=0, le=999999)
    document_url: str = Field(..., max_length=1000)


class ZeroToleranceReport(BaseModel):
    ride_request_id: Optional[int] = None
    driver_id: int
    description: str = Field(..., min_length=10, max_length=2000)
    reporter_type: str = "customer"  # customer, passenger, public

    @field_validator('reporter_type')
    @classmethod
    def validate_reporter_type(cls, v):
        if v not in ("customer", "passenger", "public"):
            raise ValueError("reporter_type must be customer, passenger, or public")
        return v


class BackgroundCheckStatus(str, Enum):
    NOT_STARTED = "not_started"
    PENDING = "pending"
    PASSED = "passed"
    FAILED = "failed"
    REVIEW = "needs_review"


class InspectionStatus(str, Enum):
    VALID = "valid"
    EXPIRED = "expired"
    MISSING = "missing"


# =============================================================================
# TNC-07: CRIMINAL BACKGROUND CHECK VIA PERSONA
# =============================================================================

@router.post("/background-check/initiate")
async def initiate_background_check(
    data: BackgroundCheckRequest,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_admin),
):
    """TNC-07: Initiate a criminal background check for a driver via Persona Reports.
    Admin-only. Creates a Persona Report (background check) for the driver.
    Includes national criminal DB + sex offender registry (SSN-based)."""

    driver = db.query(Driver).filter(Driver.id == data.driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if not PERSONA_API_KEY:
        raise HTTPException(status_code=503, detail="Persona API key not configured")

    # Create a Persona Report (background check)
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{PERSONA_API_URL}/reports",
                headers={
                    "Authorization": f"Bearer {PERSONA_API_KEY}",
                    "Persona-Version": "2023-01-05",
                    "Content-Type": "application/json",
                },
                json={
                    "data": {
                        "type": "report",
                        "attributes": {
                            "report-template-id": os.getenv("PERSONA_BG_CHECK_TEMPLATE_ID", ""),
                            "reference-id": f"driver-{driver.id}",
                            "fields": {
                                "name-first": driver.first_name,
                                "name-last": driver.last_name,
                                "email-address": driver.email,
                                "phone-number": driver.phone,
                                "birthdate": driver.date_of_birth,
                            }
                        }
                    }
                },
            )

            if response.status_code in (200, 201):
                result = response.json()
                report_id = result.get("data", {}).get("id", "")

                # Update driver record
                driver.background_check = False  # Pending
                driver.background_check_date = datetime.utcnow()
                driver.verification_notes = (driver.verification_notes or "") + f"\nBG check initiated: {report_id}"
                db.commit()

                logger.info(f"Background check initiated for driver {driver.id}: {report_id}")
                return {
                    "success": True,
                    "report_id": report_id,
                    "status": "pending",
                    "message": "Background check initiated via Persona. Results will arrive via webhook."
                }
            else:
                logger.error(f"Persona Reports API error: {response.status_code} {response.text}")
                raise HTTPException(status_code=502, detail=f"Persona API error: {response.status_code}")

    except httpx.HTTPError as e:
        logger.error(f"Persona connection error: {e}")
        raise HTTPException(status_code=502, detail="Failed to connect to Persona")


@router.post("/background-check/webhook")
async def background_check_webhook(request: Request, db: Session = Depends(get_db)):
    """TNC-07: Webhook handler for Persona background check results.
    Processes report completion and applies disqualification logic."""

    # SECURITY: Verify Persona webhook signature
    raw_body = await request.body()
    signature = request.headers.get("Persona-Signature", "")
    if not _verify_persona_webhook(raw_body, signature):
        raise HTTPException(status_code=401, detail="Invalid webhook signature")

    body = await request.json()
    event_type = body.get("data", {}).get("attributes", {}).get("event-type", "")

    if event_type != "report.completed":
        return {"received": True, "processed": False}

    report_data = body.get("data", {}).get("attributes", {}).get("payload", {}).get("data", {})
    report_attrs = report_data.get("attributes", {})
    reference_id = report_attrs.get("reference-id", "")
    status = report_attrs.get("status", "")

    # Extract driver ID from reference
    if not reference_id.startswith("driver-"):
        return {"received": True, "processed": False, "reason": "Not a driver report"}

    driver_id = int(reference_id.replace("driver-", ""))
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        logger.warning(f"Background check webhook for unknown driver {driver_id}")
        return {"received": True, "processed": False}

    # Process results
    records = report_attrs.get("records", [])
    disqualified = False
    disqualification_reasons = []

    for record in records:
        charge_type = record.get("charge_type", "").lower()
        conviction_date_str = record.get("conviction_date", "")

        # Check permanent disqualifiers
        for disqualifier in PERMANENT_DISQUALIFIERS:
            if disqualifier in charge_type:
                disqualified = True
                disqualification_reasons.append(f"Permanent disqualifier: {charge_type}")

        # Check 7-year disqualifiers
        if conviction_date_str:
            try:
                conviction_date = datetime.strptime(conviction_date_str, "%Y-%m-%d").date()
                years_ago = (date.today() - conviction_date).days / 365.25
                if years_ago <= 7:
                    for disqualifier in SEVEN_YEAR_DISQUALIFIERS:
                        if disqualifier in charge_type:
                            disqualified = True
                            disqualification_reasons.append(f"Within 7 years: {charge_type} ({conviction_date_str})")
            except ValueError:
                pass

    if disqualified:
        driver.background_check = False
        driver.status = DriverStatus.SUSPENDED
        driver.verification_notes = (driver.verification_notes or "") + f"\nBG CHECK FAILED: {'; '.join(disqualification_reasons)}"
        logger.warning(f"Driver {driver_id} disqualified: {disqualification_reasons}")
    else:
        driver.background_check = True
        driver.background_check_date = datetime.utcnow()
        driver.verification_notes = (driver.verification_notes or "") + f"\nBG check PASSED at {datetime.utcnow().isoformat()}"
        logger.info(f"Driver {driver_id} passed background check")

    db.commit()

    return {
        "received": True,
        "processed": True,
        "driver_id": driver_id,
        "passed": not disqualified,
    }


@router.get("/background-check/{driver_id}/status")
async def get_background_check_status(
    driver_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """Get background check status for a driver."""
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if driver.background_check:
        status = BackgroundCheckStatus.PASSED
    elif driver.background_check_date:
        status = BackgroundCheckStatus.PENDING
    else:
        status = BackgroundCheckStatus.NOT_STARTED

    return {
        "driver_id": driver_id,
        "status": status.value,
        "checked_at": driver.background_check_date.isoformat() if driver.background_check_date else None,
        "passed": driver.background_check,
    }


# =============================================================================
# TNC-08: DMV DRIVING RECORD CHECK VIA PERSONA
# =============================================================================

@router.post("/dmv-check/initiate")
async def initiate_dmv_check(
    data: DMVCheckRequest,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_admin),
):
    """TNC-08: Initiate DMV driving record check via Persona Database Verifications.
    Checks license validity, driving history (1+ year required), points (max 3)."""

    driver = db.query(Driver).filter(Driver.id == data.driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    if not PERSONA_API_KEY:
        raise HTTPException(status_code=503, detail="Persona API key not configured")

    license_number = data.license_number or driver.license_number
    if not license_number:
        raise HTTPException(status_code=400, detail="Driver license number required")

    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{PERSONA_API_URL}/verifications/database",
                headers={
                    "Authorization": f"Bearer {PERSONA_API_KEY}",
                    "Persona-Version": "2023-01-05",
                    "Content-Type": "application/json",
                },
                json={
                    "data": {
                        "type": "verification/database",
                        "attributes": {
                            "database-verification-template-id": os.getenv("PERSONA_DMV_TEMPLATE_ID", ""),
                            "reference-id": f"dmv-driver-{driver.id}",
                            "fields": {
                                "name-first": driver.first_name,
                                "name-last": driver.last_name,
                                "birthdate": driver.date_of_birth,
                                "driver-license-number": license_number,
                                "driver-license-state": data.license_state,
                            }
                        }
                    }
                },
            )

            if response.status_code in (200, 201):
                result = response.json()
                verification_id = result.get("data", {}).get("id", "")

                driver.verification_notes = (driver.verification_notes or "") + f"\nDMV check initiated: {verification_id}"
                db.commit()

                logger.info(f"DMV check initiated for driver {driver.id}: {verification_id}")
                return {
                    "success": True,
                    "verification_id": verification_id,
                    "status": "pending",
                    "message": "DMV driving record check initiated. Results will arrive via webhook."
                }
            else:
                logger.error(f"Persona DMV API error: {response.status_code} {response.text}")
                raise HTTPException(status_code=502, detail=f"Persona API error: {response.status_code}")

    except httpx.HTTPError as e:
        logger.error(f"Persona connection error: {e}")
        raise HTTPException(status_code=502, detail="Failed to connect to Persona")


@router.post("/dmv-check/webhook")
async def dmv_check_webhook(request: Request, db: Session = Depends(get_db)):
    """TNC-08: Webhook handler for DMV driving record results.
    Validates: license status, 1+ year history, max 3 points, no serious violations."""

    # SECURITY: Verify Persona webhook signature
    raw_body = await request.body()
    signature = request.headers.get("Persona-Signature", "")
    if not _verify_persona_webhook(raw_body, signature):
        raise HTTPException(status_code=401, detail="Invalid webhook signature")

    body = await request.json()
    event_type = body.get("data", {}).get("attributes", {}).get("event-type", "")

    if "verification" not in event_type:
        return {"received": True, "processed": False}

    verification_data = body.get("data", {}).get("attributes", {}).get("payload", {}).get("data", {})
    attrs = verification_data.get("attributes", {})
    reference_id = attrs.get("reference-id", "")

    if not reference_id.startswith("dmv-driver-"):
        return {"received": True, "processed": False}

    driver_id = int(reference_id.replace("dmv-driver-", ""))
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        return {"received": True, "processed": False}

    # Extract DMV data
    license_status = attrs.get("license-status", "").lower()
    points = attrs.get("points", 0)
    license_issue_date = attrs.get("license-issue-date", "")
    violations = attrs.get("violations", [])

    disqualified = False
    reasons = []

    # Check license status
    if license_status in ("suspended", "revoked", "expired", "cancelled"):
        disqualified = True
        reasons.append(f"License status: {license_status}")

    # Check minimum 1 year driving history
    if license_issue_date:
        try:
            issue_date = datetime.strptime(license_issue_date, "%Y-%m-%d").date()
            years_licensed = (date.today() - issue_date).days / 365.25
            if years_licensed < 1:
                disqualified = True
                reasons.append(f"Less than 1 year driving history ({years_licensed:.1f} years)")
        except ValueError:
            pass

    # Check max 3 points
    if isinstance(points, (int, float)) and points > 3:
        disqualified = True
        reasons.append(f"Driving record points: {points} (max 3 allowed)")

    # Check for serious violations
    for violation in violations:
        v_type = violation.get("type", "").lower()
        if any(d in v_type for d in ["dui", "reckless", "hit_and_run", "hit and run"]):
            disqualified = True
            reasons.append(f"Serious violation: {v_type}")

    notes = f"\nDMV check completed at {datetime.utcnow().isoformat()}"
    if disqualified:
        driver.status = DriverStatus.SUSPENDED
        notes += f" — FAILED: {'; '.join(reasons)}"
        logger.warning(f"Driver {driver_id} DMV disqualified: {reasons}")
    else:
        notes += f" — PASSED (points: {points}, license: {license_status})"
        logger.info(f"Driver {driver_id} DMV check passed")

    driver.verification_notes = (driver.verification_notes or "") + notes
    db.commit()

    return {
        "received": True,
        "processed": True,
        "driver_id": driver_id,
        "passed": not disqualified,
    }


# =============================================================================
# TNC-09: 19-POINT VEHICLE INSPECTION TRACKING
# =============================================================================

@router.post("/vehicle-inspection/submit")
async def submit_vehicle_inspection(
    data: VehicleInspectionSubmit,
    db: Session = Depends(get_db),
    auth_driver: Driver = Depends(require_driver),
):
    """TNC-09: Submit a 19-point vehicle inspection record.
    Vehicle must be inspected by a CA Bureau of Automotive Repair licensed facility:
    - Before first service
    - Every 12 months or 50,000 miles, whichever comes first
    Records maintained for minimum 3 years."""

    # SECURITY: Driver can only submit their own inspection
    if auth_driver.id != data.driver_id:
        raise HTTPException(status_code=403, detail="Cannot submit inspection for another driver")
    driver = auth_driver

    # Validate inspection date
    try:
        inspection_date = datetime.strptime(data.inspection_date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    if inspection_date > date.today():
        raise HTTPException(status_code=400, detail="Inspection date cannot be in the future")

    # Calculate next due date (12 months from inspection)
    next_due_date = date(inspection_date.year + 1, inspection_date.month, inspection_date.day)

    # Store in driver's verification notes (until we add a dedicated inspection table)
    inspection_record = (
        f"\n--- VEHICLE INSPECTION ---"
        f"\nDate: {data.inspection_date}"
        f"\nFacility: {_sanitize(data.facility_name)}"
        f"\nBAR License: {_sanitize(data.facility_bar_license) if data.facility_bar_license else 'N/A'}"
        f"\nMileage: {data.mileage_at_inspection or 'N/A'}"
        f"\nDocument: {_sanitize(data.document_url)}"
        f"\nNext Due: {next_due_date.isoformat()}"
        f"\nSubmitted: {datetime.utcnow().isoformat()}"
    )

    driver.verification_notes = (driver.verification_notes or "") + inspection_record
    db.commit()

    logger.info(f"Vehicle inspection recorded for driver {driver.id}, next due {next_due_date}")

    return {
        "success": True,
        "driver_id": driver.id,
        "inspection_date": data.inspection_date,
        "next_due_date": next_due_date.isoformat(),
        "facility": data.facility_name,
        "status": "valid",
        "expires_in_days": (next_due_date - date.today()).days
    }


@router.get("/vehicle-inspection/{driver_id}/status")
async def get_vehicle_inspection_status(
    driver_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """TNC-09: Check vehicle inspection compliance for a driver. The driver themself or an admin only."""
    caller_driver_id = _auth.get("driver_id")
    is_self = caller_driver_id is not None and int(caller_driver_id) == driver_id
    if not (is_self or _auth.get("role") == "admin"):
        raise HTTPException(status_code=403, detail="Access denied")

    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    notes = driver.verification_notes or ""

    # Parse last inspection from notes
    if "VEHICLE INSPECTION" in notes:
        lines = notes.split("--- VEHICLE INSPECTION ---")
        last_inspection = lines[-1] if len(lines) > 1 else ""

        # Extract next due date
        next_due = None
        for line in last_inspection.split("\n"):
            if line.strip().startswith("Next Due:"):
                try:
                    next_due = datetime.strptime(line.split("Next Due:")[1].strip(), "%Y-%m-%d").date()
                except ValueError:
                    pass

        if next_due:
            days_until = (next_due - date.today()).days
            if days_until < 0:
                status = InspectionStatus.EXPIRED
            else:
                status = InspectionStatus.VALID
            return {
                "driver_id": driver_id,
                "status": status.value,
                "next_due_date": next_due.isoformat(),
                "days_until_due": days_until,
                "warning": days_until <= 30 and days_until >= 0,
            }

    return {
        "driver_id": driver_id,
        "status": InspectionStatus.MISSING.value,
        "next_due_date": None,
        "days_until_due": None,
        "warning": True,
        "message": "No vehicle inspection on file. Required before providing TNC services."
    }


# =============================================================================
# TNC-10: ZERO-TOLERANCE DRUG/ALCOHOL REPORTING + AUTO-SUSPENSION
# =============================================================================

@router.post("/zero-tolerance/report")
async def report_zero_tolerance_violation(
    data: ZeroToleranceReport,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """TNC-10: Report a suspected drug/alcohol violation by a driver.
    CPUC Decision 13-09-045 requires:
    - Immediate driver suspension pending investigation
    - Investigation process
    Promptly after a zero-tolerance complaint is filed, the TNC must suspend the driver."""

    driver = db.query(Driver).filter(Driver.id == data.driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    # Immediate suspension per CPUC requirement
    old_status = driver.status
    driver.status = DriverStatus.SUSPENDED
    driver.verification_notes = (
        (driver.verification_notes or "")
        + f"\n--- ZERO TOLERANCE REPORT ---"
        f"\nDate: {datetime.utcnow().isoformat()}"
        f"\nRide: {data.ride_request_id or 'N/A'}"
        f"\nReporter: {data.reporter_type}"
        f"\nDescription: {data.description}"
        f"\nAction: IMMEDIATE SUSPENSION (was {old_status})"
        f"\nStatus: UNDER INVESTIGATION"
    )

    db.commit()

    logger.warning(
        f"ZERO TOLERANCE: Driver {driver.id} ({driver.first_name} {driver.last_name}) "
        f"suspended. Ride: {data.ride_request_id}. Report: {data.description[:100]}"
    )

    return {
        "success": True,
        "driver_id": driver.id,
        "action_taken": "Driver immediately suspended pending investigation",
        "report_reference": f"ZT-{driver.id}-{datetime.utcnow().strftime('%Y%m%d%H%M')}",
        "cpuc_note": "You may also file a complaint with the CPUC at 1-800-894-9444 or CIU_intake@cpuc.ca.gov",
        "next_steps": "Our safety team will investigate within 48 hours. The driver cannot provide service until cleared."
    }


@router.get("/zero-tolerance/{driver_id}/history")
async def get_zero_tolerance_history(
    driver_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_admin),
):
    """TNC-10: Get zero-tolerance complaint history for a driver. Admin only."""
    driver = db.query(Driver).filter(Driver.id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    notes = driver.verification_notes or ""
    reports = []
    for section in notes.split("--- ZERO TOLERANCE REPORT ---"):
        if "Description:" in section:
            report = {}
            for line in section.strip().split("\n"):
                line = line.strip()
                if line.startswith("Date:"):
                    report["date"] = line.split("Date:")[1].strip()
                elif line.startswith("Ride:"):
                    report["ride_id"] = line.split("Ride:")[1].strip()
                elif line.startswith("Description:"):
                    report["description"] = line.split("Description:")[1].strip()
                elif line.startswith("Status:"):
                    report["status"] = line.split("Status:")[1].strip()
            if report:
                reports.append(report)

    return {
        "driver_id": driver_id,
        "driver_name": f"{driver.first_name} {driver.last_name}",
        "current_status": driver.status.value if hasattr(driver.status, 'value') else str(driver.status),
        "total_reports": len(reports),
        "reports": reports
    }


# =============================================================================
# TNC-22: CPUC QUARTERLY COMPLIANCE REPORTING
# =============================================================================

@router.get("/cpuc/quarterly-report")
async def get_quarterly_report(
    year: int = None,
    quarter: int = None,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_admin),
):
    """TNC-22: Generate CPUC quarterly compliance report.
    Includes trip data, fee collection, driver stats, and accessibility metrics
    for PUCTRA and Access for All Fund reporting."""

    now = datetime.utcnow()
    if not year:
        year = now.year
    if not quarter:
        quarter = (now.month - 1) // 3 + 1

    # Quarter date ranges
    quarter_starts = {1: 1, 2: 4, 3: 7, 4: 10}
    quarter_ends = {1: 3, 2: 6, 3: 9, 4: 12}
    start_date = datetime(year, quarter_starts[quarter], 1)
    if quarter == 4:
        end_date = datetime(year + 1, 1, 1)
    else:
        end_date = datetime(year, quarter_ends[quarter] + 1, 1)

    # Trip metrics
    completed_rides = db.query(RideRequest).filter(
        and_(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= start_date,
            RideRequest.completed_at < end_date,
        )
    ).all()

    total_trips = len(completed_rides)
    total_fare_revenue = sum(float(r.final_price or r.suggested_price or 0) for r in completed_rides)
    total_platform_fees = sum(float(r.platform_fee or 0) for r in completed_rides)
    total_tips = sum(float(r.tip_amount or 0) for r in completed_rides)
    total_driver_payouts = sum(float(r.driver_payout or 0) for r in completed_rides)

    # Access for All fee
    access_for_all_total = total_trips * 0.10  # $0.10 per trip

    # Accessibility metrics
    accessible_trips = len([r for r in completed_rides if getattr(r, 'accessibility_requested', False)])

    # Driver stats
    active_drivers = db.query(Driver).filter(
        Driver.status.in_([DriverStatus.ACTIVE, DriverStatus.APPROVED])
    ).count()

    total_drivers = db.query(Driver).count()

    bg_checked_drivers = db.query(Driver).filter(Driver.background_check == True).count()

    # WAV-capable drivers: accessibility_capable flag OR wheelchair in accessibility_features JSON
    wav_drivers = db.query(Driver).filter(
        or_(
            Driver.accessibility_capable == True,
            Driver.accessibility_features.like('%"wheelchair": true%'),
        )
    ).count()

    # Customer stats
    unique_customers = len(set(r.customer_id for r in completed_rides))

    return {
        "report": {
            "title": f"CPUC Quarterly Compliance Report — Q{quarter} {year}",
            "tnc_operator": "Zietra Technologies inc (dba Dollor.ai)",
            "permit_number": None,  # Fill after CPUC issues permit
            "period": f"Q{quarter} {year}",
            "start_date": start_date.strftime("%Y-%m-%d"),
            "end_date": (end_date - timedelta(days=1)).strftime("%Y-%m-%d"),
            "generated_at": now.isoformat(),
        },
        "trip_metrics": {
            "total_completed_trips": total_trips,
            "total_fare_revenue": round(total_fare_revenue, 2),
            "total_platform_fees_collected": round(total_platform_fees, 2),
            "total_tips_collected": round(total_tips, 2),
            "total_driver_payouts": round(total_driver_payouts, 2),
            "average_fare": round(total_fare_revenue / total_trips, 2) if total_trips > 0 else 0,
        },
        "puctra": {
            "total_intrastate_revenue": round(total_fare_revenue, 2),
            "puctra_fee_rate": "See current CPUC schedule",
            "estimated_puctra_due": round(total_fare_revenue * 0.001, 2),  # ~0.1% estimate
        },
        "access_for_all_fund": {
            "total_trips": total_trips,
            "fee_per_trip": 0.10,
            "total_collected": round(access_for_all_total, 2),
            "customer_share": round(total_trips * 0.05, 2),
            "driver_share": round(total_trips * 0.05, 2),
            "amount_due_to_cpuc": round(access_for_all_total, 2),
        },
        "accessibility_metrics": {
            "total_accessibility_requests": accessible_trips,
            "percentage_of_trips": round(accessible_trips / total_trips * 100, 1) if total_trips > 0 else 0,
            "wav_vehicles_available": wav_drivers,
        },
        "driver_metrics": {
            "total_registered_drivers": total_drivers,
            "active_drivers": active_drivers,
            "background_checked_drivers": bg_checked_drivers,
            "unique_drivers_completed_trips": len(set(r.matched_driver_id for r in completed_rides if r.matched_driver_id)),
        },
        "customer_metrics": {
            "unique_customers_served": unique_customers,
        },
        "safety": {
            "zero_tolerance_reports": "See /api/tnc/zero-tolerance/{driver_id}/history for per-driver details",
            "total_driver_suspensions": db.query(Driver).filter(Driver.status == DriverStatus.SUSPENDED).count(),
        }
    }


# =============================================================================
# TNC-23: ANTI-DISCRIMINATION MONITORING FOR DRIVER RATINGS
# =============================================================================

@router.get("/discrimination-monitor/report")
async def get_discrimination_monitoring_report(
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_admin),
):
    """TNC-23: Anti-discrimination monitoring report.
    Analyzes driver rating patterns to detect potential discrimination.
    Flags drivers with significantly lower ratings on accessibility rides vs normal rides.
    CPUC requires monitoring to prevent discrimination in driver reviews."""

    # Get all completed rides with ratings
    rated_rides = db.query(RideRequest).filter(
        and_(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.passenger_rating.isnot(None),  # Driver rated the passenger
        )
    ).all()

    if not rated_rides:
        return {
            "report_date": datetime.utcnow().isoformat(),
            "total_rated_rides": 0,
            "flagged_drivers": [],
            "summary": "No rated rides to analyze"
        }

    # Analyze ratings by driver — compare accessible vs non-accessible rides
    driver_ratings: Dict[int, Dict[str, list]] = {}

    for ride in rated_rides:
        did = ride.matched_driver_id
        if not did:
            continue
        if did not in driver_ratings:
            driver_ratings[did] = {"normal": [], "accessible": []}

        rating = ride.passenger_rating  # Driver's rating of passenger
        if getattr(ride, 'accessibility_requested', False):
            driver_ratings[did]["accessible"].append(rating)
        else:
            driver_ratings[did]["normal"].append(rating)

    flagged_drivers = []

    for driver_id, ratings in driver_ratings.items():
        normal = ratings["normal"]
        accessible = ratings["accessible"]

        # Only flag if enough data (at least 3 accessible rides)
        if len(accessible) < 3:
            continue

        avg_normal = sum(normal) / len(normal) if normal else 5.0
        avg_accessible = sum(accessible) / len(accessible)

        # Flag if average rating for accessible rides is >1 star lower
        rating_gap = avg_normal - avg_accessible
        if rating_gap > 1.0:
            driver = db.query(Driver).filter(Driver.id == driver_id).first()
            flagged_drivers.append({
                "driver_id": driver_id,
                "driver_name": f"{driver.first_name} {driver.last_name}" if driver else "Unknown",
                "avg_normal_rating": round(avg_normal, 2),
                "avg_accessible_rating": round(avg_accessible, 2),
                "rating_gap": round(rating_gap, 2),
                "normal_ride_count": len(normal),
                "accessible_ride_count": len(accessible),
                "risk_level": "HIGH" if rating_gap > 2.0 else "MEDIUM",
                "recommended_action": "Review driver behavior and consider retraining" if rating_gap <= 2.0 else "Immediate investigation required"
            })

    # Also check customer ratings of drivers — are accessibility riders rating drivers lower?
    customer_flagged = []
    driver_customer_ratings: Dict[int, Dict[str, list]] = {}

    for ride in db.query(RideRequest).filter(
        and_(
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.customer_rating.isnot(None),
        )
    ).all():
        did = ride.matched_driver_id
        if not did:
            continue
        if did not in driver_customer_ratings:
            driver_customer_ratings[did] = {"normal": [], "accessible": []}

        if getattr(ride, 'accessibility_requested', False):
            driver_customer_ratings[did]["accessible"].append(ride.customer_rating)
        else:
            driver_customer_ratings[did]["normal"].append(ride.customer_rating)

    for driver_id, ratings in driver_customer_ratings.items():
        accessible = ratings["accessible"]
        normal = ratings["normal"]
        if len(accessible) < 3 or not normal:
            continue
        avg_normal = sum(normal) / len(normal)
        avg_accessible = sum(accessible) / len(accessible)
        gap = avg_normal - avg_accessible
        if gap > 1.0:
            driver = db.query(Driver).filter(Driver.id == driver_id).first()
            customer_flagged.append({
                "driver_id": driver_id,
                "driver_name": f"{driver.first_name} {driver.last_name}" if driver else "Unknown",
                "avg_normal_customer_rating": round(avg_normal, 2),
                "avg_accessible_customer_rating": round(avg_accessible, 2),
                "gap": round(gap, 2),
                "note": "Customers with accessibility needs rate this driver significantly lower"
            })

    return {
        "report_date": datetime.utcnow().isoformat(),
        "total_rated_rides": len(rated_rides),
        "driver_bias_flags": {
            "description": "Drivers who rate accessibility passengers significantly lower than others",
            "flagged_count": len(flagged_drivers),
            "flagged_drivers": flagged_drivers,
        },
        "service_quality_flags": {
            "description": "Drivers rated significantly lower by accessibility passengers",
            "flagged_count": len(customer_flagged),
            "flagged_drivers": customer_flagged,
        },
        "summary": f"{len(flagged_drivers) + len(customer_flagged)} drivers flagged for review"
                   if (flagged_drivers or customer_flagged)
                   else "No discrimination patterns detected"
    }


# =============================================================================
# DRIVER ACCESSIBILITY CAPABILITY
# =============================================================================

class DriverAccessibilityUpdate(BaseModel):
    accessibility_capable: bool = False
    accessibility_features: Optional[Dict[str, bool]] = None

    @field_validator('accessibility_features')
    @classmethod
    def validate_features(cls, v):
        if v is None:
            return v
        allowed_keys = {"wheelchair", "service_animal", "mobility_storage", "audio_visual"}
        for key in v:
            if key not in allowed_keys:
                raise ValueError(f"Unknown accessibility feature: {key}. Allowed: {allowed_keys}")
        return v


@router.patch("/driver/accessibility")
async def update_driver_accessibility(
    data: DriverAccessibilityUpdate,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db),
):
    """Update driver's accessibility capability settings.
    Driver can only update their own profile (enforced by require_driver)."""
    import json

    driver.accessibility_capable = data.accessibility_capable
    if data.accessibility_features is not None:
        driver.accessibility_features = json.dumps(data.accessibility_features)
    elif not data.accessibility_capable:
        driver.accessibility_features = None

    db.commit()
    db.refresh(driver)

    features = {}
    if driver.accessibility_features:
        try:
            features = json.loads(driver.accessibility_features)
        except (json.JSONDecodeError, TypeError):
            features = {}

    return {
        "success": True,
        "driver_id": driver.id,
        "accessibility_capable": driver.accessibility_capable,
        "accessibility_features": features,
    }


@router.get("/driver/accessibility")
async def get_driver_accessibility(
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db),
):
    """Get driver's current accessibility capability settings."""
    import json

    features = {}
    if driver.accessibility_features:
        try:
            features = json.loads(driver.accessibility_features)
        except (json.JSONDecodeError, TypeError):
            features = {}

    return {
        "driver_id": driver.id,
        "accessibility_capable": driver.accessibility_capable,
        "accessibility_features": features,
    }
