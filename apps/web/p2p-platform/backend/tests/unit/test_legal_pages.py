"""Public legal pages (store requirement): served without auth and free of claims the product does not back."""
import pytest

PAGES = ["/terms", "/driver-terms", "/privacy", "/delete-account"]

UNSUPPORTED_CLAIMS = [
    "Proposition 22",
    "Earnings Guarantee",
    "120% of the California minimum wage",
    "Healthcare stipend",
    "Occupational accident insurance",
    "$1,000,000",
    "DOJ and FBI",
    "California-licensed",
    "24/7",
    "Founding Member",
    "restaurant",
    "food delivery",
]


@pytest.mark.parametrize("path", PAGES)
def test_legal_page_is_public_html(client, path):
    response = client.get(path)

    assert response.status_code == 200, response.text
    assert response.headers["content-type"].startswith("text/html")


@pytest.mark.parametrize("path", PAGES)
def test_legal_page_has_no_unsupported_claims(client, path):
    body = client.get(path).text.lower()

    for claim in UNSUPPORTED_CLAIMS:
        assert claim.lower() not in body, f"{path} still contains: {claim}"


def test_terms_state_the_coded_fee_and_cancellation_model(client):
    body = client.get("/terms").text

    assert "$1.00 if the fare is $35 or less" in body
    assert "$0.05" in body
    assert "5 minutes" in body
    assert "$5.00" in body
    assert "100% of tips" in body


def test_driver_terms_state_background_check_gate(client):
    body = client.get("/driver-terms").text

    assert "cannot go online until your account is approved and your background check has cleared" in body
    assert "21 years old" in body


def test_delete_account_page_gives_in_app_and_email_paths(client):
    body = client.get("/delete-account").text

    assert "Profile" in body and "Delete Account" in body
    assert "support@dollor.ai" in body
    assert "30 days" in body


def test_legal_terms_json_is_rideshare_only(client):
    body = client.get("/api/legal/terms").json()

    assert "food_delivery" not in body["summary"]["pricing"]
    assert body["summary"]["pricing"]["rideshare"]["cpuc_access_for_all_rider"] == 0.05
    assert body["summary"]["cancellation_policy"]["rideshare"]["rider_no_show_fee"] == 5.0
