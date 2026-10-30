# Sign in with Apple token revocation: owner checklist (App Store 5.1.1(v))

Apple requires that deleting an account also revokes the user's Sign in with Apple token. The backend
(`apps/web/p2p-platform/backend/apple_signin.py`) does this on account deletion. It is a **no-op (with a log line)
until the AWS secret below exists**, and Apple trouble never fails a deletion. The task definition in the repo is
deliberately **unchanged**, so normal deploys stay safe (ECS refuses to start tasks that reference a missing secret).

## How it works
- The apps send `authorization_code` with the apple-auth request. The backend exchanges it for a refresh token and
  stores it encrypted (needs `ENCRYPTION_KEY`) in `apple_signin_tokens`.
- On delete (and on a repeated delete, as a retry) the backend revokes that token. The row is removed only after
  Apple answers 200.
- The client id is chosen per account role, because a refresh token can only be exchanged or revoked with the client id
  it was issued for, and the client secret JWT must have `sub` = that client id:

| Role | Client id env var | Default |
|------|-------------------|---------|
| Rider (customer) | `APPLE_CLIENT_ID_CUSTOMER` | `com.dollorai.customer` |
| Driver | `APPLE_CLIENT_ID_DRIVER` | `com.dollorai.delivery` |

  Legacy `APPLE_CLIENT_ID`, if set, is used for any role whose own variable is unset.
- Identity tokens are accepted only when `aud` is one of those bundle ids (plus legacy `APPLE_CLIENT_ID`).
- Optional: `APPLE_KEY_ID_DRIVER` + `APPLE_PRIVATE_KEY_DRIVER` (both required) give the driver app its own key.
  Do not add them unless step A3 says you need a second key.

## A. Apple Developer portal (developer.apple.com > Certificates, Identifiers & Profiles)
1. Identifiers: open App IDs `com.dollorai.customer` and `com.dollorai.delivery` (both must be in the same team) and
   confirm the **Sign in with Apple** capability is enabled on each.
2. Keys > "+" > name it, tick **Sign in with Apple** > Configure > choose a **primary App ID**
   (`com.dollorai.customer`) and save > Continue > Register.
3. Grouping: Apple groups Sign in with Apple App IDs under one primary App ID. In each App ID's Sign in with Apple
   > Edit, set `com.dollorai.delivery` as grouped with the primary `com.dollorai.customer` so one key serves both.
   If Apple will not let you group them, create a second key whose primary App ID is `com.dollorai.delivery` and use
   the optional `APPLE_KEY_ID_DRIVER` / `APPLE_PRIVATE_KEY_DRIVER` (see B and C).
4. **Download the `.p8` once** (Apple will not show it again). Store it somewhere safe.
5. Write down the **Key ID** (10 characters, shown on the key page) and the **Team ID** (Membership details).

## B. AWS Secrets Manager (account 134607809447, us-east-1)
Create the secret `dollor/production/apple-signin` as key/value pairs:
- `APPLE_TEAM_ID` = the Team ID
- `APPLE_KEY_ID` = the Key ID
- `APPLE_PRIVATE_KEY` = the full `.p8` text including its BEGIN and END header lines and
  `-----END PRIVATE KEY-----` lines, with real newlines (paste into the console's plaintext editor; `\n` escapes
  are also accepted)

Example CLI (reads the key from the file, prints no secret):
`aws secretsmanager create-secret --name dollor/production/apple-signin --secret-string "$(jq -n --arg t TEAMID --arg k KEYID --rawfile p AuthKey_KEYID.p8 '{APPLE_TEAM_ID:$t,APPLE_KEY_ID:$k,APPLE_PRIVATE_KEY:$p}')"`

Check the task execution role can read it (`secretsmanager:GetSecretValue` on
`arn:aws:secretsmanager:us-east-1:134607809447:secret:dollor/production/apple-signin-*`).

## C. Apply the task-definition patch, then deploy
The fragment is `infrastructure/ecs/apple-signin-task-definition-patch.json` (3 secrets + the 2 plain client ids).
Only after step B:
```
jq --slurpfile p infrastructure/ecs/apple-signin-task-definition-patch.json \
  '.containerDefinitions[0].environment += $p[0].environment | .containerDefinitions[0].secrets += $p[0].secrets' \
  infrastructure/ecs/task-definition.json > /tmp/td.json && mv /tmp/td.json infrastructure/ecs/task-definition.json
```
Confirm the container you patched (index 0) is the API container, commit the result, and deploy through the normal
workflow (it renders `task-definition.json`). If you need the second driver key, also add `APPLE_KEY_ID_DRIVER` and
`APPLE_PRIVATE_KEY_DRIVER` keys to the same secret and matching `secrets` entries.

## D. Verify
1. Install the new build, sign up with Apple on a **test** account (rider; repeat with the driver app).
2. Delete the account in the app.
3. Check the API logs for `apple revoke ok for customer <id>` (or `driver <id>`). Problems log
   `apple token exchange failed ...` / `apple token revocation failed ... HTTP <code>`; `... not configured` means
   the secret is not applied yet.
4. Settings > Apple ID > Sign in with Apple no longer lists the app.

## Limits
- The apps must send `authorization_code` (the new builds do). Accounts created **before** this ships have no stored
  token and cannot be revoked server-side; those users can remove the app under Settings > Apple ID > Sign in with Apple.
- The `.p8` client secret is regenerated per request (5 minute expiry), so nothing to rotate except the key itself.
