"""
Unit tests for email_service.py

Tests cover:
- send_email() with mocked SMTP server
- send_email() without SMTP credentials (dev mode)
- send_email() with SMTP errors
- send_vendor_approval_email()
- send_vendor_registration_confirmation()
- send_driver_approval_email()
- send_driver_registration_confirmation()
- Email formatting validation
- Various input scenarios (edge cases)
"""

import pytest
import logging
from unittest.mock import MagicMock, patch, Mock, call
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import smtplib
import sys
import os

# Add backend directory to path
backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
sys.path.insert(0, backend_dir)

import email_service


class TestSendEmail:
    """Tests for the send_email() function"""

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('email_service.SMTP_HOST', 'smtp.gmail.com')
    @patch('email_service.SMTP_PORT', 587)
    @patch('email_service.FROM_EMAIL', 'noreply@dollor.ai')
    @patch('email_service.FROM_NAME', 'Dollor.ai')
    @patch('smtplib.SMTP')
    def test_send_email_success(self, mock_smtp_class):
        """Should successfully send email with valid SMTP configuration"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"
        text_body = "Test plain text"

        # Act
        result = email_service.send_email(to_email, subject, html_body, text_body)

        # Assert
        assert result is True
        mock_smtp_class.assert_called_once_with('smtp.gmail.com', 587, timeout=30)
        mock_server.starttls.assert_called_once()
        mock_server.login.assert_called_once_with('test@example.com', 'test_password')
        mock_server.sendmail.assert_called_once()

        # Verify sendmail was called with correct parameters
        call_args = mock_server.sendmail.call_args[0]
        assert call_args[0] == 'noreply@dollor.ai'  # from
        assert call_args[1] == to_email  # to
        assert subject in call_args[2]  # message contains subject

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_html_only(self, mock_smtp_class):
        """Should send email with HTML body only (no text body)"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True
        mock_server.sendmail.assert_called_once()

    @patch('email_service.SMTP_USER', '')
    @patch('email_service.SMTP_PASSWORD', '')
    @patch('email_service.IS_DEVELOPMENT', True)
    @patch('email_service.IS_PRODUCTION', False)
    def test_send_email_dev_mode_no_credentials(self, capsys, caplog):
        """Should log email and return True when SMTP credentials not configured in dev mode"""
        # Arrange
        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        with caplog.at_level(logging.INFO):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True
        # Check either print output or log message
        captured = capsys.readouterr()
        assert to_email in captured.out or to_email in caplog.text

    @patch('email_service.SMTP_USER', '')
    @patch('email_service.SMTP_PASSWORD', 'password_only')
    @patch('email_service.IS_DEVELOPMENT', True)
    @patch('email_service.IS_PRODUCTION', False)
    def test_send_email_dev_mode_missing_user(self, capsys, caplog):
        """Should log email and return True when SMTP_USER is missing in dev mode"""
        # Arrange
        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        with caplog.at_level(logging.INFO):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True
        # Check that it's in dev mode simulation
        captured = capsys.readouterr()
        assert "[DEV]" in captured.out or "DEV MODE" in caplog.text

    @patch('email_service.SMTP_USER', 'user_only')
    @patch('email_service.SMTP_PASSWORD', '')
    @patch('email_service.IS_DEVELOPMENT', True)
    @patch('email_service.IS_PRODUCTION', False)
    def test_send_email_dev_mode_missing_password(self, capsys, caplog):
        """Should log email and return True when SMTP_PASSWORD is missing in dev mode"""
        # Arrange
        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        with caplog.at_level(logging.INFO):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True
        # Check that it's in dev mode simulation
        captured = capsys.readouterr()
        assert "[DEV]" in captured.out or "DEV MODE" in caplog.text

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_smtp_connection_error(self, mock_smtp_class, caplog):
        """Should return False when SMTP connection fails"""
        # Arrange
        mock_smtp_class.side_effect = smtplib.SMTPConnectError(421, "Connection refused")
        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act — SMTPConnectError is a transient error logged at WARNING, not ERROR
        with caplog.at_level(logging.WARNING):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is False
        assert "SMTP transient error" in caplog.text or "Connection refused" in caplog.text

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_authentication_error(self, mock_smtp_class, caplog):
        """Should return False when SMTP authentication fails"""
        # Arrange
        mock_server = MagicMock()
        mock_server.login.side_effect = smtplib.SMTPAuthenticationError(535, "Authentication failed")
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        with caplog.at_level(logging.ERROR):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is False
        assert "authentication" in caplog.text.lower()

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_send_error(self, mock_smtp_class, caplog):
        """Should return False when email sending fails"""
        # Arrange
        mock_server = MagicMock()
        mock_server.sendmail.side_effect = smtplib.SMTPException("Failed to send")
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        with caplog.at_level(logging.ERROR):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is False
        assert "SMTP error" in caplog.text or "Failed to send" in caplog.text

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_generic_exception(self, mock_smtp_class, caplog):
        """Should return False and handle generic exceptions"""
        # Arrange
        mock_smtp_class.side_effect = Exception("Unexpected error")
        to_email = "recipient@example.com"
        subject = "Test Subject"
        html_body = "<h1>Test HTML</h1>"

        # Act
        with caplog.at_level(logging.ERROR):
            result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is False
        assert to_email in caplog.text or "Unexpected error" in caplog.text

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('email_service.FROM_EMAIL', 'noreply@dollor.ai')
    @patch('email_service.FROM_NAME', 'Dollor.ai')
    @patch('smtplib.SMTP')
    def test_send_email_correct_headers(self, mock_smtp_class):
        """Should set correct email headers (From, To, Subject)"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = "Test Subject Line"
        html_body = "<h1>Test</h1>"

        # Act
        result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True

        # Get the message that was sent
        call_args = mock_server.sendmail.call_args[0]
        message_str = call_args[2]

        # Verify headers are in the message
        assert "Subject: Test Subject Line" in message_str
        assert f"To: {to_email}" in message_str
        assert "From: Dollor.ai <noreply@dollor.ai>" in message_str

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_special_characters_in_subject(self, mock_smtp_class):
        """Should handle special characters in subject line"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = "🎉 Congratulations! Special chars: <>&\""
        html_body = "<h1>Test</h1>"

        # Act
        result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True
        mock_server.sendmail.assert_called_once()

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_send_email_empty_subject(self, mock_smtp_class):
        """Should handle empty subject"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        to_email = "recipient@example.com"
        subject = ""
        html_body = "<h1>Test</h1>"

        # Act
        result = email_service.send_email(to_email, subject, html_body)

        # Assert
        assert result is True
        mock_server.sendmail.assert_called_once()


class TestSendVendorApprovalEmail:
    """Tests for send_vendor_approval_email()"""

    @patch('email_service.send_email')
    def test_vendor_approval_email_success(self, mock_send_email):
        """Should call send_email with correct vendor approval content"""
        # Arrange
        mock_send_email.return_value = True
        to_email = "vendor@restaurant.com"
        restaurant_name = "Joe's Pizza"
        contact_name = "Joe Smith"

        # Act
        result = email_service.send_vendor_approval_email(
            to_email, restaurant_name, contact_name
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

        # Verify call arguments
        call_args = mock_send_email.call_args[0]
        assert call_args[0] == to_email
        assert restaurant_name in call_args[1]  # Subject contains restaurant name
        assert contact_name in call_args[2]  # HTML body contains contact name
        assert restaurant_name in call_args[2]  # HTML body contains restaurant name
        assert contact_name in call_args[3]  # Text body contains contact name

    @patch('email_service.send_email')
    def test_vendor_approval_email_contains_login_link(self, mock_send_email):
        """Should include vendor login link in email"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_vendor_approval_email(
            "vendor@example.com", "Test Restaurant", "John Doe"
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        assert "https://dollor.ai/vendor/login" in html_body

    @patch('email_service.send_email')
    def test_vendor_approval_email_special_characters_in_name(self, mock_send_email):
        """Should handle special characters in restaurant and contact names"""
        # Arrange
        mock_send_email.return_value = True
        restaurant_name = "Café José's <Bistro> & Grill"
        contact_name = "José O'Brien-Smith"

        # Act
        result = email_service.send_vendor_approval_email(
            "vendor@example.com", restaurant_name, contact_name
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        # Names should be in the HTML (even with special chars)
        assert "José" in html_body or "Jos" in html_body

    @patch('email_service.send_email')
    def test_vendor_approval_email_empty_names(self, mock_send_email):
        """Should handle empty restaurant and contact names"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_vendor_approval_email(
            "vendor@example.com", "", ""
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

    @patch('email_service.send_email')
    def test_vendor_approval_email_send_failure(self, mock_send_email):
        """Should return False when send_email fails"""
        # Arrange
        mock_send_email.return_value = False

        # Act
        result = email_service.send_vendor_approval_email(
            "vendor@example.com", "Test Restaurant", "John Doe"
        )

        # Assert
        assert result is False


class TestSendVendorRegistrationConfirmation:
    """Tests for send_vendor_registration_confirmation()"""

    @patch('email_service.send_email')
    def test_vendor_registration_confirmation_success(self, mock_send_email):
        """Should call send_email with correct registration confirmation content"""
        # Arrange
        mock_send_email.return_value = True
        to_email = "vendor@restaurant.com"
        restaurant_name = "Joe's Pizza"
        contact_name = "Joe Smith"
        vendor_id = "VEN-12345"

        # Act
        result = email_service.send_vendor_registration_confirmation(
            to_email, restaurant_name, contact_name, vendor_id
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

        # Verify call arguments
        call_args = mock_send_email.call_args[0]
        assert call_args[0] == to_email
        assert restaurant_name in call_args[1]  # Subject
        assert contact_name in call_args[2]  # HTML body
        assert restaurant_name in call_args[2]
        assert vendor_id in call_args[2]
        assert vendor_id in call_args[3]  # Text body

    @patch('email_service.send_email')
    def test_vendor_registration_confirmation_contains_vendor_id(self, mock_send_email):
        """Should include vendor ID in email"""
        # Arrange
        mock_send_email.return_value = True
        vendor_id = "VEN-99999"

        # Act
        result = email_service.send_vendor_registration_confirmation(
            "vendor@example.com", "Test Restaurant", "John Doe", vendor_id
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        text_body = call_args[3]
        assert vendor_id in html_body
        assert vendor_id in text_body

    @patch('email_service.send_email')
    def test_vendor_registration_confirmation_timeline_info(self, mock_send_email):
        """Should include timeline information in email"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_vendor_registration_confirmation(
            "vendor@example.com", "Test Restaurant", "John Doe", "VEN-123"
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        # Check for timeline/process information
        assert "Document Review" in html_body or "review" in html_body.lower()

    @patch('email_service.send_email')
    def test_vendor_registration_confirmation_special_vendor_id(self, mock_send_email):
        """Should handle special characters in vendor ID"""
        # Arrange
        mock_send_email.return_value = True
        vendor_id = "VEN-<test>&123"

        # Act
        result = email_service.send_vendor_registration_confirmation(
            "vendor@example.com", "Test Restaurant", "John Doe", vendor_id
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()


class TestSendDriverApprovalEmail:
    """Tests for send_driver_approval_email()"""

    @patch('email_service.send_email')
    def test_driver_approval_email_success(self, mock_send_email):
        """Should call send_email with correct driver approval content"""
        # Arrange
        mock_send_email.return_value = True
        to_email = "driver@example.com"
        driver_name = "Jane Driver"
        driver_code = "DRV-54321"

        # Act
        result = email_service.send_driver_approval_email(
            to_email, driver_name, driver_code
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

        # Verify call arguments
        call_args = mock_send_email.call_args[0]
        assert call_args[0] == to_email
        assert "activate" in call_args[1].lower()  # Subject mentions activation requirement
        assert driver_name in call_args[2]  # HTML body
        assert driver_code in call_args[2]
        assert driver_name in call_args[3]  # Text body
        assert driver_code in call_args[3]

    @patch('email_service.send_email')
    def test_driver_approval_email_contains_driver_code(self, mock_send_email):
        """Should prominently display driver code"""
        # Arrange
        mock_send_email.return_value = True
        driver_code = "DRV-12345"

        # Act
        result = email_service.send_driver_approval_email(
            "driver@example.com", "John Driver", driver_code
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        text_body = call_args[3]
        assert driver_code in html_body
        assert driver_code in text_body
        assert "YOUR DRIVER CODE" in html_body or "Driver Code" in html_body

    @patch('email_service.send_email')
    def test_driver_approval_email_contains_login_link(self, mock_send_email):
        """Should include driver login link"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_driver_approval_email(
            "driver@example.com", "John Driver", "DRV-123"
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        assert "dollor.ai/driver/activate" in html_body

    @patch('email_service.send_email')
    def test_driver_approval_email_contains_app_download_links(self, mock_send_email):
        """Should tell the driver to download the Dollor Driver app (iOS or Android)"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_driver_approval_email(
            "driver@example.com", "John Driver", "DRV-123"
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        assert "Dollor Driver app" in html_body
        assert "iOS" in html_body and "Android" in html_body

    @patch('email_service.send_email')
    def test_driver_approval_email_special_characters_in_name(self, mock_send_email):
        """Should handle special characters in driver name"""
        # Arrange
        mock_send_email.return_value = True
        driver_name = "José O'Brien-Smith Jr."

        # Act
        result = email_service.send_driver_approval_email(
            "driver@example.com", driver_name, "DRV-123"
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

    @patch('email_service.send_email')
    def test_driver_approval_email_empty_name(self, mock_send_email):
        """Should handle empty driver name"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_driver_approval_email(
            "driver@example.com", "", "DRV-123"
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()


class TestSendDriverRegistrationConfirmation:
    """Tests for send_driver_registration_confirmation()"""

    @patch('email_service.send_email')
    def test_driver_registration_confirmation_success(self, mock_send_email):
        """Should call send_email with correct registration confirmation content"""
        # Arrange
        mock_send_email.return_value = True
        to_email = "driver@example.com"
        driver_name = "Jane Driver"
        driver_code = "DRV-54321"

        # Act
        result = email_service.send_driver_registration_confirmation(
            to_email, driver_name, driver_code
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

        # Verify call arguments
        call_args = mock_send_email.call_args[0]
        assert call_args[0] == to_email
        assert driver_name in call_args[1]  # Subject welcomes the driver by name
        assert "Application Received" in call_args[1]
        assert driver_name in call_args[2]  # HTML body
        assert driver_code in call_args[2]
        assert driver_name in call_args[3]  # Text body

    @patch('email_service.send_email')
    def test_driver_registration_confirmation_contains_application_id(self, mock_send_email):
        """Should display application/driver ID"""
        # Arrange
        mock_send_email.return_value = True
        driver_code = "DRV-88888"

        # Act
        result = email_service.send_driver_registration_confirmation(
            "driver@example.com", "John Driver", driver_code
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        text_body = call_args[3]
        assert driver_code in html_body
        assert driver_code in text_body
        assert "Application ID" in html_body or "application" in html_body.lower()

    @patch('email_service.send_email')
    def test_driver_registration_confirmation_timeline_info(self, mock_send_email):
        """Should include onboarding timeline information"""
        # Arrange
        mock_send_email.return_value = True

        # Act
        result = email_service.send_driver_registration_confirmation(
            "driver@example.com", "John Driver", "DRV-123"
        )

        # Assert
        assert result is True
        call_args = mock_send_email.call_args[0]
        html_body = call_args[2]
        # Check for timeline/process information
        assert "Document review" in html_body and "Background check" in html_body

    @patch('email_service.send_email')
    def test_driver_registration_confirmation_send_failure(self, mock_send_email):
        """Should return False when send_email fails"""
        # Arrange
        mock_send_email.return_value = False

        # Act
        result = email_service.send_driver_registration_confirmation(
            "driver@example.com", "John Driver", "DRV-123"
        )

        # Assert
        assert result is False

    @patch('email_service.send_email')
    def test_driver_registration_confirmation_long_name(self, mock_send_email):
        """Should handle very long driver names"""
        # Arrange
        mock_send_email.return_value = True
        driver_name = "A" * 100  # Very long name

        # Act
        result = email_service.send_driver_registration_confirmation(
            "driver@example.com", driver_name, "DRV-123"
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()


class TestEmailEdgeCases:
    """Tests for edge cases and boundary conditions"""

    @patch('email_service.send_email')
    def test_unicode_characters_in_email_content(self, mock_send_email):
        """Should handle unicode characters (emojis, international chars)"""
        # Arrange
        mock_send_email.return_value = True
        restaurant_name = "Café München 🍕🍔🍟"
        contact_name = "François García"

        # Act
        result = email_service.send_vendor_approval_email(
            "test@example.com", restaurant_name, contact_name
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

    @patch('email_service.send_email')
    def test_very_long_restaurant_name(self, mock_send_email):
        """Should handle very long restaurant names"""
        # Arrange
        mock_send_email.return_value = True
        restaurant_name = "The Best Restaurant in the Entire World " * 10

        # Act
        result = email_service.send_vendor_approval_email(
            "test@example.com", restaurant_name, "John"
        )

        # Assert
        assert result is True
        mock_send_email.assert_called_once()

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_email_with_multiline_html(self, mock_smtp_class):
        """Should handle multiline HTML content"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        html_body = """
        <html>
            <body>
                <h1>Test</h1>
                <p>Line 1</p>
                <p>Line 2</p>
                <p>Line 3</p>
            </body>
        </html>
        """

        # Act
        result = email_service.send_email(
            "test@example.com", "Test", html_body, "Plain text"
        )

        # Assert
        assert result is True
        mock_server.sendmail.assert_called_once()

    @patch('email_service.IS_PRODUCTION', False)
    @patch('email_service.SMTP_USER', 'test@example.com')
    @patch('email_service.SMTP_PASSWORD', 'test_password')
    @patch('smtplib.SMTP')
    def test_email_preserves_both_text_and_html_parts(self, mock_smtp_class):
        """Should include both text and HTML parts in message"""
        # Arrange
        mock_server = MagicMock()
        mock_smtp_class.return_value.__enter__.return_value = mock_server

        html_body = "<h1>HTML Content</h1>"
        text_body = "Plain Text Content"

        # Act
        result = email_service.send_email(
            "test@example.com", "Test", html_body, text_body
        )

        # Assert
        assert result is True
        call_args = mock_server.sendmail.call_args[0]
        message_str = call_args[2]

        # Both parts should be in the message
        assert "HTML Content" in message_str
        assert "Plain Text Content" in message_str

    @patch('email_service.send_email')
    def test_all_email_functions_return_boolean(self, mock_send_email):
        """All email functions should return boolean values"""
        # Arrange
        mock_send_email.return_value = True

        # Act & Assert
        result1 = email_service.send_vendor_approval_email(
            "test@example.com", "Restaurant", "Contact"
        )
        assert isinstance(result1, bool)

        result2 = email_service.send_vendor_registration_confirmation(
            "test@example.com", "Restaurant", "Contact", "VEN-123"
        )
        assert isinstance(result2, bool)

        result3 = email_service.send_driver_approval_email(
            "test@example.com", "Driver", "DRV-123"
        )
        assert isinstance(result3, bool)

        result4 = email_service.send_driver_registration_confirmation(
            "test@example.com", "Driver", "DRV-123"
        )
        assert isinstance(result4, bool)


# ==================== ORDER LIFECYCLE EMAIL TESTS ====================

# Test fixtures for order lifecycle emails
@pytest.fixture
def order_test_data():
    """Common test data for order lifecycle emails"""
    return {
        "customer_email": "customer@example.com",
        "customer_name": "Test Customer",
        "order_number": "ORD-TEST-001",
        "restaurant_name": "Test Restaurant",
        "order_total": 29.99,
        "driver_name": "Test Driver",
        "eta_minutes": 20,
        "items_summary": "2x Test Item, 1x Side",
        "cancel_reason": "Customer requested cancellation",
        "vendor_email": "vendor@restaurant.com"
    }


class TestSendOrderConfirmationEmail:
    """Tests for send_order_confirmation_email()"""

    @patch('email_service.send_email')
    def test_order_confirmation_email_success(self, mock_send_email, order_test_data):
        """Should send order confirmation email successfully"""
        mock_send_email.return_value = True

        result = email_service.send_order_confirmation_email(
            to_email=order_test_data["customer_email"],
            customer_name=order_test_data["customer_name"],
            order_number=order_test_data["order_number"],
            restaurant_name=order_test_data["restaurant_name"],
            order_total=order_test_data["order_total"]
        )

        assert result is True
        mock_send_email.assert_called_once()
        call_args = mock_send_email.call_args[0]
        assert call_args[0] == order_test_data["customer_email"]
        assert order_test_data["order_number"] in call_args[1]

    @patch('email_service.send_email')
    def test_order_confirmation_with_items_summary(self, mock_send_email, order_test_data):
        """Should include items summary when provided"""
        mock_send_email.return_value = True

        result = email_service.send_order_confirmation_email(
            to_email=order_test_data["customer_email"],
            customer_name=order_test_data["customer_name"],
            order_number=order_test_data["order_number"],
            restaurant_name=order_test_data["restaurant_name"],
            order_total=order_test_data["order_total"],
            items_summary=order_test_data["items_summary"]
        )

        assert result is True
        call_args = mock_send_email.call_args[0]
        assert order_test_data["items_summary"] in call_args[2]


class TestSendOrderReadyEmail:
    """Tests for send_order_ready_email()"""

    @patch('email_service.send_email')
    def test_order_ready_email_success(self, mock_send_email, order_test_data):
        """Should send order ready email successfully"""
        mock_send_email.return_value = True

        result = email_service.send_order_ready_email(
            to_email=order_test_data["customer_email"],
            customer_name=order_test_data["customer_name"],
            order_number=order_test_data["order_number"],
            restaurant_name=order_test_data["restaurant_name"]
        )

        assert result is True
        mock_send_email.assert_called_once()


class TestOrderLifecycleEmailsReturnBoolean:
    """All order lifecycle email functions should return boolean values"""

    @patch('email_service.send_email')
    def test_all_order_email_functions_return_boolean(self, mock_send_email, order_test_data):
        """All order email functions should return boolean values"""
        mock_send_email.return_value = True

        results = [
            email_service.send_order_confirmation_email(
                order_test_data["customer_email"], order_test_data["customer_name"],
                order_test_data["order_number"], order_test_data["restaurant_name"],
                order_test_data["order_total"]
            ),
            email_service.send_order_ready_email(
                order_test_data["customer_email"], order_test_data["customer_name"],
                order_test_data["order_number"], order_test_data["restaurant_name"]
            ),
        ]

        for result in results:
            assert isinstance(result, bool)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
