# Dollor.ai Android - Development Rules

## Current Phase: PRODUCTION
Production build only. No staging or local API hosts.

## Core Rules (ENFORCE ALWAYS)
1. **ONE APP AT A TIME** - Finish current app before moving to next
2. **SHARED FIRST** - Check `shared/` before writing ANY new code
3. **NO DUPLICATES** - Reuse existing code, don't recreate
4. **NO DEAD CODE** - Delete unused code immediately
5. **PRODUCTION ONLY** - All API calls use production endpoint: https://api.dollor.ai

## App Priority Order
1. `shared/` - Models, API, utilities (complete first)
2. `app/` - Customer app (ai.dollor.customer)
3. `driver/` - Driver app (ai.dollor.driver)
4. `partner/` - Partner app (ai.dollor.partner)

## API Endpoints (PRODUCTION)
- Base URL: `https://api.dollor.ai`
- Health: `/health`
- Customers: `/api/customers/*`
- Vendors: `/api/vendors/*`
- Orders: `/api/orders/*`
- Drivers: `/api/drivers/*`
- Rideshare: `/api/rideshare/*`

## Build Commands
```bash
# Production builds
./gradlew :app:assembleRelease
./gradlew :driver:assembleRelease
./gradlew :partner:assembleRelease

# Debug builds (still use production API)
./gradlew :app:assembleDebug
./gradlew :driver:assembleDebug
./gradlew :partner:assembleDebug
```

## Before ANY Code Change
- [ ] Does this exist in `shared/`?
- [ ] Does API endpoint exist in backend?
- [ ] Does schema match database?
- [ ] Run build after change

## App-Specific Docs
See `.claude/docs/` for detailed documentation:
- `shared.md` - Shared module reference
- `customer.md` - Customer app specifics
- `driver.md` - Driver app specifics
- `partner.md` - Partner app specifics
- `api.md` - API endpoints and schema
