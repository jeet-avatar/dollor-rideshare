# Dollor secrets: where they live, how to rotate them

This file lists secret NAMES and locations only. Never write a secret value into git, a doc, a log or a chat.
Secret scanning: `.gitleaks.toml` at the repo root (run `gitleaks protect --staged --config .gitleaks.toml --redact`
before committing, and `gitleaks detect --config .gitleaks.toml --redact` in CI).

Owner for every item below is the Dollor engineering owner (Jeet, support@dollor.ai) unless another owner is named.

## 1. Production backend (ECS service `dollor-api`, cluster `dollor-production`)

Source of truth: `infrastructure/ecs/task-definition.json` (`secrets` block, injected from AWS Secrets Manager at task start).
Plain, non-secret settings stay in the `environment` block of the same file.

| Env var in the container | AWS Secrets Manager secret name (JSON key) | Rotate how |
|---|---|---|
| `DATABASE_URL` | `dollor/production/database-v2-gd1oKf` (`DATABASE_URL`) | Lambda `infrastructure/lambda/db-rotation` rotates the RDS user; otherwise change the RDS master/user password, update the secret, force a new ECS deployment |
| `JWT_SECRET_KEY` | `dollor/production/jwt-secret-kvk9j9` | Generate 64+ random chars (`python3 -c "import secrets; print(secrets.token_hex(32))"`), update the secret, redeploy. All sessions are logged out |
| `ADMIN_SECRET_KEY`, `DASHBOARD_SECRET` | `dollor/production/admin-yCDIFY` | Generate new random values, update the secret, redeploy. Update anyone who calls `X-Admin-Secret` endpoints |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET` | `dollor/production/stripe-vT8WRA` | Stripe Dashboard > Developers > API keys > Roll key; for webhooks roll the signing secret on the endpoint. Update the secret, redeploy |
| `SMTP_USER`, `SMTP_PASSWORD` | `dollor/production/smtp-credentials-eqAwat` | Create new SES SMTP credentials in IAM, update the secret, redeploy, delete the old IAM access key |
| `PERSONA_API_KEY`, `PERSONA_TEMPLATE_ID` | `dollor/production/persona-aqEOSX` | Persona dashboard > API keys > rotate; update the secret, redeploy |
| `CHECKR_API_KEY`, `CHECKR_WEBHOOK_SECRET` | `dollor/production/checkr-5utsG3` | Checkr dashboard > Settings > API keys / Webhooks; update the secret, redeploy, revoke the old key |
| `FIREBASE_CREDENTIALS_JSON` | `dollor/production/firebase-creds-DG9fC5` | Firebase console > Project settings > Service accounts > generate a new key, update the secret, redeploy, delete the old key |
| `ENCRYPTION_KEY` | `dollor/production/encryption-key-31sAkk` | Data encrypted with the old key must be re-encrypted first. Do not rotate without a migration |

Variables the backend reads but that are NOT in the task definition today. Set them in Secrets Manager and add them to
the `secrets` block before using the feature:

| Variable | Used by | Behaviour when missing |
|---|---|---|
| `ADMIN_INITIAL_PASSWORD` | `/api/admin/setup-production-admin` | Endpoint refuses to run |
| `DEMO_CUSTOMER_PASSWORD`, `DEMO_DRIVER_PASSWORD`, `DEMO_RESTAURANT_PASSWORD`, `DEMO_SUPPORT_CUSTOMER_PASSWORD`, `DOLLOR_ADMIN_PASSWORD` | `/api/demo/*` seeding endpoints and the `demo-login` endpoints in `main_new.py` (`_demo_password`) | Those admin-gated endpoints return HTTP 503. Existing accounts are unaffected |
| `UNSUBSCRIBE_SECRET` | `email_service.py` unsubscribe links | Falls back to `JWT_SECRET_KEY`; with neither set, tokens are not issued or accepted |
| `SECRET_KEY` | `password_reset_service.py` code hashing | Falls back to `JWT_SECRET_KEY`; with neither set, reset codes cannot be hashed (error) |
| `APPLE_APP_BUNDLE_ID`, `APPLE_DRIVER_APP_BUNDLE_ID` | Apple sign-in audience check | See `infrastructure/ecs/apple-signin-task-definition-patch.json` |
| `STRIPE_CONNECT_WEBHOOK_SECRET` | Stripe Connect webhook | Webhook returns 500 |

Deploying a rotated value: update the secret in Secrets Manager, then `aws ecs update-service --cluster dollor-production --service dollor-api-service --force-new-deployment`.

## 2. GitHub Actions secrets (`.github/workflows/deploy-dollar-ai.yml`)

| Secret name | Purpose | Rotate how |
|---|---|---|
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Frontend S3 sync, CloudFront invalidation, ECR push, ECS deploy | Create a new IAM access key for the deploy user, update both repository secrets, delete the old key. Prefer moving to GitHub OIDC with a role |

Non-secret values in the same workflow (`S3_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `VITE_API_URL`)
are identifiers, not credentials. The `SECRET_KEY` / `JWT_SECRET_KEY` values in the test job are throwaway CI values.

## 3. Web frontend (`apps/web/p2p-platform/frontend`)

Everything in `.env.production` / `.env.staging` is public by design (API URL, Google OAuth web client id, Apple service id, redirect URI).
Build-time only, never committed: `VITE_INVESTOR_DECK_PASSWORD` (investor deck gate; the deck stays locked if unset).
Note a Vite variable is embedded in the JS bundle, so this gate is a speed bump, not real access control.

## 4. Android (`apps/android`)

Local developer file `apps/android/local.properties` (gitignored, never committed):

| Property | Purpose |
|---|---|
| `RELEASE_KEYSTORE_PATH`, `RELEASE_KEYSTORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD` | Release signing (read in `app/build.gradle.kts` and `driver/build.gradle.kts`) |
| `GOOGLE_MAPS_API_KEY` | BuildConfig field + manifest placeholder |
| `STRIPE_PUBLISHABLE_KEY` | BuildConfig field |

Other local-only files (all gitignored): the `.jks`/`.keystore` file, `google-services.json` (Firebase client config; its API key is restricted by package name and SHA-1, download from Firebase console), and the Play service-account JSON.
Play publishing: `fastlane` reads `PLAY_STORE_JSON_KEY_PATH` (absolute path to the service-account JSON kept outside the repo).
Public identifiers kept in `build.gradle.kts`: Google OAuth web client ids and the API base URL.

Rotate: keystore password/alias cannot be changed for a published app without Play App Signing upload-key reset; Maps key via Google Cloud Console > Credentials (restrict by package + SHA-1); Play service account via Google Cloud IAM.

## 5. iOS (`apps/ios`)

| Item | Where it lives | Rotate how |
|---|---|---|
| `GOOGLE_MAPS_API_KEY` | `apps/ios/customer/Config/Debug.xcconfig` and `Release.xcconfig` (gitignored). Copy from the committed `*.xcconfig.example` and fill in. Substituted into `Info.plist` as `$(GOOGLE_MAPS_API_KEY)` | Google Cloud Console > Credentials; restrict by bundle id |
| `GoogleService-Info.plist` (per app) | Local only (gitignored). Firebase client config, restricted by bundle id | Download from Firebase console |
| App Store Connect API key (`AuthKey_<KEYID>.p8`) | Outside the repo, e.g. `~/.private_keys/`. Fastlane reads `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_PATH` (template: `apps/ios/fastlane/.env.default.example`) | App Store Connect > Users and Access > Integrations: revoke and create a new key |
| fastlane `MATCH_PASSWORD` | Team password manager, passed as an env var | Re-encrypt the match repo with a new passphrase (`fastlane match change_password`) |
| Demo login (DEBUG builds and UI tests only) | `DEMO_LOGIN_PASSWORD` env var in the Xcode scheme / test runner (`TEST_RUNNER_DEMO_LOGIN_PASSWORD` for xcodebuild test) | Change the demo account password on the server |

Committed and public: Apple Team ID in `project.pbxproj`, bundle ids, merchant id, API base URL. The Apple App Review demo accounts and their passwords
are documented in `docs/APP_REVIEW_NOTES.md`, `docs/APPLE_REVIEW_REPLY.md` and `apps/ios/*/fastlane/metadata/review_information/` because Apple needs them; keep those accounts low-privilege and rotate after each review.

## 6. Local backend development

`apps/web/p2p-platform/backend/.env` (gitignored; template `.env.example`, placeholders only). Required: `DATABASE_URL`, `JWT_SECRET_KEY` (32+ bytes).
Utility scripts that log in as demo users read `DEMO_CUSTOMER_PASSWORD`, `DEMO_DRIVER_PASSWORD`, `DEMO_RESTAURANT_PASSWORD`, `DOLLOR_ADMIN_PASSWORD` from the environment
(`apps/web/p2p-platform/backend/rideshare_*.py`, `scripts/qa-runner.sh`, `scripts/uat-comprehensive.sh`, `scripts/validation-meta.sh`, `scripts/admin-smoke-test.sh`, `scripts/insurance-smoke.py`, `scripts/sync-quick-tasks-to-tracker.py`).
GoDaddy DNS helpers read `GODADDY_API_KEY` / `GODADDY_API_SECRET`.

## 7. Kubernetes manifests (`infrastructure/kubernetes`)

Not used by production (production is ECS). The `stringData` blocks contain `CHANGE_ME_USE_SEALED_SECRETS` placeholders; supply real values through
Sealed Secrets or External Secrets, never by editing the manifest.

## Rotation checklist after a leak

1. Rotate the credential at its provider (table above), then update Secrets Manager / GitHub / local files.
2. Redeploy ECS (`--force-new-deployment`), then confirm `https://api.dollor.ai/health`.
3. Anything that ever appeared in git history stays compromised even after the file is deleted. Rewriting history is optional once rotated.
4. Record the rotation date in `KEYS_TO_ROTATE.md`.
