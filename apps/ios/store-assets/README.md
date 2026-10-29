# App Store screenshots (captured 2026-10-29)

Source: Release simulator builds of CURRENT_PROJECT_VERSION 202610291200 on the iPhone 16 Pro Max simulator (iOS 18.6), prod API, demo accounts. Status bar overridden to 9:41.

Size produced: 1320x2868 (iPhone 6.9-inch display), PNG, RGB. This is an accepted size for the required 6.9-inch iPhone slot.

| Folder | App | Files |
|---|---|---|
| customer/ | Dollor (rider) | 01-request, 02-bids, 03-matched, 04-chat, 05-trips, 06-receipt, 07-profile, 08-safety |
| delivery/ | Dollor Driver | 01-available, 02-submit-bid, 03-my-bids, 04-active-ride, 05-chat, 06-profile-earnings, 07-payouts, 08-online-home |

Counts: customer 8 and delivery 8 at 1320x2868 (iPhone 6.9-inch). The 6.9-inch set satisfies the required iPhone slot (Apple scales it down for smaller iPhones).

iPad: both apps are universal (TARGETED_DEVICE_FAMILY = "1,2" in customer/eatfaircustomer.xcodeproj/project.pbxproj and delivery/eatffairdelivery.xcodeproj/project.pbxproj), so Apple REQUIRES iPad 13-inch screenshots (2064x2752). NOT YET PRODUCED. Both Release apps are installed on the iPad Pro 13-inch (M4) iOS 18.6 simulator (F5D2A7BB-4584-4710-BAD1-CD88D4DE8446) but need login plus a full ride flow on that device. Missing required size: iPad 13-inch, 8 per app.

Not produced: 6.5-inch (1284x2778); optional because the 6.9-inch set is accepted.

Config change after capture: the only code delta since these shots is xcconfig/test host cleanup (CDN_URL, WEBSOCKET_URL now https://api.dollor.ai); no UI change.
