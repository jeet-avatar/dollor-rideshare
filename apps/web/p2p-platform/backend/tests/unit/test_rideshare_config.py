"""The rideshare config endpoint and the single fee-tier source."""
import pytest
from fastapi.testclient import TestClient

from main_new import app, get_fare_tier_description
from pricing_config import fare_tier_description, platform_fee_for, pricing_engine
from rideshare_payments import get_tier_fee

client = TestClient(app)


@pytest.mark.parametrize("fare,expected", [(0.01, 1.0), (35.0, 1.0), (35.01, 2.0), (70.0, 2.0), (70.01, 3.0), (500, 3.0)])
def test_platform_fee_boundaries(fare, expected):
    assert platform_fee_for(fare) == expected
    assert get_tier_fee(fare) == expected


def test_tier_description_follows_config(monkeypatch):
    monkeypatch.setattr(pricing_engine.config, "TIER_1_MAX", 40.0)
    monkeypatch.setattr(pricing_engine.config, "TIER_1_FEE", 1.5)
    assert platform_fee_for(40.0) == 1.5
    assert fare_tier_description(39.0) == "fare <= $40"
    assert get_fare_tier_description(45.0) == "fare $40-$70"


def test_config_endpoint_is_public_and_matches_engine():
    response = client.get("/api/config/rideshare")
    assert response.status_code == 200
    body = response.json()
    cfg = pricing_engine.config
    assert body["fees"]["tier1MaxFare"] == cfg.TIER_1_MAX
    assert body["fees"]["tier3Fee"] == cfg.TIER_3_FEE
    assert body["fees"]["accessForAllRiderShare"] + body["fees"]["accessForAllDriverShare"] == pytest.approx(body["fees"]["accessForAllFee"])
    assert body["bidding"]["etaOptionsMinutes"] == list(cfg.BID_ETA_OPTIONS_MINUTES)
    assert body["dispatch"]["radiusSteps"][0] == {"afterSeconds": 0, "miles": 3.0}


def test_unconfigured_support_claims_are_null(monkeypatch):
    for name in ("SUPPORT_HOURS_TEXT", "SUPPORT_RESPONSE_MINUTES", "ACH_FEE_DISCOUNT_TEXT"):
        monkeypatch.delenv(name, raising=False)
    support = client.get("/api/config/rideshare").json()["support"]
    assert support["hoursText"] is None and support["responseMinutes"] is None and support["achFeeDiscountText"] is None


def test_support_claims_come_from_environment(monkeypatch):
    monkeypatch.setenv("SUPPORT_HOURS_TEXT", "Daily 8AM-8PM PT")
    monkeypatch.setenv("SUPPORT_RESPONSE_MINUTES", "5")
    support = client.get("/api/config/rideshare").json()["support"]
    assert support["hoursText"] == "Daily 8AM-8PM PT" and support["responseMinutes"] == 5


def test_referral_reward_is_null_until_configured(monkeypatch):
    monkeypatch.delenv("REFERRAL_REWARD_TEXT", raising=False)
    assert client.get("/api/config/rideshare").json()["referral"]["rewardText"] is None
    monkeypatch.setenv("REFERRAL_REWARD_TEXT", "$5 off your first ride")
    assert client.get("/api/config/rideshare").json()["referral"]["rewardText"] == "$5 off your first ride"
