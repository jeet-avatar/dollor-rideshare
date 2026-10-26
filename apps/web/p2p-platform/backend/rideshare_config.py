"""Public rideshare configuration: the single source the iOS and Android apps read.

Fees, bidding presets, dispatch policy and support details are served from here so a change is made once
(in pricing_config / ride_dispatch / environment) and reaches every app without a release. The apps keep
bundled defaults only as an offline fallback.
"""
import os
from typing import Optional

from fastapi import APIRouter

import ride_dispatch
from pricing_config import pricing_engine

router = APIRouter(prefix="/api/config", tags=["Config"])

CONFIG_VERSION = 1


def _env(name: str) -> Optional[str]:
    value = os.getenv(name, "").strip()
    return value or None


def build_rideshare_config() -> dict:
    cfg = pricing_engine.config
    return {
        "version": CONFIG_VERSION,
        "fees": {
            "tier1MaxFare": cfg.TIER_1_MAX,
            "tier2MaxFare": cfg.TIER_2_MAX,
            "tier1Fee": cfg.TIER_1_FEE,
            "tier2Fee": cfg.TIER_2_FEE,
            "tier3Fee": cfg.TIER_3_FEE,
            "accessForAllFee": cfg.ACCESS_FOR_ALL_FEE,
            "accessForAllRiderShare": cfg.ACCESS_FOR_ALL_RIDER_SHARE,
            "accessForAllDriverShare": cfg.ACCESS_FOR_ALL_DRIVER_SHARE,
            "riderCancellationFee": cfg.RIDER_CANCELLATION_FEE,
        },
        "pricing": {
            "baseFare": cfg.BASE_FARE,
            "perMileRate": cfg.PER_MILE_RATE,
            "perMinuteRate": cfg.PER_MINUTE_RATE,
            "minimumFare": cfg.MINIMUM_FARE,
        },
        "bidding": {
            "windowMinutes": cfg.BIDDING_WINDOW_MINUTES,
            "quickAcceptFactor": cfg.BID_QUICK_ACCEPT_FACTOR,
            "fairFactor": cfg.BID_FAIR_FACTOR,
            "premiumFactor": cfg.BID_PREMIUM_FACTOR,
            "etaOptionsMinutes": list(cfg.BID_ETA_OPTIONS_MINUTES),
        },
        "dispatch": {
            "maxNotifiedDrivers": ride_dispatch.MAX_NOTIFIED_DRIVERS,
            "radiusSteps": [
                {"afterSeconds": seconds, "miles": miles}
                for seconds, miles in ride_dispatch.RADIUS_STEPS_MILES
            ],
        },
        # Referral reward shown in the share message. Null (no claim) until a reward really exists
        # and REFERRAL_REWARD_TEXT is set, e.g. "$5 off your first ride".
        "referral": {"rewardText": _env("REFERRAL_REWARD_TEXT")},
        # Support details. Hours, response time and the ACH note are shown only when set,
        # so the apps never display a claim the business has not configured.
        "support": {
            "email": _env("SUPPORT_EMAIL") or "support@dollor.ai",
            "phone": _env("SUPPORT_PHONE") or "+1-800-365-5671",
            "url": _env("SUPPORT_URL") or "https://www.dollor.ai/support",
            "hoursText": _env("SUPPORT_HOURS_TEXT"),
            "responseMinutes": int(_env("SUPPORT_RESPONSE_MINUTES")) if (_env("SUPPORT_RESPONSE_MINUTES") or "").isdigit() else None,
            "achFeeDiscountText": _env("ACH_FEE_DISCOUNT_TEXT"),
        },
    }


@router.get("/rideshare")
def get_rideshare_config():
    return build_rideshare_config()
