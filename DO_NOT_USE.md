# DO NOT USE — legacy code register (Dollor rideshare: backend, iOS, Android)

Scope: the rideshare stack only (`apps/web/p2p-platform/backend`, `apps/ios/{customer,delivery,eatfair-ios-shared}`,
`apps/android/{app,driver,shared}`). Other projects in this monorepo are out of scope.

Rule of thumb: **if it is on this list, do not call it, copy it, or extend it.** Use the replacement.
Nothing here is lost: removed code is in git history. Last verified 2026-10-26.

## 1. Removed in this cleanup (do not reintroduce)

| What | Why it was a problem | Use instead |
|---|---|---|
| Duplicate route registrations in `main_new.py`: `/api/erp/rides/available`, `/api/erp/rides/{id}/accept`, `/api/erp/rides/{id}/picked-up`, `/api/rides/available`, `POST /api/erp/rides/estimate`, `PUT /api/erp/drivers/{id}/status`, `PUT /api/erp/drivers/{id}/location` | Each path existed twice in the live app; FastAPI serves the first registered, so the `main_new.py` copy was a dead handler that looked live and diverged (it had no online check or dispatch rule). | `bid_routes.py` and `order_flow.py` handlers (one per path). Check with the route-duplicate script in section 6. |
| `proxy_update_driver_status`, `proxy_update_driver_location` (main_new.py) | Fully shadowed by `order_flow.py`. | `order_flow.update_driver_status` / `update_driver_current_location` |
| Unprefixed `/rides/available` pointing at the old `main_new` function | Same path with and without `/api` returned different results. | Now aliased to `bid_routes.get_available_ride_requests` (one handler). |
| iOS `PrimaryButtonStyle`, `SecondaryButtonStyle`, `SuccessButtonStyle`, `DangerButtonStyle`, `CardStyle`/`.cardStyle()` (both apps' `Theme.swift`) | Zero users; green/light styling that contradicts the dark/orange design. | `.buttonStyle(.lxPrimary / .lxSecondary / .lxSuccess / .lxDestructive / .lxCompact(_))`, `.lxCard()` |
| iOS unused tokens: `brandGradient`, `cornerRadius*`, `spacing*`, `cardShadow*`, `brandRed`, `backgroundGrey`, `lightGrey`, `statusActive`, `statusWarning`, `earningsGradient`, `mapGradient` | Zero users. | `Lx.Radius`, `Lx.Spacing`, `Lx.Palette` |
| Android legacy light/dark Material schemes, `ColorFamily`, `brandGradient`, `brandVerticalGradient`, `pinkVerticalGradientReverse` (`Theme.kt`) | App is always dark; schemes unused. | `LxDarkScheme` in `Theme.kt`, tokens in `shared/ui/Lx.kt` |
| ~118 unused Android color vals (`Color.kt`, `DollorTheme.kt`, driver `Color.kt`) | Zero references; many were old green/blue/purple brand colors. | `Lx.*` |
| Untracked test databases and `:memory:?cache=shared` files | Test artifacts. | Tests create their own. |
| "96% goes to your driver" claims; Android `0.96` earnings math | Not true (flat $1–$3 fee). | `AppConfig.Rideshare.calculatePlatformFee`, `AppConfig.rideshareFeeSummary` |
| iOS `$5` / `$10` rider cancellation fee text | The server charges riders no cancel fee. | Config now 0; a real fee needs a backend change first. |

## 2. Still present — DO NOT USE (names that mislead)

| Legacy name | Trap | Use instead |
|---|---|---|
| Android `BrandGreen`, `BrandGrey`, `BrandBlack`, `BrandWhite`, `DollorTheme.Brand.green` | **The names lie.** They were remapped to the dark/orange palette (`BrandGreen` is now orange). ~65 + 28 call sites still use them. | `Lx.Orange`, `Lx.Bg`, `Lx.Text`, `Lx.Surface`, `Lx.Success` |
| Android driver `DollorDriverColors.*` (Blue = orange now, Gray900 = white) | Same: remapped values under old names (~281 uses). | `Lx.*` |
| iOS `Theme.lx*` aliases (1,500+ uses) and `Theme.brand*/text*/status*` (~40) | Thin aliases onto `Lx.Palette`. Fine to read, do not add new ones. | `Lx.Palette.*`, `Lx.Typography.*`, `Lx.Radius.*`, `Lx.Spacing.*` |
| Hex colors, fixed `.font(.system(size:))`, numeric corner radii in views | Breaks design parity. Zero outside theme files today (third-party brand colors such as Google blue/red have named tokens); keep it that way. | Tokens |
| Hardcoded fee tiers or preset factors in UI/legal text | Drifted before ($25/$50 vs $35/$70). | iOS `AppConfig.shared.rideshareTierRows` / `rideshareFeeSummary`; Android `AppConfig.Rideshare` |
| Whole-dollar price formatting (`%.0f`) | Showed a $9.50 bid as "$10". | iOS `Lx.Money.text(_)`; Android `String.format("%.2f")` |

## 3. Legacy API surface — DO NOT CALL from new code

| Endpoint / module | Status | Use instead |
|---|---|---|
| `GET /erp/rides/available`, `POST /erp/rides/{id}/accept`, `/picked-up` (unprefixed, `main_new.py`) | Old "ERP/food-era" aliases; still routed (the accept note says "legacy — actual flow uses the bid system"). The old available-list logic behind it has no online check, WAV filter or dispatch. | `GET /api/rides/available`, bid flow `/api/rides/request/{id}/bid`, `/api/rides/bid/{id}/...` |
| `order_flow.py` `/api/erp/*` ride endpoints | Legacy ERP ride flow superseded by `bid_routes.py`. | `bid_routes.py` |
| iOS `P2PAPIService.fetchAvailableRides` (`/erp/rides/available`) | Old list. | `fetchAvailableRideRequests` (`/rides/available`) |
| `main_new.get_available_ride_requests` (function body) | Dead except through the legacy `/erp` alias. | `bid_routes.get_available_ride_requests` |

## 4. Food delivery / restaurant remnants (product is rideshare-only) — DO NOT USE

- iOS driver: `EarningsViewModel` food-delivery counters (`today/week/monthFoodDeliveries`), `ChatManager` restaurant conversation (`restaurantName`), `VoiceAssistantManager.announceDelivery(restaurant:...)`.
- Backend `order_flow.py` / `main_new.py` order, vendor, restaurant and menu routes.
- Android/iOS strings or models that mention restaurants, menus, carts.
These are not user-visible after this cleanup, but they are dead weight and should be deleted in a dedicated pass.

## 5. Repo hygiene — do not rely on / candidates to delete

- Tracked: `backend/eatfair.db`, `backend/test_report_v1.txt` (and v2/v3), `backend/driver_test_agent.py`, `backend/rideshare_e2e_test.py`, `backend/test_negotiation_flow.py`, `backend/test_order_flow.py`, `backend/test_ride_checkout.py` (ad-hoc scripts outside `tests/`), root `firebase-debug.log`, `keep-driver-online.sh`.
- Demo logins exist only under `#if DEBUG` (iOS) and are absent from release binaries (verified). Never ship them.
- **Dev venv `backend/venv` is stale (Starlette 0.27) and hangs request tests.** Build a venv from `requirements.txt` (FastAPI 0.115.0 / Starlette 0.38.6) before running tests.
- Pushing to `main` auto-deploys production; staging is broken. Use a branch and review.

## 6. Checks that keep it clean

```bash
# Backend: no (method, path) may be registered twice. Run from apps/web/p2p-platform/backend (needs DATABASE_URL, JWT_SECRET_KEY):
python - <<'PY'
import collections
from main_new import app
by=collections.defaultdict(list)
for r in app.routes:
    for m in (getattr(r,'methods',None) or []):
        if m not in ('HEAD','OPTIONS'): by[(m,r.path)].append(r.endpoint.__module__+'.'+r.endpoint.__name__)
d={k:v for k,v in by.items() if len(v)>1}; print(len(d),'duplicates'); [print(k,v) for k,v in d.items()]
PY

# iOS / Android: no raw colors, fixed fonts or numeric radii in views (outside theme files)
grep -rnE 'Color\(hex|\.font\(\.system\(size:|cornerRadius\([0-9]' --include='*.swift' apps/ios/customer apps/ios/delivery | grep -v 'Theme.swift\|UITests'
grep -rnE 'Color\(0x' --include='*.kt' apps/android/app/src/main apps/android/driver/src/main | grep -v '/ui/theme/\|DollorLogo'
```

Open items that this register does not fix: driver 129 approval (admin), ride PIN, off-route alerts, drivers-contacted count, backend branch review and deploy.
