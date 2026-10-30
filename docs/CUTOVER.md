# Cutover runbook: `dollor-rideshare` monorepo to this Dollor-only repo

This repository was created from `jeet-avatar/dollor-rideshare@73be80033` (origin/main). It contains only the Dollor
product: `apps/android`, `apps/ios`, `apps/web/p2p-platform` (backend and frontend), the Dollor ECS task definitions,
the Dollor Lambdas, selected docs and scripts, and four GitHub Actions workflows.

**Rule: the old repository stays untouched until the new pipeline has deployed successfully at least once.**
Nothing in this runbook changes production until step 5, and step 5 deploys identical code.

Production targets (unchanged, taken from `.github/workflows/deploy-dollar-ai.yml`):

| Item | Value |
|---|---|
| AWS account / region | `134607809447` / `us-east-1` |
| Frontend bucket | `dollar-ai-frontend` |
| CloudFront distribution | `E1TL8YTTU1SF3A` |
| ECR repository | `dollor-api` |
| ECS cluster / service | `dollor-production` / `dollor-api-service` |
| Task definition family | `dollor-api` (rendered from `infrastructure/ecs/task-definition.json`) |

## 1. Create the empty GitHub repository

Suggested name: `dollor-ai` (private). Create it **empty**: no README, no .gitignore, no license.
Enable Actions. Do not enable branch protection yet (step 7), because the first push goes to `main`.

```bash
gh repo create jeet-avatar/dollor-ai --private --disable-wiki
```

## 2. Add the remote and push (do this before adding AWS secrets)

```bash
cd path/to/dollor-ai   # this repository
git remote add origin git@github.com:jeet-avatar/dollor-ai.git
git push -u origin main
```

Why before secrets: a push to `main` touching `apps/web/p2p-platform/**` triggers `deploy-dollar-ai.yml`
automatically. With no AWS secrets set, `run-tests` runs and both deploy jobs fail at "Configure AWS credentials"
with no AWS side effects. That failed run is expected. It also proves the tests pass on GitHub's runners.

## 3. Set GitHub Actions secrets (names only)

Repository, Settings, Secrets and variables, Actions, "New repository secret":

| Secret | Used by | Value |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `deploy-dollar-ai.yml` (two jobs) | access key of the Dollor-only deploy user from step 6 |
| `AWS_SECRET_ACCESS_KEY` | `deploy-dollar-ai.yml` (two jobs) | its secret |
| `ANDROID_GOOGLE_SERVICES_APP_B64` | `android-ci.yml` | `base64 < apps/android/app/google-services.json` |
| `ANDROID_GOOGLE_SERVICES_DRIVER_B64` | `android-ci.yml` | `base64 < apps/android/driver/google-services.json` |

`ci-security.yml` and `ci-complete.yml` need no secrets (`GITHUB_TOKEN` only, no AWS). Application secrets
(database, Stripe, JWT, Checkr, Persona, SMTP, Firebase, encryption key) are not in GitHub: ECS injects them from AWS
Secrets Manager (see step 6). Local-only Android and iOS signing material is never uploaded.

The old repository's `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` can be reused for the first deploy to cut risk,
but create the dedicated user (step 6) and rotate to it before closing the cutover.

## 4. Confirm the workflows are present and valid

```bash
gh workflow list --repo jeet-avatar/dollor-ai
```

Expected: `Deploy to Dollor.ai`, `Android CI/CD`, `CI - Security & Quality`, `CI/CD Pipeline`.

## 5. Verify the deploy workflow without touching main's code

The deploy workflow has a `workflow_dispatch` trigger and no environment gate, so a dispatch from any branch deploys that
branch's code to production. Use a branch that is byte-identical to `main` so the deploy is functionally a no-op
(new ECS task definition revision and a freshly built image from the same source, same behaviour).

```bash
git switch -c cutover-verify
git commit --allow-empty -m "chore: verify Dollor deploy pipeline (no-op)"
git push -u origin cutover-verify
gh workflow run deploy-dollar-ai.yml --ref cutover-verify
gh run list --workflow=deploy-dollar-ai.yml --limit 3
gh run watch <run-id>
```

Pass criteria (all must hold before step 7 or step 8):

1. `Run Tests` green (`pytest tests/unit/`).
2. `Deploy Frontend to CloudFront` green. Then `curl -sI https://dollor.ai | head -3` returns 200.
3. `Deploy Backend to ECS` green, `wait-for-service-stability` satisfied.
4. `curl -s https://api.dollor.ai/health` returns a healthy body.
5. `aws ecs describe-services --cluster dollor-production --services dollor-api-service --query 'services[0].deployments'`
   shows one PRIMARY deployment, running count equals desired count.
6. Open the Dollor apps (TestFlight and Play internal track builds) and complete a login. No client change is needed:
   API host, bundle ids (`com.dollorai.customer`, `com.dollorai.delivery`) and package names (`ai.dollor.customer`,
   `ai.dollor.driver`) are unchanged.

## 6. IAM: Dollor-only deploy identity (least privilege)

Create IAM user `dollor-ai-github-deploy` (or, better, a role assumed through GitHub OIDC; that needs a small
workflow change: `permissions: id-token: write` and `role-to-assume` instead of the two key secrets, so it is left as a
follow-up to keep behaviour identical).

AWS actions the workflow uses, derived from `deploy-dollar-ai.yml`:

| Workflow step | AWS actions |
|---|---|
| `amazon-ecr-login` | `ecr:GetAuthorizationToken` (resource `*`) |
| `docker push` to `dollor-api` | `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` |
| `aws s3 sync dist/ ... --delete` | `s3:ListBucket` on bucket; `s3:PutObject`, `s3:DeleteObject` on objects (add `s3:GetObject` if sync of metadata fails) |
| `aws cloudfront create-invalidation` | `cloudfront:CreateInvalidation` on the distribution |
| `amazon-ecs-deploy-task-definition@v2` | `ecs:RegisterTaskDefinition` (resource `*`), `ecs:DescribeTaskDefinition`, `ecs:DescribeServices`, `ecs:UpdateService`, `ecs:DescribeTasks`, `ecs:ListTasks` |
| task registration with roles | `iam:PassRole` on the two task roles |

Policy (replace nothing; ARNs come from the workflow and `task-definition.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "EcrLogin", "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    { "Sid": "EcrPush", "Effect": "Allow",
      "Action": ["ecr:BatchCheckLayerAvailability","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:PutImage"],
      "Resource": "arn:aws:ecr:us-east-1:134607809447:repository/dollor-api" },
    { "Sid": "FrontendBucketList", "Effect": "Allow", "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::dollar-ai-frontend" },
    { "Sid": "FrontendBucketObjects", "Effect": "Allow", "Action": ["s3:PutObject","s3:DeleteObject"],
      "Resource": "arn:aws:s3:::dollar-ai-frontend/*" },
    { "Sid": "CdnInvalidate", "Effect": "Allow", "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::134607809447:distribution/E1TL8YTTU1SF3A" },
    { "Sid": "EcsRegister", "Effect": "Allow", "Action": ["ecs:RegisterTaskDefinition","ecs:DescribeTaskDefinition"], "Resource": "*" },
    { "Sid": "EcsDeploy", "Effect": "Allow", "Action": ["ecs:DescribeServices","ecs:UpdateService"],
      "Resource": "arn:aws:ecs:us-east-1:134607809447:service/dollor-production/dollor-api-service" },
    { "Sid": "EcsWait", "Effect": "Allow", "Action": ["ecs:DescribeTasks","ecs:ListTasks"], "Resource": "*",
      "Condition": { "ArnEquals": { "ecs:cluster": "arn:aws:ecs:us-east-1:134607809447:cluster/dollor-production" } } },
    { "Sid": "PassTaskRoles", "Effect": "Allow", "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::134607809447:role/DollorECSTaskExecutionRole",
        "arn:aws:iam::134607809447:role/DollorECSTaskRole"
      ],
      "Condition": { "StringEquals": { "iam:PassedToService": "ecs-tasks.amazonaws.com" } } }
  ]
}
```

Secrets Manager: the **deploy identity does not read secrets**. The ECS task execution role
(`DollorECSTaskExecutionRole`, already exists and is not changed) calls `secretsmanager:GetSecretValue` when a task
starts, for the secrets referenced in `infrastructure/ecs/task-definition.json`:
`dollor/production/persona`, `database-v2`, `admin`, `jwt-secret`, `stripe`, `smtp-credentials`, `firebase-creds`,
`encryption-key`, `checkr` (and `apple-signin` once `infrastructure/ecs/apple-signin-task-definition-patch.json` is
merged). Plus `logs:CreateLogStream`/`logs:PutLogEvents` on `/ecs/dollor-api` for awslogs. Do not widen the deploy user
to cover these.

This policy was derived from the workflow text, not exercised against IAM. On the first run (step 5) watch CloudTrail
for `AccessDenied` events and add only the missing action. The `ecs:cluster` condition on `DescribeTasks/ListTasks` can
be dropped to `Resource: "*"` if the waiter is denied.

Once the new user deploys successfully, deactivate the key shared with the monorepo only after step 8 (the old workflows
use it until they are disabled).

## 7. Branch protection (GitHub repo settings, Rules, main)

- Require a pull request before merging; 1 approval; dismiss stale approvals; require review from code owners.
- Require status checks to pass: `Lint Code`, `Semgrep SAST Scan`, `Tests & Coverage` (from `CI - Security & Quality`),
  and `Lint & Format`, `API Contract Validation`, `Tests & Coverage` (from `CI/CD Pipeline`). Require branches up to date.
- Block force pushes and branch deletion; require linear history; restrict who can push to `main`.
- Require signed commits (optional but recommended since a push to `main` is a production deploy).
- Settings, Code security: enable secret scanning, push protection, Dependabot alerts and security updates.
- Settings, Actions: restrict to GitHub-owned plus verified actions; workflow permissions "read repository contents".
- Add a GitHub Environment `production` with required reviewers, then add `environment: production` to the two deploy jobs
  (this changes behaviour by adding an approval gate, so it is a deliberate follow-up, not part of the import).

## 8. Disable the Dollor paths in the OLD repository (only after step 5 passed)

Edit in `jeet-avatar/dollor-rideshare` (line numbers refer to `73be80033`):

| File | Lines | Change |
|---|---|---|
| `.github/workflows/deploy-dollar-ai.yml` | 4-9 | Delete the `push:` trigger (keep `workflow_dispatch:` on line 10), or `git mv` the file to `.disabled`. This is the one that deploys production, so it MUST go first. |
| `.github/workflows/deploy-staging.yml` | 4-9 | Delete the `push:` trigger. It deploys `dollor-api-staging-service` from the same ECR repo `dollor-api`. It was NOT migrated (see "Not migrated" below). |
| `.github/workflows/android-ci.yml` | 4-13 | Delete `push:` and `pull_request:` triggers. |
| `.github/workflows/ci-security.yml` | 5-13 | Delete `pull_request:` and `push:` triggers. |
| `.github/workflows/ci-complete.yml` | 4-14 | Delete `pull_request:` and `push:` triggers. |
| `.github/workflows/integration-tests.yml` | 10-20 | Remove the `p2p-platform` and `apps/ios` path triggers and the nightly `schedule`. |
| `.github/workflows/promote-staging-to-production.yml` | whole file | Leave manual, or archive with the staging workflow. |

Do not deploy both repos at once: two pipelines racing to `UpdateService` on `dollor-api-service` and to
`s3 sync --delete` on `dollar-ai-frontend` can ship a stale frontend. Disable the old workflows within the same change
window as the first successful new deploy, then archive the old repo's Dollor directories in a later cleanup commit.

## 9. Rollback

| Layer | Rollback |
|---|---|
| Backend | `aws ecs update-service --cluster dollor-production --service dollor-api-service --task-definition dollor-api:<previous-revision> --force-new-deployment`. List revisions with `aws ecs list-task-definitions --family-prefix dollor-api --sort DESC`. Images are tagged by commit sha in ECR, so any older image remains deployable. |
| Frontend | Check `aws s3api get-bucket-versioning --bucket dollar-ai-frontend` first. If versioned, restore previous objects; otherwise rebuild the previous commit and `aws s3 sync dist/ s3://dollar-ai-frontend/ --delete`, then invalidate `E1TL8YTTU1SF3A`. |
| Pipeline | Re-enable the old repo's `deploy-dollar-ai.yml` push trigger (revert the step 8 edit) and dispatch it. Because the old repo was untouched until step 8, this is a one-commit revert. |
| Both pipelines misbehaving | `gh workflow disable deploy-dollar-ai.yml` in either repo and deploy manually with the commands above. |

## Known differences from the old repo's workflows (review before step 5)

- `android-ci.yml`: the inline Firebase `google-services.json` blobs (which contained an API key) were replaced by the two
  `*_B64` secrets, and the non-existent `:partner` module was dropped. Until those secrets exist the Android CI job fails.
- `ci-complete.yml`: no longer pushes images to ECR or runs SonarCloud (project key pointed at the old repo); it builds and
  scans the image locally. Semgrep runs only in `ci-security.yml`. `ci-security.yml` also dropped SonarCloud.
- `deploy-dollar-ai.yml`: identical behaviour; only a comment block listing the required secrets was added.

## Not migrated (decide before step 8)

- `deploy-staging.yml` / `promote-staging-to-production.yml` (Dollor staging on `dollor-api-staging-service`) and the
  staging task definition (`dollor-api-staging`, fetched with `describe-task-definition`, not stored in git). If staging
  is still used, port `deploy-staging.yml` into this repo with the same path scoping before disabling the old one.
- `infrastructure/terraform`, `helm`, `kubernetes`, `kustomize`, `argocd`: legacy EKS/microservices design, not used by the
  live ECS deploy and shared with other services, so excluded. Recover from the old repo if needed.
- `infrastructure/ecs/notification-service-task-definition.json` and `.github/workflows/deploy-notification-service.yml`:
  belong to `services/notification`, excluded.
- Root `CLAUDE.md`, `.claude/`, `.planning/`, `KEYS_TO_ROTATE.md`: agent configuration and session notes, excluded.
