"""
Dollor.ai - Standardized Authentication Utilities
===================================================

Provides reusable auth dependencies for FastAPI endpoints and routers.

Usage:
    # Router-level (all endpoints in router require valid JWT):
    app.include_router(my_router, dependencies=[Depends(require_any_auth)])

    # Per-endpoint (specific role required):
    @router.get("/my-endpoint")
    async def my_endpoint(customer: Customer = Depends(require_customer)):
        ...

    # Lightweight JWT-only check (no DB query):
    @router.post("/my-endpoint")
    async def my_endpoint(payload: dict = Depends(require_any_auth)):
        ...
"""

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import jwt, JWTError
import os
import logging

from database import get_db
from models import User, UserRole, Customer, Driver, Vendor
from cache import is_account_revoked, is_token_blacklisted

logger = logging.getLogger(__name__)

# OAuth2 scheme with auto_error=False so we can provide better error messages
# (distinguishing "no token" from "invalid token")
_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login", auto_error=False)

# JWT config - same values as main_new.py
_SECRET_KEY = os.getenv("JWT_SECRET_KEY", "")
_ALGORITHM = "HS256"

# Email domain of anonymised (deleted) accounts, see account_deletion.py
DELETED_EMAIL_SUFFIX = "@deleted.invalid"


def _reject_if_deleted(role: str, account):
    """401 for an account that was deleted (anonymised) in-app; otherwise return it unchanged."""
    if is_account_revoked(role, account.id) or (account.email or "").endswith(DELETED_EMAIL_SUFFIX):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Account has been deleted",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return account


async def require_any_auth(token: str = Depends(_oauth2_scheme)) -> dict:
    """
    Require a valid JWT token. Any role accepted.

    Returns the JWT payload dict (not a DB object) for lightweight auth checks.
    Use this for router-level dependencies or endpoints that accept any authenticated user.

    Raises:
        HTTPException 401 if no token or invalid/expired token.
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
        sub = payload.get("sub")
        if not sub:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: missing subject",
                headers={"WWW-Authenticate": "Bearer"},
            )
        # G3: Check token blacklist (logout/revocation)
        jti = payload.get("jti")
        if jti and is_token_blacklisted(jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked",
                headers={"WWW-Authenticate": "Bearer"},
            )
        # Account deletion revokes every token of the deleted customer/driver
        if is_account_revoked("customer", payload.get("customer_id")) or is_account_revoked("driver", payload.get("driver_id")):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Account has been deleted",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return payload
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def require_customer(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> Customer:
    """
    Require a valid customer JWT. Returns the Customer ORM object.

    Raises:
        HTTPException 401 if not authenticated or not a customer.
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
        jti = payload.get("jti")
        if jti and is_token_blacklisted(jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # M4: Reject tokens that carry a role claim for a different role
        token_role = payload.get("role")
        if token_role and token_role != "customer":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Customer token required",
            )

        # Try customer_id first (set during customer registration)
        customer_id = payload.get("customer_id")
        if customer_id:
            customer = db.query(Customer).filter(Customer.id == customer_id).first()
            if customer:
                return _reject_if_deleted("customer", customer)

        # Fallback to email
        email = payload.get("sub")
        if email:
            customer = db.query(Customer).filter(Customer.email == email).first()
            if customer:
                return _reject_if_deleted("customer", customer)

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Customer account not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def require_driver(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> Driver:
    """
    Require a valid driver JWT. Returns the Driver ORM object.

    Raises:
        HTTPException 401 if not authenticated or not a driver.
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
        jti = payload.get("jti")
        if jti and is_token_blacklisted(jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # M4: Reject tokens that carry a role claim for a different role
        token_role = payload.get("role")
        if token_role and token_role != "driver":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Driver token required",
            )

        # Try driver_id first
        driver_id = payload.get("driver_id")
        if driver_id:
            if isinstance(driver_id, int):
                driver = db.query(Driver).filter(Driver.id == driver_id).first()
            else:
                driver = db.query(Driver).filter(Driver.driver_id == driver_id).first()
            if driver:
                return _reject_if_deleted("driver", driver)

        # Fallback to email
        email = payload.get("sub")
        if email:
            driver = db.query(Driver).filter(Driver.email == email).first()
            if driver:
                return _reject_if_deleted("driver", driver)

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Driver account not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def require_vendor(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> Vendor:
    """
    Require a valid vendor JWT. Returns the Vendor ORM object.

    Raises:
        HTTPException 401 if not authenticated or not a vendor.
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
        jti = payload.get("jti")
        if jti and is_token_blacklisted(jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Try vendor_id first
        vendor_id = payload.get("vendor_id")
        if vendor_id:
            vendor = db.query(Vendor).filter(Vendor.id == vendor_id).first()
            if vendor:
                return vendor

        # Fallback to email (Vendor uses contact_email)
        email = payload.get("sub")
        if email:
            vendor = db.query(Vendor).filter(Vendor.contact_email == email).first()
            if vendor:
                return vendor

        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Vendor account not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )


async def require_admin(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """
    Require a valid admin JWT. Returns the User ORM object with admin role.

    Raises:
        HTTPException 401 if not authenticated.
        HTTPException 403 if authenticated but not admin.
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        payload = jwt.decode(token, _SECRET_KEY, algorithms=[_ALGORITHM])
        jti = payload.get("jti")
        if jti and is_token_blacklisted(jti):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked",
                headers={"WWW-Authenticate": "Bearer"},
            )
        email = payload.get("sub")
        if not email:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token",
                headers={"WWW-Authenticate": "Bearer"},
            )

        user = db.query(User).filter(User.email == email).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
                headers={"WWW-Authenticate": "Bearer"},
            )

        if user.role != UserRole.ADMIN:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admin privileges required",
            )

        return user
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
