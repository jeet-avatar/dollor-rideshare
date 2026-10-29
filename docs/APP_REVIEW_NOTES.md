# App review notes (Apple App Review and Google Play review)

Paste the relevant parts into App Store Connect "App Review Information" (notes) and the Play Console "App access" section. The same text is in `apps/ios/customer/fastlane/metadata/review_information/notes.txt` and `apps/ios/delivery/fastlane/metadata/review_information/notes.txt`.

## What the apps are
Dollor is a ride marketplace for California. Riders request a ride, independent drivers bid on it, and the rider accepts, counters or declines. There are two apps: the rider app (iOS `com.dollorai.customer`, Android `ai.dollor.customer`) and the driver app (iOS `com.dollorai.delivery`, Android `ai.dollor.driver`). Neither app sells any digital goods or subscriptions. The only payments are the fare for a real-world ride (and an optional tip), charged by Stripe.

## Demo logins (email and password only; do not use Google or Apple sign-in for these)

| App | Email | Password |
|---|---|---|
| Rider | demo.customer@dollor.ai | DemoCustomer2025! |
| Driver | demo.driver@dollor.ai | DemoDriver2025! |

Both accounts are real accounts on the production server (api.dollor.ai). Demo accounts skip card charges: no money is charged, and a ride made with the demo rider is paid with a "demo" payment marker. The demo rider already has a saved payment method, so no card entry is needed.

## Important: the demo driver must be online with a location
Rides are only offered to drivers who are online and have a recent location. To test the full flow with two devices:
1. Sign in to the driver app with the demo driver, allow location, and tap the Online switch on the home screen (iOS: Go Online on the dashboard). If you test on a simulator or emulator, set a location (Simulator: Features > Location > Custom location; Android emulator: Extended controls > Location) in California, near the pickup you will use.
2. Keep the driver app open and online.
3. Then request the ride from the rider app with a pickup near the same location.
A request made while no driver is online simply stays open for the 5-minute bidding window and then expires. That is expected behaviour, not a crash.

## How to reach each feature

### Rider app
- Sign in: Login screen > email and password.
- Request a ride: Home/Ride tab > enter pickup and destination > fare estimate with fee breakdown > Request / Find Driver.
- Bids: bids from drivers appear on the same screen during the 5-minute bidding window. Accept, Counter, or Decline.
- Active ride: live map, driver details, in-app chat with the driver, Cancel Ride.
- After the trip: rate the driver, optional tip, receipt in the Trips tab.
- Payment methods: Profile > Payment Methods (cards are entered into Stripe's card form; the app never sees full card numbers).
- Saved addresses: Profile > Manage Addresses.
- Settings: Profile > Settings.
- Help and FAQ, contact support: Profile > Help & Support (FAQ list, chat, email, phone).
- Safety information: Profile > Safety Features. On iOS the active ride screen also has Share trip and an emergency button that calls 911 from the phone.
- Account deletion: Settings > Delete Account (Android also at the bottom of Profile; iOS Profile > Delete Account). It asks for confirmation, deletes the account and signs the user out.

### Driver app
- Sign in: Driver login > email and password (Android also offers Continue with Google; do not use it for the demo). The demo driver is already approved, with documents and background check done, so setup screens are skipped.
- Go online: home screen Online switch (Go Online on iOS). Location permission is required.
- Ride requests: Available/Requests list > open a request > Submit Bid. The bid sheet shows the estimated earnings after fees before submitting. Rider counter-offers appear under My Bids / Counter-offers.
- Active ride: navigate to pickup (opens Google Maps), arrive, start, complete, rate rider; chat with the rider.
- Earnings: Earnings tab (and Profile > Earnings History) shows trip earnings and payouts (Request Payout button).
- Support: Android: Profile > Help & Support (opens an email to support@dollor.ai) and Home > Support. iOS: Profile > support/legal links.
- Account deletion: Profile > Delete Account.
- Real drivers must submit a license and insurance card and complete a Checkr background check, then be approved, before the server lets them go online.

## Fees and payments
- Payments use Stripe. Riders pay with a card (Apple Pay is also offered on iOS where the device supports it).
- Fee model: a flat connection fee based on the fare ($1 up to $35, $2 from $35 to $70, $3 above $70) charged to the rider and to the driver, plus a $0.05 California Public Utilities Commission Access for All charge on each side. Tips are optional and go 100% to the driver.
- There is no in-app purchase, subscription, membership or any other digital item. (The earlier "Founding Member" $100 membership was removed from all four apps before this submission.)

## Permissions and why
- Location (rider: while using the app; driver: while online, and in the background on iOS during rides): pickup location, nearby requests, live trip tracking.
- Camera: rider iOS, scan a card when adding a payment method; rider Android, profile photo; driver, photos of license and insurance card.
- Photo library (driver iOS and Android): choose a profile photo or document image.
- Microphone and speech recognition (driver iOS only): dictate chat messages.
- Notifications: ride and bid updates.
- No tracking, no ads, no contacts, no Bluetooth.

## Contact
support@dollor.ai. Operator: Zietra Technologies, Inc., Rancho Santa Margarita, CA 92688. CPUC TNC permit application PSG0050982 (the application is in review; do not describe the service as licensed).
