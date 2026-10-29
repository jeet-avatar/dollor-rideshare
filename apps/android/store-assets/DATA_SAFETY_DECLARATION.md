# Dollor.ai - Google Play Data Safety Declaration (rider + driver apps)

Derived from the code of the two shipped Android apps (rider `ai.dollor.customer`, driver `ai.dollor.driver`). The restaurant/partner app is not part of this launch and is not covered here.

Sources checked: both `AndroidManifest.xml` files (permissions), `shared/build.gradle.kts` (Firebase Auth, Firestore, Storage, Messaging, Analytics; Stripe in the rider app only), register/profile/ride/chat/compliance screens, `DollorApiService.kt`.

## Form answers common to both apps

| Question | Answer |
|---|---|
| Does the app collect or share required user data types? | Yes |
| Is all data encrypted in transit? | Yes (HTTPS only) |
| Can users request deletion? | Yes. In app: Profile > Delete Account. Web link: none exists yet (see "Console actions") |
| Ads / advertising ID | No ads, no ad SDKs, no advertising ID use |
| Data sold | No |
| Independent security review | No |
| Families Policy | Not designed for children |
| Account creation methods | Email and password (rider); email and password or Google sign-in (driver) |

## Rider app (ai.dollor.customer)

Permissions in manifest: INTERNET, ACCESS_NETWORK_STATE, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, CAMERA (optional, profile photo; photo stays on the device), POST_NOTIFICATIONS, VIBRATE.

| Play data type | Collected | Shared | Optional | Purpose | Source in code |
|---|---|---|---|---|---|
| Personal info > Name | Yes | Yes, first name to matched driver | Required | App functionality, account management | RegisterScreen.kt |
| Personal info > Email address | Yes | No | Required | Account management, communications | RegisterScreen.kt |
| Personal info > Phone number | Yes | Yes, to matched driver for the trip | Required | App functionality | RegisterScreen.kt |
| Personal info > Address (ZIP code, saved addresses) | Yes | Pickup and destination shared with matched driver | Saved addresses optional | App functionality | RegisterScreen.kt, SavedAddressesScreen.kt |
| Location > Precise location | Yes, only while the app is open | Yes, pickup point to drivers who see the request | Required to request a ride | App functionality | RideRequestScreen.kt (ACCESS_FINE_LOCATION) |
| Financial info > Payment info (card) | Entered into Stripe's card form; Dollor stores only Stripe tokens and the card brand/last 4 | Yes, with Stripe (payment processor) | Required to book | App functionality (payments) | PaymentMethodsScreen.kt |
| Financial info > Purchase history (ride receipts) | Yes | No | Required | App functionality | TripsScreen.kt |
| Health and fitness > Health info (optional accessibility request) | Yes, only if the rider turns it on | Yes, to the matched driver | Optional | App functionality | RideRequestViewModel.kt (accessibility options and notes) |
| Messages > Other in-app messages (chat with driver and with support) | Yes | Yes, chat with driver is visible to that driver | Optional | App functionality | DriverChatScreen.kt, SupportChatScreen.kt |
| App activity > App interactions | Yes (Firebase Analytics default events) | No | Required | Analytics | `firebase-analytics-ktx` dependency |
| Device or other IDs (FCM token, Firebase installation ID) | Yes | No | Required | App functionality (push), Analytics | DollorFirebaseMessagingService.kt |
| Photos and videos | No. The profile photo is chosen/taken on the device and stored locally only (ProfileViewModel.onProfileImageChange saves a URI) | - | - | - | ProfileScreen.kt |
| Contacts, calendar, audio, files, web history, crash logs/diagnostics | Not collected (no Crashlytics, no Sentry) | - | - | - | - |

Sharing statement for "Shared": data given to the matched driver is part of the ride and is disclosed in-app (Profile > What Drivers See). Data given to Stripe is processing on Dollor's behalf (service provider). Google Maps and Firebase act as service providers.

## Driver app (ai.dollor.driver)

Permissions in manifest: INTERNET, ACCESS_NETWORK_STATE, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, CAMERA (document photos), POST_NOTIFICATIONS, VIBRATE. There is NO background location permission and no foreground-service location permission.

| Play data type | Collected | Shared | Optional | Purpose | Source in code |
|---|---|---|---|---|---|
| Personal info > Name | Yes | Yes, to matched rider | Required | App functionality, account management | driver login/registration |
| Personal info > Email address | Yes | No | Required | Account management, communications | driver login/registration |
| Personal info > Phone number | Yes | Yes, to matched rider for the trip | Required | App functionality | driver profile |
| Personal info > Other info (driver's license, insurance card, vehicle make/model/plate) | Yes | No (vehicle and plate are shown to the matched rider) | Required to drive | App functionality, fraud prevention and safety (verification) | DriverDocumentCaptureScreen.kt, DriverDocumentViewModel.kt |
| Photos and videos (photos of license and insurance card) | Yes | No | Required to drive | App functionality (verification) | DriverDocumentCaptureScreen.kt |
| Location > Precise location | Yes, only while the driver is online and the app is open | Yes, live position to the matched rider during a trip | Required to go online | App functionality | DriverHomeViewModel.kt |
| Financial info > Other financial info (earnings, payout history; bank details are entered on Stripe's hosted onboarding page and are not stored by the app) | Yes | Yes, with Stripe for payouts | Required to be paid | App functionality | EarningsViewModel.kt |
| Messages > Other in-app messages | Yes | Chat is visible to the rider | Optional | App functionality | driver ride chat |
| Health and fitness > Health info (optional accessibility setting: extra trunk space for mobility aids) | Yes | No | Optional | App functionality | Profile > Accessibility |
| App activity > App interactions | Yes (Firebase Analytics default events) | No | Required | Analytics | `firebase-analytics-ktx` dependency |
| Device or other IDs (FCM token, Firebase installation ID) | Yes | No | Required | App functionality (push), Analytics | DriverFirebaseMessagingService.kt |
| Background check (name, date of birth, SSN, license number) | Entered on the Checkr-hosted page opened from the app; Dollor receives only the result/status | Checkr is the service provider | Required to drive | Fraud prevention, safety and compliance | DriverNavGraph.kt (opens Checkr URL) |

## Third parties used by the apps

| Service | Purpose | Data |
|---|---|---|
| Stripe | Rider card payments; driver payouts | Card details (rider, entered in Stripe's form), bank details (driver, Stripe-hosted) |
| Google Maps / Places / Location | Maps, address search, location | Location, search text |
| Firebase (Auth, Firestore, Storage, Cloud Messaging, Analytics) | Push notifications, analytics | Device tokens, installation ID, app interactions |
| Checkr | Driver background check | Identity data entered on Checkr's page |

## Account deletion (Play Console)

- Rider: Profile > Delete Account (also Settings > Delete Account). Driver: Profile > Delete Account.
- Retention to state in the console: transaction and ride records may be kept where required for tax, legal or CPUC compliance. Confirm the retention period with the backend owner before filling the form (the previous draft said 90 days deletion and 7 years for tax records; neither number was verified in code).
- Web URL for deletion requests: none exists yet. `https://www.dollor.ai/delete-account` serves the web-app shell, not a deletion page.

## Console actions needed (cannot be done from the repo)

1. Fill the Data safety form from the tables above (rider and driver separately).
2. Provide a web page for account deletion requests (required by Play) and enter its URL.
3. Set the privacy policy URL to https://api.dollor.ai/privacy (static page, HTTP 200). Its text must stay consistent with this form.
4. Confirm that the privacy policy covers: Firebase Analytics, optional accessibility information, chat messages, driver documents.

Last reviewed: 2026-10-29 (from code at origin/main 4754f72e3 plus the store cleanup changes).
