# Quick Start Guide - Testing Backend Integration

## **Prerequisites**
- Android Studio installed
- Firebase project configured (eatfair-app)
- All three apps built successfully

---

## **1. Install All Apps**

```bash
# Navigate to project directory
cd <repo-root>

# Build all apps
./gradlew assembleDebug

# Install Customer App
adb install -r app/build/outputs/apk/debug/app-debug.apk

# Install Partner App
adb install -r partner/build/outputs/apk/debug/partner-debug.apk

# Install Delivery Driver App
adb install -r orderapp/build/outputs/apk/debug/orderapp-debug.apk
```

---

## **2. Test Complete Flow**

### **Step 1: Create User Account (Customer App)**

1. Open **EatFair Customer** app
2. Click **"Sign Up"**
3. Enter details:
   - Email: `test@example.com`
   - Password: `password123`
   - Name: `Test User`
   - Phone: `+1234567890`
   - Zip Code: `12345`
4. Click **"Sign Up"**

**Verify in Firebase Console**:
- Go to: https://console.firebase.google.com/project/eatfair-app/authentication/users
- You should see the new user
- Go to: https://console.firebase.google.com/project/eatfair-app/firestore/data
- Navigate to `users/{userId}` - you should see the profile

---

### **Step 2: Place Order (Customer App)**

1. Login with the account you just created
2. Browse restaurants (should see 3 sample restaurants)
3. Click on a restaurant
4. Add items to cart
5. Click **"View Cart"**
6. Click **"Proceed to Checkout"**
7. Complete the order

**Verify in Firestore**:
- Go to Firestore Console
- Navigate to `orders` collection
- You should see a new order document with:
  - `orderId`: "EF..." format
  - `status`: "ORDER_PLACED"
  - `customerId`: Your user ID
  - `items`: Array of items
  - All order details

---

### **Step 3: Accept Order (Partner App)**

1. Open **EatFair Partner** app
2. Navigate to **"Orders"** tab
3. You should see the order you just placed
4. Click **"Accept"** on the order

**Verify in Firestore**:
- Refresh the order document
- `status` should now be: "PREPARING"
- `updatedAt` should be updated

**Verify in Customer App**:
- Go back to customer app
- Order status should update to "Preparing"

---

### **Step 4: Mark as Ready (Partner App)**

1. In Partner app
2. Click **"Mark as Ready"** on the order

**Verify in Firestore**:
- `status` should now be: "OUT_FOR_DELIVERY"

---

### **Step 5: Deliver Order (Driver App)**

1. Open **EatFair Delivery** app
2. You should see the active order
3. Update status through the delivery flow
4. Mark as delivered

**Verify in Firestore**:
- `status` should now be: "DELIVERED"

**Verify in Customer App**:
- Order should show as "Delivered"

---

## **3. Monitor Real-time Updates**

### **Open Multiple Devices/Emulators**

**Device 1**: Customer App
**Device 2**: Partner App
**Device 3**: Driver App

**Test Real-time Sync**:
1. Place order on Device 1 (Customer)
2. Immediately see it appear on Device 2 (Partner)
3. Accept on Device 2
4. See status update on Device 1
5. Mark ready on Device 2
6. See update on Device 3 (Driver)
7. Deliver on Device 3
8. See final status on Device 1

---

## **4. Test Address Management**

### **Add Address (Customer App)**

1. Open Customer app
2. Go to Profile → Addresses
3. Click **"Add Address"**
4. Fill in details
5. Save

**Verify in Firestore**:
- Navigate to `users/{userId}/addresses`
- You should see the new address document

**Verify Local Storage**:
- Address should also be in Room database
- Works offline

---

## **5. Common Issues & Solutions**

### **Issue: User not created in Firestore**

**Solution**:
- Check internet connection
- Check Firebase Console → Authentication is enabled
- Check Firestore rules allow writes

### **Issue: Order not appearing in Partner app**

**Solution**:
- Verify `restaurantId` matches
- Check Firestore listener is active
- Refresh the app

### **Issue: Status not updating in real-time**

**Solution**:
- Check internet connection
- Verify Firestore listeners are set up
- Check Firebase Console for the update

---

## **6. Firebase Console Quick Links**

- **Authentication**: https://console.firebase.google.com/project/eatfair-app/authentication/users
- **Firestore**: https://console.firebase.google.com/project/eatfair-app/firestore/data
- **Project Settings**: https://console.firebase.google.com/project/eatfair-app/settings/general

---

## **7. Useful ADB Commands**

```bash
# Check connected devices
adb devices

# View logs for customer app
adb logcat | grep "com.eatfair.app"

# View logs for partner app
adb logcat | grep "com.eatfair.partner"

# View logs for driver app
adb logcat | grep "com.eatfair.orderapp"

# Clear app data (customer)
adb shell pm clear com.eatfair.app

# Uninstall all apps
adb uninstall com.eatfair.app
adb uninstall com.eatfair.partner
adb uninstall com.eatfair.orderapp
```

---

## **8. Firestore Data Verification**

### **Check User Profile**

```
Firestore → users → {userId}

Expected fields:
- userId: String
- name: String
- email: String
- phone: String
- zipCode: String
- role: "customer"
- createdAt: Timestamp
- updatedAt: Timestamp
```

### **Check Order**

```
Firestore → orders → {orderId}

Expected fields:
- orderId: String (EF...)
- customerId: String
- customerName: String
- restaurantId: Number
- restaurantName: String
- items: Array
- subtotal: Number
- deliveryFee: Number
- tax: Number
- totalAmount: Number
- status: String
- deliveryAddress: Map
- createdAt: Timestamp
- updatedAt: Timestamp
```

### **Check Address**

```
Firestore → users → {userId} → addresses → {addressId}

Expected fields:
- id: Number
- locationName: String
- completeAddress: String
- houseNumber: String
- apartmentRoad: String
- latitude: Number
- longitude: Number
- isDefault: Boolean
- createdAt: Timestamp
```

---

## **9. Testing Checklist**

- [ ] User signup creates Firebase Auth user
- [ ] User profile saved to Firestore
- [ ] User login works with Firebase Auth
- [ ] Order creation saves to Firestore
- [ ] Order appears in Partner app
- [ ] Partner can accept order
- [ ] Status updates in real-time
- [ ] Partner can mark as ready
- [ ] Driver can update delivery status
- [ ] Customer sees all status updates
- [ ] Address saves to Firestore
- [ ] Address saves to Room DB
- [ ] Cart clears after order

---

## **10. Sample Test Data**

### **Test User 1**
- Email: `customer1@test.com`
- Password: `test123456`
- Name: `John Doe`
- Phone: `+1234567890`
- Zip: `10001`

### **Test User 2**
- Email: `customer2@test.com`
- Password: `test123456`
- Name: `Jane Smith`
- Phone: `+0987654321`
- Zip: `10002`

### **Test Address**
- Location: `Home`
- House: `123`
- Street: `Main Street`
- Complete: `123 Main Street, New York, NY 10001`
- Lat: `40.7580`
- Lng: `-73.9855`

---

## **Success Criteria** ✅

Your integration is working correctly if:

1. ✅ New users appear in Firebase Authentication
2. ✅ User profiles appear in Firestore `users` collection
3. ✅ Orders appear in Firestore `orders` collection
4. ✅ Order status updates in real-time across all apps
5. ✅ Addresses save to both Room DB and Firestore
6. ✅ All apps can read and write to Firestore
7. ✅ No crashes or errors during the flow

---

**Happy Testing!** 🎉

For detailed implementation information, see: `BACKEND_INTEGRATION_COMPLETE.md`
