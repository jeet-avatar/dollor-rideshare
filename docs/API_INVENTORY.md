# API inventory: every endpoint the four apps call

Generated 2026-10-26. Apps: AR Android rider, AD Android driver, IR iOS rider, ID iOS driver. "Route" = a matching route exists in the release backend (`release/rideshare-backend-20261026`); several of these routes are not on production until it is deployed. "Prod GET" = result of a read-only call to https://api.dollor.ai with the demo account (blank for calls that change data, which are covered by the action matrix and UI runs instead). "Exercised" = seen working in a run: UI = the endpoint appeared in the Android debug ApiTiming log during the UI test; matrix = called by docs/audit-2026-10-26/action_matrix.py against production. These marks are matched by path, so an iOS-only row marked UI means the Android app made the same call, not that the iOS app was logged. The iOS run (no per-call logger) confirmed the effects of the ride, bid, chat, rating, receipt, history, address and card calls by server read-back; see docs/audit-2026-10-26/ios_feature_test.md section 3. Blank means this pass did not exercise it.

| Method | Path | Apps | Route in release backend | Prod GET | Exercised |
|---|---|---|---|---|---|
| GET | `/api/addresses/1` | AR | yes | 200 (181 ms) | UI, matrix |
| DELETE | `/api/addresses/1/1` | AR | yes |  |  |
| PUT | `/api/addresses/1/1` | AR | yes |  |  |
| POST | `/api/addresses/1/1/set-default` | AR | yes |  |  |
| GET | `/api/addresses/{x}` | IR | yes | 200 (158 ms) | UI, matrix |
| POST | `/api/addresses/{x}` | IR | yes | 200 (158 ms) | UI, matrix |
| DELETE | `/api/addresses/{x}/{x}` | IR | yes |  |  |
| PUT | `/api/addresses/{x}/{x}` | IR | yes |  |  |
| POST | `/api/addresses/{x}/{x}/set-default` | IR | yes |  |  |
| POST | `/api/auth/customer/google` | AR, IR | yes |  |  |
| POST | `/api/auth/customer/login` | AR, IR | yes |  | UI, matrix |
| PUT | `/api/auth/customer/profile` | AR, IR | yes |  | matrix |
| POST | `/api/auth/customer/register` | AR, IR | yes |  |  |
| POST | `/api/auth/driver/apple-auth` | ID | yes |  |  |
| GET | `/api/auth/driver/documents` | AD, ID | yes | 200 (182 ms) | UI, matrix |
| POST | `/api/auth/driver/documents` | AD, ID | yes | 200 (182 ms) | UI, matrix |
| POST | `/api/auth/driver/google` | AD, ID | yes |  |  |
| PUT | `/api/auth/driver/location` | ID | yes |  |  |
| POST | `/api/auth/driver/login` | AD, ID | yes |  | UI, matrix |
| GET | `/api/auth/driver/me` | AD, ID | yes | 200 (171 ms) | UI, matrix |
| PUT | `/api/auth/driver/online` | AD, ID | yes |  | matrix |
| POST | `/api/auth/driver/register` | ID | yes |  |  |
| GET | `/api/checkr/background-check/1/status` | AD | yes | 404 (200 ms) | UI |
| POST | `/api/checkr/background-check/initiate` | AD, ID | yes |  |  |
| GET | `/api/checkr/background-check/{x}/status` | ID | yes | 404 (161 ms) | UI |
| GET | `/api/config/rideshare` | AD, AR | yes | 404 (155 ms) | matrix |
| PUT | `/api/customer/1/profile` | AR | yes |  |  |
| POST | `/api/customer/apple-auth` | IR | yes |  |  |
| POST | `/api/customer/demo-login` | AR | yes |  |  |
| POST | `/api/customer/email/send-verification` | AR | yes |  |  |
| GET | `/api/customer/email/status` | AR | yes | 200 (166 ms) | UI, matrix |
| POST | `/api/customer/email/verify` | AR | yes |  |  |
| POST | `/api/customer/password-reset/confirm` | AR, IR | yes |  |  |
| POST | `/api/customer/password-reset/request` | AR, IR | yes |  |  |
| GET | `/api/customer/rides/history` | AR, IR | yes | 200 (180 ms) | UI, matrix |
| GET | `/api/customers/1/cards` | AR | yes | 200 (539 ms) | UI, matrix |
| DELETE | `/api/customers/1/cards/1` | AR | yes |  |  |
| POST | `/api/customers/1/cards/1/default` | AR | yes |  |  |
| DELETE | `/api/customers/1/delete` | AR | yes |  |  |
| GET | `/api/customers/1/stripe/setup-intent` | AR | yes | 200 (381 ms) | matrix |
| GET | `/api/customers/{x}/cards` | IR | yes | 200 (338 ms) | UI, matrix |
| POST | `/api/customers/{x}/cards` | IR | yes | 200 (338 ms) | UI, matrix |
| DELETE | `/api/customers/{x}/cards/{x}` | IR | yes |  |  |
| POST | `/api/customers/{x}/cards/{x}/default` | IR | yes |  |  |
| DELETE | `/api/customers/{x}/delete` | IR | yes |  |  |
| GET | `/api/customers/{x}/stripe/setup-intent` | IR | yes | 200 (376 ms) | matrix |
| GET | `/api/driver/earnings` | AD | yes | 200 (170 ms) | UI, matrix |
| POST | `/api/driver/location` | AD | yes |  | matrix |
| POST | `/api/driver/password-reset/confirm` | AD, ID | yes |  |  |
| POST | `/api/driver/password-reset/request` | AD, ID | yes |  |  |
| GET | `/api/driver/prop22/periods` | ID | yes | 200 (173 ms) |  |
| GET | `/api/driver/prop22/periods/{x}/rides` | ID | yes | 404 (163 ms) |  |
| DELETE | `/api/drivers/1/delete` | AD | yes |  |  |
| POST | `/api/drivers/1/payouts` | AD | yes |  |  |
| PUT | `/api/drivers/{x}` | ID | yes |  |  |
| DELETE | `/api/drivers/{x}/delete` | ID | yes |  |  |
| GET | `/api/drivers/{x}/documents` | ID | yes | 200 (169 ms) |  |
| POST | `/api/drivers/{x}/documents` | ID | yes | 200 (169 ms) |  |
| GET | `/api/drivers/{x}/payout-history` | ID | yes | 200 (178 ms) |  |
| POST | `/api/drivers/{x}/stripe/dashboard-link` | ID | yes |  |  |
| GET | `/api/drivers/{x}/stripe/onboarding-link` | ID | yes | 500 (334 ms) |  |
| POST | `/api/erp/customers/1/fcm-token` | AR | yes |  | UI, matrix |
| POST | `/api/erp/customers/{x}/fcm-token` | IR | yes |  | UI, matrix |
| POST | `/api/erp/drivers/1/fcm-token` | AD | yes |  | UI |
| GET | `/api/erp/drivers/{x}` | ID | yes | 200 (168 ms) |  |
| POST | `/api/erp/drivers/{x}/fcm-token` | ID | yes |  | UI |
| PUT | `/api/erp/orders/{x}/driver-location` | ID | **NO** |  |  |
| POST | `/api/erp/rides/{x}/customer-accept-fare` | IR | yes |  |  |
| POST | `/api/erp/rides/{x}/customer-negotiate` | IR | yes |  |  |
| GET | `/api/erp/rides/{x}/negotiation-status` | IR | yes | 200 (174 ms) |  |
| GET | `/api/erp/rides/{x}/track` | IR | yes | 200 (170 ms) | matrix |
| POST | `/api/founding/driver/join` | AD | yes |  |  |
| GET | `/api/founding/driver/status` | AD | yes | 200 (178 ms) | UI |
| POST | `/api/founding/join` | AR | yes |  |  |
| GET | `/api/founding/status` | AR | yes | 200 (170 ms) | UI, matrix |
| GET | `/api/p2p/ride-requests/1/chat` | AD, AR | yes | 200 (183 ms) | UI, matrix |
| POST | `/api/p2p/ride-requests/1/chat` | AD, AR | yes | 200 (183 ms) | UI, matrix |
| GET | `/api/p2p/ride-requests/{x}/chat` | ID, IR | yes | 200 (173 ms) | UI, matrix |
| POST | `/api/p2p/ride-requests/{x}/chat` | ID, IR | yes | 200 (173 ms) | UI, matrix |
| POST | `/api/rides/1/rate` | AR | yes |  | UI, matrix |
| POST | `/api/rides/1/tip` | AR | yes |  | matrix |
| GET | `/api/rides/1/track` | AR | yes | 200 (202 ms) | UI, matrix |
| GET | `/api/rides/available` | AD, ID | yes | 200 (173 ms) | UI, matrix |
| POST | `/api/rides/bid/1/accept-counter` | AD | yes |  | UI, matrix |
| POST | `/api/rides/bid/1/driver-counter` | AD | yes |  | matrix |
| POST | `/api/rides/bid/1/reject-counter` | AD | yes |  | matrix |
| POST | `/api/rides/bid/1/respond` | AR | yes |  | UI, matrix |
| POST | `/api/rides/bid/{x}/accept-counter` | ID | yes |  | UI, matrix |
| POST | `/api/rides/bid/{x}/driver-counter` | ID | yes |  | matrix |
| POST | `/api/rides/bid/{x}/reject-counter` | ID | yes |  | matrix |
| POST | `/api/rides/bid/{x}/respond` | IR | yes |  | UI, matrix |
| POST | `/api/rides/bid/{x}/withdraw` | ID | yes |  |  |
| GET | `/api/rides/customer/1/requests` | AR | yes | 200 (438 ms) | UI |
| GET | `/api/rides/customer/{x}/recurring-rides` | IR | yes | 200 (165 ms) |  |
| POST | `/api/rides/customer/{x}/recurring-rides` | IR | yes | 200 (165 ms) |  |
| POST | `/api/rides/dispute` | IR | yes |  |  |
| GET | `/api/rides/driver/1/bids` | AD | yes | 200 (351 ms) | UI, matrix |
| GET | `/api/rides/driver/active` | AD | yes | 200 (177 ms) | UI, matrix |
| GET | `/api/rides/driver/{x}/bids` | ID | yes | 200 (343 ms) | UI, matrix |
| POST | `/api/rides/estimate` | AR, IR | yes |  | UI, matrix |
| DELETE | `/api/rides/recurring-rides/{x}` | IR | yes |  |  |
| PUT | `/api/rides/recurring-rides/{x}` | IR | yes |  |  |
| POST | `/api/rides/request` | AR, IR | yes |  | UI, matrix |
| POST | `/api/rides/request/1/arrived` | AD | yes |  | UI, matrix |
| POST | `/api/rides/request/1/bid` | AD | yes |  | UI, matrix |
| GET | `/api/rides/request/1/bids` | AR | yes | 200 (178 ms) | UI, matrix |
| POST | `/api/rides/request/1/cancel` | AR | yes |  | UI, matrix |
| POST | `/api/rides/request/1/complete` | AD | yes |  | UI, matrix |
| POST | `/api/rides/request/1/driver-cancel` | AD | yes |  | matrix |
| POST | `/api/rides/request/1/no-show` | AD | yes |  | matrix |
| POST | `/api/rides/request/1/rate-passenger` | AD | yes |  | UI, matrix |
| GET | `/api/rides/request/1/receipt` | AR | yes | 200 (164 ms) | UI, matrix |
| POST | `/api/rides/request/1/start` | AD | yes |  | UI, matrix |
| POST | `/api/rides/request/{x}/arrived` | ID | yes |  | UI, matrix |
| POST | `/api/rides/request/{x}/bid` | ID | yes |  | UI, matrix |
| GET | `/api/rides/request/{x}/bids` | IR | yes | 200 (175 ms) | UI, matrix |
| POST | `/api/rides/request/{x}/cancel` | IR | yes |  | UI, matrix |
| POST | `/api/rides/request/{x}/complete` | ID | yes |  | UI, matrix |
| POST | `/api/rides/request/{x}/driver-cancel` | ID | yes |  | matrix |
| POST | `/api/rides/request/{x}/email-receipt` | IR | yes |  |  |
| POST | `/api/rides/request/{x}/no-show` | ID | yes |  | matrix |
| POST | `/api/rides/request/{x}/rate-passenger` | ID | yes |  | UI, matrix |
| GET | `/api/rides/request/{x}/receipt` | IR | yes | 200 (172 ms) | UI, matrix |
| POST | `/api/rides/request/{x}/start` | ID | yes |  | UI, matrix |
| GET | `/api/rides/request/{x}/waybill` | ID | yes | 200 (157 ms) |  |
| POST | `/api/rides/{x}/rate` | IR | yes |  | UI, matrix |
| POST | `/api/rides/{x}/tip` | IR | yes |  | matrix |
| POST | `/api/support/chat` | AR, IR | yes |  | matrix |
| GET | `/api/tnc/driver/accessibility` | AD, ID | yes | 200 (169 ms) | UI |
| PATCH | `/api/tnc/driver/accessibility` | AD, ID | yes | 200 (169 ms) | UI |
| POST | `/api/tnc/vehicle-inspection/submit` | ID | yes |  |  |
| GET | `/api/tnc/vehicle-inspection/{x}/status` | ID | yes | 404 (164 ms) |  |
| POST | `/api/tnc/zero-tolerance/report` | IR | yes |  |  |
| GET | `/api/v5/driver/{x}/dashboard` | ID | yes | 200 (188 ms) |  |
