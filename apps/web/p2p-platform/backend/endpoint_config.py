#!/usr/bin/env python3
"""
================================================================================
DOLLOR.AI - DYNAMIC ENDPOINT CONFIGURATION
================================================================================
Version: 1.0.0
Date: 2026-01-10

This module provides dynamic endpoint discovery from the production OpenAPI spec.
It ensures tests always use the correct endpoints that actually exist.

Usage:
    from endpoint_config import EndpointConfig
    config = EndpointConfig(environment="production")
    endpoint = config.get_endpoint("chat_send")
================================================================================
"""

import os

import requests
import json
from typing import Dict, Optional, List
from dataclasses import dataclass
from enum import Enum
import re


class Environment(Enum):
    PRODUCTION = "https://api.dollor.ai"
    # Local development only: set LOCAL_API_URL to the base URL of a backend you run yourself
    LOCAL = os.getenv("LOCAL_API_URL", "")


@dataclass
class EndpointInfo:
    """Information about a discovered endpoint"""
    path: str
    method: str
    summary: str = ""
    requires_auth: bool = True
    expected_statuses: List[int] = None

    def __post_init__(self):
        if self.expected_statuses is None:
            self.expected_statuses = [200, 401, 403, 404, 422]


class EndpointConfig:
    """
    Dynamic endpoint configuration that discovers available endpoints
    from the production OpenAPI specification.
    """

    def __init__(self, environment: str = "production"):
        self.environment = environment
        self.base_url = Environment[environment.upper()].value
        self._endpoints: Dict[str, EndpointInfo] = {}
        self._openapi_cache: Dict = {}
        self._load_openapi()
        self._build_endpoint_map()

    def _load_openapi(self) -> None:
        """Load OpenAPI specification from the API"""
        try:
            resp = requests.get(f"{self.base_url}/openapi.json", timeout=30)
            if resp.status_code == 200:
                self._openapi_cache = resp.json()
            else:
                print(f"Warning: Could not load OpenAPI spec: {resp.status_code}")
                self._openapi_cache = {"paths": {}}
        except Exception as e:
            print(f"Warning: Failed to load OpenAPI: {e}")
            self._openapi_cache = {"paths": {}}

    def _build_endpoint_map(self) -> None:
        """Build a mapping of logical endpoint names to actual endpoints"""
        paths = self._openapi_cache.get("paths", {})

        # Map logical names to endpoint patterns
        endpoint_patterns = {
            # Authentication
            "customer_login": (r"/api/auth/customer/login", "POST"),
            "customer_register": (r"/api/auth/customer/register", "POST"),
            "customer_refresh": (r"/api/auth/customer/refresh", "POST"),
            "driver_login": (r"/api/auth/driver/login", "POST"),
            "vendor_login": (r"/api/auth/vendor/login", "POST"),

            # Chat
            "chat_send": (r"/api/chat/send", "POST"),
            "chat_messages": (r"/api/chat/messages/\{order_id\}", "GET"),
            "chat_conversation": (r"/api/chat/conversation/\{order_id\}", "GET"),

            # Rideshare/Bids
            "rideshare_bid_submit": (r"/api/rides/request/\{request_id\}/bid", "POST"),
            "rideshare_bids_list": (r"/api/rides/request/\{request_id\}/bids", "GET"),
            "rideshare_bid_respond": (r"/api/rides/bid/\{bid_id\}/respond", "POST"),
            "rideshare_bid_withdraw": (r"/api/rides/bid/\{bid_id\}/withdraw", "POST"),

            # Payments
            "payment_ride_intent": (r"/api/payments/ride/create-intent", "POST"),

            # Promotions
            "promotions_apply": (r"/api/promotions/apply", "POST"),
            "promotions_featured": (r"/api/promotions/featured", "GET"),
            "promotions_active": (r"/api/promotions/active", "GET"),
            "cart_apply_promo": (r"/api/cart/apply-promo", "POST"),

            # Vendors
            "vendors_published": (r"/api/vendors/published", "GET"),
            "vendor_get": (r"/api/vendors/\{vendor_id\}", "GET"),
            "vendor_menu": (r"/api/vendors/\{vendor_id\}/menu", "GET"),

            # Restaurants (ERP)
            "restaurants_nearby": (r"/api/erp/restaurants/nearby", "GET"),

            # Orders
            "orders_create": (r"/api/orders", "POST"),
            "order_get": (r"/api/orders/\{order_id\}", "GET"),
            "order_schedule": (r"/api/orders/schedule", "POST"),

            # Health
            "health": (r"/health", "GET"),
            "api_health": (r"/api/health", "GET"),
            "config": (r"/api/config", "GET"),
        }

        for name, (pattern, method) in endpoint_patterns.items():
            # Find matching endpoint in OpenAPI
            for path, methods in paths.items():
                # Convert OpenAPI path params to regex
                regex_pattern = pattern.replace(r"\{", "{").replace(r"\}", "}")
                if re.match(f"^{regex_pattern}$", path.replace("{", r"\{").replace("}", r"\}")):
                    if method.lower() in methods:
                        info = methods[method.lower()]
                        self._endpoints[name] = EndpointInfo(
                            path=path,
                            method=method,
                            summary=info.get("summary", ""),
                            requires_auth="security" in info
                        )
                        break

            # If not found via regex, try direct match
            if name not in self._endpoints:
                direct_path = pattern.replace(r"\{", "{").replace(r"\}", "}")
                if direct_path in paths and method.lower() in paths[direct_path]:
                    info = paths[direct_path][method.lower()]
                    self._endpoints[name] = EndpointInfo(
                        path=direct_path,
                        method=method,
                        summary=info.get("summary", ""),
                        requires_auth="security" in info
                    )

    def get_endpoint(self, name: str) -> Optional[EndpointInfo]:
        """Get endpoint info by logical name"""
        return self._endpoints.get(name)

    def get_path(self, name: str, **params) -> Optional[str]:
        """Get endpoint path with parameters substituted"""
        endpoint = self._endpoints.get(name)
        if not endpoint:
            return None

        path = endpoint.path
        for key, value in params.items():
            path = path.replace(f"{{{key}}}", str(value))
        return path

    def endpoint_exists(self, path: str, method: str = "GET") -> bool:
        """Check if an endpoint exists in the OpenAPI spec"""
        paths = self._openapi_cache.get("paths", {})
        return path in paths and method.lower() in paths[path]

    def find_endpoints(self, pattern: str) -> List[str]:
        """Find all endpoints matching a pattern"""
        paths = self._openapi_cache.get("paths", {})
        return [p for p in paths.keys() if pattern.lower() in p.lower()]

    def get_all_endpoints(self) -> Dict[str, EndpointInfo]:
        """Get all discovered endpoints"""
        return self._endpoints.copy()

    def print_summary(self) -> None:
        """Print a summary of discovered endpoints"""
        print(f"\n{'='*60}")
        print(f"ENDPOINT CONFIGURATION - {self.environment.upper()}")
        print(f"{'='*60}")
        print(f"Base URL: {self.base_url}")
        print(f"Total OpenAPI endpoints: {len(self._openapi_cache.get('paths', {}))}")
        print(f"Mapped endpoints: {len(self._endpoints)}")
        print(f"\nMapped Endpoints:")
        for name, info in sorted(self._endpoints.items()):
            print(f"  {name}: {info.method} {info.path}")
        print(f"{'='*60}\n")


# Pre-defined expected status codes for different endpoint types
EXPECTED_STATUSES = {
    "auth": [200, 400, 401, 422, 429],
    "protected": [200, 401, 403, 404, 422],
    "public": [200, 404],
    "create": [200, 201, 400, 401, 422],
    "validation": [200, 400, 422],
}


def get_expected_statuses(endpoint_type: str) -> List[int]:
    """Get expected HTTP status codes for an endpoint type"""
    return EXPECTED_STATUSES.get(endpoint_type, [200, 401, 403, 404, 422])


# Singleton instance for easy access
_config_instance: Optional[EndpointConfig] = None


def get_config(environment: str = "production") -> EndpointConfig:
    """Get or create the endpoint configuration singleton"""
    global _config_instance
    if _config_instance is None or _config_instance.environment != environment:
        _config_instance = EndpointConfig(environment)
    return _config_instance


if __name__ == "__main__":
    # Test the configuration
    import argparse

    parser = argparse.ArgumentParser(description="Test endpoint configuration")
    parser.add_argument("--env", choices=["production", "staging", "local"],
                       default="production", help="Environment to test")
    args = parser.parse_args()

    config = EndpointConfig(args.env)
    config.print_summary()

    # Test some endpoint lookups
    print("Testing endpoint lookups:")
    test_endpoints = ["chat_send", "rideshare_bid_submit", "promotions_apply", "vendors_published"]
    for name in test_endpoints:
        endpoint = config.get_endpoint(name)
        if endpoint:
            print(f"  ✅ {name}: {endpoint.method} {endpoint.path}")
        else:
            print(f"  ❌ {name}: NOT FOUND")
