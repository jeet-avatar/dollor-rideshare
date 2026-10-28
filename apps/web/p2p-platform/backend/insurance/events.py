"""Core insurance event logger for Dollor.ai Usage-Based Insurance (UBI) tracking.

This module is intentionally defensive: log_insurance_event() must NEVER raise
an exception that would break ride or delivery flows.
"""
import logging
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from cache import redis_client, REDIS_AVAILABLE
from insurance.models import InsuranceEvent
from insurance.utils import haversine_miles
from models import Driver

logger = logging.getLogger(__name__)

# Redis TTL for GPS / mileage accumulator keys (24 hours)
_GPS_TTL = 86400

# GPS jitter threshold — ignore movements smaller than ~5 feet
_JITTER_THRESHOLD_MILES = 0.001


# ── Redis key helpers ──────────────────────────────────────────────────────────

def _mileage_key(driver_id: int, session_id: str) -> str:
    return f"insurance:mileage:{driver_id}:{session_id}"


def _last_gps_key(driver_id: int, session_id: str) -> str:
    return f"insurance:last_gps:{driver_id}:{session_id}"


# ── Public mileage helpers ─────────────────────────────────────────────────────

def accumulate_mileage(driver_id: int, session_id: str, lat: float, lng: float) -> None:
    """Record a GPS update and accumulate Haversine distance in Redis.

    Silently no-ops when Redis is unavailable or on any error.
    """
    if not REDIS_AVAILABLE or redis_client is None:
        return

    try:
        gps_key = _last_gps_key(driver_id, session_id)
        mile_key = _mileage_key(driver_id, session_id)

        raw = redis_client.get(gps_key)
        if raw:
            try:
                prev_lat, prev_lng = (float(v) for v in raw.split(","))
                delta = haversine_miles(prev_lat, prev_lng, lat, lng)
                if delta is not None and delta >= _JITTER_THRESHOLD_MILES:
                    redis_client.incrbyfloat(mile_key, delta)
                    redis_client.expire(mile_key, _GPS_TTL)
            except (ValueError, AttributeError):
                pass  # Corrupt stored value — skip, will self-heal on next update

        # Always store latest GPS position
        redis_client.set(gps_key, f"{lat},{lng}", ex=_GPS_TTL)

    except Exception:
        logger.debug("accumulate_mileage: Redis error (non-fatal)", exc_info=True)


def get_accumulated_mileage(driver_id: int, session_id: str) -> Optional[float]:
    """Read accumulated mileage from Redis. Returns None when unavailable."""
    if not REDIS_AVAILABLE or redis_client is None:
        return None

    try:
        raw = redis_client.get(_mileage_key(driver_id, session_id))
        return float(raw) if raw is not None else None
    except Exception:
        return None


def reset_period_mileage(driver_id: int, session_id: str) -> None:
    """Delete mileage accumulator keys at period transitions."""
    if not REDIS_AVAILABLE or redis_client is None:
        return

    try:
        redis_client.delete(
            _mileage_key(driver_id, session_id),
            _last_gps_key(driver_id, session_id),
        )
    except Exception:
        logger.debug("reset_period_mileage: Redis error (non-fatal)", exc_info=True)


# ── Session helpers ────────────────────────────────────────────────────────────

def get_or_create_session_id(db: Session, driver_id: int) -> str:
    """Return driver's active insurance session_id with 3-tier fallback.

    1. Driver.insurance_session_id column (if it exists)
    2. Most recent InsuranceEvent row for this driver
    3. Generate a new UUID
    """
    # Tier 1: column on Driver row (not yet migrated — use getattr)
    try:
        driver = db.query(Driver).filter(Driver.id == driver_id).first()
        if driver:
            sid = getattr(driver, "insurance_session_id", None)
            if sid:
                return sid
    except Exception:
        pass

    # Tier 2: most recent event for this driver
    try:
        latest = (
            db.query(InsuranceEvent)
            .filter(InsuranceEvent.driver_id == driver_id)
            .order_by(InsuranceEvent.created_at.desc())
            .first()
        )
        if latest and latest.session_id:
            return latest.session_id
    except Exception:
        pass

    # Tier 3: fresh session
    return str(uuid.uuid4())


# ── Core event logger ──────────────────────────────────────────────────────────

def log_insurance_event(
    db: Session,
    driver_id: int,
    trip_type: str,
    trip_id: Optional[int],
    session_id: str,
    period: int,
    event_type: str,
    metadata: Optional[dict] = None,
) -> Optional[InsuranceEvent]:
    """Create an InsuranceEvent row and (optionally) fire webhooks.

    This function is completely non-blocking and will NEVER raise an exception
    that could disrupt ride or delivery flows. If anything goes wrong, it logs
    the error and returns None.

    Args:
        db: SQLAlchemy session
        driver_id: Driver primary key
        trip_type: "rideshare", "delivery", or "available"
        trip_id: Associated ride/delivery order ID (None for app-open events)
        session_id: Insurance session UUID
        period: UBI period number (1, 2, or 3)
        event_type: "period_start" or "period_end"
        metadata: Arbitrary extra data stored in metadata_json

    Returns:
        The created InsuranceEvent, or None on any error.
    """
    try:
        now = datetime.utcnow()

        # ── Resolve driver GPS ─────────────────────────────────────────────────
        driver = db.query(Driver).filter(Driver.id == driver_id).first()
        if driver is None:
            logger.warning(f"log_insurance_event: driver {driver_id} not found")
            return None

        lat = driver.current_latitude
        lng = driver.current_longitude

        # ── Period-end: compute segment stats ─────────────────────────────────
        segment_miles: Optional[float] = None
        segment_duration_seconds: Optional[int] = None

        if event_type == "period_end":
            # 1. Try Redis accumulated mileage
            redis_miles = get_accumulated_mileage(driver_id, session_id)

            if redis_miles is not None and redis_miles > 0:
                segment_miles = redis_miles
            else:
                # 2. Fallback: Haversine from matching period_start to now
                start_event = (
                    db.query(InsuranceEvent)
                    .filter(
                        InsuranceEvent.driver_id == driver_id,
                        InsuranceEvent.session_id == session_id,
                        InsuranceEvent.period == period,
                        InsuranceEvent.event_type == "period_start",
                    )
                    .order_by(InsuranceEvent.timestamp.desc())
                    .first()
                )
                if start_event:
                    fallback = haversine_miles(
                        start_event.latitude, start_event.longitude, lat, lng
                    )
                    if fallback is not None:
                        segment_miles = fallback

            # 3. Duration from matching period_start timestamp
            start_event = (
                db.query(InsuranceEvent)
                .filter(
                    InsuranceEvent.driver_id == driver_id,
                    InsuranceEvent.session_id == session_id,
                    InsuranceEvent.period == period,
                    InsuranceEvent.event_type == "period_start",
                )
                .order_by(InsuranceEvent.timestamp.desc())
                .first()
            )
            if start_event:
                delta = now - start_event.timestamp
                segment_duration_seconds = int(delta.total_seconds())

            # 4. Reset accumulator for next period
            reset_period_mileage(driver_id, session_id)

        # ── Cumulative odometer ────────────────────────────────────────────────
        # Sum all prior segment_miles for this session and add current segment
        try:
            prior = (
                db.query(InsuranceEvent)
                .filter(
                    InsuranceEvent.driver_id == driver_id,
                    InsuranceEvent.session_id == session_id,
                    InsuranceEvent.segment_miles.isnot(None),
                )
                .all()
            )
            odometer = sum(e.segment_miles for e in prior if e.segment_miles)
            if segment_miles:
                odometer += segment_miles
            odometer_miles: Optional[float] = odometer if odometer > 0 else None
        except Exception:
            odometer_miles = None

        # ── Create row ─────────────────────────────────────────────────────────
        event = InsuranceEvent(
            driver_id=driver_id,
            trip_type=trip_type,
            trip_id=trip_id,
            session_id=session_id,
            period=period,
            event_type=event_type,
            timestamp=now,
            latitude=lat,
            longitude=lng,
            odometer_miles=odometer_miles,
            segment_miles=segment_miles,
            segment_duration_seconds=segment_duration_seconds,
            metadata_json=metadata,
        )
        # A savepoint keeps a duplicate-event violation (e.g. the same driver re-matching a ride after cancelling)
        # from poisoning the caller's transaction: without it the caller's next commit raises PendingRollbackError.
        try:
            with db.begin_nested():
                db.add(event)
                db.flush()  # Assign PK without committing (caller owns transaction)
        except IntegrityError:
            logger.info(
                f"log_insurance_event: duplicate event ignored (trip_type={trip_type}, trip_id={trip_id}, "
                f"period={period}, event_type={event_type})"
            )
            return None

        # ── Dispatch webhooks (non-blocking, failures are silent) ──────────────
        try:
            from insurance.webhooks import dispatch_event  # noqa: F401 — Task 4
            dispatch_event(db, event)
        except ImportError:
            pass  # webhooks module not yet implemented (Task 4) — expected
        except Exception:
            logger.debug("log_insurance_event: webhook dispatch error (non-fatal)", exc_info=True)

        return event

    except Exception:
        logger.exception(
            f"log_insurance_event: unexpected error for driver {driver_id} "
            f"(trip_type={trip_type}, period={period}, event_type={event_type})"
        )
        return None
