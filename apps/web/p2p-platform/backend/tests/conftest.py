"""
Pytest configuration and shared fixtures for all tests.

Provides:
- Test database setup (with PostgreSQL schema recreation for clean state)
- FastAPI TestClient
- Authentication fixtures
- Mock data factories

Uses DROP OWNED BY for clean PostgreSQL state to avoid index conflicts.
"""

import pytest
import os
import sys
import tempfile
from datetime import datetime
from typing import Generator, Dict, Any
from unittest.mock import MagicMock, patch

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

# IMPORTANT: Set up test database URL BEFORE importing main_new/database
# This ensures database.py uses the same test database as conftest

# Use in-memory SQLite for testing - avoids all persistence issues
# Each test run gets a completely fresh database
import uuid
_test_session_id = uuid.uuid4().hex[:8]

# Check if we're in CI with PostgreSQL available
_original_db_url = os.getenv("DATABASE_URL")
if _original_db_url and "postgresql" in _original_db_url:
    # Use a separate test database for PostgreSQL
    # Parse the URL and append "_test" to database name if not already test
    if "_test" not in _original_db_url and "invoice_db" in _original_db_url:
        TEST_DATABASE_URL = _original_db_url.replace("invoice_db", "invoice_db_test")
    else:
        TEST_DATABASE_URL = _original_db_url
    os.environ["DATABASE_URL"] = TEST_DATABASE_URL
else:
    # Use in-memory SQLite with cache=shared so multiple connections can access
    # the same database (needed for TestClient which runs in a different thread)
    TEST_DATABASE_URL = "sqlite:///file::memory:?cache=shared&uri=true"
    os.environ["DATABASE_URL"] = TEST_DATABASE_URL

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool, NullPool

# Now import app and models (they will use the TEST_DATABASE_URL)
from main_new import app, get_db, create_access_token, get_password_hash
from auth_utils import require_any_auth, require_customer, require_admin, require_driver, require_vendor
from database import Base
from models import User, Vendor, Driver, Customer, VendorStatus, OnboardingPhase, UserRole

# Import extended models to ensure all tables are registered before create_all
import models_extended  # noqa: F401

# Create test engine
if "postgresql" in TEST_DATABASE_URL:
    engine = create_engine(TEST_DATABASE_URL, poolclass=NullPool)
else:
    engine = create_engine(
        TEST_DATABASE_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

# Replace the engine that database.py created during import — it shares the same
# in-memory SQLite (cache=shared) but with a different pool, causing "database is locked"
# when the test engine tries to DROP/CREATE tables. By pointing database.py at our
# test engine (StaticPool), all code paths use a single connection.
import database as _database_module
_database_module.engine.dispose()
_database_module.engine = engine
_database_module.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    """Override database dependency for testing"""
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(autouse=True)
def _clear_rate_limits():
    """Clear in-memory rate limits before each test to prevent cross-test pollution.
    The in-memory rate limiter (NSA-004 fallback) persists across tests when Redis
    is unavailable, causing spurious 429 failures."""
    import cache
    from cache import reset_memory_rate_limits
    reset_memory_rate_limits()
    # Account deletion revokes by account id; rolled-back test DBs reuse ids (production never does)
    cache._revoked_accounts.clear()
    yield
    reset_memory_rate_limits()
    cache._revoked_accounts.clear()


@pytest.fixture(scope="session")
def test_db():
    """Create test database tables"""
    # For PostgreSQL, use DROP SCHEMA to completely clean the database
    if "postgresql" in TEST_DATABASE_URL:
        with engine.connect() as conn:
            try:
                # Drop and recreate public schema to clear everything
                conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
                conn.execute(text("CREATE SCHEMA public"))
                conn.execute(text("GRANT ALL ON SCHEMA public TO public"))
                conn.commit()
            except Exception as e:
                print(f"Warning: DROP SCHEMA failed: {e}")
                conn.rollback()
                # Fallback: try DROP OWNED
                try:
                    result = conn.execute(text("SELECT current_user"))
                    current_user = result.scalar()
                    conn.execute(text(f"DROP OWNED BY {current_user} CASCADE"))
                    conn.commit()
                except Exception as e2:
                    print(f"Warning: DROP OWNED also failed: {e2}")
                    conn.rollback()
    else:
        # For SQLite, drop all tables first
        try:
            # Drop tables in reverse dependency order
            with engine.connect() as conn:
                conn.execute(text("PRAGMA foreign_keys = OFF"))
                # Get all table names
                result = conn.execute(text("SELECT name FROM sqlite_master WHERE type='table'"))
                tables = [row[0] for row in result]
                for table in tables:
                    if table != 'sqlite_sequence':
                        conn.execute(text(f"DROP TABLE IF EXISTS {table}"))
                conn.execute(text("PRAGMA foreign_keys = ON"))
                conn.commit()
        except Exception as e:
            print(f"Warning: SQLite drop failed: {e}")

    # Create all tables with checkfirst to handle any remaining conflicts
    try:
        Base.metadata.create_all(bind=engine, checkfirst=True)
    except Exception as e:
        # If create_all fails, try creating tables individually
        print(f"Warning: Bulk create_all failed: {e}")
        for table in Base.metadata.sorted_tables:
            try:
                table.create(bind=engine, checkfirst=True)
            except Exception as table_error:
                print(f"Warning: Could not create table {table.name}: {table_error}")

    yield

    # Cleanup
    try:
        Base.metadata.drop_all(bind=engine)
    except Exception:
        pass  # Ignore errors on cleanup


@pytest.fixture(scope="function")
def db_session(test_db) -> Generator:
    """Get a test database session"""
    connection = engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)

    yield session

    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture(scope="function")
def client(db_session) -> Generator:
    """Get a TestClient with test database"""
    def override_get_db_fixture():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db_fixture

    # Clear startup event handlers to prevent init_db from running
    # (tables are already created by test_db fixture)
    original_startup_handlers = app.router.on_startup.copy()
    app.router.on_startup.clear()

    with TestClient(app) as c:
        yield c

    # Restore original handlers
    app.router.on_startup = original_startup_handlers
    app.dependency_overrides.clear()


@pytest.fixture(scope="function")
def test_user(db_session) -> User:
    """Create a test user"""
    user = User(
        email=f"testuser_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("TestPassword123!"),
        full_name="Test User",
        role=UserRole.USER,
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


@pytest.fixture(scope="function")
def test_admin(db_session) -> User:
    """Create a test admin user"""
    admin = User(
        email=f"admin_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("AdminPassword123!"),
        full_name="Test Admin",
        role=UserRole.ADMIN,
    )
    db_session.add(admin)
    db_session.commit()
    db_session.refresh(admin)
    return admin


@pytest.fixture(scope="function")
def test_vendor(db_session) -> Vendor:
    """Create a test vendor"""
    vendor = Vendor(
        company_name=f"Test Company {datetime.now().timestamp()}",
        restaurant_name=f"Test Restaurant {datetime.now().timestamp()}",
        contact_email=f"vendor_{datetime.now().timestamp()}@test.com",
        contact_phone="+14155551234",
        street="123 Test St",
        city="San Francisco",
        state="CA",
        zip_code="94102",
        onboarding_status=VendorStatus.APPROVED,
        onboarding_phase=OnboardingPhase.COMPLETED,
    )
    db_session.add(vendor)
    db_session.commit()
    db_session.refresh(vendor)
    return vendor


@pytest.fixture(scope="function")
def test_driver(db_session) -> Driver:
    """Create a test driver"""
    import uuid
    from models import DriverStatus
    driver = Driver(
        driver_id=f"drv_{uuid.uuid4().hex[:8]}",
        email=f"driver_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("DriverPassword123!"),
        first_name="Test",
        last_name="Driver",
        phone="+14155551234",
        status=DriverStatus.APPROVED,
    )
    db_session.add(driver)
    db_session.commit()
    db_session.refresh(driver)
    return driver


@pytest.fixture(scope="function")
def auth_headers(test_user) -> Dict[str, str]:
    """Get authentication headers for test user"""
    token = create_access_token(data={"sub": test_user.email})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="function")
def admin_auth_headers(test_admin) -> Dict[str, str]:
    """Get authentication headers for admin user"""
    token = create_access_token(data={"sub": test_admin.email})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="function")
def vendor_auth_headers(test_vendor) -> Dict[str, str]:
    """Get authentication headers for vendor"""
    token = create_access_token(data={"sub": test_vendor.contact_email, "vendor_id": test_vendor.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="function")
def driver_auth_headers(test_driver) -> Dict[str, str]:
    """Get authentication headers for driver"""
    token = create_access_token(data={"sub": test_driver.email, "driver_id": test_driver.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="function")
def test_customer(db_session) -> Customer:
    """Create a test customer for contract tests.
    Also creates a matching User record because many endpoints use
    Depends(get_current_user) which queries the users table by email.
    """
    email = f"customer_{datetime.now().timestamp()}@test.com"
    # Create matching User record (needed for get_current_user lookups)
    user = User(
        email=email,
        password_hash=get_password_hash("CustomerPassword123!"),
        full_name="Test Customer",
        role=UserRole.USER,
    )
    db_session.add(user)
    db_session.flush()

    customer = Customer(
        email=email,
        password_hash=get_password_hash("CustomerPassword123!"),
        first_name="Test",
        last_name="Customer",
        phone="+14155551234",
        is_active=True,
    )
    db_session.add(customer)
    db_session.commit()
    db_session.refresh(customer)
    return customer


@pytest.fixture(scope="function")
def customer_auth_headers(test_customer) -> Dict[str, str]:
    """Get authentication headers for customer -- includes customer_id in JWT payload"""
    token = create_access_token(data={
        "sub": test_customer.email,
        "customer_id": test_customer.id
    })
    return {"Authorization": f"Bearer {token}"}


# Mock data factories
class UserFactory:
    """Factory for creating test users"""
    counter = 0

    @classmethod
    def create(cls, db_session, **kwargs) -> User:
        cls.counter += 1
        defaults = {
            "email": f"user_{cls.counter}_{datetime.now().timestamp()}@test.com",
            "password_hash": get_password_hash("Password123!"),
            "full_name": f"Test User {cls.counter}",
            "role": UserRole.USER,
        }
        defaults.update(kwargs)
        user = User(**defaults)
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        return user


class VendorFactory:
    """Factory for creating test vendors"""
    counter = 0

    @classmethod
    def create(cls, db_session, **kwargs) -> Vendor:
        cls.counter += 1
        defaults = {
            "company_name": f"Test Company {cls.counter}",
            "restaurant_name": f"Test Restaurant {cls.counter}",
            "contact_email": f"vendor_{cls.counter}_{datetime.now().timestamp()}@test.com",
            "contact_phone": f"+1415555{1000 + cls.counter}",
            "street": f"{100 + cls.counter} Test St",
            "city": "San Francisco",
            "state": "CA",
            "zip_code": "94102",
            "onboarding_status": VendorStatus.PENDING,
        }
        defaults.update(kwargs)
        vendor = Vendor(**defaults)
        db_session.add(vendor)
        db_session.commit()
        db_session.refresh(vendor)
        return vendor


class DriverFactory:
    """Factory for creating test drivers"""
    counter = 0

    @classmethod
    def create(cls, db_session, **kwargs) -> Driver:
        cls.counter += 1
        defaults = {
            "email": f"driver_{cls.counter}_{datetime.now().timestamp()}@test.com",
            "password_hash": get_password_hash("DriverPass123!"),
            "name": f"Test Driver {cls.counter}",
            "phone": f"+1415555{2000 + cls.counter}",
            "status": "pending",
        }
        defaults.update(kwargs)
        driver = Driver(**defaults)
        db_session.add(driver)
        db_session.commit()
        db_session.refresh(driver)
        return driver


@pytest.fixture
def user_factory():
    """Get user factory"""
    return UserFactory


@pytest.fixture
def vendor_factory():
    """Get vendor factory"""
    return VendorFactory


@pytest.fixture
def driver_factory():
    """Get driver factory"""
    return DriverFactory


# Test data helpers
@pytest.fixture
def sample_user_data() -> Dict[str, Any]:
    """Sample user registration data"""
    return {
        "email": f"sample_{datetime.now().timestamp()}@test.com",
        "password": "SamplePassword123!",
        "full_name": "Sample User",
        "role": "user",
    }


@pytest.fixture
def sample_vendor_data() -> Dict[str, Any]:
    """Sample vendor registration data"""
    return {
        "restaurant_name": "Sample Restaurant",
        "cuisine_type": "Italian",
        "contact_name": "John Owner",
        "contact_email": f"restaurant_{datetime.now().timestamp()}@test.com",
        "contact_phone": "+14155559999",
        "password": "RestaurantPass123!",
        "street_address": "456 Main St",
        "city": "San Francisco",
        "state": "CA",
        "zip_code": "94102",
        "description": "A great Italian restaurant",
    }


@pytest.fixture
def sample_driver_data() -> Dict[str, Any]:
    """Sample driver registration data"""
    return {
        "email": f"newdriver_{datetime.now().timestamp()}@test.com",
        "password": "DriverPass123!",
        "name": "New Driver",
        "phone": "+14155558888",
    }
