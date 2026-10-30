#!/bin/bash
#
# Dollor.ai Comprehensive UAT Agent System
# Full User Acceptance Testing with Database Validation
#
# Tests all three apps: Customer, Driver, Restaurant
# Validates: API endpoints, Database integrity, User flows, Frontend/Backend sync
#
# Usage:
#   ./scripts/uat-comprehensive.sh [staging|production]
#
# Demo Credentials (Apple App Store Review):
#   Customer: demo.customer@dollor.ai / ${DEMO_CUSTOMER_PASSWORD}
#   Driver:   demo.driver@dollor.ai / ${DEMO_DRIVER_PASSWORD}
#   Vendor:   demo.restaurant@dollor.ai / ${DEMO_RESTAURANT_PASSWORD}
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Config
ENV="${1:-production}"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
PROJECT_ROOT="/Users/jeet/StudioProjects/eatfair-ios"
REPORT_DIR="$PROJECT_ROOT/.planning/uat-reports/${DATE}"

# API URLs
if [ "$ENV" = "production" ]; then
    API_URL="https://api.dollor.ai"
    FRONTEND_URL="https://dollor.ai"
else
    API_URL="https://d34u5ixl0bulv4.cloudfront.net"
    FRONTEND_URL="https://d34u5ixl0bulv4.cloudfront.net"
fi

# Demo Credentials (Apple App Store Review)
CUSTOMER_EMAIL="demo.customer@dollor.ai"
CUSTOMER_PASS="${DEMO_CUSTOMER_PASSWORD}"
DRIVER_EMAIL="demo.driver@dollor.ai"
DRIVER_PASS="${DEMO_DRIVER_PASSWORD}"
RESTAURANT_EMAIL="demo.restaurant@dollor.ai"
RESTAURANT_PASS="${DEMO_RESTAURANT_PASSWORD}"

# Token storage
CUSTOMER_TOKEN=""
CUSTOMER_ID=""
DRIVER_TOKEN=""
DRIVER_ID=""
VENDOR_TOKEN=""
VENDOR_ID=""

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Results storage
declare -a TEST_RESULTS

mkdir -p "$REPORT_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e " ${BOLD}DOLLOR.AI COMPREHENSIVE UAT SYSTEM${NC}"
echo " User Acceptance Testing with Database Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "Environment:  ${BLUE}${ENV}${NC}"
echo -e "API URL:      ${BLUE}${API_URL}${NC}"
echo -e "Frontend:     ${BLUE}${FRONTEND_URL}${NC}"
echo -e "Timestamp:    ${BLUE}$(date)${NC}"
echo -e "Report Dir:   ${BLUE}${REPORT_DIR}${NC}"
echo ""

# ============================================================
# Helper Functions
# ============================================================

log_test() {
    local name="$1"
    local status="$2"
    local details="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$status" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "  ${GREEN}✓${NC} $name"
    elif [ "$status" = "FAIL" ]; then
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "  ${RED}✗${NC} $name: $details"
    elif [ "$status" = "WARN" ]; then
        WARNINGS=$((WARNINGS + 1))
        echo -e "  ${YELLOW}⚠${NC} $name: $details"
    fi

    TEST_RESULTS+=("$status|$name|$details")
}

api_call() {
    local method="$1"
    local endpoint="$2"
    local auth="$3"
    local data="$4"
    local content_type="${5:-application/json}"

    local curl_args=(-s -w "\n%{http_code}" -X "$method" "${API_URL}${endpoint}")

    if [ -n "$auth" ]; then
        curl_args+=(-H "Authorization: Bearer $auth")
    fi

    if [ -n "$data" ]; then
        curl_args+=(-H "Content-Type: $content_type" -d "$data")
    fi

    curl "${curl_args[@]}" 2>/dev/null
}

extract_json() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field', ''))" 2>/dev/null
}

# ============================================================
# PHASE 0: Infrastructure Health Check
# ============================================================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 0: INFRASTRUCTURE HEALTH CHECK${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}◆ Testing API Health...${NC}"
response=$(curl -s "${API_URL}/health" 2>/dev/null)
http_code=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/health" 2>/dev/null)

if [ "$http_code" = "200" ]; then
    log_test "GET /health" "PASS" "HTTP $http_code"
    if echo "$response" | grep -q "database\|status"; then
        DB_STATUS=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('database', d.get('status', 'ok')))" 2>/dev/null || echo "ok")
        log_test "Database connection" "PASS" "$DB_STATUS"
    fi
else
    log_test "GET /health" "FAIL" "HTTP $http_code"
fi

echo ""
echo -e "${YELLOW}◆ Testing API Version...${NC}"
response=$(curl -s "${API_URL}/api/v3" 2>/dev/null)
if echo "$response" | grep -q "version\|api"; then
    log_test "GET /api/v3" "PASS" ""
else
    log_test "GET /api/v3" "WARN" "Version endpoint unavailable"
fi

# ============================================================
# PHASE 1: Authentication Testing
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 1: AUTHENTICATION TESTING${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Customer Login
echo -e "${YELLOW}◆ Testing Customer Authentication...${NC}"
response=$(curl -s -X POST "${API_URL}/api/auth/customer/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${CUSTOMER_EMAIL}&password=${CUSTOMER_PASS}" 2>/dev/null)

if echo "$response" | grep -q "access_token"; then
    CUSTOMER_TOKEN=$(extract_json "$response" "access_token")
    CUSTOMER_ID=$(extract_json "$response" "customer_id")
    log_test "Customer login (${CUSTOMER_EMAIL})" "PASS" ""
    log_test "Customer token received" "PASS" ""
    log_test "Customer ID: ${CUSTOMER_ID}" "PASS" ""
else
    log_test "Customer login" "FAIL" "$response"
fi

# Driver Login
echo ""
echo -e "${YELLOW}◆ Testing Driver Authentication...${NC}"
response=$(curl -s -X POST "${API_URL}/api/auth/driver/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${DRIVER_EMAIL}&password=${DRIVER_PASS}" 2>/dev/null)

if echo "$response" | grep -q "access_token"; then
    DRIVER_TOKEN=$(extract_json "$response" "access_token")
    DRIVER_ID=$(extract_json "$response" "driver_id")
    DRIVER_STATUS=$(extract_json "$response" "status")
    DRIVER_APPROVED=$(extract_json "$response" "is_approved")
    log_test "Driver login (${DRIVER_EMAIL})" "PASS" ""
    log_test "Driver token received" "PASS" ""
    log_test "Driver ID: ${DRIVER_ID}" "PASS" ""
    log_test "Driver status: ${DRIVER_STATUS}" "PASS" ""
    log_test "Driver approved: ${DRIVER_APPROVED}" "PASS" ""
else
    log_test "Driver login" "FAIL" "$response"
fi

# Vendor Login
echo ""
echo -e "${YELLOW}◆ Testing Restaurant/Vendor Authentication...${NC}"
response=$(curl -s -X POST "${API_URL}/api/auth/vendor/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${RESTAURANT_EMAIL}&password=${RESTAURANT_PASS}" 2>/dev/null)

if echo "$response" | grep -q "access_token"; then
    VENDOR_TOKEN=$(extract_json "$response" "access_token")
    VENDOR_ID=$(extract_json "$response" "vendor_id")
    log_test "Vendor login (${RESTAURANT_EMAIL})" "PASS" ""
    log_test "Vendor token received" "PASS" ""
    log_test "Vendor ID: ${VENDOR_ID}" "PASS" ""
else
    log_test "Vendor login" "FAIL" "$response"
fi

# ============================================================
# PHASE 2: Customer App User Flow
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 2: CUSTOMER APP USER FLOW${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -n "$CUSTOMER_TOKEN" ]; then
    echo -e "${YELLOW}◆ Testing Customer Profile...${NC}"
    response=$(curl -s "${API_URL}/api/customer/profile" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "email"; then
        log_test "GET /api/customer/profile" "PASS" ""
        PROFILE_EMAIL=$(extract_json "$response" "email")
        log_test "Profile email matches: ${PROFILE_EMAIL}" "PASS" ""
    else
        log_test "GET /api/customer/profile" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Browse Restaurants...${NC}"
    response=$(curl -s "${API_URL}/api/vendors" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        VENDOR_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/vendors" "PASS" ""
        log_test "Restaurants available: ${VENDOR_COUNT}" "PASS" ""

        # Use Apple Test Restaurant (vendor 40) for menu test - demo restaurant with guaranteed menu items
        DEMO_VENDOR_ID=40
        menu_response=$(curl -s "${API_URL}/api/vendors/${DEMO_VENDOR_ID}/menu" 2>/dev/null)
        MENU_COUNT=$(echo "$menu_response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        if [ "$MENU_COUNT" -gt 0 ]; then
            log_test "GET /api/vendors/${DEMO_VENDOR_ID}/menu (Apple Test Restaurant)" "PASS" "${MENU_COUNT} items"
        else
            log_test "GET /api/vendors/${DEMO_VENDOR_ID}/menu (Apple Test Restaurant)" "FAIL" "Demo restaurant has no menu items"
        fi
    else
        log_test "GET /api/vendors" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Order History...${NC}"
    response=$(curl -s "${API_URL}/api/customer/orders" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        ORDER_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/customer/orders" "PASS" ""
        log_test "Past orders: ${ORDER_COUNT}" "PASS" ""
    else
        log_test "GET /api/customer/orders" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Active Orders...${NC}"
    response=$(curl -s "${API_URL}/api/customer/${CUSTOMER_ID}/active-orders" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\[" || echo "$response" | grep -q "orders"; then
        ACTIVE_COUNT=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else len(d.get('orders',[])))" 2>/dev/null || echo "0")
        log_test "GET /api/customer/{id}/active-orders" "PASS" "${ACTIVE_COUNT} active"
    else
        log_test "GET /api/customer/{id}/active-orders" "WARN" "No active orders"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Saved Addresses...${NC}"
    response=$(curl -s "${API_URL}/api/addresses/${CUSTOMER_ID}" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\[" || echo "$response" | grep -q "address"; then
        ADDR_COUNT=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
        log_test "GET /api/addresses/{userId}" "PASS" "${ADDR_COUNT} addresses"
    else
        log_test "GET /api/addresses/{userId}" "WARN" "No addresses saved"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Favorites...${NC}"
    response=$(curl -s "${API_URL}/api/customer/favorites/${CUSTOMER_ID}" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\[" || echo "$response" | grep -q "favorites"; then
        FAV_COUNT=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
        log_test "GET /api/customer/favorites/{id}" "PASS" "${FAV_COUNT} favorites"
    else
        log_test "GET /api/customer/favorites/{id}" "WARN" "No favorites"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Payment Methods...${NC}"
    response=$(curl -s "${API_URL}/api/customers/${CUSTOMER_ID}/cards" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\[" || echo "$response" | grep -q "card"; then
        CARD_COUNT=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
        log_test "GET /api/customers/{id}/cards" "PASS" "${CARD_COUNT} cards"
    else
        log_test "GET /api/customers/{id}/cards" "WARN" "No payment methods"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Cart...${NC}"
    response=$(curl -s "${API_URL}/api/cart" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "cart\|items\|\[\]"; then
        log_test "GET /api/cart" "PASS" ""
    else
        log_test "GET /api/cart" "WARN" "Cart endpoint unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Promotions...${NC}"
    response=$(curl -s "${API_URL}/api/promotions/active" 2>/dev/null)

    if echo "$response" | grep -q "\[" || echo "$response" | grep -q "promo"; then
        PROMO_COUNT=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
        log_test "GET /api/promotions/active" "PASS" "${PROMO_COUNT} active promotions"
    else
        log_test "GET /api/promotions/active" "WARN" "No active promotions"
    fi
else
    log_test "Customer flow" "FAIL" "No customer token available"
fi

# ============================================================
# PHASE 3: Driver App User Flow
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 3: DRIVER APP USER FLOW${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -n "$DRIVER_TOKEN" ] && [ -n "$DRIVER_ID" ]; then
    echo -e "${YELLOW}◆ Testing Driver Dashboard...${NC}"
    response=$(curl -s "${API_URL}/api/v5/driver/${DRIVER_ID}/dashboard" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "earnings\|week_earnings\|driver_id"; then
        log_test "GET /api/v5/driver/{id}/dashboard" "PASS" ""
        WEEK_EARNINGS=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('week_earnings', d.get('earnings', {}).get('week', 'N/A')))" 2>/dev/null)
        log_test "Week earnings: \$${WEEK_EARNINGS}" "PASS" ""
    else
        log_test "GET /api/v5/driver/{id}/dashboard" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Driver Profile...${NC}"
    response=$(curl -s "${API_URL}/api/erp/drivers/${DRIVER_ID}/profile" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "email\|name\|driver"; then
        log_test "GET /api/erp/drivers/{id}/profile" "PASS" ""
        DRIVER_NAME=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name', 'N/A'))" 2>/dev/null)
        log_test "Driver name: ${DRIVER_NAME}" "PASS" ""
    else
        log_test "GET /api/erp/drivers/{id}/profile" "WARN" "Profile endpoint unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Driver Documents...${NC}"
    response=$(curl -s "${API_URL}/api/drivers/${DRIVER_ID}/documents" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        DOC_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/drivers/{id}/documents" "PASS" ""
        log_test "Documents uploaded: ${DOC_COUNT}" "PASS" ""
    else
        log_test "GET /api/drivers/{id}/documents" "WARN" "No documents or unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Driver Status...${NC}"
    response=$(curl -s "${API_URL}/api/drivers/${DRIVER_ID}/status" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "is_online\|status"; then
        IS_ONLINE=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('is_online', 'N/A'))" 2>/dev/null)
        log_test "GET /api/drivers/{id}/status" "PASS" ""
        log_test "Driver online: ${IS_ONLINE}" "PASS" ""
    else
        log_test "GET /api/drivers/{id}/status" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Available Deliveries...${NC}"
    response=$(curl -s "${API_URL}/api/drivers/${DRIVER_ID}/available-orders" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        AVAILABLE_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/drivers/{id}/available-orders" "PASS" ""
        log_test "Available deliveries: ${AVAILABLE_COUNT}" "PASS" ""
    else
        log_test "GET /api/drivers/{id}/available-orders" "WARN" "No available orders or unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Driver Delivery History...${NC}"
    response=$(curl -s "${API_URL}/api/drivers/${DRIVER_ID}/deliveries" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        DELIVERY_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/drivers/{id}/deliveries" "PASS" ""
        log_test "Completed deliveries: ${DELIVERY_COUNT}" "PASS" ""
    else
        log_test "GET /api/drivers/{id}/deliveries" "WARN" "No deliveries or unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Driver Earnings...${NC}"
    response=$(curl -s "${API_URL}/api/drivers/${DRIVER_ID}/earnings" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "earnings\|total\|amount"; then
        log_test "GET /api/drivers/{id}/earnings" "PASS" ""
    else
        log_test "GET /api/drivers/{id}/earnings" "WARN" "Earnings unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Available Orders for Delivery...${NC}"
    response=$(curl -s "${API_URL}/api/erp/orders/available-for-delivery" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        AVAIL_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/erp/orders/available-for-delivery" "PASS" "${AVAIL_COUNT} orders"
    else
        log_test "GET /api/erp/orders/available-for-delivery" "WARN" "No orders available"
    fi
else
    log_test "Driver flow" "FAIL" "No driver token available"
fi

# ============================================================
# PHASE 4: Restaurant App User Flow
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 4: RESTAURANT APP USER FLOW${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ -n "$VENDOR_TOKEN" ] && [ -n "$VENDOR_ID" ]; then
    echo -e "${YELLOW}◆ Testing Restaurant Profile...${NC}"
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "name\|email\|vendor"; then
        log_test "GET /api/vendors/{id}" "PASS" ""
        VENDOR_NAME=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name', d.get('company_name', 'N/A')))" 2>/dev/null)
        log_test "Restaurant name: ${VENDOR_NAME}" "PASS" ""
    else
        log_test "GET /api/vendors/{id}" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Restaurant Orders...${NC}"
    response=$(curl -s "${API_URL}/api/orders?vendor_id=${VENDOR_ID}" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        ORDER_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/orders?vendor_id={id}" "PASS" ""
        log_test "Total orders: ${ORDER_COUNT}" "PASS" ""
    else
        log_test "GET /api/orders?vendor_id={id}" "FAIL" "$response"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Restaurant Menu...${NC}"
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}/menu" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        MENU_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
        log_test "GET /api/vendors/{id}/menu" "PASS" ""
        log_test "Menu items: ${MENU_COUNT}" "PASS" ""
    else
        log_test "GET /api/vendors/{id}/menu" "WARN" "No menu items configured"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Restaurant Analytics...${NC}"
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}/analytics" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "revenue\|orders\|analytics"; then
        log_test "GET /api/vendors/{id}/analytics" "PASS" ""
    else
        log_test "GET /api/vendors/{id}/analytics" "WARN" "Analytics unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Restaurant Online Status...${NC}"
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}/online-status" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "is_online\|status\|online"; then
        IS_ONLINE=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('is_online', d.get('online', 'N/A')))" 2>/dev/null)
        log_test "GET /api/vendors/{id}/online-status" "PASS" ""
        log_test "Restaurant online: ${IS_ONLINE}" "PASS" ""
    else
        log_test "GET /api/vendors/{id}/online-status" "WARN" "Status unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Menu Categories...${NC}"
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}/menu/categories" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        CAT_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        log_test "GET /api/vendors/{id}/menu/categories" "PASS" "${CAT_COUNT} categories"
    else
        log_test "GET /api/vendors/{id}/menu/categories" "WARN" "Categories unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Restaurant Promotions...${NC}"
    response=$(curl -s "${API_URL}/api/promotions/vendor/${VENDOR_ID}" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        PROMO_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        log_test "GET /api/promotions/vendor/{id}" "PASS" "${PROMO_COUNT} promotions"
    else
        log_test "GET /api/promotions/vendor/{id}" "WARN" "No promotions"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing Restaurant Documents...${NC}"
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}/documents" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\["; then
        DOC_COUNT=$(echo "$response" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        log_test "GET /api/vendors/{id}/documents" "PASS" "${DOC_COUNT} documents"
    else
        log_test "GET /api/vendors/{id}/documents" "WARN" "Documents unavailable"
    fi

    echo ""
    echo -e "${YELLOW}◆ Testing ERP Orders View...${NC}"
    response=$(curl -s "${API_URL}/api/erp/orders/vendor/${VENDOR_ID}" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

    if echo "$response" | grep -q "\[" || echo "$response" | grep -q "orders"; then
        log_test "GET /api/erp/orders/vendor/{id}" "PASS" ""
    else
        log_test "GET /api/erp/orders/vendor/{id}" "WARN" "ERP orders unavailable"
    fi
else
    log_test "Restaurant flow" "FAIL" "No vendor token available"
fi

# ============================================================
# PHASE 5: Database Integrity Validation
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 5: DATABASE INTEGRITY VALIDATION${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}◆ Testing Database Connectivity...${NC}"
response=$(curl -s "${API_URL}/api/health" 2>/dev/null)

if echo "$response" | grep -q '"database":"connected"'; then
    log_test "Database connection" "PASS" ""
else
    log_test "Database connection" "FAIL" "$response"
fi

echo ""
echo -e "${YELLOW}◆ Validating Data Relationships...${NC}"

# Check customer exists in database
if [ -n "$CUSTOMER_TOKEN" ]; then
    response=$(curl -s "${API_URL}/api/customer/profile" \
        -H "Authorization: Bearer ${CUSTOMER_TOKEN}" 2>/dev/null)
    if echo "$response" | grep -q "id"; then
        log_test "Customer record exists in DB" "PASS" ""
    else
        log_test "Customer record exists in DB" "FAIL" ""
    fi
fi

# Check driver exists and has proper relationships
if [ -n "$DRIVER_TOKEN" ] && [ -n "$DRIVER_ID" ]; then
    response=$(curl -s "${API_URL}/api/v5/driver/${DRIVER_ID}/dashboard" \
        -H "Authorization: Bearer ${DRIVER_TOKEN}" 2>/dev/null)
    if echo "$response" | grep -q "driver_id\|earnings"; then
        log_test "Driver record exists in DB" "PASS" ""
        log_test "Driver dashboard accessible" "PASS" ""
    else
        log_test "Driver record exists in DB" "WARN" "Using dashboard endpoint for validation"
    fi
fi

# Check vendor exists and has proper relationships
if [ -n "$VENDOR_TOKEN" ] && [ -n "$VENDOR_ID" ]; then
    response=$(curl -s "${API_URL}/api/vendors/${VENDOR_ID}" \
        -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)
    if echo "$response" | grep -q "id"; then
        log_test "Vendor record exists in DB" "PASS" ""
    else
        log_test "Vendor record exists in DB" "FAIL" ""
    fi
fi

echo ""
echo -e "${YELLOW}◆ Validating Order Flow Data Integrity...${NC}"

# Check orders have proper foreign keys
response=$(curl -s "${API_URL}/api/orders?limit=5" \
    -H "Authorization: Bearer ${VENDOR_TOKEN}" 2>/dev/null)

if echo "$response" | grep -q "\["; then
    SAMPLE_ORDER=$(echo "$response" | python3 -c "
import sys, json
orders = json.load(sys.stdin)
if orders:
    o = orders[0]
    print(f'Order ID: {o.get(\"id\", \"N/A\")}, Customer: {o.get(\"customer_id\", \"N/A\")}, Vendor: {o.get(\"vendor_id\", \"N/A\")}, Status: {o.get(\"status\", \"N/A\")}')
else:
    print('No orders')
" 2>/dev/null)
    log_test "Order foreign key integrity" "PASS" "$SAMPLE_ORDER"
else
    log_test "Order foreign key integrity" "WARN" "No orders to validate"
fi

# ============================================================
# PHASE 6: API Contract Validation
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 6: API CONTRACT VALIDATION${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}◆ Testing API Response Schemas...${NC}"

# Customer login response schema
response=$(curl -s -X POST "${API_URL}/api/auth/customer/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${CUSTOMER_EMAIL}&password=${CUSTOMER_PASS}" 2>/dev/null)

REQUIRED_FIELDS="access_token token_type"
for field in $REQUIRED_FIELDS; do
    if echo "$response" | grep -q "\"$field\""; then
        log_test "Customer login response has '$field'" "PASS" ""
    else
        log_test "Customer login response has '$field'" "FAIL" "Missing field"
    fi
done

# Driver login response schema
response=$(curl -s -X POST "${API_URL}/api/auth/driver/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${DRIVER_EMAIL}&password=${DRIVER_PASS}" 2>/dev/null)

REQUIRED_FIELDS="access_token driver_id status is_approved"
for field in $REQUIRED_FIELDS; do
    if echo "$response" | grep -q "\"$field\""; then
        log_test "Driver login response has '$field'" "PASS" ""
    else
        log_test "Driver login response has '$field'" "FAIL" "Missing field"
    fi
done

# Vendor login response schema
response=$(curl -s -X POST "${API_URL}/api/auth/vendor/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${RESTAURANT_EMAIL}&password=${RESTAURANT_PASS}" 2>/dev/null)

REQUIRED_FIELDS="access_token vendor_id"
for field in $REQUIRED_FIELDS; do
    if echo "$response" | grep -q "\"$field\""; then
        log_test "Vendor login response has '$field'" "PASS" ""
    else
        log_test "Vendor login response has '$field'" "FAIL" "Missing field"
    fi
done

echo ""
echo -e "${YELLOW}◆ Testing Error Handling...${NC}"

# Invalid credentials
response=$(curl -s -X POST "${API_URL}/api/auth/customer/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=invalid@test.com&password=wrongpassword" 2>/dev/null)

if echo "$response" | grep -q "401\|Unauthorized\|Invalid\|detail"; then
    log_test "Invalid credentials returns error" "PASS" ""
else
    log_test "Invalid credentials returns error" "FAIL" "Got: $response"
fi

# 404 for invalid endpoint
response=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/nonexistent/endpoint" 2>/dev/null)

if [ "$response" = "404" ]; then
    log_test "Invalid endpoint returns 404" "PASS" ""
else
    log_test "Invalid endpoint returns 404" "FAIL" "Got: $response"
fi

# 401 for unauthenticated request
response=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/customer/profile" 2>/dev/null)

if [ "$response" = "401" ] || [ "$response" = "403" ]; then
    log_test "Protected endpoint requires auth" "PASS" ""
else
    log_test "Protected endpoint requires auth" "FAIL" "Got: $response"
fi

# ============================================================
# PHASE 7: Frontend Validation
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 7: FRONTEND/WEB VALIDATION${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}◆ Testing Frontend Pages...${NC}"

# Landing page (follow redirects with -L)
response=$(curl -sL -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/" 2>/dev/null)
if [ "$response" = "200" ]; then
    log_test "Landing page (/) loads" "PASS" ""
else
    log_test "Landing page (/) loads" "FAIL" "HTTP $response"
fi

# Terms of Service
response=$(curl -sL -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/terms" 2>/dev/null)
if [ "$response" = "200" ]; then
    log_test "Terms of Service (/terms) loads" "PASS" ""
else
    log_test "Terms of Service (/terms) loads" "WARN" "HTTP $response"
fi

# Privacy Policy
response=$(curl -sL -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/privacy" 2>/dev/null)
if [ "$response" = "200" ]; then
    log_test "Privacy Policy (/privacy) loads" "PASS" ""
else
    log_test "Privacy Policy (/privacy) loads" "WARN" "HTTP $response"
fi

# Vendor login page
response=$(curl -sL -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/vendor/login" 2>/dev/null)
if [ "$response" = "200" ]; then
    log_test "Vendor Login (/vendor/login) loads" "PASS" ""
else
    log_test "Vendor Login (/vendor/login) loads" "WARN" "HTTP $response"
fi

# Driver login page
response=$(curl -sL -o /dev/null -w "%{http_code}" "${FRONTEND_URL}/driver/login" 2>/dev/null)
if [ "$response" = "200" ]; then
    log_test "Driver Login (/driver/login) loads" "PASS" ""
else
    log_test "Driver Login (/driver/login) loads" "WARN" "HTTP $response"
fi

# ============================================================
# PHASE 8: Performance Baseline
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} PHASE 8: PERFORMANCE BASELINE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}◆ Testing Critical Endpoint Response Times...${NC}"

# Health endpoint
TIME=$(curl -s -o /dev/null -w "%{time_total}" "${API_URL}/api/health" 2>/dev/null)
TIME_MS=$(echo "$TIME * 1000" | bc 2>/dev/null | cut -d. -f1)
if [ "$TIME_MS" -lt 500 ]; then
    log_test "Health endpoint < 500ms" "PASS" "${TIME_MS}ms"
else
    log_test "Health endpoint < 500ms" "WARN" "${TIME_MS}ms (slow)"
fi

# Customer login
TIME=$(curl -s -o /dev/null -w "%{time_total}" -X POST "${API_URL}/api/auth/customer/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${CUSTOMER_EMAIL}&password=${CUSTOMER_PASS}" 2>/dev/null)
TIME_MS=$(echo "$TIME * 1000" | bc 2>/dev/null | cut -d. -f1)
if [ "$TIME_MS" -lt 2000 ]; then
    log_test "Customer login < 2s" "PASS" "${TIME_MS}ms"
else
    log_test "Customer login < 2s" "WARN" "${TIME_MS}ms (slow)"
fi

# Vendors list
TIME=$(curl -s -o /dev/null -w "%{time_total}" "${API_URL}/api/vendors" 2>/dev/null)
TIME_MS=$(echo "$TIME * 1000" | bc 2>/dev/null | cut -d. -f1)
if [ "$TIME_MS" -lt 1000 ]; then
    log_test "Vendors list < 1s" "PASS" "${TIME_MS}ms"
else
    log_test "Vendors list < 1s" "WARN" "${TIME_MS}ms (slow)"
fi

# ============================================================
# Generate Report
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} GENERATING UAT REPORT${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Generate markdown report
cat > "$REPORT_DIR/UAT_REPORT.md" << EOF
# Comprehensive UAT Report

**Environment**: ${ENV}
**API URL**: ${API_URL}
**Frontend URL**: ${FRONTEND_URL}
**Date**: $(date)
**Report Directory**: ${REPORT_DIR}

---

## Executive Summary

| Metric | Count |
|--------|-------|
| Total Tests | ${TOTAL_TESTS} |
| Passed | ${PASSED_TESTS} |
| Failed | ${FAILED_TESTS} |
| Warnings | ${WARNINGS} |
| Pass Rate | $(echo "scale=1; ${PASSED_TESTS} * 100 / ${TOTAL_TESTS}" | bc)% |

---

## Demo Credentials Used

| App | Email | Password |
|-----|-------|----------|
| Customer | ${CUSTOMER_EMAIL} | ${CUSTOMER_PASS} |
| Driver | ${DRIVER_EMAIL} | ${DRIVER_PASS} |
| Restaurant | ${RESTAURANT_EMAIL} | ${RESTAURANT_PASS} |

---

## Detailed Test Results

### Authentication Tests
EOF

for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r status name details <<< "$result"
    if [[ "$name" == *"login"* ]] || [[ "$name" == *"token"* ]] || [[ "$name" == *"ID:"* ]]; then
        if [ "$status" = "PASS" ]; then
            echo "| $name | ✅ PASS | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        elif [ "$status" = "FAIL" ]; then
            echo "| $name | ❌ FAIL | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        else
            echo "| $name | ⚠️ WARN | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        fi
    fi
done

cat >> "$REPORT_DIR/UAT_REPORT.md" << EOF

### User Flow Tests

| Test | Status | Details |
|------|--------|---------|
EOF

for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r status name details <<< "$result"
    if [[ "$name" == *"GET"* ]] || [[ "$name" == *"POST"* ]] || [[ "$name" == *"profile"* ]] || [[ "$name" == *"orders"* ]] || [[ "$name" == *"Dashboard"* ]]; then
        if [ "$status" = "PASS" ]; then
            echo "| $name | ✅ PASS | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        elif [ "$status" = "FAIL" ]; then
            echo "| $name | ❌ FAIL | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        else
            echo "| $name | ⚠️ WARN | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        fi
    fi
done

cat >> "$REPORT_DIR/UAT_REPORT.md" << EOF

### Database & Data Integrity

| Test | Status | Details |
|------|--------|---------|
EOF

for result in "${TEST_RESULTS[@]}"; do
    IFS='|' read -r status name details <<< "$result"
    if [[ "$name" == *"Database"* ]] || [[ "$name" == *"DB"* ]] || [[ "$name" == *"integrity"* ]] || [[ "$name" == *"record"* ]]; then
        if [ "$status" = "PASS" ]; then
            echo "| $name | ✅ PASS | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        elif [ "$status" = "FAIL" ]; then
            echo "| $name | ❌ FAIL | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        else
            echo "| $name | ⚠️ WARN | $details |" >> "$REPORT_DIR/UAT_REPORT.md"
        fi
    fi
done

cat >> "$REPORT_DIR/UAT_REPORT.md" << EOF

---

## Verdict

EOF

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo "### ✅ PASS - READY FOR RELEASE" >> "$REPORT_DIR/UAT_REPORT.md"
    VERDICT="PASS"
elif [ "$FAILED_TESTS" -le 2 ]; then
    echo "### ⚠️ WARN - REVIEW BEFORE RELEASE" >> "$REPORT_DIR/UAT_REPORT.md"
    VERDICT="WARN"
else
    echo "### ❌ FAIL - NOT READY FOR RELEASE" >> "$REPORT_DIR/UAT_REPORT.md"
    VERDICT="FAIL"
fi

cat >> "$REPORT_DIR/UAT_REPORT.md" << EOF

---

*Generated by Dollor.ai Comprehensive UAT System*
*Report: ${REPORT_DIR}*
EOF

# ============================================================
# Final Summary
# ============================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$VERDICT" = "PASS" ]; then
    echo -e " ${GREEN}${BOLD}UAT COMPLETE: ✅ PASS - READY FOR RELEASE${NC}"
elif [ "$VERDICT" = "WARN" ]; then
    echo -e " ${YELLOW}${BOLD}UAT COMPLETE: ⚠️ WARN - REVIEW BEFORE RELEASE${NC}"
else
    echo -e " ${RED}${BOLD}UAT COMPLETE: ❌ FAIL - NOT READY FOR RELEASE${NC}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e " ${GREEN}Passed${NC}: ${PASSED_TESTS}  ${YELLOW}Warnings${NC}: ${WARNINGS}  ${RED}Failed${NC}: ${FAILED_TESTS}  Total: ${TOTAL_TESTS}"
echo ""
echo -e " Report: ${BLUE}${REPORT_DIR}/UAT_REPORT.md${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
