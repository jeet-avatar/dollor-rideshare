"""
Email Service for Dollor.AI
Sends transactional emails for vendor approvals, order notifications, etc.

Production vs Development:
- Production: Requires SMTP credentials AND recipient must exist in DB.
- Development: Logs emails to console but doesn't actually send.

Security:
- STRICT mode: Only sends emails to registered customers, vendors, or drivers.
- All emails are logged to the Communication table for audit trail.
- Retry mechanism with exponential backoff for transient failures.
"""
import smtplib
import os
import logging
import uuid
import time
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional, Tuple
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# Environment detection
ENVIRONMENT = os.getenv("ENVIRONMENT", "production").lower()
IS_PRODUCTION = ENVIRONMENT in ("production", "prod")
IS_DEVELOPMENT = ENVIRONMENT in ("development", "dev", "local", "staging")

# Email configuration from environment
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
FROM_EMAIL = os.getenv("FROM_EMAIL", "noreply@dollor.ai")
FROM_NAME = os.getenv("FROM_NAME", "Dollor.AI")

# Retry configuration
MAX_RETRIES = 3
RETRY_DELAY_SECONDS = [1, 2, 4]  # Exponential backoff: 1s, 2s, 4s

# Base URLs for links
API_BASE_URL = os.getenv("API_BASE_URL", "https://api.dollor.ai")
WEB_BASE_URL = os.getenv("WEB_BASE_URL", "https://dollor.ai")

# Secret for signing unsubscribe tokens
UNSUBSCRIBE_SECRET = os.getenv("UNSUBSCRIBE_SECRET", "dollor-unsubscribe-secret-change-in-prod")


def _generate_unsubscribe_token(email: str, recipient_type: str) -> str:
    """
    Generate a signed token for unsubscribe links.
    Token format: base64(email:recipient_type:timestamp:signature)
    """
    import hashlib
    import base64

    timestamp = str(int(datetime.utcnow().timestamp()))
    data = f"{email}:{recipient_type}:{timestamp}"
    signature = hashlib.sha256(f"{data}:{UNSUBSCRIBE_SECRET}".encode()).hexdigest()[:16]
    token = base64.urlsafe_b64encode(f"{data}:{signature}".encode()).decode()
    return token


def verify_unsubscribe_token(token: str, max_age_days: int = 30) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Verify an unsubscribe token and extract email and recipient type.
    Returns: (is_valid, email, recipient_type)
    """
    import hashlib
    import base64

    try:
        decoded = base64.urlsafe_b64decode(token.encode()).decode()
        parts = decoded.split(":")
        if len(parts) != 4:
            return False, None, None

        email, recipient_type, timestamp, signature = parts

        # Verify signature
        data = f"{email}:{recipient_type}:{timestamp}"
        expected_sig = hashlib.sha256(f"{data}:{UNSUBSCRIBE_SECRET}".encode()).hexdigest()[:16]
        if signature != expected_sig:
            logger.warning(f"Invalid unsubscribe token signature for {email}")
            return False, None, None

        # Check token age
        token_time = int(timestamp)
        current_time = int(datetime.utcnow().timestamp())
        max_age_seconds = max_age_days * 24 * 60 * 60
        if current_time - token_time > max_age_seconds:
            logger.warning(f"Expired unsubscribe token for {email}")
            return False, None, None

        return True, email, recipient_type

    except Exception as e:
        logger.error(f"Error verifying unsubscribe token: {e}")
        return False, None, None


def generate_unsubscribe_link(email: str, recipient_type: str = "customer") -> str:
    """Generate a full unsubscribe URL with signed token."""
    token = _generate_unsubscribe_token(email, recipient_type)
    return f"{API_BASE_URL}/api/email/unsubscribe?token={token}"


def generate_tracking_pixel(communication_id: str) -> str:
    """
    Generate an HTML tracking pixel for email open tracking.
    The pixel URL will be hit when the email is opened.
    """
    tracking_url = f"{API_BASE_URL}/api/email/track/open/{communication_id}"
    return f'<img src="{tracking_url}" width="1" height="1" style="display:none;" alt="" />'


def generate_email_footer(
    email: str,
    recipient_type: str = "customer",
    include_unsubscribe: bool = True,
    communication_id: str = None
) -> str:
    """
    Generate a standard email footer with unsubscribe link and tracking pixel.
    CAN-SPAM compliant footer for all marketing/transactional emails.
    """
    unsubscribe_link = generate_unsubscribe_link(email, recipient_type)
    preferences_link = f"{WEB_BASE_URL}/{recipient_type}/settings/notifications"

    tracking_pixel = ""
    if communication_id:
        tracking_pixel = generate_tracking_pixel(communication_id)

    # Build unsubscribe row separately to avoid f-string escaping issues
    unsubscribe_row = ""
    if include_unsubscribe:
        unsubscribe_row = f'''<tr><td style="padding: 10px 0;"><p style="margin: 0;">Don't want these emails? <a href="{unsubscribe_link}" style="color: #64748b; text-decoration: underline;">Unsubscribe</a> or <a href="{preferences_link}" style="color: #64748b; text-decoration: underline;">Manage Preferences</a></p></td></tr>'''

    footer = f"""
    <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #e2e8f0;">
        <table width="100%" cellpadding="0" cellspacing="0" style="font-size: 12px; color: #64748b; text-align: center;">
            <tr>
                <td style="padding: 10px 0;">
                    <p style="margin: 0 0 10px 0;">© {datetime.utcnow().year} Dollor.AI - The $1 Delivery Platform</p>
                    <p style="margin: 0 0 10px 0;">
                        <a href="{WEB_BASE_URL}/terms" style="color: #64748b; text-decoration: underline;">Terms</a> |
                        <a href="{WEB_BASE_URL}/privacy" style="color: #64748b; text-decoration: underline;">Privacy</a> |
                        <a href="{WEB_BASE_URL}/support" style="color: #64748b; text-decoration: underline;">Support</a>
                    </p>
                </td>
            </tr>
            {unsubscribe_row}
            <tr>
                <td style="padding: 10px 0;">
                    <p style="margin: 0; font-size: 11px; color: #94a3b8;">
                        Dollor.AI, Inc. | 123 Tech Street, San Francisco, CA 94105
                    </p>
                </td>
            </tr>
        </table>
    </div>
    {tracking_pixel}
    """
    return footer


# Validate production configuration
def _validate_smtp_config() -> bool:
    """Check if SMTP is properly configured for sending emails."""
    return bool(SMTP_USER and SMTP_PASSWORD)


def _get_db_session():
    """Get a database session for email validation and logging."""
    try:
        from database import SessionLocal
        return SessionLocal()
    except Exception as e:
        logger.error(f"Failed to get database session: {e}")
        return None


def _validate_recipient_in_db(email: str, db_session) -> Tuple[bool, Optional[str], Optional[int]]:
    """
    SECURITY: Validate that the recipient email exists in our database.
    Only registered customers, vendors, or drivers can receive emails.
    Exception: 3 demo emails are allowlisted for App Store / Google Play review.

    Returns: (is_valid, recipient_type, recipient_id)
    """
    # Demo emails needed for Apple/Google app store review
    DEMO_EMAILS_ALLOWLIST = {
        "demo.customer@dollor.ai",
        "demo.driver@dollor.ai",
        "jeetnair.in@gmail.com",  # Admin compliance emails (quarterly reports)
    }
    if email and email.lower() in DEMO_EMAILS_ALLOWLIST:
        return True, "demo", 0

    if not db_session:
        logger.error("No database session available for recipient validation")
        return False, None, None

    try:
        from models import Customer, Vendor, Driver

        # Check if email belongs to a customer
        customer = db_session.query(Customer).filter(Customer.email == email).first()
        if customer:
            return True, "customer", customer.id

        # Check if email belongs to a vendor
        vendor = db_session.query(Vendor).filter(Vendor.contact_email == email).first()
        if vendor:
            return True, "vendor", vendor.id

        # Check if email belongs to a driver
        driver = db_session.query(Driver).filter(Driver.email == email).first()
        if driver:
            return True, "driver", driver.id

        logger.warning(f"SECURITY: Email {email} not found in customers, vendors, or drivers tables")
        return False, None, None

    except Exception as e:
        logger.error(f"Error validating recipient in database: {e}")
        return False, None, None


def _log_communication(
    db_session,
    to_email: str,
    subject: str,
    body: str,
    recipient_type: str,
    recipient_id: int,
    status: str,
    template_name: str = None,
    failure_reason: str = None,
    order_id: int = None,
    vendor_id: int = None
) -> Optional[int]:
    """
    Log email communication to the database for audit trail.
    Returns the communication ID or None if logging failed.
    """
    if not db_session:
        logger.warning("No database session - skipping communication logging")
        return None

    try:
        from models_extended import Communication, CommunicationChannel, CommunicationStatus, RecipientType

        # Map string status to enum
        status_map = {
            "pending": CommunicationStatus.PENDING,
            "sent": CommunicationStatus.SENT,
            "failed": CommunicationStatus.FAILED,
            "delivered": CommunicationStatus.DELIVERED
        }

        # Map string recipient type to enum
        recipient_type_map = {
            "customer": RecipientType.CUSTOMER,
            "vendor": RecipientType.VENDOR,
            "driver": RecipientType.DRIVER
        }

        communication = Communication(
            communication_id=f"EMAIL-{uuid.uuid4().hex[:12].upper()}",
            recipient_type=recipient_type_map.get(recipient_type, RecipientType.CUSTOMER),
            recipient_id=recipient_id or 0,
            recipient_email=to_email,
            channel=CommunicationChannel.EMAIL,
            template_name=template_name,
            subject=subject,
            body=body[:5000] if body else "",  # Truncate to avoid DB issues
            status=status_map.get(status, CommunicationStatus.PENDING),
            sent_at=datetime.utcnow() if status == "sent" else None,
            failed_at=datetime.utcnow() if status == "failed" else None,
            failure_reason=failure_reason,
            order_id=order_id,
            vendor_id=vendor_id,
            created_at=datetime.utcnow()
        )

        db_session.add(communication)
        db_session.commit()
        db_session.refresh(communication)

        logger.info(f"Communication logged: {communication.communication_id} ({status})")
        return communication.id

    except Exception as e:
        logger.error(f"Failed to log communication: {e}")
        db_session.rollback()
        return None


def _send_smtp_with_retry(to_email: str, subject: str, html_body: str, text_body: str = None) -> Tuple[bool, Optional[str]]:
    """
    Send email via SMTP with retry mechanism for transient failures.
    Returns: (success, error_message)
    """
    last_error = None

    for attempt in range(MAX_RETRIES):
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = f"{FROM_NAME} <{FROM_EMAIL}>"
            msg["To"] = to_email

            if text_body:
                msg.attach(MIMEText(text_body, "plain"))
            msg.attach(MIMEText(html_body, "html"))

            with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as server:
                server.starttls()
                server.login(SMTP_USER, SMTP_PASSWORD)
                server.sendmail(FROM_EMAIL, to_email, msg.as_string())

            logger.info(f"Email sent to {to_email}: {subject} (attempt {attempt + 1})")
            return True, None

        except smtplib.SMTPAuthenticationError as e:
            # Auth errors won't be fixed by retrying
            error_msg = f"SMTP authentication failed: {e}"
            logger.error(error_msg)
            return False, error_msg

        except (smtplib.SMTPServerDisconnected, smtplib.SMTPConnectError, ConnectionError, TimeoutError) as e:
            # Transient errors - retry
            last_error = str(e)
            logger.warning(f"SMTP transient error (attempt {attempt + 1}/{MAX_RETRIES}): {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY_SECONDS[attempt])
            continue

        except smtplib.SMTPException as e:
            last_error = str(e)
            logger.error(f"SMTP error sending to {to_email}: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY_SECONDS[attempt])
            continue

        except Exception as e:
            last_error = str(e)
            logger.error(f"Failed to send email to {to_email}: {e}")
            return False, last_error

    return False, f"Failed after {MAX_RETRIES} attempts. Last error: {last_error}"


SUPPORT_EMAIL = "support@dollor.ai"


def notify_support(subject: str, details: dict) -> bool:
    """
    Send an internal admin notification to support@dollor.ai.
    Bypasses the DB recipient validation — only used for internal alerts.
    Fails silently if SMTP is not configured so form saves still succeed.
    """
    if not _validate_smtp_config():
        logger.warning(f"[notify_support] SMTP not configured — skipping email: {subject}")
        return False

    rows = "".join(
        f"<tr><td style='padding:6px 12px;color:#94a3b8;font-size:13px;vertical-align:top;white-space:nowrap'>{k}</td>"
        f"<td style='padding:6px 12px;color:#fff;font-size:13px;word-break:break-word'>{v}</td></tr>"
        for k, v in details.items()
    )
    html = f"""
    <div style='background:#0a0a0f;padding:32px;font-family:Inter,sans-serif'>
      <div style='max-width:600px;margin:0 auto'>
        <div style='background:linear-gradient(135deg,#ff6b00,#ff9500);padding:3px;border-radius:14px;margin-bottom:24px'>
          <div style='background:#0a0a0f;border-radius:12px;padding:20px 24px'>
            <span style='font-size:22px;font-weight:900;color:#fff'>dollor<span style="color:#ff6b00">.ai</span></span>
            <span style='font-size:12px;color:rgba(255,255,255,0.4);margin-left:12px'>Admin Notification</span>
          </div>
        </div>
        <h2 style='color:#fff;font-size:20px;font-weight:800;margin-bottom:20px'>{subject}</h2>
        <table style='width:100%;border-collapse:collapse;background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.08);border-radius:12px;overflow:hidden'>
          {rows}
        </table>
        <p style='color:rgba(255,255,255,0.25);font-size:12px;margin-top:24px'>
          dollor.ai · CPUC Permit TNC0050982-N · Zietra Technologies Inc.
        </p>
      </div>
    </div>
    """
    text = f"{subject}\n\n" + "\n".join(f"{k}: {v}" for k, v in details.items())
    success, err = _send_smtp_with_retry(SUPPORT_EMAIL, f"[Dollor] {subject}", html, text)
    if not success:
        logger.error(f"[notify_support] Failed to send '{subject}': {err}")
    return success


def send_email(
    to_email: str,
    subject: str,
    html_body: str,
    text_body: str = None,
    template_name: str = None,
    order_id: int = None,
    vendor_id: int = None,
    skip_validation: bool = False
) -> bool:
    """
    Send an email using SMTP with authenticated credentials.

    SECURITY (Production Mode):
    - Requires SMTP_USER and SMTP_PASSWORD to be set
    - STRICT: Recipient email MUST exist in customers, vendors, or drivers table
    - All emails are logged to Communication table for audit trail
    - Retry mechanism with exponential backoff for transient SMTP failures

    Development Mode:
    - Logs email details to console
    - Does not actually send emails
    - Returns True (simulates success)

    Args:
        to_email: Recipient email address (must be registered in DB for production)
        subject: Email subject line
        html_body: HTML content of the email
        text_body: Plain text fallback (optional)
        template_name: Name of email template for logging (optional)
        order_id: Related order ID for logging (optional)
        vendor_id: Related vendor ID for logging (optional)
        skip_validation: DANGEROUS - Skip DB validation (only for system emails)

    Returns True if successful, False otherwise.
    """
    # Demo redirect: for the underwriter walkthrough we route ALL demo-account
    # emails (customer/driver) to a single real inbox so receipts
    # are visible in one place. Production senders are untouched.
    DEMO_REDIRECT_TO = "jeetnair.in@gmail.com"
    DEMO_ACCOUNTS = {
        "demo.customer@dollor.ai",
        "demo.driver@dollor.ai",
    }
    if to_email and to_email.lower() in DEMO_ACCOUNTS:
        subject = f"[demo:{to_email.split('@')[0]}] {subject}"
        to_email = DEMO_REDIRECT_TO
        skip_validation = True

    db_session = None
    recipient_type = None
    recipient_id = None

    try:
        # Validate email address format (basic check)
        if not to_email or "@" not in to_email:
            logger.error(f"Invalid email address format: {to_email}")
            return False

        # Get database session for validation and logging
        db_session = _get_db_session()

        # SECURITY: In production, validate recipient exists in our database
        if IS_PRODUCTION and not skip_validation:
            if db_session:
                is_valid, recipient_type, recipient_id = _validate_recipient_in_db(to_email, db_session)
                if not is_valid:
                    logger.error(f"SECURITY BLOCK: Attempted to send email to unregistered address: {to_email}")
                    # Log the blocked attempt
                    _log_communication(
                        db_session=db_session,
                        to_email=to_email,
                        subject=subject,
                        body=html_body,
                        recipient_type="unknown",
                        recipient_id=0,
                        status="failed",
                        template_name=template_name,
                        failure_reason="SECURITY: Recipient not found in database",
                        order_id=order_id,
                        vendor_id=vendor_id
                    )
                    return False
            else:
                # No DB connection in production = security risk, block email
                logger.error(f"SECURITY BLOCK: Cannot validate recipient (no DB connection): {to_email}")
                return False

        # Check SMTP configuration
        if not _validate_smtp_config():
            if IS_PRODUCTION:
                logger.error(f"SMTP not configured in production! Email NOT sent to {to_email}: {subject}")
                if db_session and recipient_type:
                    _log_communication(
                        db_session=db_session,
                        to_email=to_email,
                        subject=subject,
                        body=html_body,
                        recipient_type=recipient_type or "unknown",
                        recipient_id=recipient_id or 0,
                        status="failed",
                        template_name=template_name,
                        failure_reason="SMTP not configured",
                        order_id=order_id,
                        vendor_id=vendor_id
                    )
                return False
            else:
                # Development mode - simulate success and log
                logger.info(f"[DEV MODE] Email simulated to {to_email}: {subject}")
                print(f"[DEV] Email would be sent to {to_email}: {subject}")
                if db_session:
                    _log_communication(
                        db_session=db_session,
                        to_email=to_email,
                        subject=subject,
                        body=html_body,
                        recipient_type=recipient_type or "customer",
                        recipient_id=recipient_id or 0,
                        status="sent",
                        template_name=template_name,
                        failure_reason=None,
                        order_id=order_id,
                        vendor_id=vendor_id
                    )
                return True

        # Send email with retry mechanism
        success, error_message = _send_smtp_with_retry(to_email, subject, html_body, text_body)

        # Log to database
        if db_session:
            _log_communication(
                db_session=db_session,
                to_email=to_email,
                subject=subject,
                body=html_body,
                recipient_type=recipient_type or "customer",
                recipient_id=recipient_id or 0,
                status="sent" if success else "failed",
                template_name=template_name,
                failure_reason=error_message,
                order_id=order_id,
                vendor_id=vendor_id
            )

        return success

    except Exception as e:
        logger.error(f"Unexpected error in send_email: {e}")
        if db_session:
            try:
                _log_communication(
                    db_session=db_session,
                    to_email=to_email,
                    subject=subject,
                    body=html_body,
                    recipient_type=recipient_type or "unknown",
                    recipient_id=recipient_id or 0,
                    status="failed",
                    template_name=template_name,
                    failure_reason=str(e),
                    order_id=order_id,
                    vendor_id=vendor_id
                )
            except Exception:
                pass
        return False

    finally:
        if db_session:
            try:
                db_session.close()
            except Exception:
                pass


def _dollor_email(icon: str, title: str, subtitle: str, body_html: str, footer_note: str = "") -> str:
    """
    Shared Dollor email base template.
    All consumer-facing emails use this for consistent branding.
    Dark header, orange accents, light body — works in all major email clients.
    """
    footer_extra = f'<br>{footer_note}' if footer_note else ''
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<style>
  *{{margin:0;padding:0;box-sizing:border-box}}
  body{{background:#f0f0f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;-webkit-font-smoothing:antialiased;color:#111827}}
  .wrap{{max-width:600px;margin:28px auto}}
  .hdr{{background:#0a0a0f;padding:22px 28px;border-radius:14px 14px 0 0;display:table;width:100%}}
  .logo-d{{display:inline-block;width:34px;height:34px;background:linear-gradient(135deg,#ff6b00,#ff9500);border-radius:9px;text-align:center;line-height:34px;font-size:17px;font-weight:900;color:#fff;vertical-align:middle}}
  .logo-txt{{display:inline-block;font-size:19px;font-weight:800;color:#fff;letter-spacing:-0.4px;vertical-align:middle;margin-left:10px}}
  .hero{{background:#fff;padding:36px 28px 28px;text-align:center;border-left:1px solid #e5e5ea;border-right:1px solid #e5e5ea}}
  .hero-icon{{font-size:52px;display:block;margin-bottom:14px}}
  .hero-title{{font-size:24px;font-weight:800;color:#0a0a0f;letter-spacing:-0.5px;margin-bottom:6px}}
  .hero-sub{{font-size:14px;color:#6b7280;line-height:1.6}}
  .body{{background:#fff;padding:4px 28px 28px;border-left:1px solid #e5e5ea;border-right:1px solid #e5e5ea}}
  .body p{{font-size:15px;color:#374151;line-height:1.75;margin:14px 0}}
  .divider{{height:1px;background:#f3f4f6;margin:20px 0}}
  .box{{background:#f7f7fa;border-radius:12px;padding:20px;margin:20px 0}}
  .row{{display:table;width:100%;padding:9px 0;border-bottom:1px solid #efeff3}}
  .row:last-child{{border-bottom:none}}
  .row-lbl{{display:table-cell;font-size:13px;color:#9ca3af;font-weight:500;width:40%;vertical-align:top;padding-top:1px}}
  .row-val{{display:table-cell;font-size:14px;color:#111827;font-weight:600;text-align:right}}
  .stats{{display:table;width:100%;margin:22px 0;background:#f7f7fa;border-radius:12px;padding:18px 0}}
  .stat{{display:table-cell;text-align:center;padding:0 12px;border-right:1px solid #e5e5ea}}
  .stat:last-child{{border-right:none}}
  .stat-val{{font-size:28px;font-weight:900;color:#0a0a0f;letter-spacing:-1px}}
  .stat-lbl{{font-size:11px;color:#9ca3af;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;margin-top:4px}}
  .cta{{display:block;background:linear-gradient(135deg,#ff6b00,#ff9500);color:#fff;text-align:center;padding:17px 28px;border-radius:12px;text-decoration:none;font-weight:800;font-size:16px;margin:24px 0;letter-spacing:-0.2px}}
  .cta-ghost{{display:block;background:transparent;color:#ff6b00;text-align:center;padding:14px 28px;border-radius:12px;text-decoration:none;font-weight:700;font-size:14px;border:1.5px solid rgba(255,107,0,.3);margin:10px 0}}
  .code-wrap{{background:#0a0a0f;border-radius:14px;padding:30px;text-align:center;margin:22px 0}}
  .code{{font-family:'Courier New',Courier,monospace;font-size:42px;font-weight:900;color:#ff6b00;letter-spacing:10px}}
  .code-hint{{color:rgba(255,255,255,.4);font-size:13px;margin-top:10px}}
  .alert{{background:#fff7ed;border:1px solid rgba(255,107,0,.25);border-radius:10px;padding:15px 18px;margin:18px 0;font-size:14px;color:#92400e;line-height:1.6}}
  .green-tag{{display:inline-block;background:rgba(74,222,128,.12);border:1px solid rgba(74,222,128,.3);color:#15803d;border-radius:20px;padding:4px 14px;font-size:12px;font-weight:700}}
  .orange-tag{{display:inline-block;background:rgba(255,107,0,.1);border:1px solid rgba(255,107,0,.3);color:#ff6b00;border-radius:20px;padding:4px 14px;font-size:12px;font-weight:700}}
  ul.perks{{list-style:none;margin:14px 0}}
  ul.perks li{{padding:8px 0;font-size:14px;color:#374151;border-bottom:1px solid #f3f4f6;display:flex;align-items:flex-start;gap:10px}}
  ul.perks li:last-child{{border-bottom:none}}
  .check{{color:#ff6b00;font-weight:700;flex-shrink:0}}
  .ftr{{background:#0a0a0f;padding:22px 28px;border-radius:0 0 14px 14px}}
  .ftr-logo{{font-size:16px;font-weight:800;color:#fff;margin-bottom:10px}}
  .ftr-links{{font-size:12px;color:rgba(255,255,255,.4);line-height:1.8}}
  .ftr-links a{{color:rgba(255,255,255,.5);text-decoration:none}}
  .ftr-legal{{font-size:11px;color:rgba(255,255,255,.2);margin-top:14px;padding-top:12px;border-top:1px solid rgba(255,255,255,.06);line-height:1.7}}
</style>
</head>
<body>
<div class="wrap">
  <div class="hdr">
    <span class="logo-d">D</span>
    <span class="logo-txt">dollor<span style="color:#ff6b00">.ai</span></span>
  </div>
  <div class="hero">
    <span class="hero-icon">{icon}</span>
    <div class="hero-title">{title}</div>
    <div class="hero-sub">{subtitle}</div>
  </div>
  <div class="body">
    {body_html}
  </div>
  <div class="ftr">
    <div class="ftr-logo">dollor<span style="color:#ff6b00">.ai</span></div>
    <div class="ftr-links">
      CPUC Permit TNC0050982-N · Zietra Technologies Inc., RSM, CA 92688<br>
      <a href="https://dollor.ai/zero-tolerance">Zero Tolerance</a> &nbsp;·&nbsp;
      <a href="https://dollor.ai/terms">Terms</a> &nbsp;·&nbsp;
      <a href="https://dollor.ai/privacy">Privacy</a> &nbsp;·&nbsp;
      <a href="https://dollor.ai/safety">Safety</a>
      {footer_extra}
    </div>
    <div class="ftr-legal">
      © 2026 Zietra Technologies Inc. · support@dollor.ai · dollor.ai<br>
      You're receiving this because you have a Dollor account.
    </div>
  </div>
</div>
</body>
</html>"""


def send_vendor_approval_email(
    to_email: str,
    restaurant_name: str,
    contact_name: str
) -> bool:
    subject = f"Your partner account is live — {restaurant_name}"

    body = f"""
<p>Hi <strong>{contact_name}</strong>,</p>
<p><strong>{restaurant_name}</strong> has been approved and is now live on Dollor. Customers can start ordering right away.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Restaurant</span><span class="row-val">{restaurant_name}</span></div>
  <div class="row"><span class="row-lbl">Status</span><span class="row-val"><span class="green-tag">Live</span></span></div>
</div>

<ul class="perks">
  <li><span class="check">→</span>Log in to your dashboard to review your menu and hours</li>
  <li><span class="check">→</span>Download the Dollor Restaurant app for real-time order alerts</li>
  <li><span class="check">→</span>Set up your bank account for weekly payouts via Stripe</li>
</ul>

<a href="https://dollor.ai/vendor/login" class="cta">Open Vendor Dashboard →</a>
<p style="font-size:13px;color:#9ca3af;">Questions? Reply to this email or contact support@dollor.ai.</p>
"""
    html_body = _dollor_email("🎉", "Partner Account Approved", f"{restaurant_name} is now live on Dollor.", body)

    text_body = f"""Your partner account is live — {restaurant_name}

Hi {contact_name},

{restaurant_name} has been approved and is now live on Dollor.

Next steps:
1. Log in to your dashboard — https://dollor.ai/vendor/login
2. Download the Dollor Restaurant app for real-time order alerts
3. Set up your bank account for weekly payouts via Stripe

Questions? support@dollor.ai

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_vendor_registration_confirmation(
    to_email: str,
    restaurant_name: str,
    contact_name: str,
    vendor_id: str
) -> bool:
    subject = f"Application received — {restaurant_name}"

    body = f"""
<p>Hi <strong>{contact_name}</strong>,</p>
<p>We've received your application for <strong>{restaurant_name}</strong> to join the Dollor platform.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Application ID</span><span class="row-val" style="font-family:monospace;font-size:15px">{vendor_id}</span></div>
  <div class="row"><span class="row-lbl">Restaurant</span><span class="row-val">{restaurant_name}</span></div>
  <div class="row"><span class="row-lbl">Status</span><span class="row-val"><span class="orange-tag">Under Review</span></span></div>
</div>

<ul class="perks">
  <li><span class="check">1</span>Document review by our team — typically 1–2 business days</li>
  <li><span class="check">2</span>Menu setup and pricing configuration</li>
  <li><span class="check">3</span>Go live and start receiving orders</li>
</ul>

<p>Once approved, you'll receive a separate email with your dashboard login instructions.</p>
<p style="font-size:13px;color:#9ca3af;">Questions? Reply to this email or contact support@dollor.ai.</p>
"""
    html_body = _dollor_email("📋", "Application Received", "We'll review your application within 1–2 business days.", body)

    text_body = f"""Application received — {restaurant_name}

Hi {contact_name},

We've received your application for {restaurant_name}.

Application ID: {vendor_id}

What happens next:
1. Document review (1–2 business days)
2. Menu setup and configuration
3. Go live!

Once approved, you'll receive login instructions for your dashboard.

Questions? support@dollor.ai

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_driver_approval_email(
    to_email: str,
    driver_name: str,
    driver_code: str,
    activation_token: str = None
) -> bool:
    """
    Send approval notification email to a driver with Terms of Service acceptance.
    Driver must click activation link to accept terms and become active.
    """
    activation_url = f"{API_BASE_URL}/drivers/activate/{activation_token}" if activation_token else f"{WEB_BASE_URL}/driver/activate"

    subject = f"Action required: activate your Dollor driver account"

    body = f"""
<p>Hi <strong>{driver_name}</strong>,</p>
<p>Your application to drive with Dollor has been <strong style="color:#ff6b00">approved</strong>. One step left: activate your account to accept rides.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Driver Code</span><span class="row-val" style="font-family:monospace;font-size:18px;font-weight:900;color:#ff6b00">{driver_code}</span></div>
  <div class="row" style="border:none"><span class="row-lbl">Status</span><span class="row-val"><span class="orange-tag">Approved — Activation Pending</span></span></div>
</div>

<div class="alert">
  <strong>⚠️ Action Required</strong> — You must click Activate below to accept our Terms of Service and go live. Until then, you cannot accept ride requests.
</div>

<p style="font-weight:700;color:#0a0a0f;margin:24px 0 10px">What you're approved for:</p>
<ul class="perks">
  <li><span class="check">✅</span> <span><strong>Rideshare services</strong> — set your own fares, keep the negotiated rate, plus 100% of tips</span></li>
  <li><span class="check">✅</span> <span><strong>Flexible schedule</strong> — go online and offline whenever you choose</span></li>
  <li><span class="check">✅</span> <span><strong>Instant payouts</strong> — earnings deposited via Stripe Connect after each ride</span></li>
</ul>

<div class="box" style="margin-top:20px">
  <p style="font-weight:700;font-size:14px;margin:0 0 12px;color:#0a0a0f">Independent Contractor Agreement — Summary</p>
  <p style="font-size:13px;color:#6b7280;margin:0 0 10px">By clicking Activate, you acknowledge and agree to all of the following:</p>
  <ul style="margin:0;padding:0 0 0 18px;font-size:13px;color:#374151;line-height:1.9">
    <li><strong>Independent Contractor Status</strong> — you are not an employee of Dollor or Zietra Technologies Inc. You are responsible for your own taxes, insurance, and business expenses.</li>
    <li><strong>Matchmaking Platform</strong> — Dollor connects drivers and riders. We do not set mandatory prices or control how you perform services.</li>
    <li><strong>Vehicle &amp; Insurance</strong> — you must maintain valid vehicle registration and TNC/commercial auto insurance as required by California law.</li>
    <li><strong>Background Check Consent</strong> — you consent to periodic background and MVR checks as required by law and CPUC regulations.</li>
    <li><strong>Service Standards</strong> — maintain a 4.5+ star rating; follow all traffic laws; no discrimination of any kind.</li>
    <li><strong>Payment Terms</strong> — weekly automatic payouts via Stripe Connect. You keep 100% of tips. A flat platform fee applies per ride.</li>
    <li><strong>Deactivation Policy</strong> — your account may be deactivated for rating below 4.5 stars, safety violations, fraud, or Terms of Service violations.</li>
  </ul>
  <p style="font-size:12px;color:#9ca3af;margin:14px 0 0">
    Full legal documents: <a href="{WEB_BASE_URL}/terms" style="color:#ff6b00">Terms of Service</a> · <a href="{WEB_BASE_URL}/privacy" style="color:#ff6b00">Privacy Policy</a> · <a href="{WEB_BASE_URL}/zero-tolerance" style="color:#ff6b00">Zero Tolerance Policy</a>
  </p>
</div>

<a href="{activation_url}" class="cta">Activate My Account →</a>
<p style="font-size:13px;color:#9ca3af;text-align:center">By clicking above you accept the Driver Terms of Service and Independent Contractor Agreement.</p>

<p style="font-weight:700;color:#0a0a0f;margin:24px 0 10px">After activation, get started:</p>
<ul class="perks">
  <li><span class="check">1.</span> <span>Download the <strong>Dollor Driver app</strong> on iOS or Android</span></li>
  <li><span class="check">2.</span> <span>Log in with this email and complete your Stripe payout setup</span></li>
  <li><span class="check">3.</span> <span>Tap <strong>Go Online</strong> — riders in your area will start sending requests</span></li>
</ul>
"""
    html_body = _dollor_email("✅", f"You're Approved, {driver_name}", "Activate your account to start accepting rides.",
                              body, footer_note=f'Driver Code: {driver_code}')

    text_body = f"""Driver Approved — Dollor

Congratulations, {driver_name}!

Your application to drive with Dollor has been APPROVED.

Driver Code: {driver_code}
Status:      Approved — Activation Pending

ACTION REQUIRED: You must activate your account to go live.
Activate here: {activation_url}

By activating, you agree to the Independent Contractor Agreement:
1. Independent Contractor — you are NOT an employee of Dollor/Zietra Technologies.
2. Matchmaking Platform — we connect you with riders, we don't set mandatory prices.
3. Vehicle & Insurance — maintain valid CA registration and TNC insurance.
4. Background Check Consent — you consent to periodic Checkr checks.
5. Service Standards — maintain 4.5+ stars, follow traffic laws, no discrimination.
6. Payment Terms — Stripe Connect payouts, 100% of tips kept by you.
7. Deactivation Policy — violations may result in permanent deactivation.

Full legal docs:
Terms: {WEB_BASE_URL}/terms
Privacy: {WEB_BASE_URL}/privacy
Zero Tolerance: {WEB_BASE_URL}/zero-tolerance

AFTER ACTIVATION:
1. Download the Dollor Driver app (iOS / Android)
2. Log in and complete Stripe payout setup
3. Tap Go Online — start earning

Questions? support@dollor.ai

© 2026 Zietra Technologies Inc. · dollor.ai · CPUC Permit TNC0050982-N
"""

    return send_email(to_email, subject, html_body, text_body)


def send_driver_registration_confirmation(
    to_email: str,
    driver_name: str,
    driver_code: str
) -> bool:
    """
    Send registration confirmation email to a new driver.
    """
    subject = f"Application Received — Welcome to Dollor, {driver_name}"

    body = f"""
<p>Hi <strong>{driver_name}</strong>,</p>
<p>Your application to drive with Dollor is in. We've received everything and our team is reviewing it now.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Application ID</span><span class="row-val" style="font-family:monospace;font-size:15px;color:#ff6b00">{driver_code}</span></div>
  <div class="row"><span class="row-lbl">Status</span><span class="row-val"><span class="orange-tag">Under Review</span></span></div>
  <div class="row"><span class="row-lbl">Typical timeline</span><span class="row-val">1–3 business days</span></div>
</div>

<p style="font-weight:700;color:#0a0a0f;margin-top:22px">What happens next:</p>
<ul class="perks">
  <li><span class="check">1.</span> <span><strong>Document review</strong> — we verify your California license and vehicle details</span></li>
  <li><span class="check">2.</span> <span><strong>Background check</strong> — standard safety verification via Checkr</span></li>
  <li><span class="check">3.</span> <span><strong>Activation</strong> — you'll get an email to accept terms and go live</span></li>
  <li><span class="check">4.</span> <span><strong>Start earning</strong> — set your price, accept rides, keep the fare</span></li>
</ul>

<div class="alert">
  <strong>Save your Application ID: {driver_code}</strong><br>
  Reference it if you contact us. Questions? Reply to this email or write to support@dollor.ai.
</div>

<p style="font-size:13px;color:#9ca3af;text-align:center;margin-top:24px">
  With Dollor, you keep 100% of every fare. We charge riders a flat $1 — nothing more, never.
</p>
"""
    html_body = _dollor_email("🚗", "Application Received", "We'll be in touch within 1–3 business days.", body)

    text_body = f"""Application Received — Dollor

Hi {driver_name},

Your application to drive with Dollor is in.

Application ID: {driver_code}
Status: Under Review
Timeline: 1–3 business days

WHAT HAPPENS NEXT:
1. Document review — California license and vehicle check
2. Background check — via Checkr
3. Activation email — accept terms and go live
4. Start earning — set your price, keep the fare

Questions? Email support@dollor.ai with your Application ID.

With Dollor, you keep 100% of every fare. Riders pay a flat $1.

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_customer_welcome_email(
    to_email: str,
    customer_name: str,
    customer_code: str = None
) -> bool:
    """
    Send welcome email to a new customer after registration.
    """
    subject = f"Welcome to Dollor, {customer_name} 👋"

    code_line = f'<div class="row"><span class="row-lbl">Your rider code</span><span class="row-val" style="font-family:monospace;color:#ff6b00">{customer_code}</span></div>' if customer_code else ''
    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>You're in. Dollor is California's rideshare platform where riders pay a flat $1 — and drivers keep everything else. No surge pricing. No percentage cuts. Just fair.</p>

<div class="box">
  {code_line}
  <div class="row"><span class="row-lbl">Platform fee</span><span class="row-val">$1 flat, always</span></div>
  <div class="row"><span class="row-lbl">Surge pricing</span><span class="row-val">Never</span></div>
  <div class="row"><span class="row-lbl">Tips</span><span class="row-val">100% go to your driver</span></div>
</div>

<a href="https://dollor.ai/customer/rides" class="cta">Book Your First Ride →</a>

<ul class="perks">
  <li><span class="check">✓</span> <span><strong>Set your own route</strong> — pick up and drop off anywhere</span></li>
  <li><span class="check">✓</span> <span><strong>Choose your driver</strong> — review bids before you accept</span></li>
  <li><span class="check">✓</span> <span><strong>Track your ride live</strong> — real-time GPS in the app</span></li>
  <li><span class="check">✓</span> <span><strong>Pay $1 platform fee</strong> — driver keeps the rest</span></li>
</ul>

<p style="font-size:13px;color:#9ca3af;text-align:center;margin-top:20px">
  CPUC Licensed · Background Checked Drivers · Zero Tolerance Safety Policy
</p>
"""
    html_body = _dollor_email("📍", f"Welcome, {customer_name}.", "California rideshare, done right.", body)

    text_body = f"""Welcome to Dollor, {customer_name}!

You're in. Dollor is California's rideshare platform where riders pay a flat $1 — and drivers keep everything else.

Platform fee: $1 flat, always
Surge pricing: Never
Tips: 100% go to your driver
{"Rider code: " + customer_code if customer_code else ""}

Book your first ride: https://dollor.ai/customer/rides

WHAT MAKES DOLLOR DIFFERENT:
- Set your own route
- Choose your driver from bids
- Track your ride live
- Pay $1 platform fee — driver keeps the rest

CPUC Licensed · Background Checked Drivers · Zero Tolerance Safety Policy

© 2026 Zietra Technologies Inc. · support@dollor.ai · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_email_verification_code(
    to_email: str,
    customer_name: str,
    verification_code: str
) -> bool:
    """
    Send email verification code to customer.
    """
    subject = f"Your Dollor verification code: {verification_code}"

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Enter this code to verify your email address and complete your Dollor account setup.</p>
<div class="code-wrap">
  <div class="code">{verification_code}</div>
  <div class="code-hint">Expires in 10 minutes · Do not share</div>
</div>
<div class="alert">
  Didn't request this? You can safely ignore this email. Your account remains unchanged.
</div>
"""
    html_body = _dollor_email("🔒", "Verify Your Email", "One quick step to secure your account.", body)

    text_body = f"""Verify Your Email — Dollor

Hi {customer_name},

Your verification code: {verification_code}

Enter this in the app to complete your registration.
Expires in 10 minutes. Do not share this code.

Didn't request this? Ignore this email.

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


# ==================== ORDER LIFECYCLE EMAILS ====================

def send_order_confirmation_email(
    to_email: str,
    customer_name: str,
    order_number: str,
    restaurant_name: str,
    order_total: float,
    items_summary: str = ""
) -> bool:
    subject = f"Order confirmed — #{order_number} from {restaurant_name}"

    items_row = f'<div class="row"><span class="row-lbl">Items</span><span class="row-val">{items_summary}</span></div>' if items_summary else ""
    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your order from <strong>{restaurant_name}</strong> has been confirmed and is being prepared.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Order #</span><span class="row-val" style="font-family:monospace">{order_number}</span></div>
  <div class="row"><span class="row-lbl">Restaurant</span><span class="row-val">{restaurant_name}</span></div>
  {items_row}
  <div class="row"><span class="row-lbl">Total</span><span class="row-val">${order_total:.2f}</span></div>
  <div class="row"><span class="row-lbl">Status</span><span class="row-val"><span class="orange-tag">Being Prepared</span></span></div>
</div>

<p>We'll send you another update when a driver picks up your order. Track in the Dollor app.</p>
"""
    html_body = _dollor_email("🍽️", "Order Confirmed", f"#{order_number} is on its way soon.", body)

    text_body = f"""Order confirmed — #{order_number}

Hi {customer_name},

Your order from {restaurant_name} has been confirmed.

Order #: {order_number}
{f'Items: {items_summary}' if items_summary else ''}Total: ${order_total:.2f}

We'll notify you when a driver picks up your order.

— The Dollor Team
"""

    return send_email(to_email, subject, html_body, text_body)


def send_order_ready_email(
    to_email: str,
    customer_name: str,
    order_number: str,
    restaurant_name: str
) -> bool:
    subject = f"Your order is ready — #{order_number}"

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your order <strong>#{order_number}</strong> from <strong>{restaurant_name}</strong> is ready and waiting for a driver.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Order #</span><span class="row-val" style="font-family:monospace">{order_number}</span></div>
  <div class="row"><span class="row-lbl">Restaurant</span><span class="row-val">{restaurant_name}</span></div>
  <div class="row"><span class="row-lbl">Status</span><span class="row-val"><span class="green-tag">Ready for Pickup</span></span></div>
</div>

<p>A driver will be assigned shortly and your food will be on its way. Track in the Dollor app.</p>
"""
    html_body = _dollor_email("✅", "Order Ready!", "Your food is packed and waiting for a driver.", body)

    text_body = f"""Your order is ready — #{order_number}

Hi {customer_name},

Your order #{order_number} from {restaurant_name} is ready!
A driver will pick it up shortly.

Track your order in the Dollor app.

— The Dollor Team
"""

    return send_email(to_email, subject, html_body, text_body)


def send_order_delivered_with_receipt_email(
    to_email: str,
    customer_name: str,
    order_number: str,
    restaurant_name: str,
    order_items: list,
    subtotal: float,
    delivery_fee: float,
    service_fee: float,
    tax_amount: float,
    tip: float,
    order_total: float,
    driver_name: str,
    delivery_address: str,
    order_date: str,
    discount_amount: float = 0.0,
    promo_code: str = None
) -> bool:
    """
    Send thank you email with full receipt when order is delivered.
    """
    subject = f"Thank You! Your Order #{order_number} Has Been Delivered"

    items_rows = ""
    for item in order_items:
        item_name = item.get("name", "Item")
        item_qty = item.get("quantity", 1)
        item_price = item.get("price", 0) or item.get("unit_price", 0)
        item_total = item_qty * item_price
        items_rows += f'<div class="row"><span class="row-lbl">{item_name} ×{item_qty}</span><span class="row-val">${item_total:.2f}</span></div>'

    discount_row = ""
    if discount_amount and discount_amount > 0:
        discount_row = f'<div class="row"><span class="row-lbl">Discount ({promo_code or "Promo"})</span><span class="row-val" style="color:#15803d">−${discount_amount:.2f}</span></div>'

    tip_row = f'<div class="row"><span class="row-lbl">Tip</span><span class="row-val">${tip:.2f}</span></div>' if tip > 0 else ""

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your order from <strong>{restaurant_name}</strong> has been delivered. We hope you enjoy your meal!</p>

<div class="box">
  <div class="row"><span class="row-lbl">Order #</span><span class="row-val" style="font-family:monospace">{order_number}</span></div>
  <div class="row"><span class="row-lbl">Date</span><span class="row-val">{order_date}</span></div>
  <div class="row"><span class="row-lbl">Restaurant</span><span class="row-val">{restaurant_name}</span></div>
  <div class="row"><span class="row-lbl">Driver</span><span class="row-val">{driver_name}</span></div>
  <div class="row"><span class="row-lbl">Delivered to</span><span class="row-val">{delivery_address}</span></div>
</div>

<div class="box">
  {items_rows}
  <div class="divider"></div>
  <div class="row"><span class="row-lbl">Subtotal</span><span class="row-val">${subtotal:.2f}</span></div>
  <div class="row"><span class="row-lbl">Delivery fee</span><span class="row-val">${delivery_fee:.2f}</span></div>
  <div class="row"><span class="row-lbl">Service fee</span><span class="row-val">${service_fee:.2f}</span></div>
  <div class="row"><span class="row-lbl">Tax</span><span class="row-val">${tax_amount:.2f}</span></div>
  {discount_row}
  {tip_row}
  <div class="row"><span class="row-lbl" style="font-weight:700;color:#0a0a0f">Total</span><span class="row-val" style="font-weight:900;font-size:16px">${order_total:.2f}</span></div>
</div>

<div class="alert">Drivers keep 100% of tips on Dollor. Rate your experience in the app!</div>
"""

    html_body = _dollor_email(
        "🚗", "Order Delivered!", f"Your receipt for order #{order_number}.", body,
        footer_note="Safety concern? Email support@dollor.ai · CPUC: 1-800-894-9444"
    )

    items_text = "\n".join([
        f"  {item.get('name', 'Item')} ×{item.get('quantity', 1)} — ${(item.get('quantity', 1) * (item.get('price', 0) or item.get('unit_price', 0))):.2f}"
        for item in order_items
    ])

    text_body = f"""Delivered! Receipt for order #{order_number}

Hi {customer_name},

Your order from {restaurant_name} has been delivered.

ORDER RECEIPT
=============
Order #: {order_number}
Date: {order_date}
Restaurant: {restaurant_name}
Delivered to: {delivery_address}
Driver: {driver_name}

ITEMS:
{items_text}

Subtotal: ${subtotal:.2f}
Delivery fee: ${delivery_fee:.2f}
Service fee: ${service_fee:.2f}
Tax: ${tax_amount:.2f}
{"Discount (" + (promo_code or "") + "): -${:.2f}".format(discount_amount) if discount_amount and discount_amount > 0 else ""}
{"Tip: ${:.2f}".format(tip) if tip > 0 else ""}
TOTAL: ${order_total:.2f}

Drivers keep 100% of tips. Rate your experience in the app!

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_delivery_completed_driver_email(
    to_email: str,
    driver_name: str,
    order_number: str,
    restaurant_name: str,
    delivery_fee: float,
    tip: float,
    total_earnings: float = None
) -> bool:
    """
    Send earnings email to driver after food delivery completion.
    Drivers keep 100% — $0 platform fee for food delivery.
    """
    if total_earnings is None:
        total_earnings = delivery_fee + tip

    subject = f"Delivery complete — you earned ${total_earnings:.2f}"

    tip_row = f'<div class="row"><span class="row-lbl">Tip</span><span class="row-val">${tip:.2f}</span></div>' if tip > 0 else ""

    body = f"""
<p>Great work, <strong>{driver_name}</strong>!</p>
<p>You completed a delivery from <strong>{restaurant_name}</strong> (Order #{order_number}).</p>

<div class="stats">
  <div class="stat">
    <div class="stat-val">${total_earnings:.2f}</div>
    <div class="stat-lbl">Total Earned</div>
  </div>
  <div class="stat">
    <div class="stat-val">${delivery_fee:.2f}</div>
    <div class="stat-lbl">Delivery Fee</div>
  </div>
  <div class="stat">
    <div class="stat-val">${tip:.2f}</div>
    <div class="stat-lbl">Tip</div>
  </div>
</div>

<div class="box">
  <div class="row"><span class="row-lbl">Order #</span><span class="row-val" style="font-family:monospace">{order_number}</span></div>
  <div class="row"><span class="row-lbl">Restaurant</span><span class="row-val">{restaurant_name}</span></div>
  <div class="row"><span class="row-lbl">Delivery Fee</span><span class="row-val">${delivery_fee:.2f}</span></div>
  {tip_row}
  <div class="row"><span class="row-lbl">Platform Fee</span><span class="row-val" style="color:#15803d">$0.00</span></div>
  <div class="row"><span class="row-lbl" style="font-weight:700;color:#0a0a0f">Your Earnings</span><span class="row-val" style="font-weight:900;font-size:16px;color:#ff6b00">${total_earnings:.2f}</span></div>
</div>

<div class="alert">You keep 100% — Dollor charges $0 platform fee for food deliveries.</div>
"""
    html_body = _dollor_email("💰", "Delivery Complete!", f"Order #{order_number} · ${total_earnings:.2f} earned.", body)

    text_body = f"""Delivery complete — Order #{order_number}

Hi {driver_name},

You delivered from {restaurant_name}.

Delivery Fee: ${delivery_fee:.2f}
{"Tip: ${:.2f}".format(tip) if tip > 0 else ""}Platform Fee: $0.00
YOUR EARNINGS: ${total_earnings:.2f}

You keep 100% — Dollor charges $0 platform fee for food deliveries.

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_password_reset_email(
    to_email: str,
    customer_name: str,
    reset_code: str
) -> bool:
    """
    Send password reset code to customer.
    """
    subject = "Your Dollor password reset code"

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>We received a request to reset your Dollor password. Use the code below — it expires in 15 minutes.</p>
<div class="code-wrap">
  <div class="code">{reset_code}</div>
  <div class="code-hint">Expires in 15 minutes · Do not share</div>
</div>
<div class="alert">
  <strong>Didn't request this?</strong> Your password has not been changed. You can safely ignore this email. If you're concerned, contact support@dollor.ai.
</div>
"""
    html_body = _dollor_email("🔑", "Password Reset", "Enter this code in the app to reset your password.", body)

    text_body = f"""Password Reset — Dollor

Hi {customer_name},

Your password reset code: {reset_code}

Enter this in the app. Expires in 15 minutes.

Didn't request this? Ignore this email. Your password is unchanged.
Concerned? Contact support@dollor.ai

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_password_reset_link_email(
    to_email: str,
    recipient_name: str,
    reset_token: str
) -> bool:
    """
    Send password reset link to vendor/admin users (link-based flow).
    """
    reset_url = f"https://dollor.ai/reset-password?token={reset_token}"
    subject = "Reset your Dollor password"

    body = f"""
<p>Hi <strong>{recipient_name}</strong>,</p>
<p>We received a request to reset your Dollor password. Click the button below — the link expires in 1 hour.</p>
<a href="{reset_url}" class="cta">Reset My Password →</a>
<div class="alert">
  <strong>Didn't request this?</strong> Your password has not been changed. Ignore this email. If you're concerned, contact support@dollor.ai.
</div>
<p style="font-size:12px;color:#9ca3af;word-break:break-all">Or copy this link: {reset_url}</p>
"""
    html_body = _dollor_email("🔑", "Password Reset", "Set a new password for your Dollor account.", body)

    text_body = f"""Password Reset — Dollor

Hi {recipient_name},

Reset your password (expires in 1 hour):
{reset_url}

Didn't request this? Ignore this email.
Concerned? Contact support@dollor.ai

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_delivery_completed_vendor_email(
    to_email: str,
    restaurant_name: str,
    order_number: str,
    customer_name: str,
    order_items: list,
    subtotal: float,
    platform_fee: float,
    discount_amount: float,
    promo_code: str,
    vendor_payout: float,
    driver_name: str,
    delivered_at_str: str,
) -> bool:
    """quick-374: per-order payout receipt for the restaurant on delivery.

    The customer and driver already get emails on delivery; the restaurant
    only got a "new order" email at order-placement time. Restaurants need
    a definitive payout confirmation per order — what they earned, what
    was deducted, when it transferred. This closes that loop.
    """
    subject = f"Payout confirmed — Order #{order_number} · ${vendor_payout:.2f}"

    items_rows = ""
    for it in (order_items or []):
        qty = it.get("quantity", 1) if isinstance(it, dict) else 1
        name = it.get("name", "Item") if isinstance(it, dict) else str(it)
        line_total = it.get("total_price") or it.get("unit_price") or 0 if isinstance(it, dict) else 0
        items_rows += f'<div class="row"><span class="row-lbl">{qty}× {name}</span><span class="row-val">${float(line_total):.2f}</span></div>'

    discount_row = ""
    if discount_amount and discount_amount > 0:
        discount_row = f'<div class="row"><span class="row-lbl">Discount ({promo_code or "Promo"})</span><span class="row-val" style="color:#15803d">−${discount_amount:.2f}</span></div>'

    body = f"""
<p>Hi <strong>{restaurant_name}</strong>,</p>
<p>Order #{order_number} has been delivered. Your payout has been recorded and will transfer to your connected bank on the next Stripe payout cycle.</p>

<div class="stats">
  <div class="stat">
    <div class="stat-val">${vendor_payout:.2f}</div>
    <div class="stat-lbl">Your Payout</div>
  </div>
  <div class="stat">
    <div class="stat-val">${subtotal:.2f}</div>
    <div class="stat-lbl">Order Subtotal</div>
  </div>
  <div class="stat">
    <div class="stat-val">${platform_fee:.2f}</div>
    <div class="stat-lbl">Platform Fee</div>
  </div>
</div>

<div class="box">
  {items_rows}
  <div class="divider"></div>
  <div class="row"><span class="row-lbl">Subtotal</span><span class="row-val">${subtotal:.2f}</span></div>
  {discount_row}
  <div class="row"><span class="row-lbl">Platform fee</span><span class="row-val">−${platform_fee:.2f}</span></div>
  <div class="row"><span class="row-lbl" style="font-weight:700;color:#0a0a0f">Your Payout</span><span class="row-val" style="font-weight:900;font-size:16px;color:#ff6b00">${vendor_payout:.2f}</span></div>
</div>

<div class="box">
  <div class="row"><span class="row-lbl">Customer</span><span class="row-val">{customer_name}</span></div>
  <div class="row"><span class="row-lbl">Driver</span><span class="row-val">{driver_name}</span></div>
  <div class="row"><span class="row-lbl">Delivered</span><span class="row-val">{delivered_at_str}</span></div>
</div>

<p style="font-size:13px;color:#9ca3af;">View your full sales history any time in the Dollor Restaurant app.</p>
"""
    html_body = _dollor_email("💳", "Payout Confirmed", f"Order #{order_number} · ${vendor_payout:.2f} recorded.", body)

    text_body = (
        f"Payout confirmed — Order #{order_number}\n\n"
        f"Restaurant: {restaurant_name}\n\n"
        f"Subtotal:     ${subtotal:.2f}\n"
        + (f"Discount ({promo_code or 'Promo'}): -${discount_amount:.2f}\n" if discount_amount and discount_amount > 0 else "")
        + f"Platform fee: -${platform_fee:.2f}\n"
        f"YOUR PAYOUT:  ${vendor_payout:.2f}\n\n"
        f"Customer: {customer_name}\nDriver: {driver_name}\nDelivered: {delivered_at_str}\n\n"
        "© 2026 Zietra Technologies Inc. · dollor.ai"
    )

    return send_email(to_email=to_email, subject=subject, html_body=html_body, text_body=text_body)


# ==================== RIDESHARE LIFECYCLE EMAILS ====================

def send_ride_request_confirmation_email(
    to_email: str,
    customer_name: str,
    request_id: str,
    pickup_address: str,
    dropoff_address: str,
    estimated_price: float,
    estimated_distance_miles: float,
    estimated_duration_minutes: int
) -> bool:
    """
    Send confirmation email when customer creates a ride request.
    """
    subject = f"Ride request live — drivers are bidding"

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your ride request is live. Nearby drivers are reviewing it and will send fare proposals. Open the app to review bids and pick your driver.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Request ID</span><span class="row-val" style="font-family:monospace;font-size:13px">{request_id}</span></div>
  <div class="row"><span class="row-lbl">Status</span><span class="row-val"><span class="orange-tag">Waiting for Bids</span></span></div>
  <div class="row"><span class="row-lbl">📍 Pickup</span><span class="row-val">{pickup_address}</span></div>
  <div class="row"><span class="row-lbl">🏁 Dropoff</span><span class="row-val">{dropoff_address}</span></div>
</div>

<div class="stats">
  <div class="stat"><div class="stat-val">${estimated_price:.0f}</div><div class="stat-lbl">Est. Fare</div></div>
  <div class="stat"><div class="stat-val">{estimated_distance_miles:.1f}</div><div class="stat-lbl">Miles</div></div>
  <div class="stat"><div class="stat-val">{estimated_duration_minutes}</div><div class="stat-lbl">Minutes</div></div>
</div>

<a href="https://dollor.ai/customer/ride-bids" class="cta">View Bids in App →</a>

<p style="font-size:13px;color:#9ca3af;text-align:center">Drivers set their own prices. You choose the best bid.</p>
"""
    html_body = _dollor_email("📍", "Your Ride Is Live", "Drivers are submitting proposals now.", body,
                              footer_note=f'Request ID: {request_id}')

    text_body = f"""Ride Request Live — Dollor

Hi {customer_name},

Your ride request is live! Drivers are submitting proposals.

Request ID: {request_id}
Pickup:  {pickup_address}
Dropoff: {dropoff_address}

Est. Fare:  ${estimated_price:.2f}
Distance:   {estimated_distance_miles:.1f} miles
Duration:   {estimated_duration_minutes} min

View bids: https://dollor.ai/customer/ride-bids

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_ride_bid_received_email(
    to_email: str,
    customer_name: str,
    request_id: str,
    driver_name: str,
    driver_rating: float,
    proposed_price: float,
    eta_minutes: int,
    total_bids: int
) -> bool:
    """
    Send email when a driver submits a bid on customer's ride request.
    """
    subject = f"New bid — ${proposed_price:.2f} from {driver_name}"

    rating_value = driver_rating if driver_rating else 0.0
    bids_label = f"{total_bids} bid{'s' if total_bids != 1 else ''} waiting"

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>A driver submitted a price for your ride. You choose the bid that works best for you.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Driver</span><span class="row-val"><strong>{driver_name}</strong></span></div>
  <div class="row"><span class="row-lbl">Bid Price</span><span class="row-val" style="font-size:20px;font-weight:900;color:#ff6b00">${proposed_price:.2f}</span></div>
  <div class="row"><span class="row-lbl">Rating</span><span class="row-val">{rating_value:.1f} / 5</span></div>
  <div class="row"><span class="row-lbl">ETA</span><span class="row-val">{eta_minutes} min away</span></div>
  <div class="row" style="border:none"><span class="row-lbl">Total Bids</span><span class="row-val"><span class="orange-tag">{bids_label}</span></span></div>
</div>

<a href="https://dollor.ai/customer/ride-bids" class="cta">Compare All Bids →</a>

<p style="font-size:13px;color:#9ca3af;text-align:center">You're in control — accept the bid that's right for you.</p>
"""
    html_body = _dollor_email("🚗", f"New Bid from {driver_name}", f"${proposed_price:.2f} · {eta_minutes} min away", body,
                              footer_note=f'Request ID: {request_id}')

    text_body = f"""New Bid Received — Dollor

Hi {customer_name},

{driver_name} submitted a bid for your ride.

Price:  ${proposed_price:.2f}
Rating: {rating_value:.1f}/5
ETA:    {eta_minutes} min

You have {bids_label}. Compare them in the app:
https://dollor.ai/customer/ride-bids

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_ride_matched_email(
    to_email: str,
    customer_name: str,
    request_id: str,
    driver_name: str,
    driver_phone: str,
    driver_vehicle: str,
    final_price: float,
    eta_minutes: int,
    pickup_address: str
) -> bool:
    """
    Send email when customer accepts a bid and ride is matched.
    """
    subject = f"Driver confirmed — {driver_name} is on the way"

    vehicle_str = driver_vehicle if driver_vehicle else 'Vehicle info in app'

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your bid has been accepted. {driver_name} is heading to pick you up now.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Driver</span><span class="row-val"><strong>{driver_name}</strong></span></div>
  <div class="row"><span class="row-lbl">Vehicle</span><span class="row-val">{vehicle_str}</span></div>
  <div class="row"><span class="row-lbl">Driver Phone</span><span class="row-val">{driver_phone}</span></div>
  <div class="row"><span class="row-lbl">📍 Pickup</span><span class="row-val">{pickup_address}</span></div>
</div>

<div class="stats">
  <div class="stat"><div class="stat-val">${final_price:.2f}</div><div class="stat-lbl">Agreed Fare</div></div>
  <div class="stat" style="border:none"><div class="stat-val">{eta_minutes}</div><div class="stat-lbl">Min to Pickup</div></div>
</div>

<a href="https://dollor.ai/customer/rides" class="cta">Track Driver in App →</a>

<p style="font-size:13px;color:#9ca3af;text-align:center">Open the app to track your driver's location in real time.</p>
"""
    html_body = _dollor_email("✅", "Driver Confirmed", f"{driver_name} is {eta_minutes} min away.", body,
                              footer_note=f'Request ID: {request_id}')

    text_body = f"""Ride Confirmed — Dollor

Hi {customer_name},

{driver_name} is on the way to pick you up!

Driver:  {driver_name}
Vehicle: {vehicle_str}
Phone:   {driver_phone}
ETA:     {eta_minutes} min
Fare:    ${final_price:.2f}
Pickup:  {pickup_address}

Track live: https://dollor.ai/customer/rides

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_ride_started_email(
    to_email: str,
    customer_name: str,
    request_id: str,
    driver_name: str,
    pickup_address: str,
    dropoff_address: str,
    estimated_duration_minutes: int,
    final_price: float
) -> bool:
    """
    Send email when ride starts (customer picked up).
    """
    subject = f"You're on your way — ride in progress"

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your ride with <strong>{driver_name}</strong> has started. Sit back and enjoy.</p>

<div class="box">
  <div class="row"><span class="row-lbl">🟢 Picked up from</span><span class="row-val">{pickup_address}</span></div>
  <div class="row" style="border:none"><span class="row-lbl">🏁 Heading to</span><span class="row-val">{dropoff_address}</span></div>
</div>

<div class="stats">
  <div class="stat"><div class="stat-val">{estimated_duration_minutes}</div><div class="stat-lbl">Min to Arrive</div></div>
  <div class="stat" style="border:none"><div class="stat-val">${final_price:.2f}</div><div class="stat-lbl">Trip Fare</div></div>
</div>

<p style="font-size:13px;color:#9ca3af;text-align:center">A receipt will be emailed when you arrive.</p>
"""
    html_body = _dollor_email("🚗", "Ride In Progress", f"Enjoy the ride with {driver_name}.", body,
                              footer_note=f'Request ID: {request_id}')

    text_body = f"""Ride In Progress — Dollor

Hi {customer_name},

Your ride with {driver_name} has started!

From:  {pickup_address}
To:    {dropoff_address}

ETA:   {estimated_duration_minutes} min
Fare:  ${final_price:.2f}

A receipt will be sent when you arrive.

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_ride_completed_email(
    to_email: str,
    customer_name: str,
    request_id: str,
    driver_name: str,
    pickup_address: str,
    dropoff_address: str,
    final_price: float,
    platform_fee: float,
    distance_miles: float,
    duration_minutes: int
) -> bool:
    """
    Send email when ride is completed with receipt.
    """
    subject = f"Your receipt — ${final_price:.2f} with {driver_name}"

    driver_earnings = final_price - platform_fee

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>You've arrived. Here's your trip receipt.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Driver</span><span class="row-val">{driver_name}</span></div>
  <div class="row"><span class="row-lbl">📍 From</span><span class="row-val">{pickup_address}</span></div>
  <div class="row"><span class="row-lbl">🏁 To</span><span class="row-val">{dropoff_address}</span></div>
  <div class="row"><span class="row-lbl">Distance</span><span class="row-val">{distance_miles:.1f} miles</span></div>
  <div class="row"><span class="row-lbl">Duration</span><span class="row-val">{duration_minutes} min</span></div>
</div>

<div class="stats">
  <div class="stat"><div class="stat-val">${final_price:.2f}</div><div class="stat-lbl">Total Charged</div></div>
  <div class="stat"><div class="stat-val">${platform_fee:.2f}</div><div class="stat-lbl">Platform Fee</div></div>
  <div class="stat" style="border:none"><div class="stat-val">${driver_earnings:.2f}</div><div class="stat-lbl">{driver_name} Earned</div></div>
</div>

<p style="font-size:13px;color:#6b7280;margin:0 0 6px">Enjoyed your ride? Add a tip — 100% goes to {driver_name}.</p>
<a href="https://dollor.ai/customer/rides/{request_id}/tip" class="cta">Add a Tip →</a>

<div class="alert" style="margin-top:20px">
  <strong>Safety:</strong> Zero tolerance for drug and alcohol use. To report a concern: <a href="mailto:support@dollor.ai?subject=Safety Report" style="color:#ff6b00">support@dollor.ai</a><br>
  CPUC Consumer Complaints: 1-800-894-9444 · CIU_intake@cpuc.ca.gov
</div>
"""
    html_body = _dollor_email("🎉", "Ride Complete", f"Thanks for riding with {driver_name}.", body,
                              footer_note=f'Request ID: {request_id}')

    text_body = f"""Ride Complete — Dollor Receipt

Hi {customer_name},

Here's your receipt for your ride with {driver_name}.

Request ID: {request_id}
From:       {pickup_address}
To:         {dropoff_address}
Distance:   {distance_miles:.1f} miles
Duration:   {duration_minutes} min
Fare:       ${final_price:.2f}
Platform:   ${platform_fee:.2f}
{driver_name} earned: ${driver_earnings:.2f}

Add a tip (100% to {driver_name}):
https://dollor.ai/customer/rides/{request_id}/tip

Safety: report concerns to support@dollor.ai
CPUC Consumer Complaints: 1-800-894-9444

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


def send_ride_cancelled_email(
    to_email: str,
    customer_name: str,
    request_id: str,
    cancelled_by: str,
    reason: str,
    refund_amount: float = None
) -> bool:
    """
    Send email when ride is cancelled.
    """
    subject = f"Ride cancelled — {request_id}"

    refund_block = f"""
<div class="box" style="text-align:center;margin-top:20px">
  <p style="font-size:13px;color:#6b7280;margin:0 0 6px">Refund processing</p>
  <p style="font-size:32px;font-weight:900;color:#ff6b00;margin:0">${refund_amount:.2f}</p>
  <p style="font-size:13px;color:#6b7280;margin:6px 0 0">Credited within 5–10 business days</p>
</div>
""" if refund_amount else ""

    body = f"""
<p>Hi <strong>{customer_name}</strong>,</p>
<p>Your ride request has been cancelled.</p>

<div class="box">
  <div class="row"><span class="row-lbl">Cancelled by</span><span class="row-val">{cancelled_by}</span></div>
  <div class="row" style="border:none"><span class="row-lbl">Reason</span><span class="row-val">{reason}</span></div>
</div>

{refund_block}

<a href="https://dollor.ai/customer/rides/new" class="cta">Request a New Ride →</a>

<p style="font-size:13px;color:#9ca3af;text-align:center">Questions? <a href="mailto:support@dollor.ai" style="color:#ff6b00">support@dollor.ai</a></p>
"""
    html_body = _dollor_email("✖", "Ride Cancelled", "We're sorry this didn't work out.", body,
                              footer_note=f'Request ID: {request_id}')

    refund_line = f'\nRefund: ${refund_amount:.2f} will be processed within 5-10 business days.' if refund_amount else ''
    text_body = f"""Ride Cancelled — Dollor

Hi {customer_name},

Your ride request {request_id} has been cancelled.

Cancelled by: {cancelled_by}
Reason:       {reason}{refund_line}

Request a new ride: https://dollor.ai
Questions: support@dollor.ai

© 2026 Zietra Technologies Inc. · dollor.ai
"""

    return send_email(to_email, subject, html_body, text_body)


# ==================== Compliance Email Templates ====================


def get_driver_ytd_earnings(db, driver_id: int, year: int) -> float:
    """Sum all completed ride + order net earnings for current year.

    Matches what driver actually received:
    - Rides: driver_payout + tip_amount (payout already has platform_fee deducted)
    - Orders: delivery_fee + tip (driver keeps 100%, $0 platform fee for food)

    Used for 1099-NEC threshold ($600) and monthly/quarterly report YTD totals.
    Per IRS 1099-NEC rules: gross payments to independent contractor including tips.
    """
    from sqlalchemy import func, extract
    from models import RideRequest, RideRequestStatus, Order, OrderStatus

    # Rides: driver_payout (fare minus platform fee) + tips
    ride_payout = db.query(func.sum(RideRequest.driver_payout)).filter(
        RideRequest.matched_driver_id == driver_id,
        extract('year', RideRequest.completed_at) == year,
        RideRequest.status == RideRequestStatus.COMPLETED
    ).scalar() or 0

    ride_tips = db.query(func.sum(RideRequest.tip_amount)).filter(
        RideRequest.matched_driver_id == driver_id,
        extract('year', RideRequest.completed_at) == year,
        RideRequest.status == RideRequestStatus.COMPLETED
    ).scalar() or 0

    # Orders: delivery_fee + tips (driver keeps 100% for food delivery)
    order_fees = db.query(func.sum(Order.delivery_fee)).filter(
        Order.driver_id == driver_id,
        extract('year', Order.delivered_at) == year,
        Order.status == OrderStatus.DELIVERED
    ).scalar() or 0

    order_tips = db.query(func.sum(Order.tip)).filter(
        Order.driver_id == driver_id,
        extract('year', Order.delivered_at) == year,
        Order.status == OrderStatus.DELIVERED
    ).scalar() or 0

    return float(ride_payout) + float(ride_tips) + float(order_fees) + float(order_tips)


def send_prop22_earnings_statement_email(
    driver_email: str,
    driver_name: str,
    period_start: str,
    period_end: str,
    engaged_hours: float,
    engaged_miles: float,
    floor_amount: float,
    net_earnings: float,
    top_up_amount: float,
    qtd_hours: float,
    healthcare_eligible: bool,
) -> bool:
    """
    Send Prop 22 Earnings Statement email after each 14-day period closes.
    BPC Section 7454(b)(2) compliant.
    """
    subject = f"Dollor -- Prop 22 Earnings Statement (Period {period_start} - {period_end})"

    # Format engaged hours as Xh Ym
    hours_int = int(engaged_hours)
    minutes_int = int((engaged_hours - hours_int) * 60)
    engaged_time_str = f"{hours_int}h {minutes_int}m"

    qtd_hours_int = int(qtd_hours)
    qtd_minutes_int = int((qtd_hours - qtd_hours_int) * 60)
    qtd_time_str = f"{qtd_hours_int}h {qtd_minutes_int}m"

    healthcare_note = ""
    if healthcare_eligible:
        healthcare_note = """
        <div style="background:#ecfdf5;border-radius:8px;padding:15px;margin:15px 0;border:1px solid #86efac;">
            <strong style="color:#16a34a;">Healthcare Stipend Eligible</strong>
            <p style="margin:8px 0 0;color:#166534;font-size:14px;">
                Your average weekly engaged hours (15+ hrs/week) qualify you for
                the Prop 22 healthcare stipend. Details will be included in your
                quarterly reconciliation.
            </p>
        </div>
        """

    top_up_row = ""
    if top_up_amount > 0:
        top_up_row = f"""
        <tr>
            <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Prop 22 Top-Up</td>
            <td style="padding:10px 12px;border:1px solid #e2e8f0;color:#16a34a;font-weight:bold;">${top_up_amount:.2f}</td>
        </tr>
        """

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#4f46e5,#7c3aed);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">Prop 22 Earnings Statement</h1>
                <p style="color:#c7d2fe;margin:8px 0 0;">Period: {period_start} - {period_end}</p>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Hi {driver_name},</p>
                <p style="margin:0 0 20px;">Here is your Prop 22 earnings statement for the completed period.</p>

                <table style="width:100%;border-collapse:collapse;margin:0 0 20px;">
                    <tr>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Period</td>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;">{period_start} - {period_end}</td>
                    </tr>
                    <tr>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Engaged Time</td>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;">{engaged_time_str}</td>
                    </tr>
                    <tr>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Engaged Miles</td>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;">{engaged_miles:.1f} mi</td>
                    </tr>
                    <tr>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Minimum Floor Amount</td>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;">${floor_amount:.2f}</td>
                    </tr>
                    <tr>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Net Earnings (excl. tips)</td>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;">${net_earnings:.2f}</td>
                    </tr>
                    {top_up_row}
                    <tr>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">QTD Engaged Hours</td>
                        <td style="padding:10px 12px;border:1px solid #e2e8f0;">{qtd_time_str}</td>
                    </tr>
                </table>

                {healthcare_note}

                <p style="color:#64748b;font-size:13px;margin:20px 0 0;">
                    This statement is provided in compliance with California Business and Professions Code
                    Section 7454(b)(2). If you have questions, contact support@dollor.ai.
                </p>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; 2026 Zietra Technologies inc</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    Prop 22 Earnings Statement — Dollor

    Hi {driver_name},

    Period: {period_start} - {period_end}
    Engaged Time: {engaged_time_str}
    Engaged Miles: {engaged_miles:.1f} mi
    Minimum Floor Amount: ${floor_amount:.2f}
    Net Earnings (excl. tips): ${net_earnings:.2f}
    {"Prop 22 Top-Up: $" + f"{top_up_amount:.2f}" if top_up_amount > 0 else ""}
    QTD Engaged Hours: {qtd_time_str}
    {"Healthcare Stipend: ELIGIBLE" if healthcare_eligible else ""}

    This statement is provided in compliance with CA BPC Section 7454(b)(2).
    Questions? Contact support@dollor.ai

    (c) 2026 Zietra Technologies inc
    """

    return send_email(driver_email, subject, html_body, text_body, template_name="prop22_earnings_statement")


def send_monthly_earnings_summary_email(
    driver_email: str,
    driver_name: str,
    year: int,
    month: int,
    food_orders: int,
    food_delivery_fees: float,
    food_tips: float,
    ride_count: int,
    ride_fares: float,
    ride_tips: float,
    platform_fees_paid: float,
    prop22_topups: float,
    net_payout: float,
    ytd_total: float,
) -> bool:
    """
    Send monthly earnings summary email on the 1st of each month.
    Covers food delivery + rideshare earnings for the previous month.
    """
    import calendar
    month_name = calendar.month_name[month]

    subject = f"Dollor -- Your {month_name} {year} Earnings Summary"

    food_total = food_delivery_fees + food_tips
    ride_total = ride_fares + ride_tips

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#4f46e5,#7c3aed);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">{month_name} {year} Earnings</h1>
                <p style="color:#c7d2fe;margin:8px 0 0;">Your monthly earnings summary</p>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Hi {driver_name},</p>
                <p style="margin:0 0 20px;">Here is your earnings summary for {month_name} {year}.</p>

                <div style="background:#f8fafc;border-radius:8px;padding:20px;margin:0 0 20px;border:1px solid #e2e8f0;">
                    <h3 style="margin:0 0 12px;color:#1e293b;">Food Delivery</h3>
                    <table style="width:100%;border-collapse:collapse;">
                        <tr><td style="padding:6px 0;color:#64748b;">Orders completed</td><td style="padding:6px 0;text-align:right;font-weight:500;">{food_orders}</td></tr>
                        <tr><td style="padding:6px 0;color:#64748b;">Delivery fees</td><td style="padding:6px 0;text-align:right;font-weight:500;">${food_delivery_fees:.2f}</td></tr>
                        <tr><td style="padding:6px 0;color:#64748b;">Tips</td><td style="padding:6px 0;text-align:right;font-weight:500;">${food_tips:.2f}</td></tr>
                        <tr><td style="padding:6px 0;color:#64748b;">Platform fees</td><td style="padding:6px 0;text-align:right;font-weight:500;color:#16a34a;">$0.00</td></tr>
                        <tr style="border-top:1px solid #e2e8f0;"><td style="padding:8px 0;font-weight:bold;">Food Total</td><td style="padding:8px 0;text-align:right;font-weight:bold;">${food_total:.2f}</td></tr>
                    </table>
                </div>

                <div style="background:#f8fafc;border-radius:8px;padding:20px;margin:0 0 20px;border:1px solid #e2e8f0;">
                    <h3 style="margin:0 0 12px;color:#1e293b;">Rideshare</h3>
                    <table style="width:100%;border-collapse:collapse;">
                        <tr><td style="padding:6px 0;color:#64748b;">Rides completed</td><td style="padding:6px 0;text-align:right;font-weight:500;">{ride_count}</td></tr>
                        <tr><td style="padding:6px 0;color:#64748b;">Fares earned</td><td style="padding:6px 0;text-align:right;font-weight:500;">${ride_fares:.2f}</td></tr>
                        <tr><td style="padding:6px 0;color:#64748b;">Tips</td><td style="padding:6px 0;text-align:right;font-weight:500;">${ride_tips:.2f}</td></tr>
                        <tr><td style="padding:6px 0;color:#64748b;">Platform fees</td><td style="padding:6px 0;text-align:right;font-weight:500;color:#dc2626;">-${platform_fees_paid:.2f}</td></tr>
                        <tr style="border-top:1px solid #e2e8f0;"><td style="padding:8px 0;font-weight:bold;">Rideshare Total</td><td style="padding:8px 0;text-align:right;font-weight:bold;">${ride_total - platform_fees_paid:.2f}</td></tr>
                    </table>
                </div>

                {"<div style='background:#ecfdf5;border-radius:8px;padding:15px;margin:0 0 20px;border:1px solid #86efac;'><strong>Prop 22 Top-Ups:</strong> $" + f"{prop22_topups:.2f}</div>" if prop22_topups > 0 else ""}

                <div style="background:#4f46e5;border-radius:8px;padding:20px;margin:0 0 20px;text-align:center;">
                    <p style="color:#c7d2fe;margin:0;font-size:14px;">Net Payout</p>
                    <p style="color:#fff;margin:8px 0 0;font-size:28px;font-weight:bold;">${net_payout:.2f}</p>
                </div>

                <div style="background:#f8fafc;border-radius:8px;padding:15px;text-align:center;border:1px solid #e2e8f0;">
                    <p style="color:#64748b;margin:0;font-size:14px;">Year-to-Date Earnings ({year})</p>
                    <p style="color:#1e293b;margin:8px 0 0;font-size:22px;font-weight:bold;">${ytd_total:.2f}</p>
                </div>

                <p style="color:#64748b;font-size:13px;margin:20px 0 0;">
                    Questions about your earnings? Contact support@dollor.ai
                </p>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; 2026 Zietra Technologies inc</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    {month_name} {year} Earnings Summary — Dollor

    Hi {driver_name},

    FOOD DELIVERY
    Orders: {food_orders}
    Delivery Fees: ${food_delivery_fees:.2f}
    Tips: ${food_tips:.2f}
    Platform Fees: $0.00
    Food Total: ${food_total:.2f}

    RIDESHARE
    Rides: {ride_count}
    Fares: ${ride_fares:.2f}
    Tips: ${ride_tips:.2f}
    Platform Fees: -${platform_fees_paid:.2f}
    Rideshare Total: ${ride_total - platform_fees_paid:.2f}

    {"Prop 22 Top-Ups: $" + f"{prop22_topups:.2f}" if prop22_topups > 0 else ""}

    NET PAYOUT: ${net_payout:.2f}
    YTD EARNINGS ({year}): ${ytd_total:.2f}

    Questions? Contact support@dollor.ai

    (c) 2026 Zietra Technologies inc
    """

    return send_email(driver_email, subject, html_body, text_body, template_name="monthly_earnings_summary")


def send_quarterly_compliance_report_email(
    admin_email: str,
    year: int,
    quarter: int,
    total_drivers: int,
    prop22_summary: dict,
    driver_breakdown: list,
    threshold_drivers: list,
    approaching_drivers: list,
    revenue_summary: dict,
) -> bool:
    """
    Send quarterly compliance report to admin.
    Data-dense format for operational review.
    """
    quarter_label = f"Q{quarter} {year}"
    subject = f"Dollor -- {quarter_label} Compliance Report"

    # Build driver breakdown table rows
    driver_rows = ""
    for d in driver_breakdown[:50]:  # cap at 50 rows for email readability
        driver_rows += f"""
        <tr>
            <td style="padding:6px 8px;border:1px solid #e2e8f0;font-size:13px;">{d.get('name', 'N/A')}</td>
            <td style="padding:6px 8px;border:1px solid #e2e8f0;font-size:13px;text-align:right;">{d.get('engaged_hours', 0):.1f}h</td>
            <td style="padding:6px 8px;border:1px solid #e2e8f0;font-size:13px;text-align:right;">${d.get('floor', 0):.2f}</td>
            <td style="padding:6px 8px;border:1px solid #e2e8f0;font-size:13px;text-align:right;">${d.get('earned', 0):.2f}</td>
            <td style="padding:6px 8px;border:1px solid #e2e8f0;font-size:13px;text-align:right;">${d.get('top_up', 0):.2f}</td>
            <td style="padding:6px 8px;border:1px solid #e2e8f0;font-size:13px;">{d.get('status', 'N/A')}</td>
        </tr>
        """

    # 1099 threshold section
    threshold_section = ""
    if threshold_drivers:
        threshold_rows = "".join(
            f"<li>{d.get('name', 'N/A')} — YTD ${d.get('ytd', 0):.2f}</li>"
            for d in threshold_drivers
        )
        threshold_section = f"""
        <div style="background:#fef2f2;border-radius:8px;padding:15px;margin:0 0 15px;border:1px solid #fca5a5;">
            <h4 style="margin:0 0 8px;color:#dc2626;">1099-NEC Threshold Crossed ($600+)</h4>
            <ul style="margin:0;padding:0 0 0 20px;">{threshold_rows}</ul>
        </div>
        """

    approaching_section = ""
    if approaching_drivers:
        approaching_rows = "".join(
            f"<li>{d.get('name', 'N/A')} — YTD ${d.get('ytd', 0):.2f}</li>"
            for d in approaching_drivers
        )
        approaching_section = f"""
        <div style="background:#fef3c7;border-radius:8px;padding:15px;margin:0 0 15px;border:1px solid #fde68a;">
            <h4 style="margin:0 0 8px;color:#b45309;">Approaching 1099 Threshold ($500+)</h4>
            <ul style="margin:0;padding:0 0 0 20px;">{approaching_rows}</ul>
        </div>
        """

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:700px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#4f46e5,#7c3aed);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">{quarter_label} Compliance Report</h1>
                <p style="color:#c7d2fe;margin:8px 0 0;">Dollor Platform Compliance</p>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">

                <h3 style="margin:0 0 12px;color:#1e293b;">Overview</h3>
                <table style="width:100%;border-collapse:collapse;margin:0 0 20px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Active Drivers</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{total_drivers}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Total Engaged Hours</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{prop22_summary.get('total_hours', 0):.1f}h</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Total Floor Amount</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">${prop22_summary.get('total_floor', 0):.2f}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Total Top-Ups Paid</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">${prop22_summary.get('total_topups', 0):.2f}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Drivers Receiving Top-Ups</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{prop22_summary.get('drivers_with_topups', 0)}</td></tr>
                </table>

                {threshold_section}
                {approaching_section}

                <h3 style="margin:20px 0 12px;color:#1e293b;">Per-Driver Breakdown</h3>
                <table style="width:100%;border-collapse:collapse;margin:0 0 20px;font-size:13px;">
                    <tr style="background:#f1f5f9;">
                        <th style="padding:8px;border:1px solid #e2e8f0;text-align:left;">Driver</th>
                        <th style="padding:8px;border:1px solid #e2e8f0;text-align:right;">Hours</th>
                        <th style="padding:8px;border:1px solid #e2e8f0;text-align:right;">Floor</th>
                        <th style="padding:8px;border:1px solid #e2e8f0;text-align:right;">Earned</th>
                        <th style="padding:8px;border:1px solid #e2e8f0;text-align:right;">Top-Up</th>
                        <th style="padding:8px;border:1px solid #e2e8f0;text-align:left;">Status</th>
                    </tr>
                    {driver_rows}
                </table>

                <h3 style="margin:20px 0 12px;color:#1e293b;">Platform Revenue</h3>
                <table style="width:100%;border-collapse:collapse;margin:0 0 20px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Customer Service Fees</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">${revenue_summary.get('customer_fees', 0):.2f}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;background:#f8fafc;font-weight:bold;">Driver Platform Fees</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">${revenue_summary.get('driver_fees', 0):.2f}</td></tr>
                    <tr style="background:#f0fdf4;"><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;">Net Platform Revenue</td><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;color:#16a34a;">${revenue_summary.get('net_revenue', 0):.2f}</td></tr>
                </table>

                <p style="color:#64748b;font-size:13px;margin:20px 0 0;">
                    Report generated automatically. For questions contact support@dollor.ai.
                </p>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; 2026 Zietra Technologies inc</p>
            </div>
        </div>
    </body>
    </html>
    """

    # Text version - driver breakdown as simple list
    driver_text = "\n".join(
        f"  {d.get('name', 'N/A')}: {d.get('engaged_hours', 0):.1f}h, "
        f"floor=${d.get('floor', 0):.2f}, earned=${d.get('earned', 0):.2f}, "
        f"top-up=${d.get('top_up', 0):.2f}, {d.get('status', 'N/A')}"
        for d in driver_breakdown[:50]
    )

    threshold_text = "\n".join(
        f"  {d.get('name', 'N/A')} — YTD ${d.get('ytd', 0):.2f}"
        for d in threshold_drivers
    ) if threshold_drivers else "  None"

    approaching_text = "\n".join(
        f"  {d.get('name', 'N/A')} — YTD ${d.get('ytd', 0):.2f}"
        for d in approaching_drivers
    ) if approaching_drivers else "  None"

    text_body = f"""
    {quarter_label} Compliance Report — Dollor

    OVERVIEW
    Active Drivers: {total_drivers}
    Total Engaged Hours: {prop22_summary.get('total_hours', 0):.1f}h
    Total Floor Amount: ${prop22_summary.get('total_floor', 0):.2f}
    Total Top-Ups Paid: ${prop22_summary.get('total_topups', 0):.2f}
    Drivers Receiving Top-Ups: {prop22_summary.get('drivers_with_topups', 0)}

    1099-NEC THRESHOLD CROSSED ($600+):
{threshold_text}

    APPROACHING 1099 THRESHOLD ($500+):
{approaching_text}

    PER-DRIVER BREAKDOWN:
{driver_text}

    PLATFORM REVENUE:
    Customer Service Fees: ${revenue_summary.get('customer_fees', 0):.2f}
    Driver Platform Fees: ${revenue_summary.get('driver_fees', 0):.2f}
    Net Platform Revenue: ${revenue_summary.get('net_revenue', 0):.2f}

    (c) 2026 Zietra Technologies inc
    """

    return send_email(admin_email, subject, html_body, text_body, template_name="quarterly_compliance_report", skip_validation=True)


def send_1099_threshold_alert_email(
    driver_email: str,
    driver_name: str,
    ytd_earnings: float,
) -> bool:
    """
    Send 1099-NEC threshold alert when driver YTD earnings first cross $600.
    Sent exactly once per driver per calendar year (dedup via Communication table).
    """
    subject = "Dollor -- Important Tax Information"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#4f46e5,#7c3aed);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">Important Tax Information</h1>
                <p style="color:#c7d2fe;margin:8px 0 0;">Action may be required</p>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Hi {driver_name},</p>

                <div style="background:#fef3c7;border-radius:8px;padding:20px;margin:0 0 20px;border:1px solid #fde68a;">
                    <p style="margin:0 0 8px;font-weight:bold;color:#92400e;">Your year-to-date earnings on Dollor have exceeded $600.</p>
                    <p style="margin:0;color:#92400e;">Current YTD earnings: <strong>${ytd_earnings:.2f}</strong></p>
                </div>

                <p style="margin:0 0 12px;">Because your earnings have crossed the $600 threshold, you will receive a
                <strong>1099-NEC tax form</strong> for this calendar year.</p>

                <p style="margin:0 0 12px;">Please ensure your tax information is up to date in the Dollor app:</p>

                <ul style="margin:0 0 20px;padding:0 0 0 20px;color:#374151;">
                    <li style="margin:0 0 8px;">Verify your legal name and address</li>
                    <li style="margin:0 0 8px;">Confirm your Social Security Number or EIN</li>
                    <li style="margin:0 0 8px;">Consult a tax professional if you have questions</li>
                </ul>

                <p style="color:#64748b;font-size:13px;margin:20px 0 0;">
                    For tax-related questions, consult a qualified tax professional.
                    For account questions, contact support@dollor.ai.
                </p>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; 2026 Zietra Technologies inc</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    Important Tax Information — Dollor

    Hi {driver_name},

    Your year-to-date earnings on Dollor have exceeded $600.
    Current YTD earnings: ${ytd_earnings:.2f}

    Because your earnings have crossed the $600 threshold, you will receive a
    1099-NEC tax form for this calendar year.

    Please ensure your tax information is up to date:
    - Verify your legal name and address
    - Confirm your Social Security Number or EIN
    - Consult a tax professional if you have questions

    For account questions, contact support@dollor.ai.

    (c) 2026 Zietra Technologies inc
    """

    return send_email(driver_email, subject, html_body, text_body, template_name="1099_threshold_alert")


# ==================== Change Management Email Templates ====================


def send_approval_needed_email(
    to_email: str,
    lead_name: str,
    cr_id: str,
    cr_title: str,
    requested_by: str,
    priority: str,
) -> bool:
    """Notify department lead that a change request needs approval."""
    subject = f"[Action Required] Change Request {cr_id} Needs Your Approval"

    priority_colors = {
        "Critical": "#dc2626",
        "High": "#ea580c",
        "Medium": "#ca8a04",
        "Low": "#16a34a",
    }
    priority_color = priority_colors.get(priority, "#64748b")
    review_url = f"{WEB_BASE_URL}/admin/change-management/{cr_id}"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#7c3aed,#a855f7);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">Approval Needed</h1>
                <p style="color:#e9d5ff;margin:8px 0 0;">Dollor.AI Change Management</p>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Hi {lead_name},</p>
                <p style="margin:0 0 20px;">A new change request requires your review and approval.</p>
                <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">CR ID</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_id}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Title</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_title}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Requested By</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{requested_by}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Priority</td><td style="padding:8px 12px;border:1px solid #e2e8f0;"><span style="color:{priority_color};font-weight:bold;">{priority}</span></td></tr>
                </table>
                <div style="text-align:center;">
                    <a href="{review_url}" style="display:inline-block;background:#7c3aed;color:#fff;padding:12px 32px;border-radius:8px;text-decoration:none;font-weight:bold;">Review Request</a>
                </div>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; {datetime.utcnow().year} Dollor.AI Change Management</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    Approval Needed - Dollor.AI Change Management

    Hi {lead_name},

    A new change request requires your review and approval.

    CR ID: {cr_id}
    Title: {cr_title}
    Requested By: {requested_by}
    Priority: {priority}

    Review at: {review_url}

    (c) {datetime.utcnow().year} Dollor.AI
    """

    return send_email(to_email, subject, html_body, text_body, skip_validation=True)


def send_cr_rejected_email(
    to_email: str,
    cr_id: str,
    cr_title: str,
    rejected_by: str,
    reason: str,
) -> bool:
    """Notify requester their change request was rejected."""
    subject = f"Change Request {cr_id} Rejected"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#dc2626,#ef4444);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">Change Request Rejected</h1>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Your change request has been rejected.</p>
                <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">CR ID</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_id}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Title</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_title}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Rejected By</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{rejected_by}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Reason</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{reason}</td></tr>
                </table>
                <p style="color:#64748b;font-size:14px;">You may revise and resubmit the request after addressing the feedback.</p>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; {datetime.utcnow().year} Dollor.AI Change Management</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    Change Request {cr_id} Rejected

    Your change request has been rejected.

    CR ID: {cr_id}
    Title: {cr_title}
    Rejected By: {rejected_by}
    Reason: {reason}

    You may revise and resubmit the request after addressing the feedback.

    (c) {datetime.utcnow().year} Dollor.AI
    """

    return send_email(to_email, subject, html_body, text_body, skip_validation=True)


def send_ci_failed_email(
    to_email: str,
    cr_id: str,
    cr_title: str,
    ci_run_id: str,
    branch_name: str,
) -> bool:
    """Notify requester that CI failed for their change request."""
    subject = f"CI Failed for Change Request {cr_id}"
    gh_run_url = f"https://github.com/dollor-ai/eatfair-ios/actions/runs/{ci_run_id}"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#ea580c,#f97316);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">CI Pipeline Failed</h1>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">The CI pipeline for your change request has failed.</p>
                <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">CR ID</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_id}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Title</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_title}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Branch</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{branch_name}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Run ID</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{ci_run_id}</td></tr>
                </table>
                <div style="text-align:center;">
                    <a href="{gh_run_url}" style="display:inline-block;background:#ea580c;color:#fff;padding:12px 32px;border-radius:8px;text-decoration:none;font-weight:bold;">View CI Run</a>
                </div>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; {datetime.utcnow().year} Dollor.AI Change Management</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    CI Failed for Change Request {cr_id}

    The CI pipeline for your change request has failed.

    CR ID: {cr_id}
    Title: {cr_title}
    Branch: {branch_name}
    Run ID: {ci_run_id}

    View CI Run: {gh_run_url}

    (c) {datetime.utcnow().year} Dollor.AI
    """

    return send_email(to_email, subject, html_body, text_body, skip_validation=True)


def send_deploy_complete_email(
    to_email: str,
    cr_id: str,
    cr_title: str,
    environment: str,
    deploy_time: str,
) -> bool:
    """Notify on staging or production deployment completion."""
    env_label = environment.capitalize()
    subject = f"Change Request {cr_id} Deployed to {env_label}"

    env_colors = {"staging": "#2563eb", "production": "#16a34a"}
    env_color = env_colors.get(environment.lower(), "#64748b")

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,{env_color},#60a5fa);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">Deployed to {env_label}</h1>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Your change request has been successfully deployed.</p>
                <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">CR ID</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_id}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Title</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_title}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Environment</td><td style="padding:8px 12px;border:1px solid #e2e8f0;"><span style="color:{env_color};font-weight:bold;">{env_label}</span></td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Deploy Time</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{deploy_time}</td></tr>
                </table>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; {datetime.utcnow().year} Dollor.AI Change Management</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    Change Request {cr_id} Deployed to {env_label}

    Your change request has been successfully deployed.

    CR ID: {cr_id}
    Title: {cr_title}
    Environment: {env_label}
    Deploy Time: {deploy_time}

    (c) {datetime.utcnow().year} Dollor.AI
    """

    return send_email(to_email, subject, html_body, text_body, skip_validation=True)


def send_rollback_triggered_email(
    to_email: str,
    cr_id: str,
    cr_title: str,
    rollback_cr_id: str,
    triggered_by: str,
) -> bool:
    """Notify that a rollback CR was created for a change request."""
    subject = f"Rollback Triggered for Change Request {cr_id}"
    review_url = f"{WEB_BASE_URL}/admin/change-management/{rollback_cr_id}"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#dc2626,#b91c1c);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">Rollback Triggered</h1>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">A rollback has been initiated for a deployed change request.</p>
                <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Original CR</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_id}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Title</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_title}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Rollback CR</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{rollback_cr_id}</td></tr>
                    <tr><td style="padding:8px 12px;border:1px solid #e2e8f0;font-weight:bold;background:#f8fafc;">Triggered By</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{triggered_by}</td></tr>
                </table>
                <div style="text-align:center;">
                    <a href="{review_url}" style="display:inline-block;background:#dc2626;color:#fff;padding:12px 32px;border-radius:8px;text-decoration:none;font-weight:bold;">View Rollback CR</a>
                </div>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; {datetime.utcnow().year} Dollor.AI Change Management</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    Rollback Triggered for Change Request {cr_id}

    A rollback has been initiated for a deployed change request.

    Original CR: {cr_id}
    Title: {cr_title}
    Rollback CR: {rollback_cr_id}
    Triggered By: {triggered_by}

    View Rollback CR: {review_url}

    (c) {datetime.utcnow().year} Dollor.AI
    """

    return send_email(to_email, subject, html_body, text_body, skip_validation=True)


def send_approval_digest_email(
    to_email: str,
    lead_name: str,
    pending_crs: list,
) -> bool:
    """Batch digest when 3+ CRs need approval from same lead."""
    count = len(pending_crs)
    subject = f"[Action Required] {count} Change Requests Awaiting Your Approval"
    review_url = f"{WEB_BASE_URL}/admin/change-management"

    # Build table rows from pending_crs list of dicts
    rows_html = ""
    rows_text = ""
    for cr in pending_crs:
        cr_id = cr.get("cr_id", "")
        title = cr.get("title", "")
        priority = cr.get("priority", "Medium")
        requested_by = cr.get("requested_by", "")
        rows_html += f'<tr><td style="padding:8px 12px;border:1px solid #e2e8f0;">{cr_id}</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{title}</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{priority}</td><td style="padding:8px 12px;border:1px solid #e2e8f0;">{requested_by}</td></tr>'
        rows_text += f"  - {cr_id}: {title} ({priority}) by {requested_by}\n"

    html_body = f"""
    <html>
    <body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f8fafc;">
        <div style="max-width:600px;margin:0 auto;padding:20px;">
            <div style="background:linear-gradient(135deg,#7c3aed,#a855f7);padding:30px;border-radius:12px 12px 0 0;text-align:center;">
                <h1 style="color:#fff;margin:0;font-size:22px;">{count} Requests Awaiting Approval</h1>
                <p style="color:#e9d5ff;margin:8px 0 0;">Dollor.AI Change Management</p>
            </div>
            <div style="background:#fff;padding:30px;border-radius:0 0 12px 12px;border:1px solid #e2e8f0;border-top:none;">
                <p style="margin:0 0 16px;">Hi {lead_name},</p>
                <p style="margin:0 0 20px;">The following change requests are awaiting your review.</p>
                <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
                    <tr style="background:#f1f5f9;">
                        <th style="padding:8px 12px;border:1px solid #e2e8f0;text-align:left;">CR ID</th>
                        <th style="padding:8px 12px;border:1px solid #e2e8f0;text-align:left;">Title</th>
                        <th style="padding:8px 12px;border:1px solid #e2e8f0;text-align:left;">Priority</th>
                        <th style="padding:8px 12px;border:1px solid #e2e8f0;text-align:left;">Requested By</th>
                    </tr>
                    {rows_html}
                </table>
                <div style="text-align:center;">
                    <a href="{review_url}" style="display:inline-block;background:#7c3aed;color:#fff;padding:12px 32px;border-radius:8px;text-decoration:none;font-weight:bold;">Review All Requests</a>
                </div>
            </div>
            <div style="text-align:center;padding:16px;color:#94a3b8;font-size:12px;">
                <p>&copy; {datetime.utcnow().year} Dollor.AI Change Management</p>
            </div>
        </div>
    </body>
    </html>
    """

    text_body = f"""
    {count} Change Requests Awaiting Your Approval

    Hi {lead_name},

    The following change requests are awaiting your review:

{rows_text}
    Review all at: {review_url}

    (c) {datetime.utcnow().year} Dollor.AI
    """

    return send_email(to_email, subject, html_body, text_body, skip_validation=True)
