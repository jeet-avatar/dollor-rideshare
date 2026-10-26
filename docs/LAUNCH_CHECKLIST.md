# Launch checklist (2026-10-26)

Only things that were verified are stated as facts. Each item says who has to act and what is not yet known.

## 1. Code state
- App branch `release/rideshare-launch-ready-20261026` and backend branch `release/rideshare-backend-20261026` are pushed. `main` is untouched.
- Local `main` is 8 commits ahead of `origin/main`. Do not push it: the workflow `.github/workflows/deploy-dollar-ai.yml` deploys on a push to `main` that touches `apps/web/p2p-platform/**`.
- Backend tests on the backend branch: 67 failures, all of which also fail on a clean `origin/main`; 9 baseline failures now pass; the new tests pass (see `FINAL_TEST_AND_STORE_REPORT.md`).
- All four apps build (Android debug and signed release; iOS Release for the simulator). iOS archives, device builds and fastlane runs have not been tried.

## 2. Decisions only you can make
1. **Founding Member $100 paid by card inside the apps.** Likely rejection on both stores (Apple 3.1.1, Google payments policy). Options: web-only sales, or hide the purchase screens in store builds.
2. **Store text with claims the code does not back:** Proposition 22 earnings guarantee, healthcare stipend and accident insurance; "only verified riders"; "earn more per mile than any other rideshare platform"; "incidents reviewed within 24 hours". Confirm each is true or remove it. The rider description's "no surge pricing" line was already replaced (the backend applies time-of-day multipliers).
3. **Play Console listing:** `android/store-assets/customer/listing.md` in the repo is the old food-delivery listing (category "Food & Drink"). What is in the console now is unknown; open it and confirm it describes a rideshare app.
4. **Tips:** the fare is captured at completion and the tip endpoint then modifies and captures the same payment again, which will probably fail with real cards. Needs a separate tip charge; cannot be verified without real Stripe.

## 3. Backend deploy (this deploys production)
1. Open a pull request from `release/rideshare-backend-20261026` into `main` (do not use local `main`).
2. The workflow runs `pytest tests/unit/` first, then builds the image to ECR `dollor-api` and updates ECS service `dollor-api-service` in cluster `dollor-production` (from the workflow file). 7 unit tests fail in my environment on `origin/main` too; whether they pass in CI is unknown, and a CI failure would block the deploy.
3. No database migration is part of the branch.
4. After it deploys, check: `curl https://api.dollor.ai/health`; `GET /api/config/rideshare` returns 200 (it returns 401 or 404 today); run `python3 docs/audit-2026-10-26/action_matrix.py https://api.dollor.ai` (it creates and finishes demo rides) and expect every row to pass, including the chat shape row; try an unrelated driver reading someone else's ride chat and expect 403.
5. Rollback: revert the merge commit on `main` and push; the same workflow redeploys. I could not read the ECS service (no AWS CLI here), so I do not know the current task revision or whether the service has a deployment circuit breaker. Someone with AWS access should note the current task definition revision before merging.

## 4. Builds and submission
- **Android:** `versionCode` is 261026 (rider) and 261024 (driver) in the Gradle files; my notes say Play already holds 261025 and 261023 (check the console; each upload needs a higher code). The release keystore path is set in `apps/android/local.properties`. Build with `./gradlew :app:bundleProductionRelease :driver:bundleProductionRelease` using JDK 17. The fastlane lanes in `apps/android/fastlane` upload to the internal track as drafts.
- **iOS:** both projects still have `CURRENT_PROJECT_VERSION = 202610140258` (the build already with Apple, per my notes) and `MARKETING_VERSION = 1.1`. The fastlane lanes `customer_testflight` and `driver_testflight` (in `apps/ios/fastlane/Fastfile`) do not change the build number, so set a new one before archiving. Signing uses fastlane match; not tried.
- Do not submit for review until sections 2 and 3 are settled. Nobody has pressed "Send for review" on either store.

## 5. Store paperwork
- App Review notes with the demo logins (rider `demo.customer@dollor.ai`, driver `demo.driver@dollor.ai`; the driver must be approved to go online).
- App Store Connect privacy labels and the Play Data safety form must match what the apps collect: location, name, email, phone, photos, chat messages, payment info, driver documents. The `PrivacyInfo.xcprivacy` files were updated for chat and photos; the Play draft in `android/store-assets/DATA_SAFETY_DECLARATION.md` describes an older three-app, food-era set.
- Account deletion exists in-app on both platforms and `https://dollor.ai/delete-account` loads.

## 6. Known gaps that remain after the fixes (not blockers by themselves)
Masked calling, Android rider SOS and share-trip, Android driver waybill, recurring rides never dispatch, Android push types do not match the backend, one-device-per-driver only on password login, Android driver loses location in the background, ride PIN, off-route alerts, "drivers contacted" count, iOS negotiation endpoints returning 500, the iOS driver location route missing, the Stripe onboarding-link 500 for the demo driver. Details: `FEATURE_TEST_REPORT.md`, `audit-2026-10-26/api_map.md`.

## 7. Still untested
Real card charges, push notifications, iOS tip and cancel flows, SOS and share on iOS, most iOS Settings actions, the two-driver competition test (driver 129 pending approval), per-call timings on iOS. See `FEATURE_TEST_REPORT.md` for the full list.
