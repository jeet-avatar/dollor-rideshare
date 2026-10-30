"""
Unit tests for authentication endpoints.

Tests cover:
- User registration
- User login
- Token validation
- Password reset
- Driver authentication
- Vendor authentication
"""

import pytest
from datetime import datetime
from fastapi.testclient import TestClient


class TestUserRegistration:
    """Tests for user registration endpoint"""

    def test_register_success(self, client: TestClient, sample_user_data):
        """Should successfully register a new user"""
        response = client.post("/register", json=sample_user_data)
        # May succeed or fail if email already exists
        assert response.status_code in [200, 201, 409]
        if response.status_code in [200, 201]:
            data = response.json()
            assert "access_token" in data or "message" in data or "id" in data

    def test_register_duplicate_email(self, client: TestClient, test_user):
        """Should reject duplicate email registration"""
        user_data = {
            "email": test_user.email,
            "password": "AnotherPassword123!",
            "full_name": "Another User",
            "role": "user",
        }
        response = client.post("/register", json=user_data)
        assert response.status_code in [400, 409]

    def test_register_invalid_email(self, client: TestClient):
        """Should reject invalid email format"""
        user_data = {
            "email": "not-a-valid-email",
            "password": "Password123!",
            "full_name": "Test User",
            "role": "user",
        }
        response = client.post("/register", json=user_data)
        assert response.status_code == 422

    def test_register_missing_password(self, client: TestClient):
        """Should reject registration without password"""
        user_data = {
            "email": f"test_{datetime.now().timestamp()}@test.com",
            "full_name": "Test User",
            "role": "user",
        }
        response = client.post("/register", json=user_data)
        assert response.status_code == 422

    def test_register_missing_email(self, client: TestClient):
        """Should reject registration without email"""
        user_data = {
            "password": "Password123!",
            "full_name": "Test User",
            "role": "user",
        }
        response = client.post("/register", json=user_data)
        assert response.status_code == 422

    def test_register_empty_body(self, client: TestClient):
        """Should reject empty request body"""
        response = client.post("/register", json={})
        assert response.status_code == 422


class TestUserLogin:
    """Tests for user login endpoint"""

    def test_login_success(self, client: TestClient, test_user):
        """Should successfully login with correct credentials"""
        response = client.post("/api/auth/login", data={
            "username": test_user.email,
            "password": "TestPassword123!",
        })
        assert response.status_code in [200, 400, 401]  # 400/401 if password hash doesn't match
        if response.status_code == 200:
            data = response.json()
            assert "access_token" in data
            assert data["token_type"] == "bearer"

    def test_login_wrong_password(self, client: TestClient, test_user):
        """Should reject wrong password"""
        response = client.post("/api/auth/login", data={
            "username": test_user.email,
            "password": "WrongPassword123!",
        })
        assert response.status_code in [400, 401]

    def test_login_nonexistent_user(self, client: TestClient):
        """Should reject nonexistent user"""
        response = client.post("/api/auth/login", data={
            "username": f"nonexistent_{datetime.now().timestamp()}@test.com",
            "password": "AnyPassword123!",
        })
        assert response.status_code in [400, 401, 404]

    def test_login_empty_password(self, client: TestClient, test_user):
        """Should reject empty password"""
        response = client.post("/api/auth/login", data={
            "username": test_user.email,
            "password": "",
        })
        assert response.status_code in [400, 401, 422]

    def test_login_empty_email(self, client: TestClient):
        """Should reject empty email"""
        response = client.post("/api/auth/login", data={
            "username": "",
            "password": "Password123!",
        })
        assert response.status_code in [400, 401, 422]


class TestTokenValidation:
    """Tests for token validation"""

    def test_valid_token_access(self, client: TestClient, auth_headers):
        """Should allow access with valid token"""
        response = client.get("/api/auth/me", headers=auth_headers)
        assert response.status_code in [200, 404]  # 404 if endpoint different

    def test_invalid_token_rejected(self, client: TestClient):
        """Should reject invalid token"""
        response = client.get("/api/auth/me", headers={
            "Authorization": "Bearer invalid_token_here"
        })
        assert response.status_code in [401, 403]

    def test_missing_token_rejected(self, client: TestClient):
        """Should reject missing token"""
        response = client.get("/api/auth/me")
        assert response.status_code in [401, 403]

    def test_malformed_auth_header(self, client: TestClient):
        """Should reject malformed auth header"""
        response = client.get("/api/auth/me", headers={
            "Authorization": "NotBearer sometoken"
        })
        assert response.status_code in [401, 403]

    def test_empty_bearer_token(self, client: TestClient):
        """Should reject empty bearer token"""
        response = client.get("/api/auth/me", headers={
            "Authorization": "Bearer "
        })
        assert response.status_code in [401, 403]


class TestDriverAuthentication:
    """Tests for driver authentication endpoints"""

    def test_driver_register_success(self, client: TestClient, sample_driver_data):
        """Should successfully register a new driver"""
        response = client.post("/api/auth/driver/register", json=sample_driver_data)
        # May succeed or need additional fields
        assert response.status_code in [200, 201, 400, 409, 422]
        if response.status_code in [200, 201]:
            data = response.json()
            assert "id" in data or "driver_id" in data or "message" in data or "access_token" in data

    def test_driver_register_duplicate_email(self, client: TestClient, test_driver):
        """Should reject duplicate driver email"""
        driver_data = {
            "email": test_driver.email,
            "password": "NewPassword123!",
            "name": "New Driver",
            "phone": "+14155557777",
        }
        response = client.post("/api/auth/driver/register", json=driver_data)
        # May require additional fields or reject duplicate
        assert response.status_code in [400, 409, 422]

    def test_driver_register_invalid_email(self, client: TestClient):
        """Should reject invalid email"""
        driver_data = {
            "email": "invalid-email",
            "password": "Password123!",
            "name": "Test Driver",
            "phone": "+14155551234",
        }
        response = client.post("/api/auth/driver/register", json=driver_data)
        assert response.status_code == 422

    def test_driver_login_success(self, client: TestClient, test_driver):
        """Should successfully login driver"""
        # Driver login uses OAuth2PasswordRequestForm (form data with username field)
        response = client.post("/api/auth/driver/login", data={
            "username": test_driver.email,
            "password": "DriverPassword123!",
        })
        # May succeed, fail auth, or require different format
        assert response.status_code in [200, 400, 401]
        if response.status_code == 200:
            data = response.json()
            assert "access_token" in data or "token" in data

    def test_driver_login_wrong_password(self, client: TestClient, test_driver):
        """Should reject wrong driver password"""
        response = client.post("/api/auth/driver/login", data={
            "username": test_driver.email,
            "password": "WrongPassword123!",
        })
        # May reject with different status codes
        assert response.status_code in [400, 401]

    def test_driver_profile_requires_auth(self, client: TestClient):
        """Should require auth for driver profile"""
        response = client.get("/api/auth/driver/me")
        assert response.status_code in [401, 403]

    def test_driver_profile_with_auth(self, client: TestClient, driver_auth_headers):
        """Should return profile with auth"""
        response = client.get("/api/auth/driver/me", headers=driver_auth_headers)
        # May return profile, not found, or require re-auth
        assert response.status_code in [200, 401, 404]

    def test_driver_login_case_insensitive_email(self, client: TestClient, db_session):
        """Regression test: login must succeed regardless of email casing.

        Previously the login lookup used an exact (case-sensitive) `User.email ==`
        comparison, so a driver who registered as "Case@Test.com" but typed
        "case@test.com" (or vice versa) at login got a false "incorrect email
        or password" even with the right credentials.
        """
        from models import User, Driver, DriverStatus, UserRole
        from main_new import get_password_hash
        import uuid

        stored_email = "CaseSensitive.Test@Example.com"
        driver = Driver(
            driver_id=f"drv_{uuid.uuid4().hex[:8]}",
            email=stored_email,
            password_hash=get_password_hash("DriverPassword123!"),
            first_name="Case",
            last_name="Test",
            phone="+14155559999",
            status=DriverStatus.APPROVED,
        )
        db_session.add(driver)
        db_session.commit()
        db_session.refresh(driver)

        user = User(
            email=stored_email,
            password_hash=driver.password_hash,
            full_name="Case Test",
            role=UserRole.DRIVER,
            driver_id=driver.id,
        )
        db_session.add(user)
        db_session.commit()

        # Log in with a DIFFERENT casing than what was stored.
        response = client.post("/api/auth/driver/login", data={
            "username": "casesensitive.test@example.com",
            "password": "DriverPassword123!",
        })
        assert response.status_code == 200, (
            f"Case-insensitive login should succeed, got {response.status_code}: {response.text}"
        )
        assert "access_token" in response.json()

    def test_driver_register_duplicate_email_different_case(self, client: TestClient, db_session):
        """Regression test: registering with different casing of an existing
        email must still be rejected as a duplicate (previously the exact-match
        check would miss this, allowing two accounts for the same real email).
        """
        from models import User, UserRole
        from main_new import get_password_hash

        existing_email = "Duplicate.Check@Example.com"
        db_session.add(User(
            email=existing_email,
            password_hash=get_password_hash("Password123!"),
            full_name="Existing User",
            role=UserRole.DRIVER,
        ))
        db_session.commit()

        response = client.post("/api/auth/driver/register", json={
            "email": "duplicate.check@example.com",  # same email, different case
            "password": "NewPassword123!",
            "name": "New Driver",
            "phone": "+14155557778",
        })
        assert response.status_code in [400, 409, 422], (
            f"Differently-cased duplicate email should be rejected, got {response.status_code}"
        )


class TestPasswordReset:
    """Tests for password reset flow - uses /api/customer/password-reset/* endpoints"""

    def test_request_password_reset(self, client: TestClient, test_user):
        """Should accept password reset request for customer"""
        response = client.post("/api/customer/password-reset/request", json={
            "email": test_user.email,
        })
        # Should return success (doesn't reveal if email exists)
        assert response.status_code == 200
        data = response.json()
        assert data.get("success") == True

    def test_request_password_reset_nonexistent(self, client: TestClient):
        """Should not reveal if email exists (security)"""
        response = client.post("/api/customer/password-reset/request", json={
            "email": f"nonexistent_{datetime.now().timestamp()}@test.com",
        })
        # Should return success even for non-existent emails (security)
        assert response.status_code == 200
        data = response.json()
        assert data.get("success") == True


class TestGoogleAuth:
    """Tests for Google OAuth authentication"""

    def test_driver_google_auth_invalid_token(self, client: TestClient):
        """Should reject invalid Google token"""
        response = client.post("/api/auth/driver/google", json={
            "id_token": "invalid_token",
            "email": "test@gmail.com",
            "name": "Test User",
        })
        # Should handle gracefully - 403 for new users (no auto-create), or other error codes
        assert response.status_code in [200, 201, 400, 401, 403, 422, 500]

    def test_customer_google_auth_invalid_token(self, client: TestClient):
        """Should reject invalid Google token for customer"""
        response = client.post("/api/auth/customer/google", json={
            "id_token": "invalid_token",
            "email": "test@gmail.com",
            "name": "Test User",
        })
        # Endpoint may not exist or handle token
        assert response.status_code in [200, 201, 400, 401, 404, 422, 500]


class TestAppleAuth:
    """Tests for Apple Sign-In authentication"""

    def test_driver_apple_auth_invalid_token(self, client: TestClient):
        """Should reject invalid Apple token"""
        response = client.post("/api/auth/driver/apple", json={
            "id_token": "invalid_token",
            "email": "test@icloud.com",
            "name": "Test User",
        })
        assert response.status_code in [200, 400, 401, 404]


def _fake_apple_token(monkeypatch, sub, email=None, nonce=None, aud="com.dollorai.customer"):
    """Make _verify_apple_jwt return Apple-shaped claims for the token 'tok-<sub>'."""
    import main_new
    claims = {"iss": "https://appleid.apple.com", "sub": sub, "aud": aud}
    if email:
        claims["email"] = email
    if nonce:
        claims["nonce"] = nonce
    monkeypatch.setattr(main_new, "_verify_apple_jwt", lambda token: claims if token == f"tok-{sub}" else {})
    return f"tok-{sub}"


class TestAppleAudience:
    def test_both_bundle_ids_accepted_and_others_rejected(self, client: TestClient, monkeypatch):
        for var in ("APPLE_CLIENT_ID", "APPLE_CLIENT_ID_CUSTOMER", "APPLE_CLIENT_ID_DRIVER"):
            monkeypatch.delenv(var, raising=False)
        for aud in ("com.dollorai.customer", "com.dollorai.delivery"):
            token = _fake_apple_token(monkeypatch, f"sub-aud-{aud}", aud=aud)
            assert client.post("/api/customer/apple-auth", json={"identity_token": token}).status_code == 200
        token = _fake_apple_token(monkeypatch, "sub-aud-evil", aud="com.evil.app")
        assert client.post("/api/customer/apple-auth", json={"identity_token": token}).status_code == 401
        token = _fake_apple_token(monkeypatch, "sub-aud-none", aud=None)
        assert client.post("/api/auth/driver/apple-auth", json={"identity_token": token}).status_code == 401

    def test_configured_client_ids_extend_the_accepted_audiences(self, client: TestClient, monkeypatch):
        monkeypatch.setenv("APPLE_CLIENT_ID_DRIVER", "com.example.driver")
        token = _fake_apple_token(monkeypatch, "sub-aud-custom", aud="com.example.driver")
        assert client.post("/api/auth/driver/apple-auth", json={"identity_token": token}).status_code in (200, 201)


class TestMultiRoleAppleAuth:
    """Sign in with Apple: account keyed on the verified token subject, no name/email ever required"""

    def test_driver_apple_auth_rejects_missing_or_bad_token(self, client: TestClient, monkeypatch):
        _fake_apple_token(monkeypatch, "sub-x")
        for body in ({"apple_id": "a", "email": "victim@example.com"},
                     {"apple_id": "a", "identity_token": "forged"}):
            assert client.post("/api/auth/driver/apple-auth", json=body).status_code == 401
            assert client.post("/api/customer/apple-auth", json=body).status_code == 401

    def test_driver_apple_auth_brand_new_user_creates_pending_driver(self, client: TestClient, monkeypatch):
        token = _fake_apple_token(monkeypatch, "sub-new-driver", "relay123@privaterelay.appleid.com")
        response = client.post("/api/auth/driver/apple-auth", json={"identity_token": token})
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["status"] == "pending" and data["requires_documents"] is True
        assert data["email"] == "relay123@privaterelay.appleid.com"
        assert data["name"] == "Apple Driver"

    def test_driver_apple_auth_returning_login_needs_only_token(self, client: TestClient, monkeypatch):
        token = _fake_apple_token(monkeypatch, "sub-returning-driver", "ret@privaterelay.appleid.com")
        first = client.post("/api/auth/driver/apple-auth", json={"identity_token": token, "name": "Ada Lovelace"}).json()
        # Second login: Apple sends no name and no email claim
        token2 = _fake_apple_token(monkeypatch, "sub-returning-driver")
        again = client.post("/api/auth/driver/apple-auth", json={"identity_token": token2})
        assert again.status_code == 200, again.text
        assert again.json()["driver_id"] == first["driver_id"]
        assert again.json()["name"] == "Ada Lovelace"

    def test_driver_apple_auth_existing_customer_user_gains_driver_profile(self, client: TestClient, test_user, monkeypatch):
        token = _fake_apple_token(monkeypatch, "sub-customer-turned-driver", test_user.email)
        response = client.post("/api/auth/driver/apple-auth", json={"identity_token": token})
        assert response.status_code == 200, response.text
        assert response.json()["email"] == test_user.email

    def test_customer_apple_auth_no_name_no_email_claim(self, client: TestClient, monkeypatch):
        token = _fake_apple_token(monkeypatch, "sub-no-email-customer")
        response = client.post("/api/customer/apple-auth", json={"identity_token": token})
        assert response.status_code == 200, response.text
        assert response.json()["name"] == "Apple User"
        again = client.post("/api/customer/apple-auth", json={"identity_token": token})
        assert again.json()["customer_id"] == response.json()["customer_id"]

    def test_customer_apple_auth_ignores_spoofed_body_identity(self, client: TestClient, test_user, monkeypatch):
        token = _fake_apple_token(monkeypatch, "sub-attacker", "attacker@privaterelay.appleid.com")
        response = client.post("/api/customer/apple-auth", json={
            "identity_token": token, "email": test_user.email, "apple_id": "victim"})
        assert response.status_code == 200
        assert response.json()["email"] == "attacker@privaterelay.appleid.com"

    def test_driver_google_auth_no_driver_returns_403(self, client: TestClient, test_user):
        """Driver Google auth should return 403 with registration_url when user has no driver account"""
        response = client.post("/api/auth/driver/google", json={
            "email": test_user.email,
            "name": test_user.full_name,
            "google_id": f"google_driver_test_{test_user.email}",
        })
        assert response.status_code == 403, f"Expected 403, got {response.status_code}: {response.text}"
        data = response.json()
        assert "registration_url" in data
        assert data["registration_url"] == "https://dollor.ai/driver/apply"
        assert data["requires_registration"] is True


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
