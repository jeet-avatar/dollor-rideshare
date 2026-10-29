# Dollor.ai - Play Store Listing (Rider App, ai.dollor.customer)

Rideshare marketplace. Every statement below is backed by the shipped code.
Screenshots and feature graphic in this folder (01-home ... 05-login, feature-graphic) are OLD food-delivery web captures: do not upload them. Capture new phone screenshots from the release build (ride request, fare estimate, bids, active ride, profile).

## App Title (30 chars max)
Dollor - Bid Your Ride

## Short Description (80 chars max)
Request a ride, compare driver bids, and pick the fare that works for you.

## Full Description (4000 chars max)

Dollor is a ride marketplace where independent drivers bid on your trip. Enter where you are going, see an estimated fare, and choose from the offers nearby drivers send you.

HOW IT WORKS
1. Enter your pickup and destination.
2. See an estimated fare with the fee breakdown before you request.
3. Nearby drivers can bid on your ride during a 5-minute bidding window.
4. Accept a bid, make a counter-offer, or decline.
5. Follow your driver on the map, message them in the app, and rate the trip when you arrive.

PRICING YOU CAN SEE
- Each ride has a flat connection fee based on the fare: $1 for fares up to $35, $2 for fares from $35 to $70, and $3 above $70.
- A $0.05 charge for the California Public Utilities Commission Access for All program is added to each ride.
- The fare estimate can vary with time of day and demand, and you always see the amount before you confirm.
- Tips are optional, and 100% of a tip goes to your driver.

FEATURES
- Fare estimate and fee breakdown before you request
- Driver bids with driver rating and vehicle details
- Counter-offers on any bid
- Live trip tracking on a map
- In-app chat with your driver
- Saved addresses and ride history with receipts
- Card payments processed by Stripe (cards are stored by Stripe, not by Dollor)
- Optional accessibility request when you book
- Rate your driver after every trip
- Help and support inside the app

ACCOUNT AND PRIVACY
- Sign up with your email address and a password.
- You can delete your account at any time from Profile in the app.
- Your phone number and exact destination are shared with your matched driver only for your trip.

Dollor is a peer-to-peer matchmaking platform. Drivers are independent contractors, not employees of Dollor. Service area: California.

## Keywords / tags (not a Play field; for reference)
rideshare, ride booking, driver bidding, fare estimate, transportation, trip tracking

## Category
Maps & Navigation   (alternative: Travel & Local). NOT Food & Drink.

## Content Rating
Everyone (complete the IARC questionnaire: no violence, no user-generated public content, in-app chat between matched users only)

## Contact Email
support@dollor.ai

## Website
https://www.dollor.ai

## Privacy Policy URL
https://api.dollor.ai/privacy   (static HTML page, HTTP 200; https://www.dollor.ai/privacy is also a route in the web app)

## Account deletion (Play Console "Data deletion" section)
In-app: Profile > Delete Account (also Settings > Delete Account).
Web URL: NONE EXISTS YET. https://www.dollor.ai/delete-account returns the web app shell, not a deletion page. Play requires a web link for account deletion: publish a page (or point to https://www.dollor.ai/support with deletion instructions) before submitting.

## Release Notes (v1.1.0)
- Rideshare marketplace: request a ride, receive driver bids, accept or counter.
- Fare estimate with fee breakdown before you request.
- Live trip tracking, in-app chat with your driver, receipts and ride history.
- Bug fixes and performance improvements.
