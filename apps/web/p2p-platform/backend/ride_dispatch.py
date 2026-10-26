"""Who gets notified about a new ride request.

Instead of showing every open request to every online driver, a request is offered to the nearest
few drivers around the pickup. If nobody has bid after a short while, the search widens, so a ride
in a thin area still gets served. Pure functions, no database access, so the rules are easy to test.
"""
from __future__ import annotations

import math
from typing import Iterable, List, Optional, Sequence, Tuple

# Tunable dispatch policy (kept in one place; adjust after real-world data).
MAX_NOTIFIED_DRIVERS = 10

# (seconds since the request was created, search radius in miles once that age is reached)
RADIUS_STEPS_MILES: Sequence[Tuple[int, float]] = (
    (0, 3.0),
    (30, 5.0),
    (60, 10.0),
    (120, 25.0),
)

# Shared reviewer/QA accounts: they work from anywhere, so they always see every open request.
SHARED_DEMO_DRIVER_EMAILS = frozenset({"demo.driver@dollor.ai", "demo.driver2@dollor.ai"})

DriverPoint = Tuple[int, float, float]  # (driver_id, latitude, longitude)
EARTH_RADIUS_MILES = 3958.8


def max_radius_miles() -> float:
    """Widest search radius the dispatch policy ever reaches."""
    return max(radius for _, radius in RADIUS_STEPS_MILES)


def haversine_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat, dlon = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_MILES * math.asin(math.sqrt(a))


def search_radius_miles(age_seconds: float, has_bids: bool) -> float:
    """Radius for a request of this age. Once riders have offers in hand, the search stops widening."""
    effective_age = 0 if has_bids else max(age_seconds, 0)
    radius = RADIUS_STEPS_MILES[0][1]
    for threshold, step_radius in RADIUS_STEPS_MILES:
        if effective_age >= threshold:
            radius = step_radius
    return radius


def select_notified_driver_ids(
    pickup_lat: float,
    pickup_lon: float,
    online_drivers: Iterable[DriverPoint],
    age_seconds: float,
    has_bids: bool = False,
    max_drivers: int = MAX_NOTIFIED_DRIVERS,
) -> List[int]:
    """Nearest online drivers within the current radius, closest first, capped at `max_drivers`."""
    radius = search_radius_miles(age_seconds, has_bids)
    ranked = sorted(
        (haversine_miles(pickup_lat, pickup_lon, lat, lon), driver_id)
        for driver_id, lat, lon in online_drivers
    )
    return [driver_id for distance, driver_id in ranked if distance <= radius][:max_drivers]


def is_driver_notified(
    driver_id: int,
    pickup_lat: Optional[float],
    pickup_lon: Optional[float],
    online_drivers: Sequence[DriverPoint],
    age_seconds: float,
    has_bids: bool = False,
) -> bool:
    """Should this driver see the request? Falls back to True when we cannot place the request."""
    if pickup_lat is None or pickup_lon is None:
        return True
    return driver_id in select_notified_driver_ids(
        pickup_lat, pickup_lon, online_drivers, age_seconds, has_bids
    )
