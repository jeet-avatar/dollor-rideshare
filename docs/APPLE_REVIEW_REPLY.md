# Reply to App Review - submission 72087a23-26e0-489f-8bfb-deefee6d0a05

New build: 1.1 (202610291400) for both Dollor (rider) and Dollor Driver.

**Guideline 4 - Sign in with Apple design.** After Sign in with Apple succeeds, the app no longer asks for a name, email or phone number. The account is created or found from the Apple user identifier (the "sub" in the verified identity token); when Apple provides no name or email (returning logins, hidden email), the server applies defaults and the user goes straight into the app. Drivers who sign in with Apple land in the app immediately; document upload and the background check are a separate compliance step after login.

**Guideline 4 - Sign in / registration in the default browser.** Registration, password reset and driver sign-up are native in-app screens. No sign-in or registration step opens the Safari app. Terms of Use, Privacy Policy and the payout/background-check pages open in an in-app Safari view (SFSafariViewController) inside the app. Google Sign-In uses the Google SDK's in-app authentication sheet.

**Guideline 2.5.4 - Background audio.** The "audio" background mode is removed. UIBackgroundModes now contains only remote-notification (rider) and location + remote-notification (driver, for live trip tracking while online). Audio is used only in the foreground for voice dictation in chat.

## App Review notes
- Rider demo: demo.customer@dollor.ai / DemoCustomer2025!
- Driver demo: demo.driver@dollor.ai / DemoDriver2025!
- Driver app: the driver must be Online and have a location (set a simulated location if needed) to see ride requests; use the demo rider to request a ride.
- Account deletion: Profile tab > Delete Account (both apps; in the driver app it is at the bottom of the Profile screen).
