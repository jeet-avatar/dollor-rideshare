from sqlalchemy import Column, Integer, String, Float, DateTime, Date, ForeignKey, Boolean, Text, Enum as SQLEnum, JSON, Computed, UniqueConstraint
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
import enum

Base = declarative_base()

class UserRole(enum.Enum):
    ADMIN = "admin"
    USER = "user"
    VENDOR = "vendor"
    DRIVER = "driver"

class InvoiceStatus(enum.Enum):
    DRAFT = "draft"
    SENT = "sent"
    PAID = "paid"
    OVERDUE = "overdue"
    CANCELLED = "cancelled"

class PaymentStatus(enum.Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    FAILED = "failed"

class VendorStatus(enum.Enum):
    PENDING = "pending"
    IN_REVIEW = "in_review"
    APPROVED = "approved"
    REJECTED = "rejected"
    SUSPENDED = "suspended"

class OnboardingPhase(enum.Enum):
    NOT_STARTED = "not_started"
    DOCUMENTS_PENDING = "documents_pending"
    UNDER_REVIEW = "under_review"
    COMPLIANCE_CHECK = "compliance_check"
    COMPLETED = "completed"

class RiskRating(enum.Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=False)
    role = Column(SQLEnum(UserRole), default=UserRole.USER)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=True)  # Link to vendor account
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)  # Link to driver account
    created_at = Column(DateTime, default=datetime.utcnow)

    invoices = relationship("Invoice", back_populates="user")
    vendor = relationship("Vendor", foreign_keys=[vendor_id])
    driver = relationship("Driver", foreign_keys=[driver_id])

class Client(Base):
    __tablename__ = "clients"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    email = Column(String(255), nullable=False)
    phone = Column(String(50))
    company = Column(String(255))
    address = Column(Text)
    city = Column(String(100))
    state = Column(String(100))
    zip_code = Column(String(20))
    country = Column(String(100))
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    invoices = relationship("Invoice", back_populates="client")

class Invoice(Base):
    __tablename__ = "invoices"
    
    id = Column(Integer, primary_key=True, index=True)
    invoice_number = Column(String(50), unique=True, nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    client_id = Column(Integer, ForeignKey("clients.id"), nullable=False)
    
    issue_date = Column(DateTime, nullable=False)
    due_date = Column(DateTime, nullable=False)
    
    subtotal = Column(Float, default=0.0)
    tax_rate = Column(Float, default=0.0)
    tax_amount = Column(Float, default=0.0)
    discount_amount = Column(Float, default=0.0)
    total_amount = Column(Float, nullable=False)
    
    status = Column(SQLEnum(InvoiceStatus), default=InvoiceStatus.DRAFT)
    notes = Column(Text)
    terms = Column(Text)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    user = relationship("User", back_populates="invoices")
    client = relationship("Client", back_populates="invoices")
    items = relationship("InvoiceItem", back_populates="invoice", cascade="all, delete-orphan")
    payments = relationship("Payment", back_populates="invoice", cascade="all, delete-orphan")

class InvoiceItem(Base):
    __tablename__ = "invoice_items"
    
    id = Column(Integer, primary_key=True, index=True)
    invoice_id = Column(Integer, ForeignKey("invoices.id"), nullable=False)
    
    description = Column(String(500), nullable=False)
    quantity = Column(Float, nullable=False)
    unit_price = Column(Float, nullable=False)
    amount = Column(Float, nullable=False)
    
    invoice = relationship("Invoice", back_populates="items")

class Payment(Base):
    __tablename__ = "payments"
    
    id = Column(Integer, primary_key=True, index=True)
    invoice_id = Column(Integer, ForeignKey("invoices.id"), nullable=False)
    
    amount = Column(Float, nullable=False)
    payment_date = Column(DateTime, nullable=False)
    payment_method = Column(String(50))
    reference_number = Column(String(100))
    status = Column(SQLEnum(PaymentStatus), default=PaymentStatus.COMPLETED)
    notes = Column(Text)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    
    invoice = relationship("Invoice", back_populates="payments")

class Vendor(Base):
    __tablename__ = "vendors"

    id = Column(Integer, primary_key=True, index=True)
    # vendor_id kept as nullable column for legacy compatibility (previously was Computed)
    vendor_id = Column(Integer, nullable=True, index=True)
    
    # Company Information
    company_name = Column(String(255), nullable=False)
    tax_id = Column(String(50))
    business_type = Column(String(100))
    industry = Column(String(100))
    website = Column(String(255))
    
    # Restaurant-Specific Fields
    restaurant_name = Column(String(255))
    cuisine_type = Column(String(100))
    operating_hours = Column(Text)
    seating_capacity = Column(Integer)
    delivery_available = Column(Boolean, default=True)
    pickup_available = Column(Boolean, default=True)
    average_prep_time = Column(Integer)  # in minutes
    # Note: image_url column added via migration but not in model to avoid query issues
    # Use stock images via get_stock_image_for_restaurant() in API response
    logo_url = Column(String(500))
    banner_url = Column(String(500))

    # Primary Contact
    contact_name = Column(String(255))
    contact_email = Column(String(255))
    contact_phone = Column(String(50))
    contact_title = Column(String(100))
    apple_id = Column(String(255), unique=True, nullable=True, index=True)  # Apple Sign In user ID
    
    # Address
    street = Column(Text)
    city = Column(String(100))
    state = Column(String(100))
    zip_code = Column(String(20))
    country = Column(String(100))
    latitude = Column(Float)
    longitude = Column(Float)
    
    # Status and Ratings
    onboarding_status = Column(SQLEnum(VendorStatus), default=VendorStatus.PENDING)
    onboarding_phase = Column(SQLEnum(OnboardingPhase), default=OnboardingPhase.NOT_STARTED)
    risk_rating = Column(SQLEnum(RiskRating), default=RiskRating.MEDIUM)
    performance_score = Column(Integer, default=0)
    
    # Contract Information
    contract_status = Column(String(50))
    contract_start_date = Column(DateTime)
    contract_end_date = Column(DateTime)
    
    # ZIP Integration
    zip_status = Column(String(50))
    zip_vendor_id = Column(String(100))
    
    # Documents
    w9_form = Column(Boolean, default=False)
    w9_form_url = Column(String(500))
    insurance = Column(Boolean, default=False)
    insurance_url = Column(String(500))
    financial_statements = Column(Boolean, default=False)
    financial_statements_url = Column(String(500))
    compliance_certs = Column(Boolean, default=False)
    compliance_certs_url = Column(String(500))
    security_policy = Column(Boolean, default=False)
    security_policy_url = Column(String(500))
    food_license = Column(Boolean, default=False)
    food_license_url = Column(String(500))
    health_permit = Column(Boolean, default=False)
    health_permit_url = Column(String(500))
    
    # Mobile App Fields
    app_registered = Column(Boolean, default=False)
    mobile_device_id = Column(String(255))
    push_token = Column(String(500))
    platform = Column(String(20))  # 'ios' or 'android'
    
    # Additional Information
    notes = Column(Text)
    onboarding_notes = Column(Text)
    rejection_reason = Column(Text)
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    approved_at = Column(DateTime)
    last_activity = Column(DateTime)

    # Document Verification (Third-Party Integration)
    verification_id = Column(String(255))  # Persona/Onfido inquiry ID
    verification_status = Column(String(50), default="not_started")  # pending, verified, rejected, needs_review
    documents_verified = Column(Boolean, default=False)
    documents_verified_at = Column(DateTime)
    verification_notes = Column(Text)
    verification_reviewer_id = Column(Integer)  # Admin who manually reviewed

    # Provider-Specific Verification IDs
    persona_inquiry_id = Column(String(255))  # Persona inquiry ID
    onfido_applicant_id = Column(String(255))  # Onfido applicant ID
    veriff_session_id = Column(String(255))  # Veriff session ID
    verification_provider = Column(String(50))  # persona, onfido, veriff

    # Publishing Status (for mobile apps - iOS, Android, Web)
    is_published = Column(Boolean, default=False)  # True when available on all platforms
    published_at = Column(DateTime)  # When vendor was published to platforms
    published_platforms = Column(Text)  # JSON array: ["ios", "android", "web"]

    # Online/Offline Status (for accepting orders)
    is_online = Column(Boolean, default=False)  # True when restaurant is accepting orders
    went_online_at = Column(DateTime)  # When vendor last went online
    went_offline_at = Column(DateTime)  # When vendor last went offline

    # Admin Approval Fields
    approved_by = Column(Integer)  # Admin user ID who approved the vendor

    # Menu Verification (admin must verify menu before go-live)
    menu_verified = Column(Boolean, default=False)  # True when admin verified menu
    menu_verified_at = Column(DateTime)  # When menu was verified
    menu_verified_by = Column(Integer)  # Admin user ID who verified menu

    # Payment/Stripe Integration
    stripe_account_id = Column(String(255))  # Stripe Connect account ID
    stripe_onboarding_complete = Column(Boolean, default=False)  # True when can receive payouts

    # KOT (Kitchen Order Ticket) / POS Integration
    # Supported types: 'none', 'square', 'clover', 'toast', 'star_cloud', 'epson_epos'
    kot_integration_type = Column(String(50), default="none")
    kot_enabled = Column(Boolean, default=False)
    kot_api_key = Column(String(500))  # Encrypted API key for POS system
    kot_api_secret = Column(String(500))  # For systems requiring secret (Toast)
    kot_location_id = Column(String(255))  # Square Location ID
    kot_merchant_id = Column(String(255))  # Clover Merchant ID
    kot_restaurant_guid = Column(String(255))  # Toast Restaurant GUID
    kot_printer_id = Column(String(255))  # For direct printer integrations
    kot_webhook_url = Column(String(500))  # Custom webhook for notifications
    kot_auto_print = Column(Boolean, default=True)  # Auto-print on order accept

    # Customer Ratings (aggregated from RestaurantRating table)
    average_rating = Column(Float, default=0.0)  # 0-5 stars
    total_ratings = Column(Integer, default=0)  # Number of ratings received

    # Relationships
    purchase_orders = relationship("VendorPurchaseOrder", back_populates="vendor", cascade="all, delete-orphan")
    menu_items = relationship("VendorMenuItem", back_populates="vendor", cascade="all, delete-orphan")
    ratings = relationship("RestaurantRating", back_populates="vendor", cascade="all, delete-orphan")


class RestaurantRating(Base):
    """Individual customer ratings for restaurants"""
    __tablename__ = "restaurant_ratings"

    id = Column(Integer, primary_key=True, index=True)

    # Foreign Keys
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=False, index=True)
    order_id = Column(Integer, ForeignKey("orders.id"), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)

    # Rating Details
    rating = Column(Integer, nullable=False)  # 1-5 stars
    review = Column(Text)  # Optional text review

    # Category Feedback (what was good)
    food_quality = Column(Boolean, default=False)
    portion_size = Column(Boolean, default=False)
    value_for_money = Column(Boolean, default=False)
    accuracy = Column(Boolean, default=False)  # Order accuracy

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    vendor = relationship("Vendor", back_populates="ratings")


class VendorPurchaseOrder(Base):
    __tablename__ = "vendor_purchase_orders"
    
    id = Column(Integer, primary_key=True, index=True)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=False)
    
    po_number = Column(String(50), unique=True, nullable=False, index=True)
    description = Column(Text)
    amount = Column(Float, nullable=False)
    status = Column(String(50))
    
    order_date = Column(DateTime, nullable=False)
    delivery_date = Column(DateTime)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    vendor = relationship("Vendor", back_populates="purchase_orders")

class VendorMenuItem(Base):
    __tablename__ = "vendor_menu_items"
    
    id = Column(Integer, primary_key=True, index=True)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=False)
    
    # Menu Item Details
    item_name = Column(String(255), nullable=False)
    description = Column(Text)
    category = Column(String(100))  # Appetizers, Main Course, Desserts, Beverages, etc.
    price = Column(Float, nullable=False)
    
    # Availability
    is_available = Column(Boolean, default=True)
    is_vegetarian = Column(Boolean, default=False)
    is_vegan = Column(Boolean, default=False)
    is_gluten_free = Column(Boolean, default=False)
    is_spicy = Column(Boolean, default=False)
    spice_level = Column(Integer, default=0)  # 0-5 scale
    
    # Additional Info
    prep_time = Column(Integer)  # in minutes
    calories = Column(Integer)
    image_url = Column(String(500))
    
    # Inventory
    in_stock = Column(Boolean, default=True)
    daily_limit = Column(Integer)
    items_sold_today = Column(Integer, default=0)

    # Customizations (stored as JSON for flexibility)
    # Format: [{"name": "Spice Level", "type": "single", "required": true, "options": [{"name": "Mild", "price": 0}, ...]}]
    customizations = Column(JSON, default=list)

    # Bestseller / Combo fields
    is_bestseller = Column(Boolean, default=False)
    is_combo = Column(Boolean, default=False)
    combo_items = Column(JSON, default=list)  # [{"item_id": int, "item_name": str, "original_price": float}]
    combo_savings = Column(Float, default=0.0)  # Dollar amount saved vs buying individually

    # Admin Review/Approval Fields
    # review_status: 'pending', 'approved', 'rejected', 'flagged'
    review_status = Column(String(50), default='pending')
    needs_review = Column(Boolean, default=True)  # New items need review by default
    admin_notes = Column(Text)  # Admin can leave notes for vendor
    reviewed_at = Column(DateTime)  # When admin reviewed
    reviewed_by = Column(Integer)  # Admin user ID who reviewed (optional FK)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    vendor = relationship("Vendor", back_populates="menu_items")


class OrderStatus(enum.Enum):
    # Payment flow
    PENDING_PAYMENT = "pending_payment"
    CONFIRMED = "confirmed"

    # Restaurant acceptance window (3 minutes)
    PENDING_RESTAURANT = "pending_restaurant"      # Waiting for restaurant to accept
    DECLINED_BY_RESTAURANT = "declined_by_restaurant"  # Restaurant declined
    RESTAURANT_TIMEOUT = "restaurant_timeout"      # No response in 3 minutes

    # Preparation and delivery flow
    PREPARING = "preparing"
    READY_FOR_PICKUP = "ready_for_pickup"

    # Delivery decision window (3 minutes) - Restaurant decides to self-deliver or send to drivers
    PENDING_DELIVERY_DECISION = "pending_delivery_decision"  # Waiting for restaurant delivery decision
    RESTAURANT_WILL_DELIVER = "restaurant_will_deliver"      # Restaurant chose to self-deliver
    DELIVERY_DECISION_TIMEOUT = "delivery_decision_timeout"  # No response - goes to drivers
    OUT_FOR_DELIVERY = "out_for_delivery"
    PENDING_DELIVERY_PROOF = "pending_delivery_proof"  # Driver must upload proof photo before payout
    DELIVERED = "delivered"
    CANCELLED = "cancelled"
    DELIVERY_FAILED = "delivery_failed"

class Order(Base):
    __tablename__ = "orders"
    
    id = Column(Integer, primary_key=True, index=True)
    order_number = Column(String(50), unique=True, nullable=False, index=True)
    
    # Customer & Vendor & Driver
    customer_id = Column(Integer)  # Reference to customer (can add Customer table later)
    customer_name = Column(String(255))
    customer_email = Column(String(255))
    customer_phone = Column(String(50))
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=False)
    driver_id = Column(Integer, nullable=True)  # Assigned driver
    driver_name = Column(String(255), nullable=True)
    
    # Order Items (JSON array)
    items = Column(Text)  # JSON: [{"menu_item_id": 1, "name": "...", "quantity": 2, "price": 15.99}]
    
    # Amounts
    subtotal = Column(Float, nullable=False)
    tax_rate = Column(Float, default=0.0)
    tax_amount = Column(Float, default=0.0)
    delivery_fee = Column(Float, default=0.0)
    tip = Column(Float, default=0.0)  # Customer tip for driver
    platform_fee = Column(Float, default=0.0)  # Your commission ($1 flat fee)

    # Prop 22 compliance columns — nullable; set at driver_accepted_at and delivery
    prop22_acceptance_lat = Column(Float, nullable=True)   # driver GPS lat at acceptance
    prop22_acceptance_lon = Column(Float, nullable=True)
    prop22_engaged_hours = Column(Float, nullable=True)    # (delivered_at - driver_accepted_at) hours
    prop22_engaged_miles = Column(Float, nullable=True)    # road miles: acceptance GPS -> delivery_lat/lon
    prop22_floor_amount = Column(Float, nullable=True)
    discount_amount = Column(Float, default=0.0)  # Promo discount applied
    promo_code = Column(String(50), nullable=True)  # Applied promo code
    promo_type = Column(String(50), nullable=True)  # percentage, flat, free_delivery, bogo
    total_amount = Column(Float, nullable=False)
    
    # Delivery Details
    delivery_address = Column(Text)  # JSON: {"street": "...", "city": "...", ...}
    delivery_instructions = Column(Text)
    delivery_latitude = Column(Float)
    delivery_longitude = Column(Float)
    driver_location = Column(Text)  # JSON: {"latitude": ..., "longitude": ..., "updated_at": ...}
    
    # Status
    status = Column(SQLEnum(OrderStatus), default=OrderStatus.PENDING_PAYMENT)
    payment_status = Column(String(50), default="pending")  # pending, processing, succeeded, failed, refunded
    
    # Stripe Integration
    stripe_payment_intent_id = Column(String(255))
    stripe_charge_id = Column(String(255))
    stripe_customer_id = Column(String(255))
    payment_method = Column(String(50))
    
    # Invoice Reference
    invoice_number = Column(String(50))
    invoice_generated = Column(Boolean, default=False)
    invoice_pdf_url = Column(String(500))
    
    # Coupa Integration (for accounting)
    coupa_synced = Column(Boolean, default=False)
    coupa_invoice_id = Column(String(100))
    coupa_status = Column(String(50))
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    confirmed_at = Column(DateTime)

    # Restaurant Acceptance Window (3-minute window)
    sent_to_restaurant_at = Column(DateTime)       # When order was sent to restaurant
    restaurant_accepted_at = Column(DateTime)      # When restaurant accepted
    restaurant_declined_at = Column(DateTime)      # When restaurant declined
    restaurant_timeout_at = Column(DateTime)       # When 3-min timeout occurred
    decline_reason = Column(Text)                  # Reason for declining

    # Delivery Decision Window (3-minute window) - Restaurant decides to self-deliver or send to drivers
    delivery_decision_sent_at = Column(DateTime)   # When delivery decision was requested
    restaurant_will_deliver = Column(Boolean)      # True = self-deliver, False = use driver
    delivery_decision_at = Column(DateTime)        # When restaurant made the decision
    delivery_decision_timeout_at = Column(DateTime)  # When 3-min timeout occurred

    preparing_at = Column(DateTime)
    picked_up_at = Column(DateTime)  # When driver picked up from restaurant
    delivered_at = Column(DateTime)
    dispatched_at = Column(DateTime)  # When driver was assigned
    cancelled_at = Column(DateTime)  # When order was cancelled

    # Delivery Proof Photo
    delivery_photo_url = Column(String(500))
    delivery_photo_uploaded_at = Column(DateTime)

    # Customer Not At Door flow
    leave_at_door = Column(Boolean, default=False)  # Customer sets at checkout
    driver_arrived_at_delivery = Column(DateTime, nullable=True)  # When driver taps "arrived"

    # Prep Time ETA for Early Driver Notification
    estimated_prep_minutes = Column(Integer, nullable=True)  # e.g., 15 minutes
    estimated_ready_at = Column(DateTime, nullable=True)  # calculated timestamp when food will be ready

    # Early Driver Acceptance (driver accepts while food is still preparing)
    driver_en_route = Column(Boolean, default=False)  # True when driver accepted but food not ready
    driver_accepted_at = Column(DateTime, nullable=True)  # When driver accepted the order
    driver_eta_to_restaurant = Column(Integer, nullable=True)  # Driver's ETA to restaurant in minutes

    # Auto-Dispatch System
    auto_dispatched = Column(Boolean, default=False)  # Was this auto-dispatched?
    broadcast_to_drivers = Column(Boolean, default=False)  # Was broadcast sent?
    broadcast_at = Column(DateTime)  # When broadcast was sent
    broadcast_radius_km = Column(Float)  # Radius used for broadcast

    # Relationships
    vendor = relationship("Vendor")

class StripePaymentLog(Base):
    __tablename__ = "stripe_payment_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("orders.id"))
    
    # Stripe Event Details
    event_type = Column(String(100))  # payment_intent.succeeded, charge.succeeded, etc.
    stripe_event_id = Column(String(255), unique=True)
    payment_intent_id = Column(String(255))
    charge_id = Column(String(255))
    
    # Payment Details
    amount = Column(Float)
    currency = Column(String(10), default="usd")
    status = Column(String(50))
    
    # Raw Data
    raw_data = Column(Text)  # Full JSON from Stripe
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    processed_at = Column(DateTime)

class VendorPayout(Base):
    __tablename__ = "vendor_payouts"
    
    id = Column(Integer, primary_key=True, index=True)
    payout_number = Column(String(50), unique=True, nullable=False)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=False)
    
    # Payout Period
    period_start = Column(DateTime, nullable=False)
    period_end = Column(DateTime, nullable=False)
    
    # Financial Details
    total_orders = Column(Integer, default=0)
    gross_revenue = Column(Float, default=0.0)  # Total order amounts
    platform_fee = Column(Float, default=0.0)  # Platform fee ($1 flat per order)
    stripe_fees = Column(Float, default=0.0)  # Stripe processing fees
    net_payout = Column(Float, default=0.0)  # What vendor receives
    
    # Status
    status = Column(String(50), default="pending")  # pending, processing, completed, failed
    
    # Coupa Integration
    coupa_invoice_id = Column(String(100))
    coupa_status = Column(String(50))
    coupa_synced_at = Column(DateTime)

    # Payment Details
    stripe_transfer_id = Column(String(255))
    paid_at = Column(DateTime)
    payment_method = Column(String(50))
    payment_reference = Column(String(255))

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    vendor = relationship("Vendor")


class CustomerStatus(enum.Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"


class Customer(Base):
    """Customer accounts for food ordering"""
    __tablename__ = "customers"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(String(50), unique=True, nullable=True, index=True)

    # Personal Information (matches database schema: first_name, last_name)
    first_name = Column(String(100))
    last_name = Column(String(100))
    email = Column(String(255), unique=True, nullable=False, index=True)
    phone = Column(String(50))
    password_hash = Column(String(255))  # For customer authentication

    # Addresses
    default_address = Column(JSON)
    saved_addresses = Column(JSON)  # Array of addresses

    # Preferences
    dietary_preferences = Column(JSON)  # ["vegetarian", "gluten_free"]
    favorite_cuisines = Column(JSON)
    favorite_vendors = Column(JSON)  # Array of vendor IDs [1, 5, 12]
    notification_preferences = Column(JSON)

    # Loyalty
    loyalty_points = Column(Integer, default=0)
    loyalty_tier = Column(String(50), default="bronze")  # bronze, silver, gold, platinum

    # Stats
    total_orders = Column(Integer, default=0)
    total_spent = Column(Float, default=0.0)
    average_order_value = Column(Float, default=0.0)

    # Engagement
    first_order_at = Column(DateTime)
    last_order_at = Column(DateTime)
    days_since_last_order = Column(Integer)

    # Mobile App
    device_id = Column(String(255))
    push_token = Column(String(500))
    platform = Column(String(20))  # ios, android
    app_version = Column(String(20))

    # Stripe
    stripe_customer_id = Column(String(255))
    saved_cards = Column(JSON)  # Array of payment cards [{id, brand, last4, exp_month, exp_year, is_default}]

    # OAuth identifiers for social login
    apple_id = Column(String(255), unique=True, nullable=True, index=True)  # Apple Sign In user ID
    google_id = Column(String(255), unique=True, nullable=True, index=True)  # Google Sign In user ID

    # Rating (from drivers)
    rating = Column(Float, default=5.0)
    total_rides = Column(Integer, default=0)

    # Status
    is_active = Column(Boolean, default=True)
    is_verified = Column(Boolean, default=False)
    # Unpaid balance flag (set when Stripe capture retries exhausted)
    has_unpaid_balance = Column(Boolean, default=False)

    # Email Verification
    email_verified = Column(Boolean, default=False)
    email_verification_code = Column(String(10))  # 6-digit code
    email_verification_expires = Column(DateTime)  # Code expiry time
    email_verified_at = Column(DateTime)  # When email was verified

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class Cart(Base):
    """Shopping cart for customers"""
    __tablename__ = "carts"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)

    # Promo code
    promo_code = Column(String(50), nullable=True)
    promo_discount = Column(Float, default=0.0)
    promo_type = Column(String(50), nullable=True)  # percentage, flat_amount, free_delivery

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    items = relationship("CartItem", back_populates="cart", cascade="all, delete-orphan")


class CartItem(Base):
    """Individual items in a shopping cart"""
    __tablename__ = "cart_items"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    cart_id = Column(Integer, ForeignKey("carts.id"), nullable=False, index=True)
    menu_item_id = Column(Integer, ForeignKey("vendor_menu_items.id"), nullable=False)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=False)

    # Item Details (denormalized for performance)
    item_name = Column(String(255), nullable=False)
    item_description = Column(Text)
    item_price = Column(Float, nullable=False)  # Price at time of adding to cart
    quantity = Column(Integer, default=1)

    # Restaurant info (denormalized)
    vendor_name = Column(String(255), nullable=False)

    # Customizations
    special_instructions = Column(Text)
    customizations = Column(JSON, default=dict)  # Selected customization options

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    cart = relationship("Cart", back_populates="items")


class DriverStatus(enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"
    ONLINE = "online"  # Driver is online and available for deliveries


class Driver(Base):
    __tablename__ = "drivers"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(String(50), unique=True, nullable=False, index=True)

    # Personal Information
    first_name = Column(String(100), nullable=False)
    last_name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, nullable=False)
    phone = Column(String(50))
    password_hash = Column(String(255))  # For driver app authentication
    date_of_birth = Column(String(20))  # YYYY-MM-DD format
    license_number = Column(String(50))  # Driver's license number
    apple_id = Column(String(255), unique=True, nullable=True, index=True)  # Apple Sign In user ID

    # Address (NOTE: Currently unused - reserved for future address-based features)
    street = Column(Text)
    city = Column(String(100))
    state = Column(String(100))
    zip_code = Column(String(20))

    # Vehicle Information
    vehicle_type = Column(String(50))  # car, motorcycle, bicycle
    vehicle_make = Column(String(100))
    vehicle_model = Column(String(100))
    vehicle_year = Column(Integer)
    vehicle_color = Column(String(50))
    license_plate = Column(String(20))

    # Documents
    drivers_license = Column(Boolean, default=False)
    drivers_license_url = Column(String(500))
    drivers_license_expiry = Column(DateTime)
    insurance = Column(Boolean, default=False)
    insurance_url = Column(String(500))
    insurance_expiry = Column(DateTime)
    vehicle_registration = Column(Boolean, default=False)
    vehicle_registration_url = Column(String(500))
    background_check = Column(Boolean, default=False)
    background_check_date = Column(DateTime)

    # Status and Ratings
    status = Column(SQLEnum(DriverStatus), default=DriverStatus.PENDING)
    rating = Column(Float, default=5.0)
    total_deliveries = Column(Integer, default=0)
    ride_accept_count = Column(Integer, default=0)  # Rides accepted (matched)
    ride_cancel_count = Column(Integer, default=0)   # Rides cancelled after matching

    # Real-time tracking
    current_latitude = Column(Float)
    current_longitude = Column(Float)
    is_online = Column(Boolean, default=False, index=True)
    location_updated_at = Column(DateTime)   # Primary field for GPS updates
    went_online_at = Column(DateTime)  # When driver came online
    went_offline_at = Column(DateTime)  # When driver went offline
    insurance_session_id = Column(String(36), nullable=True)  # Current insurance session UUID

    # Mobile App & Push Notifications
    # push_token: Generic push token for basic notifications
    # fcm_token: Firebase Cloud Messaging token specifically for order dispatch
    push_token = Column(String(500))   # Generic push token (used by register_push_token)
    platform = Column(String(20))       # 'ios' or 'android' (set during push registration)
    fcm_token = Column(String(500))     # Firebase Cloud Messaging token (used for order dispatch)
    device_type = Column(String(20))    # ios, android, web (set during FCM registration)
    fcm_token_updated_at = Column(DateTime)
    photo_url = Column(String(500))  # Driver photo
    vehicle_photo_url = Column(String(500))  # Vehicle photo for customer tracking

    # Stripe Connect (for payouts)
    stripe_account_id = Column(String(255))
    stripe_onboarded = Column(Boolean, default=False)

    # Bank Account (stored in DB, approved via admin portal)
    bank_name = Column(String(255))
    bank_last4 = Column(String(4))
    bank_routing_number = Column(String(20))
    bank_account_holder = Column(String(255))
    bank_verified = Column(Boolean, default=False)
    bank_verified_at = Column(DateTime)
    bank_verified_by = Column(Integer)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    # NOTE: approved_at should be set when driver status changes to APPROVED - currently unused
    approved_at = Column(DateTime)

    # Activation & Terms Acceptance (Legal Compliance)
    activation_token = Column(String(64), unique=True, index=True)  # Token sent via email for activation
    terms_accepted_at = Column(DateTime)  # When driver accepted Independent Contractor Agreement

    # Document Verification (Third-Party Integration - Persona/Onfido)
    verification_id = Column(String(255))  # Persona/Onfido inquiry ID
    verification_status = Column(String(50), default="not_started")  # pending, verified, rejected, needs_review
    documents_verified = Column(Boolean, default=False)
    documents_verified_at = Column(DateTime)
    verification_notes = Column(Text)
    verification_reviewer_id = Column(Integer)  # Admin who manually reviewed

    # Provider-Specific Verification IDs
    persona_inquiry_id = Column(String(255))  # Persona inquiry ID
    onfido_applicant_id = Column(String(255))  # Onfido applicant ID
    veriff_session_id = Column(String(255))  # Veriff session ID
    verification_provider = Column(String(50))  # persona, onfido, veriff

    # TNC-12: Driver accessibility capability
    accessibility_capable = Column(Boolean, default=False)
    accessibility_features = Column(Text)  # JSON: {"wheelchair": false, "service_animal": false, "mobility_storage": false}

    # Relationships
    payouts = relationship("DriverPayout", back_populates="driver")


class DriverPayout(Base):
    __tablename__ = "driver_payouts"

    id = Column(Integer, primary_key=True, index=True)
    payout_number = Column(String(50), unique=True, nullable=False)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False)
    order_id = Column(Integer, ForeignKey("orders.id"), nullable=True)

    # Payout Period
    period_start = Column(DateTime, nullable=False)
    period_end = Column(DateTime, nullable=False)

    # Financial Details
    total_deliveries = Column(Integer, default=0)
    delivery_fee = Column(Float, default=0.0)  # Base delivery fee
    tip = Column(Float, default=0.0)  # Customer tip
    bonus = Column(Float, default=0.0)  # Peak hour bonuses, etc.
    deductions = Column(Float, default=0.0)  # Any deductions
    net_payout = Column(Float, default=0.0)  # What driver receives

    # Status
    status = Column(String(50), default="pending")  # pending, processing, completed, failed

    # Payment Details
    paid_at = Column(DateTime)
    payment_method = Column(String(50))
    payment_reference = Column(String(255))
    stripe_transfer_id = Column(String(255))

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    driver = relationship("Driver", back_populates="payouts")


class DriverOnlineSession(Base):
    """One continuous online stretch for a driver; ended_at is NULL while the session is open."""
    __tablename__ = "driver_online_sessions"

    id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False, index=True)
    started_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)


class JournalEntry(Base):
    """Double-entry accounting journal entries for all transactions"""
    __tablename__ = "journal_entries"

    id = Column(Integer, primary_key=True, index=True)
    entry_number = Column(String(50), unique=True, nullable=False, index=True)

    # Reference
    order_id = Column(Integer, ForeignKey("orders.id"), nullable=True)
    vendor_payout_id = Column(Integer, ForeignKey("vendor_payouts.id"), nullable=True)
    driver_payout_id = Column(Integer, ForeignKey("driver_payouts.id"), nullable=True)

    # Entry Details
    entry_type = Column(String(50))  # ORDER_COMPLETED, VENDOR_PAYOUT, DRIVER_PAYOUT, REFUND
    description = Column(Text)

    # Status
    status = Column(String(50), default="posted")  # posted, pending, void

    # AI Employee who created this (for audit trail)
    created_by_ai = Column(String(50))  # AI_EMP_004 (LedgerBot Delta)
    created_by_ai_name = Column(String(100))

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    posted_at = Column(DateTime)

    # Relationships
    lines = relationship("JournalEntryLine", back_populates="journal_entry")


class JournalEntryLine(Base):
    """Individual lines for complex journal entries"""
    __tablename__ = "journal_entry_lines"

    id = Column(Integer, primary_key=True, index=True)
    journal_entry_id = Column(Integer, ForeignKey("journal_entries.id"), nullable=False)

    account_code = Column(String(50))
    account_name = Column(String(100))
    debit = Column(Float, default=0.0)
    credit = Column(Float, default=0.0)
    description = Column(String(255))

    # Relationships
    journal_entry = relationship("JournalEntry", back_populates="lines")


# =========================================================================
# AI EMPLOYEE MODELS - Automated Delivery Operations
# =========================================================================

class AIEmployeeStatus(enum.Enum):
    ACTIVE = "active"
    IDLE = "idle"
    PROCESSING = "processing"
    ERROR = "error"
    OFFLINE = "offline"


class AIEmployee(Base):
    """AI Employees that run the automated delivery platform"""
    __tablename__ = "ai_employees"

    id = Column(Integer, primary_key=True, index=True)
    employee_id = Column(String(20), unique=True, nullable=False, index=True)  # AI_EMP_001

    # Identity
    name = Column(String(100), nullable=False)  # OrderBot Alpha
    role = Column(String(50), nullable=False)  # order_orchestrator
    department = Column(String(50), nullable=False)  # logistics
    avatar = Column(String(10))  # 🤖

    # Status
    status = Column(SQLEnum(AIEmployeeStatus), default=AIEmployeeStatus.IDLE)
    is_online = Column(Boolean, default=True)
    last_active = Column(DateTime, default=datetime.utcnow)

    # Performance Metrics (lifetime)
    total_tasks_completed = Column(Integer, default=0)
    total_errors = Column(Integer, default=0)
    total_hours_active = Column(Float, default=0.0)
    average_task_time_seconds = Column(Float, default=0.0)
    success_rate = Column(Float, default=100.0)  # percentage

    # Current Session
    session_start = Column(DateTime)
    tasks_this_session = Column(Integer, default=0)
    errors_this_session = Column(Integer, default=0)

    # Configuration
    model_version = Column(String(50), default="gpt-4")
    config_json = Column(Text)  # JSON configuration

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    activities = relationship("AIEmployeeActivity", back_populates="ai_employee")
    hourly_reports = relationship("AIEmployeeHourlyReport", back_populates="ai_employee")


class AIEmployeeActivity(Base):
    """Activity log for AI Employee actions"""
    __tablename__ = "ai_employee_activities"

    id = Column(Integer, primary_key=True, index=True)
    ai_employee_id = Column(Integer, ForeignKey("ai_employees.id"), nullable=False)

    # Activity Details
    activity_type = Column(String(50), nullable=False)  # ORDER_PROCESSED, DISPATCH_ASSIGNED, etc.
    description = Column(Text)
    status = Column(String(20), default="completed")  # completed, failed, pending

    # Related Entities
    order_id = Column(Integer, ForeignKey("orders.id"), nullable=True)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)

    # Performance
    processing_time_ms = Column(Integer)  # Time to complete in milliseconds
    error_message = Column(Text)

    # Timestamps
    started_at = Column(DateTime, default=datetime.utcnow)
    completed_at = Column(DateTime)

    # Relationships
    ai_employee = relationship("AIEmployee", back_populates="activities")


class AIEmployeeHourlyReport(Base):
    """Hourly reports generated by each AI Employee"""
    __tablename__ = "ai_employee_hourly_reports"

    id = Column(Integer, primary_key=True, index=True)
    report_id = Column(String(50), unique=True, nullable=False, index=True)  # RPT-AI001-20241201-14
    ai_employee_id = Column(Integer, ForeignKey("ai_employees.id"), nullable=False)

    # Report Period
    report_hour = Column(DateTime, nullable=False)  # Start of the hour
    report_date = Column(DateTime, nullable=False)  # Date for grouping

    # Metrics - Common to all AI Employees
    tasks_completed = Column(Integer, default=0)
    tasks_failed = Column(Integer, default=0)
    avg_processing_time_ms = Column(Integer, default=0)
    total_processing_time_ms = Column(Integer, default=0)
    error_rate = Column(Float, default=0.0)
    uptime_percentage = Column(Float, default=100.0)

    # Role-Specific Metrics (JSON for flexibility)
    # OrderBot: orders_processed, total_order_value, payment_success_rate
    # KitchenBot: orders_sent_to_kitchen, avg_prep_time, kitchen_delays
    # DispatchBot: deliveries_dispatched, avg_delivery_time, driver_utilization
    # LedgerBot: journal_entries_created, total_debits, total_credits, reconciled
    # QualityBot: reviews_processed, complaints_handled, avg_rating
    role_specific_metrics = Column(Text)  # JSON

    # Summary
    summary_text = Column(Text)  # Human-readable summary
    alerts = Column(Text)  # JSON array of any alerts/issues
    recommendations = Column(Text)  # JSON array of recommendations

    # Status
    is_published = Column(Boolean, default=False)
    published_at = Column(DateTime)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    ai_employee = relationship("AIEmployee", back_populates="hourly_reports")


class AIEmployeeDailyReport(Base):
    """Daily summary reports aggregating hourly reports"""
    __tablename__ = "ai_employee_daily_reports"

    id = Column(Integer, primary_key=True, index=True)
    report_id = Column(String(50), unique=True, nullable=False, index=True)  # DAILY-AI001-20241201
    ai_employee_id = Column(Integer, ForeignKey("ai_employees.id"), nullable=False)

    # Report Period
    report_date = Column(DateTime, nullable=False)

    # Aggregated Metrics
    total_tasks = Column(Integer, default=0)
    total_errors = Column(Integer, default=0)
    success_rate = Column(Float, default=100.0)
    total_active_hours = Column(Float, default=0.0)
    peak_hour = Column(Integer)  # Hour with most activity (0-23)
    peak_hour_tasks = Column(Integer, default=0)

    # Role-Specific Daily Summary (JSON)
    daily_metrics = Column(Text)

    # Performance Comparison
    vs_previous_day = Column(Float)  # % change in tasks
    vs_weekly_avg = Column(Float)  # % vs 7-day average

    # Summary
    summary_text = Column(Text)
    key_achievements = Column(Text)  # JSON array
    issues_encountered = Column(Text)  # JSON array
    recommendations = Column(Text)  # JSON array

    # Status
    is_published = Column(Boolean, default=False)
    published_at = Column(DateTime)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)


class DashboardMetric(Base):
    """Real-time metrics for the AI Operations Dashboard"""
    __tablename__ = "dashboard_metrics"

    id = Column(Integer, primary_key=True, index=True)
    metric_key = Column(String(100), unique=True, nullable=False, index=True)

    # Metric Value
    metric_value = Column(Float, nullable=False)
    metric_unit = Column(String(20))  # count, percentage, dollars, seconds
    metric_label = Column(String(100))

    # Categorization
    category = Column(String(50))  # orders, deliveries, finance, quality
    ai_employee_id = Column(Integer, ForeignKey("ai_employees.id"), nullable=True)

    # Time Window
    time_window = Column(String(20))  # realtime, hourly, daily, weekly

    # Timestamps
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# =========================================================================
# SUPPORT TICKET MODELS - Internal Issue Tracking (JIRA Dashboard)
# =========================================================================

class TicketPriority(enum.Enum):
    P0_CRITICAL = "P0 - Critical"
    P1_HIGH = "P1 - High"
    P2_MEDIUM = "P2 - Medium"
    P3_LOW = "P3 - Low"


class TicketStatus(enum.Enum):
    OPEN = "Open"
    IN_PROGRESS = "In Progress"
    UNDER_REVIEW = "Under Review"
    RESOLVED = "Resolved"
    CLOSED = "Closed"


class TicketType(enum.Enum):
    BUG = "Bug"
    FEATURE = "Feature"
    TASK = "Task"
    STORY = "Story"
    EPIC = "Epic"
    SUPPORT = "Support"


class SupportTicket(Base):
    """Support tickets for internal issue tracking (JIRA Dashboard)"""
    __tablename__ = "support_tickets"

    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(String(20), unique=True, nullable=False, index=True)  # DOLLOR-123

    # Ticket Details
    title = Column(String(255), nullable=False)
    description = Column(Text)
    ticket_type = Column(SQLEnum(TicketType), default=TicketType.TASK)
    priority = Column(SQLEnum(TicketPriority), default=TicketPriority.P2_MEDIUM)
    status = Column(SQLEnum(TicketStatus), default=TicketStatus.OPEN)

    # Assignment
    assignee = Column(String(100))
    reporter = Column(String(100))
    team = Column(String(50))  # Team A, Team B, etc.

    # Related Entities
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=True)
    order_id = Column(Integer, ForeignKey("orders.id"), nullable=True)
    vendor_id = Column(Integer, ForeignKey("vendors.id"), nullable=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)

    # Labels and Tags
    labels = Column(JSON)  # ["backend", "urgent", "customer-facing"]
    component = Column(String(100))  # "Order System", "Payment", "Driver App"

    # SLA Tracking
    due_date = Column(DateTime)
    sla_breached = Column(Boolean, default=False)
    first_response_at = Column(DateTime)
    resolved_at = Column(DateTime)

    # Resolution
    resolution = Column(Text)
    resolution_time_hours = Column(Float)

    # Comments count
    comments_count = Column(Integer, default=0)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class TicketComment(Base):
    """Comments on support tickets"""
    __tablename__ = "ticket_comments"

    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(Integer, ForeignKey("support_tickets.id"), nullable=False)

    # Comment Details
    author = Column(String(100), nullable=False)
    content = Column(Text, nullable=False)
    is_internal = Column(Boolean, default=False)  # Internal notes vs public comments

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


# =========================================================================
# CHAT/MESSAGING MODELS - Real-time communication between riders and drivers
# =========================================================================

class MessageSenderType(enum.Enum):
    CUSTOMER = "customer"
    DRIVER = "driver"
    SYSTEM = "system"


class ChatConversation(Base):
    """Chat conversation between customer and driver for an order"""
    __tablename__ = "chat_conversations"

    id = Column(Integer, primary_key=True, index=True)

    # Link to order (one conversation per order)
    order_id = Column(Integer, ForeignKey("orders.id"), unique=True, nullable=False, index=True)

    # Participants
    customer_id = Column(Integer, nullable=False, index=True)
    customer_name = Column(String(255))
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True, index=True)
    driver_name = Column(String(255))

    # Conversation state
    is_active = Column(Boolean, default=True)  # Active while order in progress
    last_message_at = Column(DateTime)
    last_message_preview = Column(String(255))

    # Unread counts
    customer_unread_count = Column(Integer, default=0)
    driver_unread_count = Column(Integer, default=0)

    # Typing indicators (ephemeral, updated via WebSocket)
    customer_typing = Column(Boolean, default=False)
    driver_typing = Column(Boolean, default=False)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    order = relationship("Order")
    driver = relationship("Driver")
    messages = relationship("ChatMessage", back_populates="conversation", order_by="ChatMessage.created_at")


class ChatMessage(Base):
    """Individual chat message in a conversation"""
    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(Integer, ForeignKey("chat_conversations.id"), nullable=False, index=True)

    # Sender info
    sender_type = Column(SQLEnum(MessageSenderType), nullable=False)
    sender_id = Column(Integer, nullable=False)  # customer_id or driver_id
    sender_name = Column(String(255))

    # Message content
    message = Column(Text, nullable=False)
    message_type = Column(String(50), default="text")  # text, image, location, system

    # Attachments (JSON for images, locations, etc.)
    attachments = Column(Text)  # JSON: [{"type": "image", "url": "..."}, {"type": "location", "lat": ..., "lng": ...}]

    # Read receipt
    is_read = Column(Boolean, default=False)
    read_at = Column(DateTime)

    # Delivery status
    is_delivered = Column(Boolean, default=False)
    delivered_at = Column(DateTime)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    conversation = relationship("ChatConversation", back_populates="messages")


# =========================================================================
# RIDE BIDDING MODELS - Matchmaking platform for price negotiation
# =========================================================================

class RideRequestStatus(enum.Enum):
    OPEN = "open"                    # Waiting for driver bids
    BIDDING = "bidding"              # Has received bids, customer reviewing
    MATCHED = "matched"              # Customer accepted a bid
    IN_PROGRESS = "in_progress"      # Ride is happening
    COMPLETED = "completed"          # Ride finished
    CANCELLED = "cancelled"          # Customer cancelled
    EXPIRED = "expired"              # No bids received in time


class BidStatus(enum.Enum):
    PENDING = "pending"              # Waiting for customer response
    ACCEPTED = "accepted"            # Customer accepted this bid
    REJECTED = "rejected"            # Customer rejected this bid
    COUNTERED = "countered"          # Customer made counter-offer
    WITHDRAWN = "withdrawn"          # Driver withdrew bid
    EXPIRED = "expired"              # Bid expired without response


class RideRequest(Base):
    """Ride request from customer - open for driver bidding"""
    __tablename__ = "ride_requests"

    id = Column(Integer, primary_key=True, index=True)
    request_id = Column(String(50), unique=True, nullable=False, index=True)  # RR-20241221-001

    # Customer
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)
    customer_name = Column(String(255))
    customer_phone = Column(String(50))

    # Pickup Location
    pickup_address = Column(Text, nullable=False)
    pickup_latitude = Column(Float, nullable=False)
    pickup_longitude = Column(Float, nullable=False)
    pickup_place_name = Column(String(255))  # "Downtown Mall"

    # Dropoff Location
    dropoff_address = Column(Text, nullable=False)
    dropoff_latitude = Column(Float, nullable=False)
    dropoff_longitude = Column(Float, nullable=False)
    dropoff_place_name = Column(String(255))  # "Airport Terminal 2"

    # Trip Details
    estimated_distance_km = Column(Float)
    estimated_duration_minutes = Column(Integer)
    ride_type = Column(String(50), default="standard")  # standard, premium, xl

    # Pricing - Customer Preferences
    suggested_price = Column(Float)           # System-calculated suggested price
    customer_max_price = Column(Float)        # Max customer willing to pay (optional)
    customer_preferred_price = Column(Float)  # What customer hopes to pay (optional)

    # Matched Bid (after acceptance)
    matched_bid_id = Column(Integer, ForeignKey("ride_bids.id"), nullable=True)
    matched_driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True, index=True)
    final_price = Column(Float)  # Agreed price after negotiation

    # Status
    status = Column(SQLEnum(RideRequestStatus), default=RideRequestStatus.OPEN, index=True)

    # Bidding Window
    bidding_expires_at = Column(DateTime)  # When bidding closes
    max_bids = Column(Integer, default=10)  # Max bids to accept
    customer_counter_count = Column(Integer, default=0)  # Track total counters (max 3)
    low_bid_warning_shown = Column(Boolean, default=False)  # Track if warning was shown

    # Broadcast
    broadcast_radius_km = Column(Float, default=10.0)
    drivers_notified = Column(Integer, default=0)

    # Notes
    special_requests = Column(Text)  # "Need car seat", "Wheelchair accessible"

    # TNC-12: Accessibility (CPUC compliance)
    accessibility_requested = Column(Boolean, default=False)  # Passenger needs WAV or accessible vehicle
    accessibility_notes = Column(Text)  # Specific accessibility needs

    # TNC-13: Access for All fee (CPUC Decision 19-06-033)
    access_for_all_fee = Column(Float, default=0.10)  # $0.10/trip — $0.05 customer + $0.05 driver

    # Payment (Stripe integration)
    stripe_payment_intent_id = Column(String(255))
    payment_status = Column(String(50), default="pending")  # pending, processing, completed, failed
    platform_fee = Column(Float)  # $2 total ($1 from customer + $1 from driver)
    driver_payout = Column(Float)  # fare - $1
    payment_completed_at = Column(DateTime)
    driver_paid_at = Column(DateTime)  # When driver received payout
    stripe_transfer_id = Column(String(255))  # Stripe Connect transfer ID

    # Payment retry tracking
    payment_retry_count = Column(Integer, default=0)  # Number of capture retry attempts

    # Tip
    tip_amount = Column(Float, default=0.0)  # Customer tip for driver (100% to driver)

    # Prop 22 compliance columns — nullable; set at matched_at and completion
    prop22_acceptance_lat = Column(Float, nullable=True)   # driver GPS lat at acceptance (matched_at)
    prop22_acceptance_lon = Column(Float, nullable=True)   # driver GPS lon at acceptance
    prop22_engaged_hours = Column(Float, nullable=True)    # (completed_at - matched_at) in hours
    prop22_engaged_miles = Column(Float, nullable=True)    # road miles: acceptance GPS -> dropoff
    prop22_floor_amount = Column(Float, nullable=True)     # floor for this ride (per-ride disclosure)

    # Rating
    customer_rating = Column(Integer)  # 1-5 stars from customer
    customer_comment = Column(Text)    # Optional review comment
    passenger_rating = Column(Integer)  # 1-5 stars from driver
    passenger_comment = Column(Text)    # Optional driver comment about passenger

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    matched_at = Column(DateTime)
    driver_arrived_at = Column(DateTime)
    completed_at = Column(DateTime)
    cancelled_at = Column(DateTime)

    # Relationships
    customer = relationship("Customer")
    matched_driver = relationship("Driver", foreign_keys=[matched_driver_id])
    bids = relationship("RideBid", back_populates="ride_request", foreign_keys="RideBid.ride_request_id")


class RideBid(Base):
    """Driver's bid on a ride request"""
    __tablename__ = "ride_bids"

    id = Column(Integer, primary_key=True, index=True)
    bid_id = Column(String(50), unique=True, nullable=False, index=True)  # BID-20241221-001

    # Ride Request
    ride_request_id = Column(Integer, ForeignKey("ride_requests.id"), nullable=False, index=True)

    # Driver
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False, index=True)
    driver_name = Column(String(255))
    driver_rating = Column(Float)
    driver_photo_url = Column(String(500))
    driver_vehicle = Column(String(255))  # "Toyota Camry 2022 - Silver"

    # Bid Details
    proposed_price = Column(Float, nullable=False)
    message = Column(Text)  # "I'm 5 mins away, can pick up quickly!"
    estimated_arrival_minutes = Column(Integer)  # ETA to pickup

    # Counter-offer tracking
    is_counter_offer = Column(Boolean, default=False)
    counter_to_bid_id = Column(Integer, ForeignKey("ride_bids.id"), nullable=True)
    original_price = Column(Float)  # Price before counter-offer

    # Multi-round negotiation tracking
    negotiation_round = Column(Integer, default=1)  # 1=initial, 2=counter, 3=final
    last_offer_by = Column(String(20), default="driver")  # 'driver' or 'customer'
    round_counter = Column(Integer, default=0)  # Total back-and-forth count

    # Status
    status = Column(SQLEnum(BidStatus), default=BidStatus.PENDING, index=True)

    # Expiration
    expires_at = Column(DateTime)  # Bid expires if not responded

    # Response
    customer_response = Column(Text)  # Customer's counter-offer message
    customer_counter_price = Column(Float)  # If customer counters

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    responded_at = Column(DateTime)  # When customer responded
    accepted_at = Column(DateTime)
    rejected_at = Column(DateTime)

    # Relationships
    ride_request = relationship("RideRequest", back_populates="bids", foreign_keys=[ride_request_id])
    driver = relationship("Driver")
    counter_to = relationship("RideBid", remote_side=[id], foreign_keys=[counter_to_bid_id])

    # Table constraints
    __table_args__ = (
        UniqueConstraint('ride_request_id', 'driver_id', name='uq_bid_per_driver_per_request'),
    )


# ============================================================================
# COUPA INTEGRATION MODELS
# ============================================================================

class CoupaPOStatus(enum.Enum):
    DRAFT = "draft"
    PENDING_APPROVAL = "pending_approval"
    APPROVED = "approved"
    ORDERED = "ordered"
    PARTIALLY_RECEIVED = "partially_received"
    RECEIVED = "received"
    INVOICED = "invoiced"
    CLOSED = "closed"
    CANCELLED = "cancelled"


class CoupaRequisitionStatus(enum.Enum):
    DRAFT = "draft"
    PENDING_APPROVAL = "pending_approval"
    APPROVED = "approved"
    ORDERED = "ordered"
    DENIED = "denied"
    CANCELLED = "cancelled"


class CoupaSupplier(Base):
    """Supplier/Vendor in Coupa system"""
    __tablename__ = "coupa_suppliers"

    id = Column(Integer, primary_key=True, index=True)
    supplier_number = Column(String(50), unique=True, index=True)
    name = Column(String(255), nullable=False)
    display_name = Column(String(255))

    # Contact Info
    contact_name = Column(String(255))
    contact_email = Column(String(255))
    contact_phone = Column(String(50))

    # Address
    address_line1 = Column(String(255))
    address_line2 = Column(String(255))
    city = Column(String(100))
    state = Column(String(100))
    postal_code = Column(String(20))
    country = Column(String(100), default="USA")

    # Status
    status = Column(String(50), default="active")  # active, inactive, blocked
    payment_terms = Column(String(50), default="Net 30")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    purchase_orders = relationship("CoupaPurchaseOrder", back_populates="supplier")


class CoupaDepartment(Base):
    """Department/Business Unit for spend tracking"""
    __tablename__ = "coupa_departments"

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(50), unique=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    manager_name = Column(String(255))
    manager_email = Column(String(255))
    budget_amount = Column(Float, default=0)
    spent_amount = Column(Float, default=0)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class CoupaCostCenter(Base):
    """Cost Center for expense allocation"""
    __tablename__ = "coupa_cost_centers"

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(50), unique=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    department_id = Column(Integer, ForeignKey("coupa_departments.id"))
    budget_amount = Column(Float, default=0)
    spent_amount = Column(Float, default=0)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    department = relationship("CoupaDepartment")


class CoupaCommodity(Base):
    """Commodity/Category for spend classification"""
    __tablename__ = "coupa_commodities"

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(50), unique=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    parent_id = Column(Integer, ForeignKey("coupa_commodities.id"), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class CoupaPurchaseOrder(Base):
    """Purchase Order in Coupa"""
    __tablename__ = "coupa_purchase_orders"

    id = Column(Integer, primary_key=True, index=True)
    po_number = Column(String(50), unique=True, index=True)

    # Supplier
    supplier_id = Column(Integer, ForeignKey("coupa_suppliers.id"))

    # Classification
    department_id = Column(Integer, ForeignKey("coupa_departments.id"))
    cost_center_id = Column(Integer, ForeignKey("coupa_cost_centers.id"))
    commodity_id = Column(Integer, ForeignKey("coupa_commodities.id"))

    # Order Details
    description = Column(Text)
    order_date = Column(DateTime, default=datetime.utcnow)
    requested_delivery_date = Column(DateTime)
    actual_delivery_date = Column(DateTime)

    # Amounts
    subtotal = Column(Float, default=0)
    tax_amount = Column(Float, default=0)
    shipping_amount = Column(Float, default=0)
    total_amount = Column(Float, default=0)

    # Status
    status = Column(SQLEnum(CoupaPOStatus), default=CoupaPOStatus.DRAFT)
    approval_status = Column(String(50), default="pending")  # pending, approved, rejected
    approved_by = Column(String(255))
    approved_at = Column(DateTime)

    # Tracking
    created_by = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    supplier = relationship("CoupaSupplier", back_populates="purchase_orders")
    department = relationship("CoupaDepartment")
    cost_center = relationship("CoupaCostCenter")
    commodity = relationship("CoupaCommodity")
    lines = relationship("CoupaPurchaseOrderLine", back_populates="purchase_order")


class CoupaPurchaseOrderLine(Base):
    """Line item in a Purchase Order"""
    __tablename__ = "coupa_po_lines"

    id = Column(Integer, primary_key=True, index=True)
    purchase_order_id = Column(Integer, ForeignKey("coupa_purchase_orders.id"))
    line_number = Column(Integer)

    # Item Details
    item_description = Column(Text)
    item_code = Column(String(100))
    quantity = Column(Float, default=1)
    unit_of_measure = Column(String(50), default="EA")
    unit_price = Column(Float, default=0)
    total_price = Column(Float, default=0)

    # Classification
    commodity_id = Column(Integer, ForeignKey("coupa_commodities.id"))

    # Status
    received_quantity = Column(Float, default=0)
    invoiced_quantity = Column(Float, default=0)

    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    purchase_order = relationship("CoupaPurchaseOrder", back_populates="lines")


class CoupaRequisition(Base):
    """Purchase Requisition in Coupa"""
    __tablename__ = "coupa_requisitions"

    id = Column(Integer, primary_key=True, index=True)
    requisition_number = Column(String(50), unique=True, index=True)

    # Requester
    requester_name = Column(String(255))
    requester_email = Column(String(255))

    # Classification
    department_id = Column(Integer, ForeignKey("coupa_departments.id"))
    cost_center_id = Column(Integer, ForeignKey("coupa_cost_centers.id"))

    # Details
    description = Column(Text)
    justification = Column(Text)
    needed_by_date = Column(DateTime)

    # Amounts
    total_amount = Column(Float, default=0)

    # Status
    status = Column(SQLEnum(CoupaRequisitionStatus), default=CoupaRequisitionStatus.DRAFT)
    approved_by = Column(String(255))
    approved_at = Column(DateTime)

    # Linked PO (after conversion)
    purchase_order_id = Column(Integer, ForeignKey("coupa_purchase_orders.id"), nullable=True)

    # Timestamps
    submitted_at = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    department = relationship("CoupaDepartment")
    cost_center = relationship("CoupaCostCenter")
    purchase_order = relationship("CoupaPurchaseOrder")


# =============================================================================
# RATE LIMITING - Distributed rate limit tracking for security
# =============================================================================

class RateLimitEntry(Base):
    """
    Database-backed rate limiting for distributed environments (ECS/K8s).
    Stores rate limit attempts per client IP and endpoint to enforce
    limits across multiple container instances.
    """
    __tablename__ = "rate_limit_entries"

    id = Column(Integer, primary_key=True, index=True)
    # Composite key: IP + endpoint type (e.g., "192.168.1.1:customer_login")
    client_key = Column(String(255), nullable=False, index=True)
    # Timestamp of the request attempt
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)

    # Index for efficient cleanup of old entries
    __table_args__ = (
        # Composite index for fast lookups by key + time window
        # This enables efficient sliding window queries
    )


# =============================================================================
# PASSWORD RESET TOKENS - Database-backed for distributed environments
# =============================================================================

class PasswordResetToken(Base):
    """
    Database-backed password reset tokens.

    CRITICAL: This replaces in-memory storage to work across multiple
    container instances (App Runner, ECS, K8s scaling).

    Features:
    - Secure hashed code storage (not plaintext)
    - Expiration tracking
    - Delivery status tracking
    - Audit trail (IP, user agent, timestamps)
    - Failed attempt tracking to prevent brute force
    """
    __tablename__ = "password_reset_tokens"

    id = Column(Integer, primary_key=True, index=True)

    # User identification
    email = Column(String(255), nullable=False, index=True)
    user_type = Column(String(50), nullable=False)  # 'customer', 'driver', 'vendor'
    user_id = Column(Integer, nullable=False)

    # Secure code storage (hashed, not plaintext)
    code_hash = Column(String(255), nullable=False)

    # Expiration
    expires_at = Column(DateTime, nullable=False, index=True)

    # Usage tracking
    used = Column(Boolean, default=False, index=True)
    used_at = Column(DateTime, nullable=True)
    failed_attempts = Column(Integer, default=0)

    # Delivery tracking
    delivery_status = Column(String(50), default='pending')  # pending, sent, delivered, failed, bounced
    delivery_provider = Column(String(50), nullable=True)  # smtp, aws_ses, sendgrid, twilio_sms
    delivery_message_id = Column(String(255), nullable=True)
    delivery_error = Column(Text, nullable=True)

    # Audit trail
    ip_address = Column(String(45), nullable=True)  # IPv6 compatible
    user_agent = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    # Indexes for efficient queries
    __table_args__ = (
        # Index for finding active tokens by email
        # Index for cleanup of expired tokens
    )


class RideChatMessage(Base):
    """Chat messages between customer and driver during a ride"""
    __tablename__ = "ride_chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    ride_request_id = Column(Integer, ForeignKey("ride_requests.id"), nullable=False, index=True)
    sender_type = Column(String(20), nullable=False)  # 'customer' or 'driver'
    sender_id = Column(Integer, nullable=False)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


# =============================================================================
# RIDE DISPUTE - Payment dispute/refund tracking
# =============================================================================

class DisputeStatus(enum.Enum):
    SUBMITTED = "submitted"
    UNDER_REVIEW = "under_review"
    RESOLVED_REFUND = "resolved_refund"
    RESOLVED_NO_REFUND = "resolved_no_refund"
    CLOSED = "closed"


class DisputeReason(enum.Enum):
    WRONG_ROUTE = "wrong_route"
    OVERCHARGED = "overcharged"
    SAFETY_CONCERN = "safety_concern"
    DRIVER_BEHAVIOR = "driver_behavior"
    OTHER = "other"


class RideDispute(Base):
    """Customer dispute on a completed ride"""
    __tablename__ = "ride_disputes"

    id = Column(Integer, primary_key=True, index=True)
    ride_request_id = Column(Integer, ForeignKey("ride_requests.id"), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)
    reason = Column(SQLEnum(DisputeReason, native_enum=False), nullable=False)
    description = Column(Text)
    status = Column(SQLEnum(DisputeStatus, native_enum=False), nullable=False, default=DisputeStatus.SUBMITTED)
    refund_amount = Column(Float)
    stripe_refund_id = Column(String(255))
    admin_notes = Column(Text)
    resolved_at = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    ride_request = relationship("RideRequest")
    customer = relationship("Customer")


# =============================================================================
# ORDER DISPUTE - Food order dispute/refund tracking
# =============================================================================

class OrderDisputeReason(enum.Enum):
    WRONG_ITEMS = "wrong_items"
    MISSING_ITEMS = "missing_items"
    QUALITY_ISSUE = "quality_issue"
    NEVER_DELIVERED = "never_delivered"
    OTHER = "other"


class OrderDispute(Base):
    """Customer dispute on a delivered food order"""
    __tablename__ = "order_disputes"

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("orders.id"), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)
    reason = Column(SQLEnum(OrderDisputeReason, native_enum=False), nullable=False)
    description = Column(Text)
    affected_items = Column(Text)  # JSON array of item names/ids that were wrong/missing
    status = Column(SQLEnum(DisputeStatus, native_enum=False), nullable=False, default=DisputeStatus.SUBMITTED)
    refund_amount = Column(Float)
    stripe_refund_id = Column(String(255))
    admin_notes = Column(Text)
    resolved_at = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    order = relationship("Order")
    customer = relationship("Customer")


# =============================================================================
# RECURRING RIDE - Saved ride patterns for P2P matchmaking
# =============================================================================

class RecurringRide(Base):
    """Saved recurring ride pattern for automatic matching"""
    __tablename__ = "recurring_rides"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)

    # Pickup
    pickup_address = Column(Text, nullable=False)
    pickup_latitude = Column(Float, nullable=False)
    pickup_longitude = Column(Float, nullable=False)

    # Dropoff
    dropoff_address = Column(Text, nullable=False)
    dropoff_latitude = Column(Float, nullable=False)
    dropoff_longitude = Column(Float, nullable=False)

    # Schedule
    schedule_days = Column(String(50), nullable=False)  # "mon,wed,fri"
    schedule_time = Column(String(10), nullable=False)   # "08:30"
    timezone = Column(String(50), default="America/New_York")

    # Preferences
    preferred_driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=True)
    max_price = Column(Float)
    ride_type = Column(String(50), default="standard")

    # State
    is_active = Column(Boolean, default=True)
    last_triggered_at = Column(DateTime)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    customer = relationship("Customer")
    preferred_driver = relationship("Driver")


# =============================================================================
# IN-APP NOTIFICATION - Notification history for customers
# =============================================================================

class InAppNotification(Base):
    """In-app notification stored for customer notification feed"""
    __tablename__ = "in_app_notifications"

    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(Integer, ForeignKey("customers.id"), nullable=False, index=True)

    title = Column(String(255), nullable=False)
    message = Column(Text, nullable=False)
    type = Column(String(50), default="system")  # order, promotion, system, delivery, ride
    is_read = Column(Boolean, default=False)

    # Optional reference to related entity
    reference_id = Column(Integer)         # order_id or ride_request_id
    reference_type = Column(String(50))    # "order" or "ride"

    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    customer = relationship("Customer")


# =============================================================================
# PROP 22 COMPLIANCE — California Proposition 22 earnings floor system
# BPC 7453 (earnings floor) + BPC 7454(b)(2) (disclosure statements)
# =============================================================================

class Prop22Config(Base):
    """Legally mandated Prop 22 rates — never hardcode in application logic."""
    __tablename__ = "prop22_config"

    id = Column(Integer, primary_key=True)
    state = Column(String(10), nullable=False)
    effective_date = Column(Date, nullable=False)
    min_wage_multiplier = Column(Float, nullable=False)   # 1.20 per BPC 7453(a)(1)
    mile_rate = Column(Float, nullable=False)              # $0.37/mile (2026)
    healthcare_hours_threshold = Column(Float, default=15.0)
    healthcare_stipend_weekly = Column(Float, default=0.0)


class Prop22CityWage(Base):
    """Per-city minimum wages for Prop 22 floor calculation (GPS-based lookup)."""
    __tablename__ = "prop22_city_wages"

    id = Column(Integer, primary_key=True)
    city = Column(String(50), nullable=False)             # "CA", "SAN_FRANCISCO", "LOS_ANGELES"
    effective_date = Column(Date, nullable=False)
    min_wage = Column(Float, nullable=False)


class Prop22EarningPeriod(Base):
    """One row per driver per 14-day pay period.

    Status flow: PENDING -> RECONCILED (no top-up) / PAID (Stripe) /
                 MANUAL_REVIEW (Stripe failed or driver not onboarded) ->
                 OVERDUE (deadline passed, escalation job triggered)
    """
    __tablename__ = "prop22_earning_periods"

    id = Column(Integer, primary_key=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False)
    period_start = Column(DateTime(timezone=True), nullable=False)
    period_end = Column(DateTime(timezone=True), nullable=False)
    status = Column(String(20), nullable=False, default="PENDING")
    service_type = Column(String(20), nullable=False, default="RIDESHARE")  # "RIDESHARE" or "FOOD_DELIVERY"
    engaged_hours = Column(Float, nullable=False, default=0.0)
    engaged_miles = Column(Float, nullable=False, default=0.0)
    net_earnings = Column(Float, nullable=False, default=0.0)   # tips excluded — driver_payout sum
    prop22_floor = Column(Float, nullable=False, default=0.0)   # sum of per-ride prop22_floor_amount
    top_up_amount = Column(Float, nullable=False, default=0.0)  # max(0, floor - earned)
    top_up_stripe_id = Column(String(255), nullable=True)       # Stripe Transfer ID or manual reference
    deadline_at = Column(DateTime(timezone=True), nullable=True) # next period close
    is_archived = Column(Boolean, default=False)                 # never DELETE; 4-year UCL retention
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("driver_id", "period_start", name="uq_prop22_period_driver_start"),
    )


class Prop22EarningsStatement(Base):
    """BPC 7454(b)(2) earnings disclosure record — one per period per driver.

    Must be retained for 4 years per California Labor Code. Never DELETE rows;
    use is_archived=True for soft-delete if needed.
    """
    __tablename__ = "prop22_earnings_statement"

    id = Column(Integer, primary_key=True)
    driver_id = Column(Integer, ForeignKey("drivers.id"), nullable=False)
    period_id = Column(Integer, ForeignKey("prop22_earning_periods.id"), nullable=False)
    period_engaged_hours = Column(Float, nullable=False, default=0.0)
    qtd_engaged_hours = Column(Float, nullable=False, default=0.0)  # BPC 7454(b)(2) calendar quarter
    period_engaged_miles = Column(Float, nullable=False, default=0.0)
    net_earnings = Column(Float, nullable=False, default=0.0)       # tips excluded
    prop22_floor = Column(Float, nullable=False, default=0.0)
    top_up_amount = Column(Float, nullable=False, default=0.0)
    top_up_stripe_id = Column(String(255), nullable=True)
    is_archived = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
