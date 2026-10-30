#!/bin/bash
# Run Full-Stack Integration Tests (LOCAL DEVELOPMENT ONLY: targets the docker-compose.integration.yml stack)
# Usage: ./scripts/run-integration-tests.sh [options]
#
# Options:
#   --backend-only    Run only backend tests
#   --frontend-only   Run only frontend tests
#   --contract-only   Run only iOS contract tests
#   --e2e-only        Run only E2E tests
#   --clean           Clean up containers after tests
#   --ci              Run in CI mode (no interactive output)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

# Default options
BACKEND_ONLY=false
FRONTEND_ONLY=false
CONTRACT_ONLY=false
E2E_ONLY=false
CLEAN=false
CI_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backend-only)
            BACKEND_ONLY=true
            shift
            ;;
        --frontend-only)
            FRONTEND_ONLY=true
            shift
            ;;
        --contract-only)
            CONTRACT_ONLY=true
            shift
            ;;
        --e2e-only)
            E2E_ONLY=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}=== Dollor.ai Integration Tests ===${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${YELLOW}>>> $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Start services
print_status "Starting services with Docker Compose..."
cd "$ROOT_DIR"
docker-compose -f docker-compose.integration.yml up -d postgres redis backend

# Wait for backend to be healthy
print_status "Waiting for backend to be ready..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:8001/health > /dev/null 2>&1; then
        print_success "Backend is ready!"
        break
    fi
    attempt=$((attempt + 1))
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    print_error "Backend failed to start"
    docker-compose -f docker-compose.integration.yml logs backend
    exit 1
fi

# Run tests based on options
cd "$ROOT_DIR"
EXIT_CODE=0

# Backend tests
if [ "$BACKEND_ONLY" = true ] || [ "$CONTRACT_ONLY" = false ] && [ "$E2E_ONLY" = false ] && [ "$FRONTEND_ONLY" = false ]; then
    print_status "Running Backend API Tests..."
    cd "$ROOT_DIR/apps/web/p2p-platform/backend"

    if [ "$CI_MODE" = true ]; then
        API_BASE_URL=http://localhost:8001 python -m pytest tests/api/ -v --tb=short || EXIT_CODE=1
    else
        API_BASE_URL=http://localhost:8001 python -m pytest tests/api/ -v --tb=short || EXIT_CODE=1
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        print_success "Backend API Tests passed!"
    else
        print_error "Backend API Tests failed!"
    fi
fi

# Contract tests
if [ "$CONTRACT_ONLY" = true ] || [ "$BACKEND_ONLY" = false ] && [ "$E2E_ONLY" = false ] && [ "$FRONTEND_ONLY" = false ]; then
    print_status "Running iOS API Contract Tests..."
    cd "$ROOT_DIR/apps/web/p2p-platform/backend"

    API_BASE_URL=http://localhost:8001 python -m pytest tests/integration/test_ios_api_contracts.py -v --tb=short || EXIT_CODE=1

    if [ $EXIT_CODE -eq 0 ]; then
        print_success "iOS Contract Tests passed!"
    else
        print_error "iOS Contract Tests failed!"
    fi
fi

# E2E tests
if [ "$E2E_ONLY" = true ] || [ "$BACKEND_ONLY" = false ] && [ "$CONTRACT_ONLY" = false ] && [ "$FRONTEND_ONLY" = false ]; then
    print_status "Running E2E Critical Flow Tests..."
    cd "$ROOT_DIR/apps/web/p2p-platform/backend"

    API_BASE_URL=http://localhost:8001 python -m pytest tests/e2e/ -v --tb=short || EXIT_CODE=1

    if [ $EXIT_CODE -eq 0 ]; then
        print_success "E2E Tests passed!"
    else
        print_error "E2E Tests failed!"
    fi
fi

# Frontend tests
if [ "$FRONTEND_ONLY" = true ] || [ "$BACKEND_ONLY" = false ] && [ "$CONTRACT_ONLY" = false ] && [ "$E2E_ONLY" = false ]; then
    print_status "Running Frontend E2E Tests..."
    cd "$ROOT_DIR/apps/web/p2p-platform/frontend"

    # Install Playwright if needed
    if ! npx playwright --version > /dev/null 2>&1; then
        npm install -D @playwright/test
        npx playwright install chromium
    fi

    # Build and run tests
    npm run build
    VITE_API_URL=http://localhost:8001 npx playwright test --project=chromium || EXIT_CODE=1

    if [ $EXIT_CODE -eq 0 ]; then
        print_success "Frontend E2E Tests passed!"
    else
        print_error "Frontend E2E Tests failed!"
    fi
fi

# Cleanup
if [ "$CLEAN" = true ]; then
    print_status "Cleaning up containers..."
    cd "$ROOT_DIR"
    docker-compose -f docker-compose.integration.yml down -v
    print_success "Cleanup complete!"
fi

# Summary
echo ""
echo -e "${GREEN}=== Test Summary ===${NC}"
if [ $EXIT_CODE -eq 0 ]; then
    print_success "All tests passed!"
else
    print_error "Some tests failed. Check the output above for details."
fi

exit $EXIT_CODE
