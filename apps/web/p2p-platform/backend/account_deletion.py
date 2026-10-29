"""In-app account deletion for customers and drivers (Apple 5.1.1(v), Google Play).

Rides, payments, receipts, payouts, CPUC/insurance/Prop 22 records must be kept, and
ride_requests.customer_id is NOT NULL, so the account row is ANONYMISED rather than deleted.
Personal data without a retention need is removed. Stripe cleanup runs after the database change
and never fails the deletion.

An anonymised account is recognised by its tombstone email (``deleted+<c|d><id>@deleted.invalid``),
so no schema change is needed. Existing JWTs are rejected through ``cache.revoke_account``.
"""
import logging
import secrets
from typing import Optional

import stripe
from sqlalchemy.orm import Session

from auth_utils import DELETED_EMAIL_SUFFIX
from cache import revoke_account
from models import (
    BidStatus, Cart, Customer, Driver, DriverPayout, DriverStatus, InAppNotification, Order,
    PasswordResetToken, RecurringRide, RideBid, RideRequest, RideRequestStatus, User, UserRole,
)
from models_extended import CustomerFavorite
from ride_dispatch import SHARED_DEMO_DRIVER_EMAILS

logger = logging.getLogger(__name__)

DELETED_NAME = "Deleted User"

# Shared App Store / Play reviewer and QA accounts. Reviewers always try the delete button; the
# endpoint answers 200 "Account deleted" for these WITHOUT changing anything, so the flow can be
# tested without destroying the shared accounts.
DEMO_ACCOUNT_EMAILS = frozenset({"demo.customer@dollor.ai"}) | SHARED_DEMO_DRIVER_EMAILS

CUSTOMER_ACTIVE_RIDE_STATUSES = (
    RideRequestStatus.OPEN, RideRequestStatus.BIDDING, RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS,
)
DRIVER_ACTIVE_RIDE_STATUSES = (RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS)
UNPAID_PAYOUT_STATUSES = ("pending", "processing")


class AccountDeletionBlocked(Exception):
    """The account cannot be deleted yet (active ride, unpaid payout). Maps to HTTP 409."""


def is_demo_account(email: Optional[str]) -> bool:
    return (email or "").strip().lower() in DEMO_ACCOUNT_EMAILS


def is_deleted_account(account) -> bool:
    return (account.email or "").endswith(DELETED_EMAIL_SUFFIX)


def tombstone_email(role: str, account_id: int) -> str:
    return f"deleted+{role[0]}{account_id}{DELETED_EMAIL_SUFFIX}"


def _unusable_password_hash() -> str:
    from main_new import get_password_hash  # local import: main_new imports this module's caller
    return get_password_hash(secrets.token_urlsafe(48))


# ----------------------------------------------------------------------------- blockers

def customer_blocker(db: Session, customer: Customer) -> Optional[str]:
    active = db.query(RideRequest.id).filter(
        RideRequest.customer_id == customer.id,
        RideRequest.status.in_(CUSTOMER_ACTIVE_RIDE_STATUSES),
    ).first()
    if active:
        return "You have a ride in progress or waiting for a driver. Please cancel or complete it before deleting your account."
    return None


def driver_blocker(db: Session, driver: Driver) -> Optional[str]:
    active = db.query(RideRequest.id).filter(
        RideRequest.matched_driver_id == driver.id,
        RideRequest.status.in_(DRIVER_ACTIVE_RIDE_STATUSES),
    ).first()
    if active:
        return "You have a ride in progress. Please finish or cancel it before deleting your account."
    unpaid = db.query(DriverPayout.id).filter(
        DriverPayout.driver_id == driver.id,
        DriverPayout.status.in_(UNPAID_PAYOUT_STATUSES),
    ).first()
    if unpaid:
        return "You have a payout that has not been paid yet. Please wait until it is paid before deleting your account."
    return None


# ----------------------------------------------------------------------------- Stripe (best effort)

def _stripe_configured() -> bool:
    return bool(getattr(stripe, "api_key", None))


def cleanup_customer_stripe(stripe_customer_id: Optional[str]) -> bool:
    """Detach saved cards and delete the Stripe customer. True when nothing is left to retry."""
    if not stripe_customer_id:
        return True
    if not _stripe_configured():
        logger.warning("account deletion: Stripe not configured, customer %s left in Stripe", stripe_customer_id)
        return False
    ok = True
    try:
        methods = stripe.PaymentMethod.list(customer=stripe_customer_id, type="card")
        for method in methods.data:
            try:
                stripe.PaymentMethod.detach(method.id)
            except Exception as exc:
                ok = False
                logger.warning("account deletion: detach %s failed: %s", method.id, exc)
    except Exception as exc:
        ok = False
        logger.warning("account deletion: listing cards of %s failed: %s", stripe_customer_id, exc)
    try:
        stripe.Customer.delete(stripe_customer_id)
    except Exception as exc:
        ok = False
        logger.warning("account deletion: Stripe customer %s delete failed: %s", stripe_customer_id, exc)
    return ok


def cleanup_driver_stripe(stripe_account_id: Optional[str]) -> bool:
    """Delete the Connect account only when its balance is zero. True when nothing is left to retry."""
    if not stripe_account_id:
        return True
    if not _stripe_configured():
        logger.warning("account deletion: Stripe not configured, Connect account %s left in Stripe", stripe_account_id)
        return False
    try:
        balance = stripe.Balance.retrieve(stripe_account=stripe_account_id)
        amounts = [b.amount for b in list(balance.available) + list(balance.pending)]
        if any(amount != 0 for amount in amounts):
            logger.warning("account deletion: Connect account %s has a balance, not deleted (finance must settle)", stripe_account_id)
            return False
        stripe.Account.delete(stripe_account_id)
        return True
    except Exception as exc:
        logger.warning("account deletion: Connect account %s cleanup failed: %s", stripe_account_id, exc)
        return False


# ----------------------------------------------------------------------------- anonymisation

def _anonymise_customer_rows(db: Session, customer: Customer, old_email: str) -> None:
    cid = customer.id
    # Retained for ride/payment history, but the personal name/phone copies go
    db.query(RideRequest).filter(RideRequest.customer_id == cid).update(
        {RideRequest.customer_name: DELETED_NAME, RideRequest.customer_phone: None}, synchronize_session=False)
    db.query(Order).filter(Order.customer_id == cid).update(
        {Order.customer_name: DELETED_NAME, Order.customer_email: tombstone_email("customer", cid),
         Order.customer_phone: None, Order.delivery_address: None, Order.delivery_instructions: None,
         Order.stripe_customer_id: None},
        synchronize_session=False)
    # No retention need
    for model in (InAppNotification, RecurringRide, CustomerFavorite):
        db.query(model).filter(model.customer_id == cid).delete(synchronize_session=False)
    for cart in db.query(Cart).filter(Cart.customer_id == cid).all():
        db.delete(cart)  # cascades to cart items
    db.query(PasswordResetToken).filter(PasswordResetToken.email == old_email).delete(synchronize_session=False)
    _anonymise_user_row(db, (User.email == old_email) & User.driver_id.is_(None), UserRole.ADMIN, tombstone_email("customer", cid))
    _anonymise_chat(db, "customer", cid)


def _anonymise_driver_rows(db: Session, driver: Driver, old_email: str) -> None:
    did = driver.id
    # A driver must not stay biddable or matchable
    db.query(RideBid).filter(
        RideBid.driver_id == did, RideBid.status.in_((BidStatus.PENDING, BidStatus.COUNTERED)),
    ).update({RideBid.status: BidStatus.WITHDRAWN}, synchronize_session=False)
    db.query(RideBid).filter(RideBid.driver_id == did).update(
        {RideBid.driver_name: DELETED_NAME, RideBid.driver_photo_url: None, RideBid.driver_vehicle: None},
        synchronize_session=False)
    db.query(Order).filter(Order.driver_id == did).update({Order.driver_name: DELETED_NAME}, synchronize_session=False)
    db.query(RecurringRide).filter(RecurringRide.preferred_driver_id == did).update(
        {RecurringRide.preferred_driver_id: None}, synchronize_session=False)
    _anonymise_user_row(db, User.driver_id == did, UserRole.ADMIN,
                        tombstone_email("driver", did), keep_driver_link=True)
    _anonymise_chat(db, "driver", did)


def _anonymise_user_row(db: Session, condition, protected_role, email: str, keep_driver_link: bool = False) -> None:
    """The login row in `users` that mirrors the account. Admin rows are never touched."""
    for user in db.query(User).filter(condition, User.role != protected_role).all():
        user.email = email
        user.full_name = DELETED_NAME
        user.password_hash = _unusable_password_hash()
        if not keep_driver_link:
            user.driver_id = None


def _anonymise_chat(db: Session, sender: str, account_id: int) -> None:
    from models import ChatConversation, ChatMessage, MessageSenderType
    if sender == "customer":
        db.query(ChatConversation).filter(ChatConversation.customer_id == account_id).update(
            {ChatConversation.customer_name: DELETED_NAME}, synchronize_session=False)
    else:
        db.query(ChatConversation).filter(ChatConversation.driver_id == account_id).update(
            {ChatConversation.driver_name: DELETED_NAME}, synchronize_session=False)
    sender_type = MessageSenderType.CUSTOMER if sender == "customer" else MessageSenderType.DRIVER
    # Message bodies are kept for safety/dispute review; only the display name goes
    db.query(ChatMessage).filter(ChatMessage.sender_type == sender_type, ChatMessage.sender_id == account_id).update(
        {ChatMessage.sender_name: DELETED_NAME}, synchronize_session=False)


def delete_customer(db: Session, customer: Customer) -> dict:
    """Anonymise `customer`. Raises AccountDeletionBlocked while a ride is active."""
    blocker = customer_blocker(db, customer)
    if blocker:
        raise AccountDeletionBlocked(blocker)

    old_email = customer.email
    stripe_customer_id = customer.stripe_customer_id
    stripe_clean = cleanup_customer_stripe(stripe_customer_id)

    _anonymise_customer_rows(db, customer, old_email)
    customer.first_name, customer.last_name = "Deleted", "User"
    customer.email = tombstone_email("customer", customer.id)
    customer.phone = None
    customer.password_hash = None
    customer.default_address = None
    customer.saved_addresses = None
    customer.saved_cards = None
    customer.dietary_preferences = None
    customer.favorite_cuisines = None
    customer.favorite_vendors = None
    customer.notification_preferences = None
    customer.device_id = None
    customer.push_token = None
    customer.platform = None
    customer.app_version = None
    customer.apple_id = None
    customer.google_id = None
    customer.email_verification_code = None
    customer.email_verification_expires = None
    customer.is_active = False
    if stripe_clean:
        customer.stripe_customer_id = None
    db.commit()
    revoke_account("customer", customer.id)
    return {"stripe_cleanup_pending": not stripe_clean}


def delete_driver(db: Session, driver: Driver) -> dict:
    """Anonymise `driver`. Raises AccountDeletionBlocked while a ride is active or a payout is unpaid."""
    blocker = driver_blocker(db, driver)
    if blocker:
        raise AccountDeletionBlocked(blocker)

    old_email = driver.email
    stripe_clean = cleanup_driver_stripe(driver.stripe_account_id)

    _anonymise_driver_rows(db, driver, old_email)
    driver.first_name, driver.last_name = "Deleted", "User"
    driver.email = tombstone_email("driver", driver.id)
    for field in (
        "phone", "password_hash", "date_of_birth", "license_number", "apple_id",
        "street", "city", "state", "zip_code",
        "vehicle_make", "vehicle_model", "vehicle_year", "vehicle_color", "license_plate",
        "drivers_license_url", "insurance_url", "vehicle_registration_url", "photo_url", "vehicle_photo_url",
        "drivers_license_expiry", "insurance_expiry",
        "current_latitude", "current_longitude",
        "push_token", "platform", "fcm_token", "device_type", "fcm_token_updated_at",
        "bank_name", "bank_last4", "bank_routing_number", "bank_account_holder",
        "activation_token", "accessibility_features",
    ):
        setattr(driver, field, None)
    driver.status = DriverStatus.INACTIVE
    driver.is_online = False
    driver.drivers_license = driver.insurance = driver.vehicle_registration = False
    driver.bank_verified = False
    if stripe_clean:
        driver.stripe_account_id = None
        driver.stripe_onboarded = False
    db.commit()
    revoke_account("driver", driver.id)
    return {"stripe_cleanup_pending": not stripe_clean}


def retry_pending_stripe_cleanup(db: Session, role: str, account) -> None:
    """A second delete call finishes Stripe cleanup that failed the first time."""
    if role == "customer" and account.stripe_customer_id:
        if cleanup_customer_stripe(account.stripe_customer_id):
            account.stripe_customer_id = None
            db.commit()
    elif role == "driver" and account.stripe_account_id:
        if cleanup_driver_stripe(account.stripe_account_id):
            account.stripe_account_id = None
            account.stripe_onboarded = False
            db.commit()
