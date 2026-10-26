"""One active session per driver: a new login revokes the previous token."""
import cache


def test_second_login_revokes_first(monkeypatch):
    monkeypatch.setattr(cache, "redis_client", None)
    cache._active_sessions.clear()
    cache._revoked_tokens.clear()

    cache.rotate_active_session("driver:1", "jti-phone-a", 3600)
    assert not cache.is_token_blacklisted("jti-phone-a")

    cache.rotate_active_session("driver:1", "jti-phone-b", 3600)
    assert cache.is_token_blacklisted("jti-phone-a")
    assert not cache.is_token_blacklisted("jti-phone-b")


def test_other_drivers_are_independent(monkeypatch):
    monkeypatch.setattr(cache, "redis_client", None)
    cache._active_sessions.clear()
    cache._revoked_tokens.clear()

    cache.rotate_active_session("driver:1", "a", 3600)
    cache.rotate_active_session("driver:2", "b", 3600)
    assert not cache.is_token_blacklisted("a")
    assert not cache.is_token_blacklisted("b")


def test_same_token_is_not_revoked_on_repeat(monkeypatch):
    monkeypatch.setattr(cache, "redis_client", None)
    cache._active_sessions.clear()
    cache._revoked_tokens.clear()

    cache.rotate_active_session("driver:1", "same", 3600)
    cache.rotate_active_session("driver:1", "same", 3600)
    assert not cache.is_token_blacklisted("same")
