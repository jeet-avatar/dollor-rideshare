# Dollor.ai iOS TestFlight QA Checklist

## Test Credentials
```
Customer: demo.customer@dollor.ai / DemoCustomer2025!
Driver:   demo.driver@dollor.ai / DemoDriver2025!
Vendor:   demo.restaurant@dollor.ai / DemoRestaurant2025!
```

---

## 1. CUSTOMER APP (Dollor)

### Authentication
- [ ] Google Sign-In works
- [ ] Email/Password login works
- [ ] Registration with new account
- [ ] Logout works
- [ ] Session persists after app restart

### Location & Maps
- [ ] Location permission prompt appears
- [ ] Map loads correctly (Google Maps)
- [ ] Current location shows on map
- [ ] Can search for addresses
- [ ] Nearby restaurants appear based on location

### Food Ordering Workflow
- [ ] Browse restaurants list
- [ ] View restaurant menu
- [ ] Add items to cart
- [ ] View cart with correct totals
- [ ] $1 platform fee shows correctly
- [ ] Checkout flow works
- [ ] Can enter delivery address
- [ ] Payment sheet appears (Stripe)
- [ ] Order confirmation screen
- [ ] Order tracking updates in real-time

### Rideshare Workflow
- [ ] Rideshare tab accessible
- [ ] Can enter pickup location
- [ ] Can enter destination
- [ ] Fare estimate shows correctly
- [ ] Platform fee tier displays ($1/$2/$3)
- [ ] Can request ride
- [ ] Driver bids appear
- [ ] Can accept a bid
- [ ] Ride tracking works

### General
- [ ] Push notifications received
- [ ] Order history displays
- [ ] Profile/settings accessible
- [ ] Terms of Service link works
- [ ] Privacy Policy link works
- [ ] Support contact works

---

## 2. DRIVER APP (Dollor Driver)

### Authentication
- [ ] Email/Password login works
- [ ] Driver code login works
- [ ] Registration flow
- [ ] Document upload works
- [ ] Logout works

### Location & Maps
- [ ] Location permission (always) prompt
- [ ] Background location works
- [ ] Map shows current location
- [ ] Navigation to pickup/dropoff

### Food Delivery Workflow
- [ ] Available orders list shows
- [ ] Can view order details
- [ ] Can accept delivery
- [ ] "Arrived at Restaurant" button works
- [ ] "Picked Up" button works
- [ ] Navigation to customer
- [ ] "Delivered" button works
- [ ] Earnings update correctly (keeps 100%)

### Rideshare Workflow
- [ ] Available ride requests show
- [ ] Can view ride details
- [ ] Can submit bid (negotiation)
- [ ] Bid confirmation
- [ ] "Arrived at Pickup" works
- [ ] "Start Trip" works
- [ ] "Complete Trip" works
- [ ] Earnings show fare minus platform fee

### General
- [ ] Earnings dashboard accurate
- [ ] Online/Offline toggle works
- [ ] Push notifications for new orders
- [ ] Order history displays

---

## 3. RESTAURANT APP (Dollor Restaurant)

### Authentication
- [ ] Google Sign-In works
- [ ] Email/Password login
- [ ] Logout works

### Order Management
- [ ] Incoming orders appear
- [ ] Push notification for new orders
- [ ] Can view order details
- [ ] "Accept Order" works
- [ ] "Preparing" status update
- [ ] "Ready for Pickup" works
- [ ] Order history displays

### Menu Management
- [ ] View menu items
- [ ] Add new menu item
- [ ] Upload item image
- [ ] Edit item price
- [ ] Toggle item availability
- [ ] Delete menu item

### Dashboard
- [ ] Today's orders count
- [ ] Revenue display
- [ ] Analytics/stats visible

---

## End-to-End Workflow Tests

### Test 1: Complete Food Delivery
1. **Customer**: Place order at a restaurant
2. **Restaurant**: Accept order → Mark preparing → Mark ready
3. **Driver**: Accept delivery → Pickup → Deliver
4. **Customer**: Verify order shows delivered

### Test 2: Complete Rideshare
1. **Customer**: Request ride (pickup → destination)
2. **Driver**: View request → Submit bid
3. **Customer**: Accept driver's bid
4. **Driver**: Arrive → Start trip → Complete trip
5. **Customer**: Verify ride completed

### Test 3: Negotiation Flow
1. **Customer**: Request ride
2. **Driver**: Submit custom bid (lower than estimate)
3. **Customer**: See bid, accept negotiated price
4. Verify both see correct amounts

---

## API Verification
- [ ] App connects to `https://api.dollor.ai` (production)
- [ ] No local-host or unreachable-API errors in console
- [ ] Real-time updates work (WebSocket)

---

## Known Issues to Watch
- dSYM warnings (Firebase) - cosmetic only, doesn't affect functionality
- First location request may take a few seconds

---

## Reporting Issues
If you find bugs, note:
1. Which app (Customer/Driver/Restaurant)
2. Steps to reproduce
3. Expected vs actual behavior
4. Screenshot if possible

