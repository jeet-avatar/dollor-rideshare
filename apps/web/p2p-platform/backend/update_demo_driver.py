#!/usr/bin/env python3
"""
Update demo driver: Set realistic driver profile with photos and vehicle details.
Used for App Store review and demo purposes.
"""
import os
import secrets
import sys
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Ensure JWT_SECRET_KEY is set for imports (random per run; this script never issues tokens)
if not os.getenv("JWT_SECRET_KEY"):
    os.environ["JWT_SECRET_KEY"] = secrets.token_hex(32)

from database import SessionLocal
from models import Driver, DriverStatus
from datetime import datetime

DEMO_DRIVER_EMAIL = "demo.driver@dollor.ai"

# Demo driver profile - realistic data for App Store review
DEMO_DRIVER_PROFILE = {
    "first_name": "Marcus",
    "last_name": "Johnson",
    "phone": "+14155551002",
    "street": "789 Driver Lane",
    "city": "San Francisco",
    "state": "CA",
    "zip_code": "94102",
    "vehicle_type": "car",
    "vehicle_make": "Toyota",
    "vehicle_model": "Camry",
    "vehicle_year": 2023,
    "vehicle_color": "Silver",
    "license_plate": "7ABC123",
    "license_number": "D1234567",
    "rating": 4.9,
    "total_deliveries": 347,
    # Professional driver photo - generated avatar (green background matches brand)
    "photo_url": "https://ui-avatars.com/api/?name=Marcus+Johnson&size=200&background=4CAF50&color=fff&bold=true&format=png",
    # Vehicle photo - silver sedan from Unsplash (royalty-free)
    "vehicle_photo_url": "https://images.unsplash.com/photo-1621007947382-bb3c3994e3fb?w=400&h=300&fit=crop",
}


def update_demo_driver():
    """Update demo driver with complete profile for App Store review."""
    print("\n" + "="*60)
    print("UPDATING DEMO DRIVER - MARCUS JOHNSON")
    print("="*60)

    db = SessionLocal()

    try:
        # Find demo driver
        driver = db.query(Driver).filter(Driver.email == DEMO_DRIVER_EMAIL).first()

        if not driver:
            print(f"ERROR: Demo driver not found: {DEMO_DRIVER_EMAIL}")
            print("Run POST /api/demo/setup first to create demo accounts.")
            return False

        print(f"\nFound driver ID: {driver.id}")
        print(f"Email: {driver.email}")

        # Current state
        print(f"\n--- BEFORE UPDATE ---")
        print(f"  Name:          {driver.first_name} {driver.last_name}")
        print(f"  Vehicle:       {driver.vehicle_year or '?'} {driver.vehicle_make or '?'} {driver.vehicle_model or '?'}")
        print(f"  Color:         {driver.vehicle_color or 'NOT SET'}")
        print(f"  License Plate: {driver.license_plate or 'NOT SET'}")
        print(f"  Rating:        {driver.rating or 'NOT SET'}")
        print(f"  Photo URL:     {driver.photo_url or 'NOT SET'}")
        print(f"  Vehicle Photo: {getattr(driver, 'vehicle_photo_url', 'N/A') or 'NOT SET'}")
        print(f"  Status:        {driver.status}")

        # Update all profile fields
        for key, value in DEMO_DRIVER_PROFILE.items():
            if hasattr(driver, key):
                setattr(driver, key, value)

        # Mark as verified/approved
        driver.status = DriverStatus.APPROVED
        driver.documents_verified = True
        driver.verification_status = "verified"
        driver.documents_verified_at = datetime.utcnow()
        driver.approved_at = datetime.utcnow()
        driver.terms_accepted_at = datetime(2024, 1, 10)

        # Mark all documents as uploaded
        driver.drivers_license = True
        driver.drivers_license_expiry = datetime(2027, 12, 31)
        driver.insurance = True
        driver.insurance_expiry = datetime(2026, 6, 30)
        driver.background_check = True
        driver.background_check_date = datetime(2024, 1, 15)

        # Set online status and location (San Francisco)
        driver.is_online = True
        driver.current_latitude = 37.7749
        driver.current_longitude = -122.4194
        driver.location_updated_at = datetime.utcnow()

        db.commit()
        db.refresh(driver)

        # Verify update
        print(f"\n--- AFTER UPDATE ---")
        print(f"  Name:          {driver.first_name} {driver.last_name}")
        print(f"  Vehicle:       {driver.vehicle_year} {driver.vehicle_make} {driver.vehicle_model}")
        print(f"  Color:         {driver.vehicle_color}")
        print(f"  License Plate: {driver.license_plate}")
        print(f"  Rating:        {driver.rating} ⭐")
        print(f"  Deliveries:    {driver.total_deliveries}")
        print(f"  Photo URL:     {driver.photo_url[:50]}...")
        print(f"  Vehicle Photo: {getattr(driver, 'vehicle_photo_url', 'N/A')[:50] if getattr(driver, 'vehicle_photo_url', None) else 'NOT SET'}...")
        print(f"  Status:        {driver.status}")
        print(f"  Verified:      {driver.documents_verified}")
        print(f"  Online:        {driver.is_online}")
        print(f"  Location:      ({driver.current_latitude}, {driver.current_longitude})")

        print(f"\n" + "="*60)
        print("✅ DEMO DRIVER UPDATED SUCCESSFULLY!")
        print("="*60)
        print(f"\nDriver ready for App Store review:")
        print(f"  Email:    {DEMO_DRIVER_EMAIL}")
        print("="*60 + "\n")

        return True

    except Exception as e:
        print(f"\nERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        db.rollback()
        return False
    finally:
        db.close()


if __name__ == "__main__":
    success = update_demo_driver()
    sys.exit(0 if success else 1)
