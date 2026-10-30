# iOS Code Signing Setup for Dollor Apps

## Current Status
- Development certificates exist locally ✓
- Fastlane Match configured ✓
- Certificate repo created: https://github.com/jeet-avatar/ios-certificates

## Required GitHub Secrets

Set these secrets in your GitHub repository settings (Settings > Secrets and variables > Actions):

### For Development Builds

1. **BUILD_CERTIFICATE_BASE64**
   - Export your development certificate from Keychain Access:
     1. Open Keychain Access
     2. Find "Apple Development: Jithesh Manoharan"
     3. Select both the certificate AND private key (expand the certificate to see the key)
     4. Right-click > Export Items
     5. Save as `.p12` file with password `dollor2025`
   - Convert to base64:
     ```bash
     base64 -i ~/path/to/certificate.p12 | pbcopy
     ```
   - Paste as the secret value

2. **P12_PASSWORD**
   - The password used when exporting the certificate (e.g., `dollor2025`)

3. **KEYCHAIN_PASSWORD**
   - A temporary keychain password for CI (e.g., `ci-keychain-password`)

### For TestFlight/App Store Builds (Distribution)

You'll need Distribution certificates. Either:

**Option A: Use Fastlane Match (Recommended)**
1. Create an App Store Connect API Key:
   - Go to https://appstoreconnect.apple.com/access/api
   - Click "+" to create a new key
   - Name: "Fastlane CI"
   - Access: Developer
   - Download the .p8 file and note the Key ID and Issuer ID

2. Add these additional secrets:
   - **APP_STORE_CONNECT_API_KEY_KEY_ID**: The Key ID
   - **APP_STORE_CONNECT_API_KEY_ISSUER_ID**: The Issuer ID
   - **APP_STORE_CONNECT_API_KEY_KEY**: The contents of the .p8 file

3. Run Match to generate distribution certificates:
   ```bash
   cd apps/ios
   MATCH_PASSWORD="<MATCH_PASSWORD - stored in the team password manager, never in git>" \
   APP_STORE_CONNECT_API_KEY_KEY_ID="YOUR_KEY_ID" \
   APP_STORE_CONNECT_API_KEY_ISSUER_ID="YOUR_ISSUER_ID" \
   APP_STORE_CONNECT_API_KEY_KEY="$(cat ~/path/to/AuthKey.p8)" \
   fastlane match appstore
   ```

**Option B: Manual Certificate Export**
1. Create Distribution certificate in Apple Developer Portal
2. Export and base64 encode it
3. Download provisioning profiles for each app

## Provisioning Profiles

For each app, you need a provisioning profile:

| App | Bundle ID | Profile Type |
|-----|-----------|--------------|
| Customer | com.dollor.customer | Development / App Store |
| Restaurant | com.dollor.restaurant | Development / App Store |
| Driver | com.dollor.driver | Development / App Store |

## Testing Locally

To build locally with signing:
```bash
cd apps/ios
fastlane customer_dev  # Development build
fastlane customer_testflight  # TestFlight build (requires distribution cert)
```

## Match Password

For decrypting certificates in the Match repo:
- **MATCH_PASSWORD**: `<MATCH_PASSWORD - stored in the team password manager, never in git>`

Store this as a GitHub secret for CI.
