"""The fare estimate, the amount authorized at accept and the driver payout all come from one function."""
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import patch

import pytest

import bid_routes
from pricing_config import (
    apply_fare_multiplier,
    get_fare_estimate,
    platform_fee_for,
    pricing_engine,
    ride_charge_breakdown,
)

DISTANCES_KM = [0.2, 1, 2.5, 5, 8, 12, 16.1, 20, 30, 41, 60, 81, 120, 200]
HOURS = [0, 3, 6, 7, 8, 9, 10, 12, 15, 16, 17, 18, 19, 21, 22, 23]
PRICES = [0.01, 5, 8, 22.21, 34.99, 35, 35.01, 50, 69.99, 70, 70.01, 100, 250.5]


def _estimate(km, hour):
    minutes = max(1, int(km / 40 * 60))
    return get_fare_estimate(km, minutes, datetime(2026, 10, 27, hour, 0))


def _cents(x):
    return int(round(x * 100))


def _lines(b, with_demand=False):
    total = (b["base_fare"] + b["distance_cost"] + b["time_cost"] + b["time_adjustment"]
             - b["long_distance_discount"] + b["minimum_fare_adjustment"])
    return total + (b["demand_adjustment"] if with_demand else 0)


@pytest.mark.parametrize("km", DISTANCES_KM)
@pytest.mark.parametrize("hour", HOURS)
def test_breakdown_lines_sum_to_subtotal_and_total_adds_fee_and_share(km, hour):
    est = _estimate(km, hour)
    assert _cents(_lines(est["breakdown"])) == _cents(est["subtotal"])
    assert est["platform_fee"] == platform_fee_for(est["subtotal"])
    assert _cents(est["total"]) == _cents(est["subtotal"] + est["platform_fee"] + 0.05)
    assert _cents(est["driver_info"]["earnings"]) == _cents(est["subtotal"] - est["platform_fee"] - 0.05)


@pytest.mark.parametrize("km", DISTANCES_KM)
def test_suggested_bids_use_the_same_fee_and_share_rules(km):
    est = _estimate(km, 12)
    for bid in est["suggested_bids"]:
        charge = ride_charge_breakdown(bid["price"])
        assert bid["driver_earnings"] == charge["driver_payout"]
        assert bid["customer_total"] == charge["customer_total"]
        assert _cents(bid["customer_total"]) == _cents(bid["price"] + platform_fee_for(bid["price"]) + 0.05)
        assert _cents(bid["driver_earnings"]) == _cents(bid["price"] - platform_fee_for(bid["price"]) - 0.05)


def test_production_example_total_is_subtotal_plus_fee_plus_share():
    # prod showed subtotal 22.21 / fee 1.00 / total 23.16; the total must be 23.26
    assert ride_charge_breakdown(22.21)["customer_total"] == 23.26


@pytest.mark.parametrize("multiplier", [0.9, 1.0, 1.1, 1.25, 1.5, 1.875])
@pytest.mark.parametrize("km", [1, 5, 16.1, 40, 120])
def test_ride_type_and_demand_multiplier_keeps_everything_reconciled(km, multiplier):
    est = apply_fare_multiplier(_estimate(km, 12), multiplier)
    assert abs(_cents(_lines(est["breakdown"], True)) - _cents(est["subtotal"])) <= 1
    assert est["platform_fee"] == platform_fee_for(est["subtotal"])
    assert _cents(est["total"]) == _cents(est["subtotal"] + est["platform_fee"] + 0.05)
    assert _cents(est["driver_info"]["earnings"]) == _cents(est["subtotal"] - est["platform_fee"] - 0.05)
    for bid in est["suggested_bids"]:
        assert _cents(bid["customer_total"]) == _cents(bid["price"] + platform_fee_for(bid["price"]) + 0.05)
        assert _cents(bid["driver_earnings"]) == _cents(bid["price"] - platform_fee_for(bid["price"]) - 0.05)


def test_multiplier_estimate_crossing_a_fee_tier_uses_the_new_tier_fee():
    est = apply_fare_multiplier(_estimate(40, 12), 1.5)
    assert est["subtotal"] > 35 and est["platform_fee"] == 2.0


@pytest.mark.parametrize("price", PRICES)
def test_charge_breakdown_is_internally_consistent(price):
    c = ride_charge_breakdown(price)
    cfg = pricing_engine.config
    assert c["platform_fee"] == platform_fee_for(price)
    assert _cents(c["customer_total"]) == _cents(price + c["platform_fee"] + cfg.ACCESS_FOR_ALL_RIDER_SHARE)
    assert _cents(c["driver_payout"]) == _cents(price - c["platform_fee"] - cfg.ACCESS_FOR_ALL_DRIVER_SHARE)
    # the platform keeps 2x the fee; the two A4A shares are a pass-through
    assert _cents(c["customer_total"] - c["driver_payout"]) == _cents(2 * c["platform_fee"] + 0.10)


@pytest.mark.parametrize("price", PRICES)
def test_amount_authorized_at_accept_equals_the_helper(db_session, test_customer, monkeypatch, price):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_unit")
    ride = SimpleNamespace(id=1, request_id="REQ-1", customer_id=test_customer.id, stripe_payment_intent_id=None,
                           status=None, payment_status=None)
    bid = SimpleNamespace(id=7, driver_id=3)
    stripe_customer = SimpleNamespace(invoice_settings=SimpleNamespace(default_payment_method="pm_test"))
    test_customer.stripe_customer_id = "cus_test"
    db_session.commit()
    with patch("stripe.Customer.retrieve", return_value=stripe_customer), \
            patch("stripe.PaymentIntent.create",
                  return_value=SimpleNamespace(id="pi_x", status="requires_capture")) as create:
        bid_routes._authorize_ride_payment(db_session, ride, bid, price)
    assert create.call_args.kwargs["amount"] == _cents(ride_charge_breakdown(price)["customer_total"])
    assert create.call_args.kwargs["amount"] == _cents(price + platform_fee_for(price) + 0.05)


def test_estimate_endpoint_is_reconciled(client):
    r = client.post("/api/rides/estimate", json={
        "pickup_latitude": 37.7879, "pickup_longitude": -122.4075,
        "dropoff_latitude": 37.3382, "dropoff_longitude": -121.8863, "ride_type": "premium"})
    assert r.status_code == 200, r.text
    est = r.json()["estimate"]
    assert abs(_cents(_lines(est["breakdown"], True)) - _cents(est["subtotal"])) <= 1
    assert _cents(est["total"]) == _cents(est["subtotal"] + est["platform_fee"] + 0.05)
    assert _cents(est["driver_info"]["earnings"]) == _cents(est["subtotal"] - est["platform_fee"] - 0.05)
