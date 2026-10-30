#!/bin/bash
#
# Dollor.ai Cross-Platform UI Test Runner
#
# Usage: scripts/run-ui-tests.sh [platform] [app] [flow]
#   platform: ios | android | all (default: all)
#   app:      customer | driver | restaurant | all (default: all)
#   flow:     auth | food | ride | profile | settings | orders | menu | all (default: all)
#
# Options:
#   --dry-run   Show commands without executing
#   --help      Show this help message
#
# Examples:
#   scripts/run-ui-tests.sh                          # Run all tests
#   scripts/run-ui-tests.sh ios customer auth         # iOS customer auth only
#   scripts/run-ui-tests.sh android driver ride       # Android driver rideshare only
#   scripts/run-ui-tests.sh --dry-run all all all     # Show all 18 test commands
#

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Directories
IOS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_REPO="${ANDROID_REPO:-$IOS_REPO/apps/android}"
LOG_DIR="/tmp/dollor-ui-tests"

# Parse flags and positional arguments
DRY_RUN=false
POSITIONAL_ARGS=()
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            head -20 "$0" | tail -18
            exit 0
            ;;
        *)
            POSITIONAL_ARGS+=("$arg")
            ;;
    esac
done

PLATFORM="${POSITIONAL_ARGS[0]:-all}"
APP="${POSITIONAL_ARGS[1]:-all}"
FLOW="${POSITIONAL_ARGS[2]:-all}"

# Validate inputs
case "$PLATFORM" in
    ios|android|all) ;;
    *) echo -e "${RED}Invalid platform: $PLATFORM. Use: ios | android | all${NC}"; exit 1 ;;
esac
case "$APP" in
    customer|driver|restaurant|all) ;;
    *) echo -e "${RED}Invalid app: $APP. Use: customer | driver | restaurant | all${NC}"; exit 1 ;;
esac
case "$FLOW" in
    auth|food|ride|profile|settings|orders|menu|all) ;;
    *) echo -e "${RED}Invalid flow: $FLOW. Use: auth | food | ride | profile | settings | orders | menu | all${NC}"; exit 1 ;;
esac

# Create log directory
mkdir -p "$LOG_DIR"

# Results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
RESULTS_FILE="$LOG_DIR/.results"
> "$RESULTS_FILE"

# Get iOS test class for app+flow
get_ios_class() {
    local app="$1"
    local flow="$2"
    case "${app}_${flow}" in
        customer_auth)     echo "CustomerAuthFlowTests" ;;
        customer_food)     echo "CustomerFoodDeliveryFlowTests" ;;
        customer_ride)     echo "CustomerRideshareFlowTests" ;;
        customer_profile)  echo "CustomerProfileSettingsTests" ;;
        driver_auth)       echo "DriverAuthFlowTests" ;;
        driver_food)       echo "DriverDeliveryFlowTests" ;;
        driver_ride)       echo "DriverRideshareFlowTests" ;;
        driver_profile)    echo "DriverProfileFlowTests" ;;
        restaurant_auth)   echo "RestaurantAuthFlowTests" ;;
        restaurant_orders) echo "RestaurantOrderManagementTests" ;;
        restaurant_menu)   echo "RestaurantMenuManagementTests" ;;
        restaurant_settings) echo "RestaurantSettingsFlowTests" ;;
        *) echo "" ;;
    esac
}

# Get Android test class for app+flow
get_android_class() {
    local app="$1"
    local flow="$2"
    case "${app}_${flow}" in
        customer_auth)     echo "ai.dollor.customer.flows.CustomerAuthFlowTest" ;;
        customer_food)     echo "ai.dollor.customer.flows.CustomerFoodDeliveryFlowTest" ;;
        customer_ride)     echo "ai.dollor.customer.flows.CustomerRideshareFlowTest" ;;
        customer_profile)  echo "ai.dollor.customer.flows.CustomerProfileSettingsFlowTest" ;;
        driver_auth)       echo "ai.dollor.driver.flows.DriverAuthFlowTest" ;;
        driver_food)       echo "ai.dollor.driver.flows.DriverDeliveryFlowTest" ;;
        driver_ride)       echo "ai.dollor.driver.flows.DriverRideshareFlowTest" ;;
        driver_profile)    echo "ai.dollor.driver.flows.DriverProfileFlowTest" ;;
        restaurant_auth)   echo "ai.dollor.partner.flows.PartnerAuthFlowTest" ;;
        restaurant_orders) echo "ai.dollor.partner.flows.PartnerOrderManagementFlowTest" ;;
        restaurant_menu)   echo "ai.dollor.partner.flows.PartnerMenuManagementFlowTest" ;;
        restaurant_settings) echo "ai.dollor.partner.flows.PartnerSettingsFlowTest" ;;
        *) echo "" ;;
    esac
}

# Get iOS scheme for app
get_ios_scheme() {
    case "$1" in
        customer)   echo "eatfaircustomer" ;;
        driver)     echo "eatffairdelivery" ;;
        restaurant) echo "eatffairrestaurant" ;;
    esac
}

# Get iOS test target for app
get_ios_target() {
    case "$1" in
        customer)   echo "eatfaircustomerUITests" ;;
        driver)     echo "eatffairdeliveryUITests" ;;
        restaurant) echo "eatffairrestaurantUITests" ;;
    esac
}

# Get Android module for app
get_android_module() {
    case "$1" in
        customer)   echo ":app" ;;
        driver)     echo ":driver" ;;
        restaurant) echo ":partner" ;;
    esac
}

# Get flows for an app
get_flows_for_app() {
    case "$1" in
        customer)   echo "auth food ride profile" ;;
        driver)     echo "auth food ride profile" ;;
        restaurant) echo "auth orders menu settings" ;;
    esac
}

# Run a single iOS test
run_ios_test() {
    local app="$1"
    local flow="$2"
    local scheme=$(get_ios_scheme "$app")
    local target=$(get_ios_target "$app")
    local test_class=$(get_ios_class "$app" "$flow")

    if [ -z "$test_class" ]; then
        return
    fi

    local log_file="$LOG_DIR/ios-${app}-${flow}.log"
    local cmd="xcodebuild test -workspace ${IOS_REPO}/apps/ios/EatFair.xcworkspace -scheme ${scheme} -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:${target}/${test_class}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if $DRY_RUN; then
        echo -e "${CYAN}[DRY-RUN] iOS ${app} ${flow}:${NC}"
        echo "  $cmd"
        echo "  Log: $log_file"
        echo ""
        echo "iOS|${app}|${flow}|DRY-RUN|-" >> "$RESULTS_FILE"
        return
    fi

    echo -e "${YELLOW}Running iOS ${app} ${flow}...${NC}"
    local start_time=$(date +%s)

    if eval "$cmd" > "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${GREEN}  PASS${NC} (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "iOS|${app}|${flow}|PASS|${duration}s" >> "$RESULTS_FILE"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${RED}  FAIL${NC} (${duration}s) -- see $log_file"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "iOS|${app}|${flow}|FAIL|${duration}s" >> "$RESULTS_FILE"
    fi
}

# Run a single Android test
run_android_test() {
    local app="$1"
    local flow="$2"
    local module=$(get_android_module "$app")
    local test_class=$(get_android_class "$app" "$flow")

    if [ -z "$test_class" ]; then
        return
    fi

    local log_file="$LOG_DIR/android-${app}-${flow}.log"
    local cmd="cd ${ANDROID_REPO} && ./gradlew ${module}:connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=${test_class}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if $DRY_RUN; then
        echo -e "${CYAN}[DRY-RUN] Android ${app} ${flow}:${NC}"
        echo "  $cmd"
        echo "  Log: $log_file"
        echo ""
        echo "Android|${app}|${flow}|DRY-RUN|-" >> "$RESULTS_FILE"
        return
    fi

    echo -e "${YELLOW}Running Android ${app} ${flow}...${NC}"
    local start_time=$(date +%s)

    if eval "$cmd" > "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${GREEN}  PASS${NC} (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo "Android|${app}|${flow}|PASS|${duration}s" >> "$RESULTS_FILE"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "${RED}  FAIL${NC} (${duration}s) -- see $log_file"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo "Android|${app}|${flow}|FAIL|${duration}s" >> "$RESULTS_FILE"
    fi
}

# Determine which apps to run
get_apps() {
    if [ "$APP" = "all" ]; then
        echo "customer driver restaurant"
    else
        echo "$APP"
    fi
}

# Determine which flows to run for an app
get_flows() {
    local app="$1"
    if [ "$FLOW" = "all" ]; then
        get_flows_for_app "$app"
    else
        echo "$FLOW"
    fi
}

# Header
echo ""
echo "======================================"
echo "  Dollor.ai UI Test Runner"
echo "======================================"
echo "  Platform: $PLATFORM"
echo "  App:      $APP"
echo "  Flow:     $FLOW"
echo "  Dry-run:  $DRY_RUN"
echo "  Logs:     $LOG_DIR"
echo "======================================"
echo ""

# Run iOS tests
if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
    echo -e "${CYAN}=== iOS Tests ===${NC}"
    for app in $(get_apps); do
        for flow in $(get_flows "$app"); do
            run_ios_test "$app" "$flow"
        done
    done
    echo ""
fi

# Run Android tests
if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
    echo -e "${CYAN}=== Android Tests ===${NC}"
    for app in $(get_apps); do
        for flow in $(get_flows "$app"); do
            run_android_test "$app" "$flow"
        done
    done
    echo ""
fi

# Summary table
echo "======================================"
echo "  Test Results Summary"
echo "======================================"
printf "%-10s %-12s %-10s %-10s %-10s\n" "Platform" "App" "Flow" "Status" "Duration"
printf "%-10s %-12s %-10s %-10s %-10s\n" "--------" "---" "----" "------" "--------"

while IFS='|' read -r platform app flow status duration; do
    case "$status" in
        PASS)     status_display="${GREEN}PASS${NC}" ;;
        FAIL)     status_display="${RED}FAIL${NC}" ;;
        DRY-RUN)  status_display="${CYAN}DRY-RUN${NC}" ;;
        *)        status_display="$status" ;;
    esac
    printf "%-10s %-12s %-10s " "$platform" "$app" "$flow"
    echo -e "${status_display}       ${duration}"
done < "$RESULTS_FILE"

echo "======================================"
if $DRY_RUN; then
    echo "  Total suites: $TOTAL_TESTS (dry-run mode)"
else
    echo "  Total: $TOTAL_TESTS | Passed: $PASSED_TESTS | Failed: $FAILED_TESTS"
fi
echo "======================================"

# Cleanup
rm -f "$RESULTS_FILE"

# Exit code
if ! $DRY_RUN && [ $FAILED_TESTS -gt 0 ]; then
    exit 1
fi
exit 0
