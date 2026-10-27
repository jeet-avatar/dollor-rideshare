"""Tests for insurance/webhooks.py — Webhook HMAC Signing & Dispatch."""
import pytest
import hmac
import hashlib
import json
from datetime import datetime
from unittest.mock import patch, MagicMock, call
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from models import Base, Driver
from insurance.models import InsuranceEvent, InsuranceWebhookConfig
from insurance.webhooks import sign_payload, build_webhook_payload, dispatch_webhooks


@pytest.fixture
def db_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture
def mock_driver(db_session):
    driver = Driver(
        id=1,
        driver_id="DRV-TEST-001",
        email="test@example.com",
        password_hash="test",
        first_name="John",
        last_name="Doe",
        license_plate="ABC1234",
    )
    db_session.add(driver)
    db_session.commit()
    return driver


@pytest.fixture
def mock_event(db_session, mock_driver):
    event = InsuranceEvent(
        id="evt-123",
        driver_id=mock_driver.id,
        trip_type="rideshare",
        trip_id=456,
        session_id="sess-789",
        period=2,
        event_type="period_start",
        timestamp=datetime(2026, 3, 15, 12, 0, 0),
        latitude=40.7128,
        longitude=-74.0060,
        odometer_miles=3.2,
        segment_miles=1.8,
        segment_duration_seconds=420,
    )
    db_session.add(event)
    db_session.commit()
    return event


class TestSignPayload:
    def test_sign_returns_valid_hmac(self):
        """Test that sign_payload returns a properly formatted HMAC signature."""
        payload = '{"event_id": "test"}'
        secret = "my-secret-key"
        signature = sign_payload(payload, secret)
        expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
        assert signature == f"sha256={expected}"

    def test_different_secrets_produce_different_signatures(self):
        """Test that different secrets produce different signatures."""
        sig1 = sign_payload('{"event_id": "test"}', "secret-1")
        sig2 = sign_payload('{"event_id": "test"}', "secret-2")
        assert sig1 != sig2

    def test_signature_format_includes_prefix(self):
        """Test that signature includes 'sha256=' prefix."""
        signature = sign_payload('{"data": "test"}', "secret")
        assert signature.startswith("sha256=")

    def test_signature_is_deterministic(self):
        """Test that same payload and secret produce same signature."""
        payload = '{"event_id": "abc123"}'
        secret = "consistent-secret"
        sig1 = sign_payload(payload, secret)
        sig2 = sign_payload(payload, secret)
        assert sig1 == sig2


class TestBuildWebhookPayload:
    def test_payload_structure(self):
        """Test that payload contains all required fields."""
        payload = build_webhook_payload(
            event_id="abc-123",
            event_type="period_start",
            timestamp=datetime(2026, 3, 15, 12, 0, 0),
            driver_id=1,
            driver_first_name="John",
            driver_last_name="Doe",
            driver_license_plate="ABC1234",
            trip_type="rideshare",
            trip_id=456,
            period=2,
            odometer_miles=3.2,
            latitude=40.7128,
            longitude=-74.0060,
            segment_miles=1.8,
            segment_duration_seconds=420,
        )
        assert payload["event_id"] == "abc-123"
        assert payload["event_type"] == "period_start"
        assert payload["driver"]["first_name"] == "John"
        assert payload["driver"]["last_name"] == "Doe"
        assert payload["driver"]["license_plate"] == "ABC1234"
        assert payload["trip"]["type"] == "rideshare"
        assert payload["trip"]["id"] == 456
        assert payload["trip"]["period"] == 2
        assert payload["location"]["latitude"] == 40.7128
        assert payload["location"]["longitude"] == -74.0060
        assert payload["segment"]["miles"] == 1.8
        assert payload["segment"]["duration_seconds"] == 420

    def test_timestamp_iso_format(self):
        """Test that timestamp is ISO 8601 formatted with milliseconds."""
        ts = datetime(2026, 3, 15, 12, 30, 45, 123456)
        payload = build_webhook_payload(
            event_id="abc", event_type="test", timestamp=ts,
            driver_id=1, driver_first_name="Test", driver_last_name="User",
            driver_license_plate="XYZ", trip_type="delivery", trip_id=100,
            period=1, odometer_miles=1.0, latitude=0.0, longitude=0.0,
            segment_miles=0.5, segment_duration_seconds=60,
        )
        # Should be ISO format with Z suffix
        assert payload["timestamp"] == "2026-03-15T12:30:45.123Z"

    def test_timestamp_with_zero_microseconds(self):
        """Test timestamp formatting with zero microseconds."""
        ts = datetime(2026, 3, 15, 12, 0, 0, 0)
        payload = build_webhook_payload(
            event_id="test", event_type="test", timestamp=ts,
            driver_id=1, driver_first_name="A", driver_last_name="B",
            driver_license_plate="XYZ", trip_type="delivery", trip_id=1,
            period=1, odometer_miles=0.0, latitude=0.0, longitude=0.0,
            segment_miles=0.0, segment_duration_seconds=0,
        )
        assert payload["timestamp"] == "2026-03-15T12:00:00.000Z"

    def test_payload_is_json_serializable(self):
        """Test that payload can be JSON serialized."""
        payload = build_webhook_payload(
            event_id="abc", event_type="test", timestamp=datetime(2026, 3, 15, 12, 0, 0),
            driver_id=1, driver_first_name="Test", driver_last_name="User",
            driver_license_plate="XYZ", trip_type="delivery", trip_id=100,
            period=1, odometer_miles=1.0, latitude=0.0, longitude=0.0,
            segment_miles=0.5, segment_duration_seconds=60,
        )
        # Should not raise
        json_str = json.dumps(payload)
        assert json_str  # Non-empty JSON string


class _InlineThread:
    """Stand-in for threading.Thread that runs the target synchronously on start()."""

    def __init__(self, target=None, args=(), kwargs=None, daemon=None):
        self._target, self._args, self._kwargs = target, args, kwargs or {}

    def start(self):
        self._target(*self._args, **self._kwargs)


@pytest.fixture(autouse=True)
def public_dns_and_inline_threads(monkeypatch):
    """Keep dispatch tests hermetic: the SSRF guard resolves hostnames via DNS (fails offline),
    and real threads would race the assertions."""
    monkeypatch.setattr(
        "insurance.webhooks.socket.getaddrinfo",
        lambda host, *a, **k: [(2, 1, 6, "", ("93.184.216.34", 0))],
    )
    monkeypatch.setattr("insurance.webhooks.threading.Thread", _InlineThread)


class TestDispatchWebhooks:
    def test_no_webhooks_configured(self, db_session, mock_event):
        """Test that dispatch gracefully handles zero configured webhooks."""
        # Should not raise
        dispatch_webhooks(mock_event, db_session)

    def test_dispatch_sends_to_all_active_webhooks(self, db_session, mock_event, mock_driver):
        """Test that dispatch sends webhook to all active configs."""
        # Create 2 webhook configs
        webhook1 = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider1.example.com/webhook",
            secret_key="secret-1",
            is_active=True,
            event_types=["period_start"],
        )
        webhook2 = InsuranceWebhookConfig(
            id="hook-2",
            provider_name="Provider2",
            callback_url="https://provider2.example.com/webhook",
            secret_key="secret-2",
            is_active=True,
            event_types=["period_start", "period_end"],
        )
        db_session.add(webhook1)
        db_session.add(webhook2)
        db_session.commit()

        with patch("insurance.webhooks._send_webhook") as mock_send:
            dispatch_webhooks(mock_event, db_session)
            # Should attempt to send to both webhooks
            assert mock_send.call_count >= 2

    def test_dispatch_respects_event_type_filter(self, db_session, mock_event, mock_driver):
        """Test that dispatch respects event_types filter on webhook config."""
        # Create webhook that only accepts period_end
        webhook = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider.example.com/webhook",
            secret_key="secret",
            is_active=True,
            event_types=["period_end"],  # Only period_end
        )
        db_session.add(webhook)
        db_session.commit()

        # Event is period_start (not in filter)
        with patch("insurance.webhooks._send_webhook") as mock_send:
            dispatch_webhooks(mock_event, db_session)
            # Should NOT call _send_webhook because event_type not in filter
            mock_send.assert_not_called()

    def test_dispatch_skips_inactive_webhooks(self, db_session, mock_event, mock_driver):
        """Test that dispatch skips inactive webhook configs."""
        webhook = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider.example.com/webhook",
            secret_key="secret",
            is_active=False,  # Inactive
            event_types=["period_start"],
        )
        db_session.add(webhook)
        db_session.commit()

        with patch("insurance.webhooks._send_webhook") as mock_send:
            dispatch_webhooks(mock_event, db_session)
            # Should NOT send to inactive webhook
            mock_send.assert_not_called()

    def test_dispatch_includes_signature_header(self, db_session, mock_event, mock_driver):
        """Test that dispatch includes X-Insurance-Signature header."""
        webhook = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider.example.com/webhook",
            secret_key="my-secret",
            is_active=True,
            event_types=None,
        )
        db_session.add(webhook)
        db_session.commit()

        with patch("insurance.webhooks._send_webhook") as mock_send:
            dispatch_webhooks(mock_event, db_session)
            # Verify _send_webhook was called with proper args
            assert mock_send.call_count >= 1
            call_args = mock_send.call_args
            if call_args:
                # Third arg should be signature
                signature = call_args[0][2]
                assert signature.startswith("sha256=")

    def test_dispatch_uses_threading_for_async(self, db_session, mock_event, mock_driver):
        """Test that dispatch uses threading for async sending."""
        webhook = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider.example.com/webhook",
            secret_key="secret",
            is_active=True,
            event_types=None,
        )
        db_session.add(webhook)
        db_session.commit()

        with patch("insurance.webhooks._send_webhook") as mock_send:
            with patch("threading.Thread") as mock_thread:
                dispatch_webhooks(mock_event, db_session)
                # Thread should be created and started
                assert mock_thread.call_count >= 1

    def test_dispatch_handles_missing_driver(self, db_session, mock_event):
        """Test dispatch gracefully handles missing driver."""
        webhook = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider.example.com/webhook",
            secret_key="secret",
            is_active=True,
            event_types=None,
        )
        db_session.add(webhook)
        db_session.commit()

        # Event references non-existent driver
        mock_event.driver_id = 99999

        with patch("insurance.webhooks._send_webhook") as mock_send:
            # Should not raise
            dispatch_webhooks(mock_event, db_session)

    def test_dispatch_logs_errors(self, db_session, mock_event, mock_driver):
        """Test that dispatch logs exceptions."""
        webhook = InsuranceWebhookConfig(
            id="hook-1",
            provider_name="Provider1",
            callback_url="https://provider.example.com/webhook",
            secret_key="secret",
            is_active=True,
            event_types=None,
        )
        db_session.add(webhook)
        db_session.commit()

        with patch("insurance.webhooks.logger.error") as mock_logger:
            # Simulate an error during query
            with patch.object(db_session, "query", side_effect=Exception("DB Error")):
                dispatch_webhooks(mock_event, db_session)
                # Should have logged error
                mock_logger.assert_called()
