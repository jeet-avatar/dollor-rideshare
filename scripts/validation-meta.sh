#!/bin/bash
#
# Dollor.ai Meta-Validation Agent
# Validates that QA and UAT systems covered all required checks
#
# This agent ensures no steps were missed by cross-referencing:
# - QA Agent reports (9 agents)
# - UAT Phase reports (8 phases)
# - API endpoint coverage
# - Security check coverage
# - User flow coverage
# - Database validation coverage
#
# Usage:
#   ./scripts/validation-meta.sh [staging|production]
#
# Run after both QA and UAT complete to verify full coverage
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
REPORT_DIR="$PROJECT_ROOT/.planning/validation-reports/${DATE}"

# API URLs
if [ "$ENV" = "production" ]; then
    API_URL="https://api.dollor.ai"
else
    API_URL="https://d34u5ixl0bulv4.cloudfront.net"
fi

# Find latest reports
QA_REPORT_DIR=$(ls -td "$PROJECT_ROOT/.planning/qa-reports"/*/ 2>/dev/null | head -1)
UAT_REPORT_DIR=$(ls -td "$PROJECT_ROOT/.planning/uat-reports"/*/ 2>/dev/null | head -1)

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
GAPS_FOUND=0

mkdir -p "$REPORT_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e " ${BOLD}DOLLOR.AI META-VALIDATION AGENT${NC}"
echo " Cross-Validation of QA and UAT Coverage"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "Environment:     ${BLUE}${ENV}${NC}"
echo -e "API URL:         ${BLUE}${API_URL}${NC}"
echo -e "QA Reports:      ${BLUE}${QA_REPORT_DIR:-NOT FOUND}${NC}"
echo -e "UAT Reports:     ${BLUE}${UAT_REPORT_DIR:-NOT FOUND}${NC}"
echo -e "Timestamp:       ${BLUE}$(date)${NC}"
echo ""

# Initialize report
cat > "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF
# Meta-Validation Report

**Purpose**: Validate that QA and UAT systems covered all required checks
**Environment**: ${ENV}
**Date**: $(date)

---

## Report Sources

| System | Report Directory | Status |
|--------|------------------|--------|
| QA | ${QA_REPORT_DIR:-NOT FOUND} | $([ -n "$QA_REPORT_DIR" ] && echo "✅ Found" || echo "❌ Missing") |
| UAT | ${UAT_REPORT_DIR:-NOT FOUND} | $([ -n "$UAT_REPORT_DIR" ] && echo "✅ Found" || echo "❌ Missing") |

---

EOF

log_check() {
    local category="$1"
    local check="$2"
    local status="$3"
    local details="$4"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if [ "$status" = "PASS" ]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        echo -e "  ${GREEN}✓${NC} $check"
    elif [ "$status" = "FAIL" ]; then
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        echo -e "  ${RED}✗${NC} $check: $details"
    elif [ "$status" = "GAP" ]; then
        GAPS_FOUND=$((GAPS_FOUND + 1))
        echo -e "  ${YELLOW}⚠${NC} $check: $details"
    fi
}

# ============================================================
# SECTION 1: QA SYSTEM COMPLETENESS
# ============================================================

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 1: QA SYSTEM COMPLETENESS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF
## Section 1: QA System Completeness

### Required QA Agents (9 total)

| # | Agent | Report File | Status |
|---|-------|-------------|--------|
EOF

echo -e "${YELLOW}◆ Checking QA Agent Reports...${NC}"

REQUIRED_QA_AGENTS=("API" "UI" "E2E" "DEADCODE" "SECURITY" "TESTS" "DATABASE" "PERFORMANCE" "DEPENDENCIES")

for agent in "${REQUIRED_QA_AGENTS[@]}"; do
    report_file="$QA_REPORT_DIR/QA_REPORT_${agent}.md"
    if [ -f "$report_file" ]; then
        log_check "QA" "QA Agent: $agent" "PASS" ""
        echo "| ${#REQUIRED_QA_AGENTS[@]} | $agent | QA_REPORT_${agent}.md | ✅ Present |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    else
        log_check "QA" "QA Agent: $agent" "FAIL" "Report not found"
        echo "| ${#REQUIRED_QA_AGENTS[@]} | $agent | QA_REPORT_${agent}.md | ❌ Missing |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    fi
done

# Check validation report exists
if [ -f "$QA_REPORT_DIR/QA_VALIDATION_REPORT.md" ]; then
    log_check "QA" "QA Validation Summary" "PASS" ""
else
    log_check "QA" "QA Validation Summary" "FAIL" "Missing QA_VALIDATION_REPORT.md"
fi

# ============================================================
# SECTION 2: UAT SYSTEM COMPLETENESS
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 2: UAT SYSTEM COMPLETENESS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 2: UAT System Completeness

### UAT Report Analysis

EOF

echo -e "${YELLOW}◆ Checking UAT Report...${NC}"

if [ -f "$UAT_REPORT_DIR/UAT_REPORT.md" ]; then
    log_check "UAT" "UAT Report exists" "PASS" ""

    # Check for all 8 phases in UAT report (with flexible matching)
    REQUIRED_PHASES=("Authentication|login|token" "Customer|profile|orders" "Driver|dashboard|documents" "Restaurant|vendor|menu" "Database|connection|integrity" "Contract|schema|response" "Frontend|page|loads" "Performance|time|ms")

    cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF
| Phase | Expected | Found |
|-------|----------|-------|
EOF

    for phase_info in "${REQUIRED_PHASES[@]}"; do
        phase_name=$(echo "$phase_info" | cut -d'|' -f1)
        phase_patterns=$(echo "$phase_info" | tr '|' '\n')
        found=0
        for pattern in $phase_patterns; do
            if grep -qiE "$pattern" "$UAT_REPORT_DIR/UAT_REPORT.md" 2>/dev/null; then
                found=1
                break
            fi
        done
        if [ $found -eq 1 ]; then
            log_check "UAT" "UAT Phase: $phase_name" "PASS" ""
            echo "| $phase_name | ✅ | ✅ Found |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
        else
            log_check "UAT" "UAT Phase: $phase_name" "GAP" "Phase not found in report"
            echo "| $phase_name | ✅ | ⚠️ Not found |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
        fi
    done
else
    log_check "UAT" "UAT Report exists" "FAIL" "UAT_REPORT.md not found"
fi

# ============================================================
# SECTION 3: API ENDPOINT COVERAGE
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 3: API ENDPOINT COVERAGE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 3: API Endpoint Coverage

### Critical Endpoints

| Endpoint | QA Tested | UAT Tested | Live Check |
|----------|-----------|------------|------------|
EOF

echo -e "${YELLOW}◆ Validating Critical Endpoint Coverage...${NC}"

# Define critical endpoints that MUST be tested (using arrays instead of associative for compatibility)
# Expanded to cover more iOS app endpoints
ENDPOINT_PATHS=(
    "/health"
    "/api/auth/customer/login"
    "/api/auth/driver/login"
    "/api/auth/vendor/login"
    "/api/vendors"
    "/api/vendors/40/menu"
    "/api/customer/profile"
    "/api/customer/orders"
    "/api/addresses"
    "/api/customer/favorites"
    "/api/customers"
    "/api/cart"
    "/api/promotions"
    "/api/v5/driver"
    "/api/drivers"
    "/api/erp/drivers"
    "/api/erp/orders"
    "/api/orders"
    "/api/vendors/40/menu/categories"
    "/api/vendors/40/online-status"
)
ENDPOINT_NAMES=(
    "Health check"
    "Customer authentication"
    "Driver authentication"
    "Vendor authentication"
    "Restaurant listing"
    "Restaurant menu"
    "Customer profile"
    "Customer orders"
    "Customer addresses"
    "Customer favorites"
    "Payment methods (cards)"
    "Cart management"
    "Promotions"
    "Driver dashboard"
    "Driver documents/status"
    "Driver ERP profile"
    "ERP orders"
    "Order management"
    "Menu categories"
    "Restaurant online status"
)

for i in "${!ENDPOINT_PATHS[@]}"; do
    endpoint="${ENDPOINT_PATHS[$i]}"
    description="${ENDPOINT_NAMES[$i]}"

    # Check if tested in QA
    qa_tested="❌"
    if [ -f "$QA_REPORT_DIR/QA_REPORT_API.md" ]; then
        if grep -q "$endpoint" "$QA_REPORT_DIR/QA_REPORT_API.md" 2>/dev/null; then
            qa_tested="✅"
        fi
    fi

    # Check if tested in UAT
    uat_tested="❌"
    if [ -f "$UAT_REPORT_DIR/UAT_REPORT.md" ]; then
        if grep -q "$endpoint" "$UAT_REPORT_DIR/UAT_REPORT.md" 2>/dev/null; then
            uat_tested="✅"
        fi
    fi

    # Live check
    live_status="❓"
    test_endpoint="${endpoint//\{id\}/48}"  # Replace {id} with demo driver ID
    response=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL$test_endpoint" 2>/dev/null)
    if [ "$response" = "200" ] || [ "$response" = "401" ] || [ "$response" = "422" ]; then
        live_status="✅ $response"
    else
        live_status="⚠️ $response"
    fi

    # Determine overall status
    if [ "$qa_tested" = "✅" ] && [ "$uat_tested" = "✅" ]; then
        log_check "API" "$description ($endpoint)" "PASS" ""
    elif [ "$qa_tested" = "✅" ] || [ "$uat_tested" = "✅" ]; then
        log_check "API" "$description ($endpoint)" "GAP" "Only tested in $([ "$qa_tested" = "✅" ] && echo 'QA' || echo 'UAT')"
    else
        log_check "API" "$description ($endpoint)" "FAIL" "Not tested in QA or UAT"
    fi

    echo "| \`$endpoint\` | $qa_tested | $uat_tested | $live_status |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
done

# ============================================================
# SECTION 4: SECURITY CHECK COVERAGE
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 4: SECURITY CHECK COVERAGE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 4: Security Check Coverage (OWASP)

| Security Check | Tested | Report |
|----------------|--------|--------|
EOF

echo -e "${YELLOW}◆ Validating Security Coverage...${NC}"

SECURITY_CHECKS=("Hardcoded secrets" "Hardcoded passwords" "Bearer tokens" "HTTPS enforcement" "SQL injection" "Keychain usage" "UserDefaults" ".env files")

for check in "${SECURITY_CHECKS[@]}"; do
    if [ -f "$QA_REPORT_DIR/QA_REPORT_SECURITY.md" ]; then
        if grep -qi "$check" "$QA_REPORT_DIR/QA_REPORT_SECURITY.md" 2>/dev/null; then
            log_check "Security" "$check" "PASS" ""
            echo "| $check | ✅ | QA_REPORT_SECURITY.md |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
        else
            log_check "Security" "$check" "GAP" "Not found in security report"
            echo "| $check | ⚠️ | Not found |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
        fi
    else
        log_check "Security" "$check" "FAIL" "Security report missing"
        echo "| $check | ❌ | Report missing |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    fi
done

# ============================================================
# SECTION 5: USER FLOW COVERAGE
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 5: USER FLOW COVERAGE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 5: User Flow Coverage

### Critical User Flows

| User Flow | App | QA | UAT | Status |
|-----------|-----|-----|-----|--------|
EOF

echo -e "${YELLOW}◆ Validating User Flow Coverage...${NC}"

# Define critical user flows (with alternative keywords for matching)
USER_FLOWS=(
    "Customer Login|Customer|login.*customer|customer.*login"
    "Browse Restaurants|Customer|vendors|restaurants|browse"
    "View Menu|Customer|menu|items"
    "Order History|Customer|orders|history"
    "Driver Login|Driver|login.*driver|driver.*login"
    "Driver Dashboard|Driver|dashboard|earnings"
    "Driver Documents|Driver|documents|upload|verification"
    "Driver Status|Driver|online|offline|status"
    "Restaurant Login|Restaurant|vendor.*login|login.*vendor"
    "View Orders|Restaurant|orders|incoming"
    "Order Status|Restaurant|status|accept|ready"
    "Menu Items|Restaurant|menu.*items|items"
)

for flow_info in "${USER_FLOWS[@]}"; do
    flow=$(echo "$flow_info" | cut -d'|' -f1)
    app=$(echo "$flow_info" | cut -d'|' -f2)
    patterns=$(echo "$flow_info" | cut -d'|' -f3-)

    # Check in QA E2E report using multiple patterns
    qa_found="❌"
    if [ -f "$QA_REPORT_DIR/QA_REPORT_E2E.md" ]; then
        for pattern in $(echo "$patterns" | tr '|' ' ') "$flow"; do
            if grep -qiE "$pattern" "$QA_REPORT_DIR/QA_REPORT_E2E.md" 2>/dev/null; then
                qa_found="✅"
                break
            fi
        done
    fi

    # Check in UAT report using multiple patterns
    uat_found="❌"
    if [ -f "$UAT_REPORT_DIR/UAT_REPORT.md" ]; then
        for pattern in $(echo "$patterns" | tr '|' ' ') "$flow"; do
            if grep -qiE "$pattern" "$UAT_REPORT_DIR/UAT_REPORT.md" 2>/dev/null; then
                uat_found="✅"
                break
            fi
        done
    fi

    # Determine status
    if [ "$qa_found" = "✅" ] && [ "$uat_found" = "✅" ]; then
        status="✅ Full"
        log_check "Flow" "$flow ($app)" "PASS" ""
    elif [ "$qa_found" = "✅" ] || [ "$uat_found" = "✅" ]; then
        status="⚠️ Partial"
        log_check "Flow" "$flow ($app)" "GAP" "Only in $([ "$qa_found" = "✅" ] && echo 'QA' || echo 'UAT')"
    else
        status="❌ Missing"
        log_check "Flow" "$flow ($app)" "FAIL" "Not tested"
    fi

    echo "| $flow | $app | $qa_found | $uat_found | $status |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
done

# ============================================================
# SECTION 6: DATABASE VALIDATION COVERAGE
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 6: DATABASE VALIDATION COVERAGE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 6: Database Validation Coverage

| Check | QA | UAT | Status |
|-------|-----|-----|--------|
EOF

echo -e "${YELLOW}◆ Validating Database Coverage...${NC}"

DB_CHECKS=("Database connection" "Demo accounts" "Migration status" "Customer record" "Driver record" "Vendor record" "Order integrity" "Foreign keys")

for check in "${DB_CHECKS[@]}"; do
    qa_found="❌"
    uat_found="❌"

    if [ -f "$QA_REPORT_DIR/QA_REPORT_DATABASE.md" ]; then
        if grep -qi "$check" "$QA_REPORT_DIR/QA_REPORT_DATABASE.md" 2>/dev/null; then
            qa_found="✅"
        fi
    fi

    if [ -f "$UAT_REPORT_DIR/UAT_REPORT.md" ]; then
        if grep -qi "$check" "$UAT_REPORT_DIR/UAT_REPORT.md" 2>/dev/null; then
            uat_found="✅"
        fi
    fi

    if [ "$qa_found" = "✅" ] || [ "$uat_found" = "✅" ]; then
        log_check "DB" "$check" "PASS" ""
        echo "| $check | $qa_found | $uat_found | ✅ |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    else
        log_check "DB" "$check" "GAP" "Not explicitly tested"
        echo "| $check | $qa_found | $uat_found | ⚠️ |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    fi
done

# ============================================================
# SECTION 7: DEMO CREDENTIALS VALIDATION
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 7: DEMO CREDENTIALS LIVE VALIDATION${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 7: Demo Credentials Live Validation

| App | Email | Live Status | Token |
|-----|-------|-------------|-------|
EOF

echo -e "${YELLOW}◆ Live Testing Demo Credentials...${NC}"

# Customer
response=$(curl -s -X POST "$API_URL/api/auth/customer/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=demo.customer@dollor.ai&password=${DEMO_CUSTOMER_PASSWORD}" 2>/dev/null)
if echo "$response" | grep -q "access_token"; then
    log_check "Demo" "Customer demo login" "PASS" ""
    echo "| Customer | demo.customer@dollor.ai | ✅ Working | ✅ Received |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
else
    log_check "Demo" "Customer demo login" "FAIL" "$response"
    echo "| Customer | demo.customer@dollor.ai | ❌ Failed | ❌ |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
fi

# Driver
response=$(curl -s -X POST "$API_URL/api/auth/driver/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=demo.driver@dollor.ai&password=${DEMO_DRIVER_PASSWORD}" 2>/dev/null)
if echo "$response" | grep -q "access_token"; then
    log_check "Demo" "Driver demo login" "PASS" ""
    echo "| Driver | demo.driver@dollor.ai | ✅ Working | ✅ Received |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
else
    log_check "Demo" "Driver demo login" "FAIL" "$response"
    echo "| Driver | demo.driver@dollor.ai | ❌ Failed | ❌ |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
fi

# Vendor
response=$(curl -s -X POST "$API_URL/api/auth/vendor/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=demo.restaurant@dollor.ai&password=${DEMO_RESTAURANT_PASSWORD}" 2>/dev/null)
if echo "$response" | grep -q "access_token"; then
    log_check "Demo" "Vendor demo login" "PASS" ""
    echo "| Restaurant | demo.restaurant@dollor.ai | ✅ Working | ✅ Received |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
else
    log_check "Demo" "Vendor demo login" "FAIL" "$response"
    echo "| Restaurant | demo.restaurant@dollor.ai | ❌ Failed | ❌ |" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
fi

# ============================================================
# SECTION 8: COVERAGE GAPS ANALYSIS
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} SECTION 8: COVERAGE GAPS ANALYSIS${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Section 8: Coverage Gaps Analysis

EOF

echo -e "${YELLOW}◆ Analyzing Coverage Gaps...${NC}"

# Check for things tested in QA but not UAT
echo "" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
echo "### Items in QA but not UAT" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
echo "" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"

qa_only_items=0
if [ -f "$QA_REPORT_DIR/QA_REPORT_SECURITY.md" ]; then
    echo "- Security scanning (OWASP checks)" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    ((qa_only_items++))
fi
if [ -f "$QA_REPORT_DIR/QA_REPORT_DEADCODE.md" ]; then
    echo "- Dead code detection" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    ((qa_only_items++))
fi
if [ -f "$QA_REPORT_DIR/QA_REPORT_UI.md" ]; then
    echo "- Code quality (hardcoded values, SwiftUI patterns)" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    ((qa_only_items++))
fi
if [ -f "$QA_REPORT_DIR/QA_REPORT_DEPENDENCIES.md" ]; then
    echo "- Dependency validation (CocoaPods, SPM, pip)" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
    ((qa_only_items++))
fi

log_check "Gap" "QA-only items identified" "PASS" "$qa_only_items items"

echo "" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
echo "### Items in UAT but not QA" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
echo "" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"

uat_only_items=0
if [ -f "$UAT_REPORT_DIR/UAT_REPORT.md" ]; then
    if grep -qi "Frontend" "$UAT_REPORT_DIR/UAT_REPORT.md" 2>/dev/null; then
        echo "- Frontend page validation (landing, terms, privacy)" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
        ((uat_only_items++))
    fi
    if grep -qi "API Contract" "$UAT_REPORT_DIR/UAT_REPORT.md" 2>/dev/null; then
        echo "- API contract validation (required response fields)" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
        ((uat_only_items++))
    fi
fi

log_check "Gap" "UAT-only items identified" "PASS" "$uat_only_items items"

echo "" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
echo "### Recommended Additional Tests" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
echo "" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"

RECOMMENDATIONS=(
    "Load testing (concurrent users)"
    "Push notification delivery"
    "Payment flow end-to-end (Stripe)"
    "Real device testing (iOS/Android)"
    "Offline mode handling"
    "Location services accuracy"
    "Image upload/download"
    "WebSocket connections (real-time updates)"
)

for rec in "${RECOMMENDATIONS[@]}"; do
    echo "- [ ] $rec" >> "$REPORT_DIR/META_VALIDATION_REPORT.md"
done

# ============================================================
# FINAL SUMMARY
# ============================================================

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} GENERATING FINAL REPORT${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Calculate coverage percentage
COVERAGE_PCT=$(echo "scale=1; $PASSED_CHECKS * 100 / $TOTAL_CHECKS" | bc 2>/dev/null || echo "0")

# Determine verdict
if [ $FAILED_CHECKS -eq 0 ] && [ $GAPS_FOUND -le 5 ]; then
    VERDICT="✅ PASS - FULL COVERAGE"
    VERDICT_COLOR="${GREEN}"
elif [ $FAILED_CHECKS -le 2 ]; then
    VERDICT="⚠️ WARN - MINOR GAPS"
    VERDICT_COLOR="${YELLOW}"
else
    VERDICT="❌ FAIL - SIGNIFICANT GAPS"
    VERDICT_COLOR="${RED}"
fi

cat >> "$REPORT_DIR/META_VALIDATION_REPORT.md" << EOF

---

## Final Summary

### Coverage Metrics

| Metric | Count |
|--------|-------|
| Total Checks | $TOTAL_CHECKS |
| Passed | $PASSED_CHECKS |
| Failed | $FAILED_CHECKS |
| Gaps Found | $GAPS_FOUND |
| Coverage | $COVERAGE_PCT% |

### Verdict

## $VERDICT

### Interpretation

- **✅ PASS**: QA and UAT cover all critical paths
- **⚠️ WARN**: Minor gaps exist, review recommended
- **❌ FAIL**: Significant gaps require attention before release

---

## Quick Commands

\`\`\`bash
# Re-run QA
./scripts/qa-runner.sh $ENV pre-deploy

# Re-run UAT
./scripts/uat-comprehensive.sh $ENV

# Re-run this validation
./scripts/validation-meta.sh $ENV

# View latest QA report
cat "$QA_REPORT_DIR/QA_VALIDATION_REPORT.md"

# View latest UAT report
cat "$UAT_REPORT_DIR/UAT_REPORT.md"
\`\`\`

---

*Generated by Dollor.ai Meta-Validation Agent*
*Report: $REPORT_DIR/META_VALIDATION_REPORT.md*
EOF

# Print final summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e " ${VERDICT_COLOR}${BOLD}META-VALIDATION: $VERDICT${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e " ${GREEN}Passed${NC}: $PASSED_CHECKS  ${YELLOW}Gaps${NC}: $GAPS_FOUND  ${RED}Failed${NC}: $FAILED_CHECKS  Total: $TOTAL_CHECKS"
echo -e " Coverage: ${BLUE}$COVERAGE_PCT%${NC}"
echo ""
echo -e " Report: ${BLUE}$REPORT_DIR/META_VALIDATION_REPORT.md${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit $([ $FAILED_CHECKS -eq 0 ] && echo 0 || echo 1)
