"""Admin manual review of driver documents, and the driver profile ride count."""
from main_new import create_access_token
from models import RideRequest, RideRequestStatus


def test_admin_can_approve_a_driver_by_manual_review(client, db_session, test_driver, admin_auth_headers, test_admin):
    response = client.post(
        f"/api/verification/driver/{test_driver.id}/manual-review?action=approve&notes=checked",
        headers=admin_auth_headers,
    )

    assert response.status_code == 200, response.text
    db_session.refresh(test_driver)
    assert test_driver.documents_verified is True
    assert test_driver.verification_status == "verified"
    assert test_driver.verification_reviewer_id == test_admin.id


def test_driver_profile_counts_completed_rides(client, db_session, test_customer, test_driver):
    db_session.add(RideRequest(
        request_id="RIDE-PROFILE-COUNT", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.COMPLETED, matched_driver_id=test_driver.id, suggested_price=10, final_price=10,
    ))
    db_session.commit()
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_driver.email, "role": "driver", "driver_id": test_driver.id})}

    body = client.get(f"/erp/drivers/{test_driver.id}", headers=headers).json()

    assert body["total_rides"] == 1
