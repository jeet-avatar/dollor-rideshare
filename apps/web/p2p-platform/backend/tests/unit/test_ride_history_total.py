"""The history list must show the same total as the receipt."""
from types import SimpleNamespace as NS

from main_new import _ride_history_total


def ride(status, fare=8.0, fee=1.0, tip=2.0, afa=0.10):
    return NS(status=NS(value=status), final_price=fare, suggested_price=fare, platform_fee=fee, tip_amount=tip, access_for_all_fee=afa)


def test_completed_total_matches_receipt_arithmetic():
    # receipt for ride 594: 8.00 + 1.00 + 0.05 + 2.00 = 11.05
    assert _ride_history_total(ride("completed")) == 11.05


def test_cancelled_and_expired_show_fare_only():
    assert _ride_history_total(ride("cancelled")) == 8.0
    assert _ride_history_total(ride("expired")) == 8.0


def test_missing_cpuc_fee_defaults_to_current_rate():
    assert _ride_history_total(ride("completed", afa=None, tip=0.0)) == 9.05
