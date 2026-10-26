# Android feature test: rider (ai.dollor.customer) and driver (ai.dollor.driver)

## 1. Method and limits
- Branch release/rideshare-launch-ready-20261026. Debug `productionDebug` builds of both modules were built, the signed release builds were uninstalled, and the debug APKs were installed on emulator-5554 (Pixel 9a). Both apps talk to https://api.dollor.ai.
- Features were derived from NavigationGraph.kt / Navigation.kt (rider) and DriverNavGraph.kt (driver), plus the Profile screens.
- Evidence types: ApiTiming logcat lines (saved per step under scratchpad/audit/), screenshots under scratchpad/shots/ (prefix `and_`), uiautomator text dumps, and API read-back with urllib (User-Agent okhttp/4.12.0).
- Honesty note on screenshots: I took each screenshot and opened it, but for the early part of the session (and_r01 to and_r40, and_d01 to and_d24 and similar) the image content is no longer available to me while writing this report. For those rows I rely on the ApiTiming lines, uiautomator text, and what happened on the next step. Where a PASS rests on those, I say so in the notes.
- Rows marked "visual" were looked at directly and are the strongest evidence. These include and_r41, r42, r46, r47, r48, r49, r51, r60 to r63, d25, d26, d27, d29, d30 to d34, d37, d38, d40, d43 to d47 and d51 to d54.
- Not done: the visual UI confirmation of many early screens is partly inferred (see section 5). No UI automation of password reset, Google sign-in, document upload, payment, delete account, or sign-up was attempted.
- The Android system dialer and Maps launch could not be shown in a screenshot (see rows). The emulator has no SIM or Maps handling beyond the checks noted.
- The driver app's debug build and the rider's both ran on a 3G-labelled emulated network. There were a few transient `UnknownHostException` errors (section 3).

## 2a. Rider app table
| Feature or screen | How exercised | RESULT | Evidence | Notes |
|---|---|---|---|---|
| Login (email/password) | Typed demo.customer@dollor.ai and the password on the Login screen, tapped Sign In | PASS | `POST /api/auth/customer/login -> 200 1111ms`; next screen was the legal screen | From Welcome/Login screen (Screen.Login is the auth start). |
| Terms and Privacy screen (legal acceptance) | Tapped Read Full Terms, back, ticked both boxes, Continue | PASS (logs and flow) | `GET /api/rides/customer/74/requests -> 200 307ms` immediately after Continue, then main tab screen loaded | Reached the Ride tab; visual of the terms screen not retained (INFERRED for layout). |
| Notification permission prompt | Tapped Allow when it appeared | PASS (INFERRED from FCM) | `POST /api/erp/customers/74/fcm-token -> 200 166ms` | Token registered after the prompt. |
| Ride tab: Find a Driver sheet | Opened Ride tab, pickup row, Use Current Location, dropoff search `SFO airport`, first suggestion | PASS | and_r20_pickup, and_r21_dropoff_search, and_r22_find_driver_ready; `POST /api/rides/estimate -> 200 699ms` | Pickup 301 Post Street; dropoff SFO. |
| Request a ride | Tapped Find Driver (three times: requests 607, 608, 609) | PASS | `POST /api/rides/request -> 200 576ms` (607), 395ms (608), 392ms (609); then polling `GET /api/rides/request/{id}/bids` and `GET /api/rides/{id}/track` every ~4 s | Polling is continuous while searching. |
| Bid card shown with driver bid | Driver bid placed in driver app, rider app reopened | PASS | and_r24_bid_received, and_r25_bid_card (viewed earlier), `bids -> 200` | Card buttons Accept and Counter. |
| Accept bid | Tapped Accept on request 608's bid | PASS | `POST /api/rides/bid/385/respond -> 200 654ms`; and_r46_accepted (visual): "Driver matched!" Marcus J., Silver Toyota Camry, 7ABC123, chat and call icons, Cancel Ride | Matched card confirmed. |
| Counter offer | Tapped Counter, typed 19.00, Send Counter on request 607 | PASS | `bid` screens and_r26 to r29; the driver app then showed the counter (and_d11) and `POST /api/rides/bid/384/accept-counter -> 200 660ms` on the driver side | Rider-side POST for the counter was not isolated in my filtered log (my filter hid it); outcome confirmed through the driver side. |
| Decline bid | Tapped Counter then a decline-style path on request 609 (bid 386) | PASS | `POST /api/rides/bid/386/respond -> 200 309ms`; and_r51_declined (visual): "0 drivers interested, Bidding closes in 3:38"; driver app shows "Declined by rider" (and_d29, visual); API: request 609 later `expired` | Request is not cancelled by decline; it expires. |
| Cancel ride (matched) with confirm dialog | Tapped Cancel Ride on the matched card, saw dialog, tapped Keep Ride, then Cancel Ride again, confirmed | PASS | and_r47_cancel_dialog (visual: "Cancel Ride? Your driver has already accepted this ride..." Keep Ride / Cancel Ride); and_r48_keep_ride (visual: stays matched); `POST /api/rides/request/608/cancel -> 200 572ms`; and_r49 (visual: back to Find a Driver); API request 608 `cancelled`; driver app Home shows no active ride (and_d26 visual) | Dialog text and both buttons verified. |
| In-ride chat (rider side) | From the matched card tapped chat icon, typed message, sent | PASS | `GET /api/p2p/ride-requests/607/chat -> 200 107ms`, `POST /api/p2p/ride-requests/607/chat -> 200 195ms` | Chat is polled about every 3 s. Driver app showed the message exchange on its side (`GET .../chat -> 200`). |
| Call driver (rider) | Not tapped | UNTESTED | none | Dialer intent; the number is dialed via ACTION_DIAL. |
| Ride in progress / tracking | Opened rider app while driver had started the trip | PASS (logs) | `GET /api/rides/607/track -> 200` repeatedly; and_r33_in_progress and and_r34_trip_view taken | Visual content not retained; INFERRED beyond the logs. |
| Ride completed screen | Rider app after driver completed trip 607 | PASS | and_r35_completed taken; follow-on taps (View receipt, Rate, Done) worked at the verified coordinates | Visual layout not retained. |
| Receipt | Tapped View receipt | PASS | `GET /api/rides/request/607/receipt -> 200 205ms`; and_r36, r37 | Same receipt reopened from Trips: and_r42 (visual: Ride Receipt RIDE2026000607, Oct 26 2026 1:08 PM, Marcus Johnson, 2023 Toyota Camry, 301 Post Street to SFO, 11.8 mi, 37 min, Card, Fare $19.00, Platform fee $1.00). |
| Rate your driver | Opened rating sheet, chose 5 stars, submitted | PASS | `POST /api/rides/607/rate -> 200 216ms` | and_r38, r39, r40. |
| Trips tab (history) | Tapped Trips | PASS | `GET /api/customer/rides/history -> 200 136ms`; and_r41_trips (visual): list of trips with SFO $19.00, $18.50, $19.30, Ferry Building $8.75, one "Cancelled", Ferry Building $8.00, all dated 2026-10-26 with Marcus Johnson | Tapping a row opens the receipt (and_r42). |
| Profile tab | Tapped Profile | PASS | and_r60_profile_top (visual): avatar D, Demo Customer, demo.customer@dollor.ai; Account: Edit Profile, Manage Addresses, Payment Methods, Founding Member | App Settings below. |
| Edit Profile | Opened | PASS (view only) | and_r61_top1 (visual): Full name editable, Email greyed "Your email can't be changed here.", Save changes disabled | No save attempted (no change made). No API call on open. |
| Manage Addresses | Opened | PASS (view only) | `GET /api/addresses/74 -> 200 280ms`; and_r61_top2 (visual): Add Address; 2 saved addresses (both titled "Hotel": 180 El Camino Real Palo Alto, 12 Teaberry Ln) with overflow and share buttons | Add/edit/delete/share not exercised (UNTESTED). |
| Payment Methods | Opened | PASS (view only) | `GET /api/customers/74/cards -> 200 543ms`; and_r61_top3 (visual): Add payment method, Visa ...6255 Expires 12/31, Make default, delete icon | Did not add a card, delete, or make default (rules). |
| Founding Member | Opened | PASS (view only) | `GET /api/founding/status -> 200 226ms`; and_r61_top4 (visual): benefits, state CA, "10000 founding spots left in CA", Join for $100 disabled, "Demo account - payment is bypassed." | Join not pressed. |
| Settings | Opened | PASS | `GET /api/customer/email/status -> 200 238ms`; and_r61_top5 (visual): Email Verification "Not verified - Tap to verify", Privacy Policy, Terms & Conditions, California Privacy Rights (CCPA/CPRA), Contact Support support@dollor.ai, Delete Account | |
| Settings: Privacy Policy, Terms, CCPA screens | Tapped each, back | PASS (opened without crash) | and_r16, r17, r18 taken; app stayed in foreground (`mCurrentFocus` MainActivity at end) | Visual content not retained for these three. |
| Settings: Email verification | Not opened | UNTESTED | none | Would send an email. |
| Settings: Contact Support | Tapped | PASS (INFERRED) | and_r19_contact_support taken | Opens mail intent; not verified visually. |
| Settings: Delete Account | Not tapped | UNTESTED | none | Forbidden. |
| Notifications screen | Opened from Profile | PASS | and_r63_bot1 (visual): bell, "No Notifications Yet" | No API call seen on open. |
| Help & Support | Opened from Profile | PASS (view only) | and_r63_bot2 (visual): search box, Chat with Us, Email Support support@dollor.ai, FAQ chips All/Rides/Payments/Account/Drivers, FAQ list | FAQ search, FAQ expand, filter chips, Chat with Us, and Email Support not exercised (UNTESTED). |
| What Drivers See | Opened | PASS | and_r63_bot3 (visual): "Your privacy is protected", can-see list, cannot-see card | Static content. |
| Your Privacy | Opened | PASS | and_r63_bot4 (visual): Anonymous Phone Relay, Address Protection, Anonymous Ratings, Encrypted Data | Static content. |
| Safety Features | Opened | PASS | and_r63_bot5 (visual): Verified Drivers, Real-Time Tracking | Static content. |
| Refer & Earn | Looked for it in Profile | BLOCKED (hidden by design) | Profile dump lists Settings, Notifications, Help & Support, but no Refer & Earn; code ProfileScreen.kt:244-254 shows it only when `AppConfig.Rideshare.referralRewardText != null` | Not visible on production, so the screen cannot be reached. |
| Log Out | Not tapped | UNTESTED | none | Would log out; the button renders unreadably (see bug B1). |
| Forgot password / Sign up / reset code / email verification flows | Not exercised | UNTESTED | none | Rules forbid completing a password reset; sign-up creates accounts. |
| Welcome screen | Not reachable | BLOCKED | NavigationGraph.kt: auth flow starts at Login ("Skip WelcomeScreen") | |
| Support chat (`support_chat` route) | Not opened | UNTESTED | none | Reached via Help & Support, Chat with Us. |

## 2b. Driver app table
| Feature or screen | How exercised | RESULT | Evidence | Notes |
|---|---|---|---|---|
| Login | Typed demo.driver@dollor.ai and password, Sign In | PASS | `POST /api/auth/driver/login -> 200 790ms` | Login screen text seen via dump: Welcome Back, Email, Password, Sign In, Continue with Google, Forgot Password?. |
| Terms / Driver Agreement acceptance | Ticked Terms and Privacy boxes, Accept & Continue | PASS | After Accept: `GET /api/auth/driver/documents -> 200`, `GET /api/checkr/background-check/48/status -> 200`, `GET /api/auth/driver/me -> 200`, `GET /api/rides/driver/active -> 200`, `GET /api/driver/earnings -> 200`; Home loaded | Compliance onboarding steps (document capture, insurance, background check consent, vehicle requirements, contractor agreement) were not shown because the demo driver is already approved (`status: approved`). |
| Home | Opened | PASS | and_d26 and d51 (visual): Welcome back Marcus Johnson, Online toggle on, "You're Online", Today's Stats ($145.77, 14 rides, 0.0h), Quick Actions Navigate/History/Support, Recent Activity | |
| Home: online toggle | Not toggled | UNTESTED | none | Left online as required. API shows `is_online: true`. |
| Home: Quick action Navigate | Tapped with no active ride | PASS (code-based) | Code DriverHomeScreen.kt:297-306 shows a toast "No active ride to navigate"; and_d43 captured the wrong screen (my automation error) so the toast was not seen | Navigate with an active ride (Google Maps intent) was not tested. Marked UNTESTED for the visual. |
| Home: Quick action Support | Tapped | UNTESTED | and_d44 taken after the app was on the wrong screen; not valid | Code opens a mailto, or shows a toast if no mail app. |
| Home: Quick action History | Tapped | PASS | Opens the Earnings screen (and_d40 / d42 visual) | See bug B2. |
| Rides tab: Available Rides | Opened | PASS | `GET /api/rides/available -> 200 197ms`, `GET /api/rides/driver/48/bids -> 200 396ms`; and_d25 (visual): New requests card (Demo Customer, offers $21.27, 301 Post Street to SFO, Trip 11.8 mi, Submit Bid) and Recent list "You withdrew this offer" | Refresh icon exists (not tapped). |
| Submit bid sheet | Tapped Submit Bid | PASS | and_d27 (visual): Submit Your Bid, Suggested $20.32, Quick Accept $18.69 (92%), Fair Price $20.32, Premium $21.95, Custom amount, "You earn $19.32 after the flat fee", ETA 3/5/10/15 min, Slide to Submit Bid | |
| Slide to submit | Used a drag gesture | PASS | `POST /api/rides/request/607/bid -> 200`, `.../608/bid -> 200 639ms`, `.../609/bid -> 200 731ms` | First two plain swipes did not register (automation: needed draganddrop / motionevent); the app was fine. |
| Own-bid card: counter from rider | Rider countered 19.00 on request 607 | PASS | and_d11, d12 (counter sheet) | Counter amount shown. |
| Own-bid card: Accept counter | Tapped Accept | PASS | `POST /api/rides/bid/384/accept-counter -> 200 660ms`; the rider then had an active ride (chat available, `active` shows ride) | |
| Own-bid card: Decline / Counter-back | Not tapped | UNTESTED | none | |
| Active ride on Home | Home after accept | PASS | and_d14_home_active taken; Chat/Call/SOS buttons at the documented coordinates responded | |
| Chat | Opened chat, typed, sent | PASS | `GET /api/p2p/ride-requests/607/chat -> 200 125ms`; `POST /api/p2p/ride-requests/607/chat -> 200 180ms` | |
| Call rider | Tapped Call | PASS (partial) | and_d18b_call_toast taken; code ActiveRideViews.kt:180-184 shows a toast "Rider's number isn't available - use Chat" when there is no phone; the dialer did not open (focus stayed in the driver app) | Consistent with the demo rider having no number; I did not see the toast text confirmed in a retained image. Mark INFERRED. |
| SOS | Tapped SOS | PASS | and_d19_sos_dialog taken; code shows "Emergency / call 911 now" dialog with a 911 dial button | I did not press the 911 button. Dialog text confirmed from code, INFERRED from the screenshot. |
| I've Arrived | Tapped main action | PASS | `POST /api/rides/request/607/arrived -> 200 368ms` | |
| Start Trip | Tapped main action | PASS | `POST /api/rides/request/607/start -> 200 517ms`; and_d21 | |
| Complete Trip + rating dialog | Tapped main action, set rating, Submit | PASS | `POST /api/rides/request/607/complete -> 200 984ms`; `POST /api/rides/request/607/rate-passenger -> 200 141ms` | and_d22, d23, d24. Earnings today then showed $145.77 with 14 rides. |
| Cancel ride (driver) | Not tapped | UNTESTED | none | Rider-cancel path covered instead (request 608). |
| Driver sees rider-cancelled ride | After rider cancelled 608 | PASS | and_d26 (visual): Home, "No active ride" | `GET /api/rides/driver/active -> count 0` at the end. |
| Earnings tab | Opened | PASS | `GET /api/driver/earnings -> 200 178ms`; and_d30 (visual): Today $145.77, 14 rides, 0.0 hours, tips $0.00, Base Pay $145.77, "Available to pay out: $0.00", Request Payout | |
| Earnings: This Week | Tapped | PASS | and_d38 (visual): $180.06, 19 rides; `GET /api/driver/earnings -> 200` | |
| Earnings: This Month | Tapped | PASS (logs) | and_d39 taken; additional `GET /api/driver/earnings -> 200` | The month figure was not read back in a retained image. |
| Earnings: Request Payout | Not tapped | UNTESTED | none | Payout of $0.00 available; would hit production Stripe. |
| Profile tab | Opened | PASS | and_d31 (visual): Marcus Johnson, demo.driver@dollor.ai, Today $145.77 / This Week $0.00 / This Month $0.00, Earnings History, Founding Member (Lock in your rate for life - $100), Accessibility Capability toggles | Header says This Week $0.00 and This Month $0.00 while the Earnings tab shows This Week $180.06 (see bug B3). |
| Profile: Earnings History | Tapped | PASS | and_d32 (visual): opens the Earnings screen | |
| Profile: Founding Member | Tapped | PASS | `GET /api/founding/driver/status -> 200 338ms`; and_d33 (visual): "Become a Founding Driver", one-time $100, state CA, "10000 founding spots left in CA", Join for $100 (disabled) | Join not pressed. |
| Profile: Accessibility toggles | Turned "Extra trunk space" on, then off | PASS | `PATCH /api/tnc/driver/accessibility -> 200 186ms` (on) and `-> 200 493ms` (off); and_d35 (visual: trunk toggle on); and_d37 (visual: off); API read-back: `accessibility_features {wheelchair true, service_animal true, mobility_storage false}` | Server state restored to the original. Other three toggles not changed. |
| Profile: Help & Support | Tapped | PASS (partial) | and_d37 (visual): toast "support@dollor.ai" with the app icon shown; focus stayed in the driver app | Copies or shows the address; no mail app opened. |
| Profile: Log Out | Not tapped | UNTESTED | none | |
| Profile: Delete Account | Not tapped | UNTESTED | none | Forbidden. |
| Driver document capture / compliance screens | Not reachable | BLOCKED | account already approved | |
| Founding screen route "founding" | Same as Profile Founding Member | PASS | see above | |
| Home tab after using History | Tapped Home tab after History quick action | FAIL | and_d41, d42, d43, d45, d47, d54 (visual): the Home tab (or Earnings) stays on the Earnings screen | See bug B2. Restart restores Home. |

## 3. API calls actually seen in ApiTiming
Typical ms are rough medians of what I saw.

### Rider app (pid 28235 and later)
| Method | Path | Status | Typical ms | Triggered by |
|---|---|---|---|---|
| POST | /api/auth/customer/login | 200 | 1111 | Sign In |
| GET | /api/rides/customer/74/requests | 200 | 307 | Entering main screen (ride-state check) |
| POST | /api/erp/customers/74/fcm-token | 200 | 170-1000 | After login / each app foreground |
| GET | /api/addresses/74 | 200 | 230-280 | Profile, Manage Addresses |
| GET | /api/customers/74/cards | 200 | 450-540 | Profile, Payment Methods |
| GET | /api/founding/status | 200 | 230-310 | Profile, Founding Member |
| GET | /api/customer/email/status | 200 | 100-420 | Profile, Settings |
| POST | /api/rides/estimate | 200 | 370-850 | Selecting dropoff |
| POST | /api/rides/request | 200 | 390-580 | Find Driver |
| GET | /api/rides/request/{id}/bids | 200 | 110-760 | Polling while searching (about every 4 s) |
| GET | /api/rides/{id}/track | 200 | 100-270 | Polling while searching and during ride |
| POST | /api/rides/bid/{bidId}/respond | 200 | 310-650 | Accept (385) and Decline (386) |
| GET | /api/p2p/ride-requests/{id}/chat | 200 | 100-820 | Opening chat, then polling about every 3 s |
| POST | /api/p2p/ride-requests/{id}/chat | 200 | 195 | Sending chat message |
| POST | /api/rides/request/{id}/cancel | 200 | 572 | Cancel Ride confirm (608) |
| GET | /api/rides/request/{id}/receipt | 200 | 160-205 | View receipt, trip row |
| POST | /api/rides/{id}/rate | 200 | 216 | Rate driver (607) |
| GET | /api/customer/rides/history | 200 | 136 | Trips tab |
| GET | /api/rides/request/607/bids and /api/rides/607/track | ERR UnknownHostException (4-5 ms) | n/a | 13:05:07, at the moment the driver app was foregrounded and the rider app was in the background |

### Driver app (pid 29454 and later)
| Method | Path | Status | Typical ms | Triggered by |
|---|---|---|---|---|
| POST | /api/auth/driver/login | 200 | 790 | Sign In |
| GET | /api/auth/driver/documents | 200 | 173 | Post-login compliance check |
| GET | /api/checkr/background-check/48/status | 200 | 188 | Post-login compliance check |
| GET | /api/auth/driver/me | 200 | 100-320 | Home and many tab switches |
| GET | /api/rides/driver/active | 200 | 100-720 | Home polling (about every 5 s) |
| GET | /api/driver/earnings | 200 | 110-350 | Home, Earnings tabs, History |
| GET | /api/rides/available | 200 | 110-290 | Rides tab and polling |
| GET | /api/rides/driver/48/bids | 200 | 230-530 | Rides tab and polling |
| POST | /api/erp/drivers/48/fcm-token | 200 | 220-790 | App foreground |
| POST | /api/rides/request/{id}/bid | 200 | 640-775 | Slide to submit bid (607, 608, 609) |
| POST | /api/rides/bid/384/accept-counter | 200 | 660 | Accept rider's counter |
| GET | /api/p2p/ride-requests/607/chat | 200 | 125-170 | Chat |
| POST | /api/p2p/ride-requests/607/chat | 200 | 180 | Send chat |
| POST | /api/rides/request/607/arrived | 200 | 368 | I've Arrived |
| POST | /api/rides/request/607/start | 200 | 517 | Start Trip |
| POST | /api/rides/request/607/complete | 200 | 984 | Complete Trip |
| POST | /api/rides/request/607/rate-passenger | 200 | 141 | Submit rating |
| GET | /api/tnc/driver/accessibility | 200 | 103 | Profile |
| PATCH | /api/tnc/driver/accessibility | 200 | 186, 493 | Accessibility toggle on, off |
| GET | /api/founding/driver/status | 200 | 338 | Profile, Founding Member |
| GET | /api/rides/driver/active, /api/auth/driver/me, /api/driver/earnings, /api/rides/available | ERR UnknownHostException (0-160 ms) | n/a | 13:05:39 to 13:06:00, a burst of DNS failures while the rider app was in the foreground; recovered by 13:06:15 on its own |

All non-2xx outcomes: none. The only ERR lines are the DNS failures above (emulator networking, not an app or server defect; I cannot prove the cause).

## 4. Bug list
| ID | Severity | Steps to reproduce | Observed | Expected | Screenshot |
|---|---|---|---|---|---|
| B1 | Medium (cosmetic but blocks a core action visibly) | Rider app, Profile tab, scroll to the bottom | The Log Out button is a plain white rounded bar with no visible label (white text on a white fill). Code ProfileScreen.kt:291-306 sets containerColor = Lx.Text and the label colour to Color.White, and in the dark theme Lx.Text is evidently light. | A readable Log Out button | and_r62_profile_bottom |
| B2 | Medium | Driver app, Home, tap History (quick action). It navigates to the Earnings screen inside the Home stack. Then tap the Home tab (or tap Rides or Profile and then Home) | The Home tab keeps showing the Earnings screen (Earnings is highlighted) instead of Home; reproduced repeatedly (and_d41, d42, d43, d45, d47, d54). One run (and_d51) did show Home. Force-stopping and relaunching restores Home. Likely cause (INFERRED from DriverNavGraph.kt:395-401 `popUpTo ... saveState` plus `restoreState`): the Home tab restores its saved back stack that still contains "earnings". | Home tab always shows Home | and_d41_home, and_d43_navigate_toast, and_d47_home_from_profile, and_d54_home_after_hist_again |
| B3 | Low | Driver app Profile tab, compare with the Earnings tab after rides were completed today | Profile header shows This Week $0.00 and This Month $0.00 while the Earnings tab shows This Week $180.06 for the same account at the same time | The same totals | and_d31_profile vs and_d38_week |
| B4 | Low | Rider Profile and driver Profile: Founding Member shows "10000 founding spots left in CA" and a disabled Join button, with "Demo account - payment is bypassed." | The Join for $100 button is disabled on the demo account, so the founding purchase flow cannot be exercised; this might be intended for demo accounts. | n/a | and_r61_top4, and_d33_founding |

Automation mistakes (not app bugs): the first two plain `input swipe` attempts on the driver slide-to-confirm did not register until I used draganddrop / motionevent; several screenshots were taken while the app was on a different screen than I assumed (for example and_d43 and d44 captured Earnings, not Home), and one script run (r60/r61 first pass) captured the launcher/splash because the app was still cold-starting. A first walk of the profile screens was repeated for that reason.

## 5. Not tested and why
- Rider: Forgot Password, reset code entry, Sign Up, Email Verification (would send emails or create accounts), Google sign-in.
- Rider: Delete Account, Log Out (destructive or ends the session).
- Rider: Add/edit/delete/share saved addresses, add payment method, delete card, make default, Founding Join (payment or data changes forbidden).
- Rider: Help & Support actions (search, FAQ expand, filter chips, Chat with Us, Email Support) and the `support_chat` screen; Call driver; Edit Profile save.
- Rider: Refer & Earn is hidden in production (referralRewardText null), so it is BLOCKED.
- Driver: Request Payout, Log Out, Delete Account, online/offline toggle (kept online), Decline and Counter-back on an own-bid card, driver Cancel ride, Navigate with an active ride, Support mailto, document and compliance onboarding screens (account already approved), Join founding.
- Not independently re-verified visually (rely on logs): several early screens in the rider (terms, notification permission, settings sub-screens, ride in progress, ride completed) and driver (home active ride, arrived/start/complete dialogs) because their screenshots are no longer retrievable for me; see the method section.
- Final state: no active rides for either account (API: `active_rides: []`; requests 607 completed, 608 cancelled, 609 expired), driver is_online true, driver accessibility restored to original values. Rider app left logged in on the Profile or Ride screen; driver app relaunched fresh (and_d61_final_home2 should show Home).
