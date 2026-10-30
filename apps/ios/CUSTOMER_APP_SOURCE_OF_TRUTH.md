# Dollor Customer App - Source of Truth

> **Last Updated:** 2026-01-28
> **Current Build:** 32 (Version 1.0)
> **Status:** Submitted for App Store Review
> **Submission Date:** 2026-01-27

---

## App Identity (Build 32 - SUBMITTED)

| Property | Value |
|----------|-------|
| **App Name** | Dollor |
| **Display Name** | Dollor |
| **Bundle Name** | Dollor |
| **Bundle ID** | `com.dollorai.customer` |
| **Version** | 1.0 |
| **Build Number** | 32 |
| **Minimum iOS** | 17.0 |

---

## Apple Developer Configuration (Build 32)

| Property | Value |
|----------|-------|
| **Team ID** | `PRKZ4UVCD7` |
| **Account** | support2dollorai (App Store submission account) |
| **Application Identifier** | `PRKZ4UVCD7.com.dollorai.customer` |
| **Code Sign Style** | Manual |

---

## Google/Firebase Configuration (Build 32)

| Property | Value |
|----------|-------|
| **Firebase Project** | `dollorai-production` |
| **Google App ID** | `1:65740760476:ios:973eaffa167f09b142d459` |
| **GCM Sender ID** | `65740760476` |
| **Storage Bucket** | `dollorai-production.firebasestorage.app` |

### Google OAuth (Build 32)

| Property | Value |
|----------|-------|
| **iOS Client ID** | `65740760476-0cnsrucn1tvadbf193cgio2siosnjg02.apps.googleusercontent.com` |
| **Reversed Client ID (URL Scheme)** | `com.googleusercontent.apps.65740760476-0cnsrucn1tvadbf193cgio2siosnjg02` |
| **Android Client ID** | `65740760476-7t1cvgv5h86s6qhncmgbori9a060no1u.apps.googleusercontent.com` |
| **API Key** | `AIza<REDACTED-see-Google-Cloud-Console>` |

---

## Google Maps Configuration (Build 32)

| Property | Value |
|----------|-------|
| **Google Maps API Key** | `AIza<REDACTED-see-Google-Cloud-Console>` |

---

## Apple Pay / Stripe Configuration (PRODUCTION)

| Property | Value |
|----------|-------|
| **Merchant ID** | `merchant.com.dollorai.customer` |
| **Merchant Display Name** | Dollor |
| **Stripe Mode** | PRODUCTION (real payments) |
| **Stripe Account** | Dollor AI Production |

### Stripe Keys (LIVE - CONFIDENTIAL)

| Key | Value |
|-----|-------|
| **Publishable Key (pk_live)** | `[REDACTED - stored in AWS Secrets Manager]` |
| **Secret Key (sk_live)** | `[REDACTED - stored in AWS Secrets Manager]` |
| **Account ID** | `[REDACTED - stored in AWS Secrets Manager]` |
| **Mode** | `live` |
| **AWS Secret Path** | `dollor/production/stripe` |

> **SECURITY:**
> - pk_live is returned by backend API to iOS app
> - sk_live is ONLY on backend server - NEVER in iOS app
> - Keys stored in AWS Secrets Manager
> - Never commit actual keys to git

---

## Info.plist Configuration (Build 32 - ACTUAL SUBMITTED)

### App Identity Keys

```xml
<key>CFBundleDisplayName</key>
<string>Dollor</string>

<key>CFBundleName</key>
<string>Dollor</string>

<key>CFBundleIdentifier</key>
<string>com.dollorai.customer</string>

<key>CFBundleVersion</key>
<string>32</string>

<key>CFBundleShortVersionString</key>
<string>1.0</string>
```

### Required Keys

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>

<key>LSRequiresIPhoneOS</key>
<true/>

<key>UILaunchStoryboardName</key>
<string>LaunchScreen</string>

<key>UIRequiresFullScreen</key>
<true/>

<key>MinimumOSVersion</key>
<string>17.0</string>
```

### Google Maps API Key

```xml
<key>GOOGLE_MAPS_API_KEY</key>
<string>AIza<REDACTED-see-Google-Cloud-Console></string>
```

### Orientation Support

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
</array>

<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>

<key>UISupportedInterfaceOrientations~iphone</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

### Permission Descriptions (All Present in Build 32)

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Dollor AI Service needs your location to show nearby restaurants, request rides, and deliver food to you.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Dollor AI Service needs your location to show nearby restaurants, request rides, and track your delivery in real-time.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>Voice commands allow hands-free food ordering and ride requests.</string>

<key>NSMicrophoneUsageDescription</key>
<string>Microphone access enables voice search and voice commands for hands-free ordering.</string>

<key>NSCameraUsageDescription</key>
<string>Camera access allows you to scan payment cards and take profile photos.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access allows you to upload profile photos.</string>

<key>NSContactsUsageDescription</key>
<string>Contacts access allows you to quickly share your delivery address from your contacts.</string>
```

### URL Schemes (Build 32)

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.65740760476-0cnsrucn1tvadbf193cgio2siosnjg02</string>
        </array>
    </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>comgooglemaps</string>
    <string>tel</string>
    <string>sms</string>
</array>
```

### Background Modes

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

### App Transport Security

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>amazonaws.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## GoogleService-Info.plist (Build 32 - ACTUAL)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>CLIENT_ID</key>
    <string>65740760476-0cnsrucn1tvadbf193cgio2siosnjg02.apps.googleusercontent.com</string>

    <key>REVERSED_CLIENT_ID</key>
    <string>com.googleusercontent.apps.65740760476-0cnsrucn1tvadbf193cgio2siosnjg02</string>

    <key>ANDROID_CLIENT_ID</key>
    <string>65740760476-7t1cvgv5h86s6qhncmgbori9a060no1u.apps.googleusercontent.com</string>

    <key>API_KEY</key>
    <string>AIza<REDACTED-see-Google-Cloud-Console></string>

    <key>GCM_SENDER_ID</key>
    <string>65740760476</string>

    <key>BUNDLE_ID</key>
    <string>com.dollorai.customer</string>

    <key>PROJECT_ID</key>
    <string>dollorai-production</string>

    <key>STORAGE_BUCKET</key>
    <string>dollorai-production.firebasestorage.app</string>

    <key>GOOGLE_APP_ID</key>
    <string>1:65740760476:ios:973eaffa167f09b142d459</string>

    <key>IS_ADS_ENABLED</key>
    <false/>

    <key>IS_ANALYTICS_ENABLED</key>
    <false/>

    <key>IS_APPINVITE_ENABLED</key>
    <true/>

    <key>IS_GCM_ENABLED</key>
    <true/>

    <key>IS_SIGNIN_ENABLED</key>
    <true/>
</dict>
</plist>
```

---

## API Configuration

| Environment | Base URL |
|-------------|----------|
| **Production** | `https://api.dollor.ai` |

### Key Endpoints

| Endpoint | Description |
|----------|-------------|
| `/api/customer/google-auth` | Google Sign-In authentication |
| `/api/customer/apple-auth` | Apple Sign-In authentication |
| `/api/customer/orders` | Customer orders |
| `/api/restaurants` | Restaurant listings |
| `/api/config` | App configuration |
| `/api/payment/create-intent` | Stripe PaymentIntent |

---

## Build Archive Location

```
~/Library/Developer/Xcode/Archives/2026-01-27/Dollor-Build32.xcarchive
```

---

## Version History

| Build | Version | Date | Status | Notes |
|-------|---------|------|--------|-------|
| 32 | 1.0 | 2026-01-27 | Submitted | App Store Review |
| 33 | 1.0 | 2026-01-27 | Not Submitted | Archive exists |

---

## Legal URLs (Required for App Store)

| Document | URL |
|----------|-----|
| **Terms of Service** | `https://api.dollor.ai/terms` |
| **Privacy Policy** | `https://api.dollor.ai/privacy` |
| **Support** | `https://api.dollor.ai/support` |
| **Support Email** | `support@dollor.ai` |
| **Support Phone** | `+1-800-365-5671` |

---

## Pricing Model

### Food Delivery
- Customer Fee: **$1 flat** per order
- Restaurant Fee: **$1 flat** per order
- Driver Fee: **$0** (drivers keep 100%)
- Tips: **100%** go to driver

### Rideshare (Tiered by Fare)
| Fare Range | Platform Fee |
|------------|--------------|
| ≤ $35 | $1 |
| $35.01 - $70 | $2 |
| > $70 | $3 |

---

## Checklist Before Submitting New Build

- [ ] Bundle ID is `com.dollorai.customer`
- [ ] Team ID is `PRKZ4UVCD7` (support2dollorai account)
- [ ] Google Client ID is `65740760476-0cnsrucn1tvadbf193cgio2siosnjg02`
- [ ] Google Maps API Key is `AIza<REDACTED-see-Google-Cloud-Console>`
- [ ] All Info.plist permission descriptions present
- [ ] GoogleService-Info.plist matches this document
- [ ] URL Scheme matches Reversed Client ID
- [ ] ITSAppUsesNonExemptEncryption = false
- [ ] Increment build number (33 for next submission)

---

## Critical Notes

1. **Bundle ID**: `com.dollorai.customer` (with "ai") - NOT `com.dollor.customer`
2. **Team ID**: `PRKZ4UVCD7` - NOT `PRKZ4UVCD7`
3. **Google Client ID**: Different from what was in git repo - must use the one in this document
4. **Google Maps API Key**: Embedded in Info.plist - `AIza<REDACTED-see-Google-Cloud-Console>`

---

**VERIFIED FROM ACTUAL BUILD 32 ARCHIVE**
**Archive Path:** `~/Library/Developer/Xcode/Archives/2026-01-27/Dollor-Build32.xcarchive`

---

**END OF DOCUMENT**
