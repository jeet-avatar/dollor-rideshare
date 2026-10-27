> Output of an automated line-by-line review of the diff against origin/main (2026-10-26). Findings were read from code, not run. Several were verified and fixed afterwards: see docs/FINAL_REVIEW_REPORT.md for which.

# Backend review: release/final-20261026 vs origin/main (apps/web/p2p-platform/backend)

Read-only. Repro scripts: scratchpad/audit/t/test_scratch.py (run with the repo conftest, nothing written to the repo; `git status` in /private/tmp/final-wt stayed clean).
`import main_new` succeeds in the venv. No model/table/column changes in this change set (models.py not in diff), so no migration gap.

## 1. Files reviewed (git diff --stat, insertions/deletions as reported)

| File | Change |
|---|---|
| bid_routes.py | 414 lines changed (full diff read) |
| main_new.py | 210 (full diff read) |
| email_service.py | 827 (full diff read; template-only rewrites, signatures unchanged, `_dollor_email` exists) |
| pricing_config.py | 41 (read) |
| cache.py | +25 (read) |
| rideshare_payments.py | 10 (read) |
| ride_dispatch.py | +82 new (read) |
| rideshare_config.py | +85 new (read) |
| tests/* (13 files, ~1250 added lines) | NOT line-by-line reviewed (see section 4). Skimmed e2e diff and smoke header only. |

## 2. CONFIRMED defects

| # | Sev | file:line | Code | Why wrong | Evidence | Fix |
|---|---|---|---|---|---|---|
| 1 | HIGH | main_new.py:10462-10470 (`_require_ride_chat_participant`) | `if not customer_id and not driver_id and auth.get("sub"): email = ...; account = db.query(Customer).filter(func.lower(Customer.email) == email).first()` | Email fallback ignores the token's `role`. `require_customer` (auth_utils.py:112-117) rejects role-mismatched tokens, this helper does not. `POST /register` is public and creates a `User` for any email with no verification; `POST /api/auth/login` (main_new.py:2153) then issues `{"sub": email}` with no role/ids. That token resolves to the victim's Customer row, so the attacker reads and posts in the victim's ride chat (needs victim email + sequential ride id). Posts appear as `sender_type: customer`. | Reproduced: registered User with a Customer's email, logged in, `GET /api/p2p/ride-requests/{id}/chat` -> 200; `POST` -> 200 `{"sender_type":"customer","sender_id":2,...}` | Only use the email fallback when `role` is absent AND never for tokens from `/api/auth/login`; better: require `role in ("customer","driver")` and reject others (as require_customer/require_driver do), or drop the fallback. Same for the Driver email branch. |
| 2 | MED | bid_routes.py:1441 + ride_dispatch.py:44 | `has_bids=bool(getattr(request, "bids", None))` | `RideRequest.bids` (models.py:1424) is every bid in any status. A ride whose only bids were withdrawn/rejected/expired/countered-then-closed is treated as "rider has offers in hand", so `search_radius_miles` pins it at the 3 mile step and never widens. Thin-area ride is stuck unserved. | `ride_dispatch.search_radius_miles(300, True)` -> 3.0 vs `(300, False)` -> 25.0 | Pass `has_bids` = any bid with status PENDING/COUNTERED. |
| 3 | MED (pre-existing key, now shared by 2 paths) | bid_routes.py:813 with 2252/2243 | `idempotency_key=f"ride-pi-{ride_request.id}"` | Key depends only on the ride id. `driver_cancel_ride` cancels the PI and re-opens the same ride to OPEN (2252), so a later accept (rider-accept or the new accept-counter) calls `PaymentIntent.create` with the same key. Per Stripe: same key + different params (amount/driver metadata) -> idempotency error (a StripeError) -> caught at bid_routes.py:~842 `except stripe.error.StripeError` -> ride auto-cancelled with 402 even though card is fine. Same key + same params -> Stripe replays the first (now cancelled) PI, status passes the check, and the cancelled PI id is stored; capture at completion then fails. | Code trace only (Stripe server behaviour not executed). Path: driver_cancel_ride 2243-2252 -> new bid -> respond_to_bid -> `_authorize_ride_payment`. | Include a per-attempt component in the key (e.g. bid id + amount: `ride-pi-{ride.id}-{bid.id}-{cents}`). |
| 4 | LOW-MED | main_new.py:3117-3128 (guard) vs main_new.py:4767 and order_flow.py:2010 | guard only inside `PUT /api/auth/driver/online`; `driver.is_online = is_online` in the two other routes | The new "cannot go offline mid-ride" guard is bypassable: `PUT /api/erp/drivers/{id}/status?is_online=false` and `POST /api/drivers/{id}/status` set offline with no check. (Apps use the guarded route: DollorApiService.kt:367, P2PAPIService.swift:2217.) | Reproduced: driver with IN_PROGRESS ride -> ERP status route returns 200 `{"is_online": false}` | Move the guard into a shared helper called by all three routes. |
| 5 | LOW-MED | main_new.py:2643 (only call site) | `_enforce_single_driver_session(...)` called only in `driver_login` | Single-session is not enforced for `/api/auth/driver/google` (2846), `/apple-auth` (2933), `/register` (2695), and tokens from `/api/auth/driver/refresh` (2669) are never registered. Second device via Google/Apple keeps the first device signed in; after a refresh, rotating on the next password login revokes the old login jti but not the refreshed token. | grep: single call site | Call the helper from every driver token issuance, including refresh. |
| 6 | LOW | bid_routes.py:796 | `final_price_cents = int(float(amount) * 100)` | Truncation: 19.99 -> 1998 cents, 4.35 -> 434, 1.15 -> 114. Pre-authorization (and capture, which has no amount) is 1 cent under the fare for many cent values; driver payout is computed from the full fare. Now also reached by countered prices. | python: `int(float(19.99)*100)` = 1998 | `int(round(Decimal(str(amount)) * 100))` / `round(amount*100)`. |
| 7 | LOW | bid_routes.py:2424, 2444 vs 2380-2383 | `amount=500` (charge), `amount=400` (Stripe Transfer) | The change made `NOSHOW_FEE` / `NOSHOW_DRIVER_SHARE` the "single source" and `/api/config/rideshare` advertises them, but the actual Stripe charge and transfer are hardcoded. Changing the config will make DB `platform_fee`/`driver_payout`, the app text and the real charge disagree. Equal today (5.00 / 0.80). | read | `int(round(NOSHOW_FEE*100))`, `int(round(NOSHOW_FEE*NOSHOW_DRIVER_SHARE*100))`; same for the "$5.00" strings. |

### Pre-existing / not introduced by this diff (found while verifying; reported so they are not lost)
- I checked the base (`git archive origin/main`, route order): the removed `@app.*("/api/erp/...")` aliases in main_new.py (available, accept, picked-up, drivers status/location, rides estimate) were already shadowed by the earlier-registered order_flow routes, so removing them changes no behaviour. Same for old `/rides/available`: that one is a real improvement (now uses the dispatch/offline-aware handler).
- order_flow.accept_ride (order_flow.py:629, served at `/api/erp/rides/{id}/accept`) has no status check: reproduced a driver re-matching a CANCELLED ride and matching an OPEN ride with no bid and no payment authorization (offline driver too). order_flow.update_driver_status (order_flow.py:1997) lets a PENDING, non-background-checked driver go online (reproduced; `/api/auth/driver/online` returns 403 for same driver).
- Unprefixed `/erp/rides/{ride_id}/accept` (main_new.py:9431) and `/erp/rides/{id}/start` and `/api/erp/rides/{id}/start` (9492) only need any valid token: reproduced an unrelated customer matching another customer's ride to an arbitrary driver_id (no payment) and starting it.
- `/api/erp/rides/estimate` POST (order_flow) returns `estimated_distance_miles`/`estimated_duration_minutes`, not `distance_miles`/`duration_minutes` that web RideBooking.tsx:649-656 reads (web only, no iOS/Android use found).

## 3. UNCERTAIN (not reported as defects)
- Double accept race, bid_routes.py:1925-1993 (`accept_counter_offer`) and respond_to_bid: no `with_for_update`, status guard (1942) is read then written later, so two drivers holding COUNTERED bids can both pass the guard. Consequence on Stripe: both use key `ride-pi-{id}` with possibly different amounts -> loser gets an idempotency error -> `_authorize_ride_payment` cancels the whole ride (bid_routes.py:~845) while winner's PI stays authorized and `stripe_payment_intent_id` is not cancelled. Need a concurrent Postgres test to confirm ordering.
- main_new.py:2569 `datetime.utcnow().timestamp()` treats a naive UTC time as local time (logout at main_new.py:3297 correctly uses `time.time()`). If the server TZ is not UTC the revocation TTL is shortened by the offset (I measured -25200 s in America/Los_Angeles against a 24 h token), letting the revoked device back in before token expiry. Fine if EC2 TZ is UTC; need `timedatectl` on the host.
- cache.py rotate_active_session falls back to a per-process dict when Redis is unavailable; with several uvicorn workers or no Redis in prod, single-session is not enforced across workers. Need to confirm prod has Redis.
- accept_counter_offer does not set Prop 22 acceptance GPS (`prop22_acceptance_lat/lon`), insurance period events or `ride_accept_count` that respond_to_bid sets (bid_routes.py ~921-945); pre-existing parity gap, compliance impact unknown.
- Driver earnings `today` (main_new.py:6822) is UTC midnight (naive UTC), and `_driver_period_total` filters on `created_at` not completion; was already the case for period=today, now applies to all three fields.
- Dispatch counts online drivers regardless of whether they are mid-ride or have stale `current_latitude`; always-online SF demo drivers (main_new.py ~2284) occupy slots near SF. Likely minor.
- `rideshare_config.py` `int(_env("SUPPORT_RESPONSE_MINUTES"))` guarded by `.isdigit()`; a value like "²" passes isdigit and raises ValueError (env misconfiguration only).
- tests/smoke/test_full_ride_e2e.py hardcodes demo credentials (lines 62, 75, ...) and targets production; acceptable only if the repo is private.

## 4. Checked and clean
- `/api/config/rideshare` (rideshare_config.py): unauthenticated GET returns 200 (TestClient); registered in `_PUBLIC_EXACT_PATHS` (main_new.py:413). Content: fee tiers, pricing, bidding presets, dispatch radii, support email/phone/url, optional env text. Nothing sensitive. (Trailing-slash `/api/config/rideshare/` returns 401; apps should use no slash.)
- Fee tiers: `platform_fee_for` -> `_get_platform_fee` uses `<= TIER_1_MAX (35)` and `<= TIER_2_MAX (70)`, identical boundaries to the old inline code at every call site (complete_ride, rideshare_payments.get_tier_fee, backfill, negotiate alias, revenue report).
- `_authorize_ride_payment`: logic is a faithful move of the old block; accept-counter 402 path cancels the ride, clears match fields, notifies both parties.
- accept_counter guard (1942) correctly blocks accepting a counter on a cancelled/matched ride (cancel_ride_request only expires PENDING bids, so a COUNTERED bid survives a rider cancel; the guard covers it).
- `driver/active` customer_phone: query is filtered by `matched_driver_id == driver.id` and only MATCHED/IN_PROGRESS rides; phone not in the public serializer.
- Undefined-name fixes: local `from models import RideRequest...` imports in set_driver_online, get_driver_profile_by_id, `_driver_period_total` are not used before assignment in those functions; `admin.id` replaces undefined `current_user` (admin param exists); all six `_bg_email` names are imported in bid_routes.py:32-39.
- Removed code: `NOSHOW_CANCELLATION_FEE` has no remaining references; no remaining references to removed aliases beyond those above; `import main_new` succeeds.
- Response-shape changes for apps are additive only (`customer_phone`, `total`, `id`, `sender_id`, earnings today/week/month now always populated). `/api/erp/rides/{id}/track` alias now passes `_auth` into `track_ride` (ownership enforced).

## 5. Could not review / limits
- The 13 test files were not reviewed line by line (only the e2e test diff and the smoke test header); I did not run any test suite as instructed.
- No live Stripe, Postgres concurrency, Redis or EC2 timezone checks were possible; items depending on them are in section 3 or noted as code-trace only (#3).
- iOS/Android were checked by grep for the endpoints/keys above (rides/available, erp status/location, driver/online, radius_km, estimate, accept); I did not read every model decoder for the added response fields.
