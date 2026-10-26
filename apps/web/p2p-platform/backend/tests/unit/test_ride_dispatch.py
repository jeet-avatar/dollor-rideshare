"""Dispatch policy: nearest drivers first, capped, widening over time."""
from ride_dispatch import (
    MAX_NOTIFIED_DRIVERS,
    haversine_miles,
    is_driver_notified,
    search_radius_miles,
    select_notified_driver_ids,
)

PICKUP = (37.7879, -122.4075)  # Union Square, SF


def drivers_at_miles(*distances):
    """Drivers due north of the pickup at the given distances (≈69 miles per degree of latitude)."""
    return [(i + 1, PICKUP[0] + d / 69.0, PICKUP[1]) for i, d in enumerate(distances)]


def test_haversine_known_distance():
    # SF -> Oakland is roughly 8-9 miles in a straight line
    assert 7.5 < haversine_miles(37.7879, -122.4075, 37.8044, -122.2712) < 9.5


def test_radius_widens_with_age_when_no_bids():
    assert search_radius_miles(0, has_bids=False) == 3.0
    assert search_radius_miles(30, has_bids=False) == 5.0
    assert search_radius_miles(60, has_bids=False) == 10.0
    assert search_radius_miles(500, has_bids=False) == 25.0


def test_radius_stops_widening_once_riders_have_offers():
    assert search_radius_miles(500, has_bids=True) == 3.0


def test_only_drivers_inside_radius_are_notified():
    ids = select_notified_driver_ids(*PICKUP, drivers_at_miles(1, 2.5, 4, 20), age_seconds=0)
    assert ids == [1, 2]


def test_closest_first_and_capped():
    many = drivers_at_miles(*[0.1 * (i + 1) for i in range(25)])
    ids = select_notified_driver_ids(*PICKUP, many, age_seconds=0)
    assert len(ids) == MAX_NOTIFIED_DRIVERS
    assert ids == list(range(1, MAX_NOTIFIED_DRIVERS + 1))


def test_search_widens_to_reach_far_driver_after_waiting():
    far = drivers_at_miles(8)
    assert select_notified_driver_ids(*PICKUP, far, age_seconds=10) == []
    assert select_notified_driver_ids(*PICKUP, far, age_seconds=65) == [1]


def test_unplaceable_request_is_shown_to_everyone():
    assert is_driver_notified(99, None, None, [], age_seconds=0) is True


def test_far_driver_is_not_notified_but_near_driver_is():
    pts = drivers_at_miles(1, 30)
    assert is_driver_notified(1, *PICKUP, pts, age_seconds=0) is True
    assert is_driver_notified(2, *PICKUP, pts, age_seconds=0) is False
