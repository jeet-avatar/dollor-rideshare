"""Stripe amounts are integer cents; truncating a float (int(x * 100)) charged a cent too little
for some fares (e.g. 35.0 + 1 + 0.05 -> 3604.9999999999995 -> 3604)."""
import uuid
from unittest.mock import MagicMock, patch

import pytest

from main_new import create_access_token
from models import RideRequest, RideRequestStatus


@pytest.mark.parametrize("fare, expected_cents", [(35.0, 3605), (28.0, 2905), (17.3, 1835), (70.0, 7205)])
def test_ride_payment_intent_amount_is_exact_cents(client, db_session, test_customer, test_driver, fare, expected_cents):
    ride = RideRequest(
        request_id=f"RIDE-{uuid.uuid4().hex[:8]}", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.COMPLETED, matched_driver_id=test_driver.id,
        suggested_price=fare, final_price=fare,
    )
    db_session.add(ride)
    db_session.commit()
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}

    with patch("rideshare_payments.stripe.PaymentIntent.create") as create:
        create.return_value = MagicMock(id="pi_test_cents", client_secret="secret")
        resp = client.post("/api/payments/ride/create-intent", json={"ride_request_id": ride.id}, headers=headers)

    assert resp.status_code == 200, resp.text
    assert create.call_args[1]["amount"] == expected_cents
