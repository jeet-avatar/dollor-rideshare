# Sign in with Apple token revocation (App Store 5.1.1(v))

Apple requires that deleting an account also revokes the user's Sign in with Apple token
(`POST https://appleid.apple.com/auth/revoke`). The backend code is in place and is a **no-op until the
secrets below exist**. Account deletion never fails because of Apple.

## What the code does
- `apps/web/p2p-platform/backend/apple_signin.py`
  - `store_refresh_token_from_code`: when the app sends `authorization_code` to
    `POST /api/customer/apple-auth` (also `/api/auth/customer/apple-auth`) or `POST /api/auth/driver/apple-auth`,
    the code is exchanged at `https://appleid.apple.com/auth/token` and the refresh token is stored
    Fernet-encrypted (`ENCRYPTION_KEY`) in the new table `apple_signin_tokens` (created by `create_all`).
    It is not stored if `ENCRYPTION_KEY` is missing.
  - `revoke_for_account`: called by `account_deletion.delete_customer/delete_driver` after the anonymisation commit,
    and again when a deleted account calls delete a second time (retry). The row is removed only after Apple
    answers 200.
- With any of the four variables missing, both functions log a line and do nothing.

## Secrets the owner must add (names only)
| Name | What it is |
|------|-----------|
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID |
| `APPLE_KEY_ID` | Key ID of a "Sign in with Apple" key (.p8) |
| `APPLE_PRIVATE_KEY` | Full contents of the .p8 file (PEM text, including its BEGIN and END header lines). `\n` escapes are accepted |
| `APPLE_CLIENT_ID` | Bundle ID of the app the token was issued to |

`APPLE_CLIENT_ID` must be the bundle ID of the app that signed the user in. The riders app is
`com.dollorai.customer` and the driver app is `com.dollorai.delivery`. The identity token is already accepted for
both audiences, but a refresh token is only revocable with the client_id it was issued for. If both apps must be
revoked, the code needs a per-role client id (for example `APPLE_CLIENT_ID_DRIVER`); today one value is used for both,
so set the rider bundle ID and tell the engineer if driver tokens must also be revoked, or create a Services ID
shared by both (Apple then requires the apps to be grouped under one primary App ID).

## How to add them
1. developer.apple.com > Certificates, Identifiers & Profiles > Keys > "+" > enable Sign in with Apple,
   configure the primary App ID, download the `.p8` once, note the Key ID. Team ID is under Membership.
2. Create the secrets in AWS Secrets Manager (same pattern as `dollor/production/encryption-key`), for example
   `dollor/production/apple-team-id`, `.../apple-key-id`, `.../apple-private-key`, `.../apple-client-id`.
3. Add four `secrets` entries (`name` = variable above, `valueFrom` = secret ARN) to
   `infrastructure/ecs/task-definition.json`, register the task definition and redeploy the service.
4. The task execution role must be allowed `secretsmanager:GetSecretValue` on those ARNs.

## What the apps must send
Both iOS apps must send the `authorizationCode` from `ASAuthorizationAppleIDCredential` (UTF-8 string) as the JSON
field `authorization_code` in the apple-auth request body (`P2PAPIService.swift` apple-auth calls, rider
`AuthViewModel.swift`, driver `DriverLoginView.swift`). They currently send only `identity_token`. Accounts created
before this ships have no stored token and cannot be revoked server-side; those users can still remove the app under
Settings > Apple ID > Sign in with Apple.

## Verify after deploy
Sign in with Apple on a test account, then check `apple_signin_tokens` has one row for it (the token itself is
encrypted). Delete the account in the app; the row disappears and the app no longer appears under the Apple ID
settings. Logs: `apple token revoked for customer <id>`; on problems `apple token revocation failed ... HTTP <code>`.
