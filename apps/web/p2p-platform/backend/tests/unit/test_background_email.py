"""Ride emails must not block the API response (start/complete were waiting ~1-2 s on SMTP)."""
import asyncio
import time
from unittest.mock import patch

import bid_routes


def test_email_send_does_not_block_the_caller():
    calls = []

    def slow_sender(**kwargs):
        time.sleep(0.5)
        calls.append(kwargs)

    async def run():
        with patch.object(bid_routes, "send_ride_started_email", slow_sender):
            started = time.perf_counter()
            bid_routes._bg_email("send_ride_started_email", to_email="a@b.c")
            returned_after = time.perf_counter() - started
            await asyncio.sleep(0.8)  # let the worker thread finish
            return returned_after

    returned_after = asyncio.run(run())
    assert returned_after < 0.1, f"caller waited {returned_after:.2f}s"
    assert calls == [{"to_email": "a@b.c"}], "the email must still be sent"


def test_sender_failure_never_breaks_the_ride():
    def boom(**kwargs):
        raise RuntimeError("smtp down")

    async def run():
        with patch.object(bid_routes, "send_ride_started_email", boom):
            bid_routes._bg_email("send_ride_started_email", to_email="a@b.c")
            await asyncio.sleep(0.1)

    asyncio.run(run())  # must not raise


def test_runs_inline_without_an_event_loop():
    calls = []
    with patch.object(bid_routes, "send_ride_started_email", lambda **k: calls.append(k)):
        bid_routes._bg_email("send_ride_started_email", to_email="x@y.z")
    assert calls == [{"to_email": "x@y.z"}]
