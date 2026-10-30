"""
Stripe Payment Integration for Dollor
Handles payment intents and webhooks (rideshare only — food-order creation,
tracking, vendor-payout sync, and invoice generation were removed along with
the rest of the food order flow; the webhook's food-order branch was removed
too, keeping only the ride-payment branch it shares with that infrastructure).
"""

from fastapi import APIRouter, Depends, HTTPException, Request, Header
from auth_utils import require_customer
from cache import check_rate_limit, RateLimiter
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional
from pydantic import BaseModel
import stripe
import json
import os
from dotenv import load_dotenv

from database import get_db
from models import StripePaymentLog, Customer, RideRequest

load_dotenv()

# Initialize Stripe
stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")  # SECURITY: No hardcoded fallback
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")  # SECURITY: No hardcoded fallback

router = APIRouter(prefix="/api", tags=["payments"])

payment_limiter = RateLimiter(max_requests=10, window_seconds=60)  # 10 per minute per user

# ===================== SIMPLE PAYMENT INTENT (for Apple Pay / Card) =====================

class SimplePaymentIntentRequest(BaseModel):
    """Request model for creating a simple PaymentIntent (Apple Pay, Google Pay, Card)"""
    amount: int  # Amount in cents
    currency: str = "usd"
    customer_email: Optional[str] = None
    order_id: Optional[str] = None

class SimplePaymentIntentResponse(BaseModel):
    """Response model matching iOS PaymentService expectations"""
    clientSecret: str
    publishableKey: str
    paymentIntent: str  # Same as clientSecret for compatibility

STRIPE_PUBLISHABLE_KEY = os.getenv("STRIPE_PUBLISHABLE_KEY", "")

@router.post("/payments/create-intent", response_model=SimplePaymentIntentResponse)
async def create_simple_payment_intent(http_request: Request, request: SimplePaymentIntentRequest, customer: Customer = Depends(require_customer)):
    """
    Create a simple Stripe PaymentIntent for Apple Pay, Google Pay, or Card payments.

    This endpoint is called by iOS/Android apps to get a client_secret for payment processing.
    The publishable key is returned so the app can configure Stripe SDK.

    Required for:
    - Apple Pay via StripeApplePay
    - Google Pay
    - Card payments via PaymentSheet
    """
    check_rate_limit(http_request, payment_limiter, "payment", identifier=str(customer.id))
    # Validate amount
    if request.amount < 50:  # Stripe minimum is $0.50
        raise HTTPException(status_code=400, detail="Amount must be at least 50 cents")
    if request.amount > 99999999:  # $999,999.99 max
        raise HTTPException(status_code=400, detail="Amount exceeds maximum")

    try:
        # Create PaymentIntent with automatic payment methods (supports Apple Pay, Google Pay, Cards)
        payment_intent = stripe.PaymentIntent.create(
            amount=request.amount,
            currency=request.currency.lower(),
            automatic_payment_methods={"enabled": True},
            metadata={
                "order_id": request.order_id or "",
                "source": "mobile_app",
                "customer_email": request.customer_email or ""
            },
            receipt_email=request.customer_email if request.customer_email else None,
            description=f"Order payment - {request.order_id}" if request.order_id else "Mobile app payment",
            idempotency_key=f"simple_pi_{request.order_id}_{int(datetime.now().timestamp())}" if request.order_id else None
        )

        return SimplePaymentIntentResponse(
            clientSecret=payment_intent.client_secret,
            publishableKey=STRIPE_PUBLISHABLE_KEY,
            paymentIntent=payment_intent.client_secret  # Alias for compatibility
        )

    except stripe.error.StripeError as e:
        import logging
        logging.error(f"Stripe payment intent error: {e}")
        raise HTTPException(status_code=500, detail="Payment processing error. Please try again or contact support.")

# ===================== STRIPE WEBHOOK =====================

@router.post("/webhooks/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(None),
    db: Session = Depends(get_db)
):
    """
    Step 2: Handle Stripe webhook events
    This is the SOURCE OF TRUTH for payment confirmation
    """
    
    payload = await request.body()
    
    # Verify webhook signature (CRITICAL for security)
    try:
        event = stripe.Webhook.construct_event(
            payload, stripe_signature, STRIPE_WEBHOOK_SECRET
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError as e:
        raise HTTPException(status_code=400, detail="Invalid signature")
    
    # Log the event
    event_type = event['type']
    event_data = event['data']['object']

    # IDEMPOTENCY: Check if we already processed this exact Stripe event.
    # Stripe retries webhooks on timeout/error, which would cause duplicate
    # confirmation emails and duplicate order status updates.
    existing_log = db.query(StripePaymentLog).filter(
        StripePaymentLog.stripe_event_id == event['id']
    ).first()
    if existing_log:
        return {"status": "already_processed", "event_type": event_type}

    stripe_log = StripePaymentLog(
        event_type=event_type,
        stripe_event_id=event['id'],
        payment_intent_id=event_data.get('id'),
        amount=event_data.get('amount', 0) / 100,
        currency=event_data.get('currency'),
        status=event_data.get('status'),
        raw_data=json.dumps(event['data']['object'], default=str)
    )
    db.add(stripe_log)
    # F7 SECURITY: Use try/except to handle race condition where two webhook
    # deliveries pass the SELECT check simultaneously. If IntegrityError on
    # unique stripe_event_id, the event was already processed.
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        if "unique" in str(e).lower() or "duplicate" in str(e).lower():
            return {"status": "already_processed", "event_type": event_type}
        raise

    # Handle payment_intent.succeeded event (rideshare only — food-order branch removed,
    # since food Orders can no longer be created)
    if event_type == 'payment_intent.succeeded':
        payment_intent = event_data
        ride = db.query(RideRequest).filter(
            RideRequest.stripe_payment_intent_id == payment_intent['id']
        ).first()
        if ride:
            ride.payment_status = "succeeded"
            ride.payment_completed_at = datetime.now()
            db.commit()
            print(f"Ride {ride.id} payment confirmed via webhook")

    elif event_type == 'payment_intent.payment_failed':
        payment_intent = event_data
        ride = db.query(RideRequest).filter(
            RideRequest.stripe_payment_intent_id == payment_intent['id']
        ).first()
        if ride:
            ride.payment_status = "failed"
            db.commit()
            print(f"Ride {ride.id} payment failed via webhook")

    return {"status": "success", "event_type": event_type}

