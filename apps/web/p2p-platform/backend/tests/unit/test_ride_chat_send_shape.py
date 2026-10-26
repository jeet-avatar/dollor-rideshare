"""The POST reply for a ride chat message carries every field the iOS RideChatMessage decoder requires."""
from main_new import create_access_token
from models import RideRequest, RideRequestStatus

IOS_REQUIRED = {"id", "ride_request_id", "sender_type", "sender_id", "message", "created_at"}


def test_chat_send_reply_is_decodable_by_ios(client, db_session, test_customer, test_driver):
    ride = RideRequest(
        request_id="RIDE-CHAT-SHAPE", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.MATCHED, matched_driver_id=test_driver.id, suggested_price=10, final_price=10,
    )
    db_session.add(ride)
    db_session.commit()
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}

    response = client.post(f"/api/p2p/ride-requests/{ride.id}/chat",
                           json={"message": "On my way out", "sender_type": "customer"}, headers=headers)

    assert response.status_code == 200, response.text
    assert IOS_REQUIRED <= set(response.json()), IOS_REQUIRED - set(response.json())
    assert response.json()["sender_id"] == test_customer.id
