"""Driver online-session logging, hours online, and the available-to-pay-out balance.

Sessions live in their own table (created by Base.metadata.create_all; no change to existing tables).
Every route that flips Driver.is_online calls record_online_state; the location heartbeat calls
ensure_open_session so a driver who was already online before this shipped still starts accruing hours.
"""
import uuid
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from models import Driver, DriverStatus, DriverOnlineSession, DriverPayout, RideRequest, RideRequestStatus

# An open session only counts up to the driver's last location update plus this grace, so a driver
# whose app died while "online" does not accrue hours forever.
HEARTBEAT_GRACE = timedelta(minutes=10)

MANUAL_PAYOUT_METHOD = "stripe_manual_payout"
_REQUESTED_PAYOUT_STATUSES = ("processing", "completed")


def _open_sessions(db: Session, driver_id: int):
    return db.query(DriverOnlineSession).filter(
        DriverOnlineSession.driver_id == driver_id,
        DriverOnlineSession.ended_at.is_(None),
    ).all()


def _open_session_end(driver: Optional[Driver], session: DriverOnlineSession, now: datetime) -> datetime:
    """Best known end of a session that was never closed."""
    last_seen = driver.location_updated_at if driver is not None else None
    if last_seen is None:
        return session.started_at
    return max(session.started_at, min(now, last_seen + HEARTBEAT_GRACE))


def record_online_state(db: Session, driver: Driver, online: bool, now: Optional[datetime] = None) -> None:
    """Open a session when the driver goes online, close open ones when they go offline. Does not commit."""
    now = now or datetime.utcnow()
    for session in _open_sessions(db, driver.id):
        session.ended_at = _open_session_end(driver, session, now) if online else now
    if online:
        db.add(DriverOnlineSession(driver_id=driver.id, started_at=now))


def ensure_can_go_online(driver: Driver) -> None:
    """TNC gate (CPUC 13-09-045): only approved drivers whose Checkr background check passed may go online."""
    status_value = driver.status.value if hasattr(driver.status, "value") else str(driver.status)
    approved = (DriverStatus.APPROVED.value, DriverStatus.ACTIVE.value, DriverStatus.ONLINE.value)
    if status_value not in approved:
        raise HTTPException(status_code=403, detail="Driver not approved. Complete verification and background check before going online.")
    if not driver.background_check:
        raise HTTPException(status_code=403, detail="Background check not passed. You cannot go online until your background check clears.")


def ensure_can_go_offline(db: Session, driver: Driver) -> None:
    """409 when the driver is in the middle of a ride; riders would be stranded with an unreachable driver."""
    in_ride = db.query(RideRequest.id).filter(
        RideRequest.matched_driver_id == driver.id,
        RideRequest.status.in_([RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS]),
    ).first()
    if in_ride:
        raise HTTPException(status_code=409, detail="Finish or cancel your current ride before going offline.")


def ensure_open_session(db: Session, driver: Driver, now: Optional[datetime] = None) -> None:
    """Location heartbeat: an online driver always has an open session. Does not commit."""
    if not driver.is_online:
        return
    if not _open_sessions(db, driver.id):
        db.add(DriverOnlineSession(driver_id=driver.id, started_at=now or datetime.utcnow()))


def hours_online(db: Session, driver: Driver, since: datetime, now: Optional[datetime] = None) -> float:
    """Hours the driver was online between `since` and `now`."""
    now = now or datetime.utcnow()
    sessions = db.query(DriverOnlineSession).filter(
        DriverOnlineSession.driver_id == driver.id,
        DriverOnlineSession.started_at < now,
        (DriverOnlineSession.ended_at.is_(None)) | (DriverOnlineSession.ended_at > since),
    ).all()
    seconds = 0.0
    for session in sessions:
        start = max(session.started_at, since)
        end = min(session.ended_at or _open_session_end(driver, session, now), now)
        if end > start:
            seconds += (end - start).total_seconds()
    return round(seconds / 3600.0, 2)


def _sum(db: Session, column, *conditions) -> float:
    return float(db.query(func.coalesce(func.sum(column), 0)).filter(*conditions).scalar() or 0)


def requested_payouts(db: Session, driver_id: int, statuses=_REQUESTED_PAYOUT_STATUSES) -> float:
    """Manual bank payouts the driver already requested (in flight or paid)."""
    return _sum(
        db, DriverPayout.net_payout,
        DriverPayout.driver_id == driver_id,
        DriverPayout.payment_method == MANUAL_PAYOUT_METHOD,
        DriverPayout.status.in_(statuses),
    )


def total_earned(db: Session, driver_id: int) -> float:
    """Completed-ride driver payouts plus delivery payouts, before any manual bank payout."""
    rides = _sum(
        db, RideRequest.driver_payout,
        RideRequest.matched_driver_id == driver_id,
        RideRequest.status == RideRequestStatus.COMPLETED,
        RideRequest.driver_payout.isnot(None),
    )
    deliveries = _sum(
        db, DriverPayout.net_payout,
        DriverPayout.driver_id == driver_id,
        DriverPayout.status.in_(["pending", "completed"]),
        (DriverPayout.payment_method.is_(None)) | (DriverPayout.payment_method != MANUAL_PAYOUT_METHOD),
    )
    return rides + deliveries


def available_balance(db: Session, driver_id: int) -> float:
    """What the driver can still request as a payout: earnings minus payouts already requested or paid."""
    return round(max(0.0, total_earned(db, driver_id) - requested_payouts(db, driver_id)), 2)


def pending_payouts(db: Session, driver_id: int) -> float:
    """Payout requests still in flight to the bank."""
    return round(requested_payouts(db, driver_id, ("processing",)), 2)


def new_manual_payout(driver_id: int, amount: float, now: Optional[datetime] = None) -> DriverPayout:
    """Ledger row for a manual payout; inserted before calling Stripe so a double tap cannot overdraw."""
    now = now or datetime.utcnow()
    return DriverPayout(
        payout_number=f"MP-{driver_id}-{uuid.uuid4().hex[:12]}",
        driver_id=driver_id,
        period_start=now,
        period_end=now,
        net_payout=round(amount, 2),
        status="processing",
        payment_method=MANUAL_PAYOUT_METHOD,
    )
