# Dollor - App Store Connect "App Privacy" answers (rider and driver iOS apps)

Derived from the code of the two shipped iOS apps (rider `com.dollorai.customer`, driver `com.dollorai.delivery`) and the two `PrivacyInfo.xcprivacy` files. Enter these answers in App Store Connect > App Privacy for each app.

Facts from code:
- No ad SDKs, no ATT prompt (`ATTrackingManager` not used), no tracking domains. `NSPrivacyTracking` = false in both manifests.
- No analytics SDK is linked on iOS (no Firebase Analytics, no Crashlytics). FirebaseAnalytics and its GoogleAppMeasurement* dependencies were removed from the driver target and nothing in either app imports them. Firebase is used for Auth (Google/Apple sign-in), Firestore and Cloud Messaging (push tokens).
- Rider app permissions (Info.plist): camera (Stripe card scanning), location when in use. Push notifications. No photo library, microphone, contacts, Bluetooth, Face ID.
- Driver app permissions: camera (document photos), photo library (profile photo and document picker), location when in use (the "Always" upgrade is requested only when a trip starts, for live trip tracking), microphone and speech recognition (voice dictation of chat messages), push notifications. Notification permission is requested in context (rider: after the first ride request; driver: when first going online), not at launch. Raw bank routing/account numbers are no longer collected in the app; payouts use Stripe Connect onboarding in an in-app browser.

## Tracking
Data is not used to track users. Answer "No" to "Do you or your third-party partners use data from this app for tracking?".

## Rider app: data types collected (all linked to the user, none used for tracking)

| Apple category | Data type | Purpose | Notes |
|---|---|---|---|
| Contact Info | Name | App Functionality | Shared with matched driver (first name) |
| Contact Info | Email Address | App Functionality | Account |
| Contact Info | Phone Number | App Functionality | Shared with matched driver for the trip |
| Contact Info | Physical Address | App Functionality | Saved addresses, pickup and destination |
| Location | Precise Location | App Functionality | While the app is in use |
| Financial Info | Payment Info | App Functionality | Card entered into Stripe's form; Dollor stores Stripe tokens and card brand/last 4 |
| Purchases | (not declared) | - | Ride receipts are order records, not In-App Purchases; declare under "Other User Content" below if you prefer to be conservative |
| User Content | Other User Content | App Functionality | Chat messages with driver and support, chat reports (reason and details) and block list, optional accessibility request text |
| Identifiers | Device ID | App Functionality | Push token (FCM) linked to the account |
| Health and Fitness | (consider "Health") | App Functionality | Optional accessibility request: only if the rider turns it on; Apple has no disability category, "Other User Content" is the closest |

Not collected by the rider app: Photos or Videos (changed: previously declared, removed because the rider app has no photo upload and no photo library permission), Contacts, Browsing/Search History, Usage Data, Diagnostics, Audio, Sensitive Info.

## Driver app: data types collected (all linked to the user, none used for tracking)

| Apple category | Data type | Purpose | Notes |
|---|---|---|---|
| Contact Info | Name | App Functionality | Shared with matched rider |
| Contact Info | Email Address | App Functionality | Account |
| Contact Info | Phone Number | App Functionality | Shared with matched rider for the trip |
| Location | Precise Location | App Functionality | While online, including in the background (location background mode is on) |
| User Content | Photos or Videos | App Functionality | Photos of driver's license and insurance card; profile photo |
| User Content | Other User Content | App Functionality | Chat messages, vehicle details, optional accessibility setting |
| Financial Info | Other Financial Info | App Functionality | Earnings and payout history; bank details are entered on Stripe's hosted page |
| Identifiers | Device ID | App Functionality | Push token (FCM) linked to the account |
| Sensitive Info | (Checkr result) | App Functionality | Background check is done on Checkr's hosted page; Dollor stores only the status |

Voice dictation uses Apple's on-device/server speech recognition (`SFSpeechRecognizer`, `requiresOnDeviceRecognition = false`). Audio goes to Apple, not to Dollor; Dollor receives only the text the driver sends as a chat message. Apple does not require declaring data that only Apple processes, but keep this in the privacy policy.

## Changes made to PrivacyInfo.xcprivacy in this cleanup
- Rider: removed `PhotosorVideos` (not collected). `DeviceID` purpose changed from Analytics to AppFunctionality and linked = true (it is the push token; there is no analytics SDK).
- Driver: `DeviceID` purpose changed from Analytics to AppFunctionality and linked = true. `PhotosorVideos` stays (document and profile photos).

## Console actions
1. Enter the tables above in App Store Connect for each app.
2. Privacy Policy URL: https://api.dollor.ai/privacy (static page, HTTP 200).
3. Account deletion: in app, Profile > Delete Account (rider also Settings > Delete Account). Apple 5.1.1(v) is met by the in-app path.
