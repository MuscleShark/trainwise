# Deployment

TrainWise runs in two environments, **staging** and **production**, each as:

```text
Browser ──► Vercel (Next.js frontend, root directory: frontend/)
   │
   └──────► AWS Lambda + Function URL (FastAPI via Mangum, us-east-2)
                 │          └── reads secrets from SSM Parameter Store at cold start
                 ├──► Neon PostgreSQL (us-east-2, pooled connection)
                 └──► starts the coach worker Lambda ──► Anthropic API (Claude Sonnet 5.5)
                                         └──► writes the advice back to Neon
EventBridge Scheduler (Monday 06:00 Los Angeles) ──► coach worker: weekly summaries
```

- **Frontend**: Vercel's Git integration deploys every push to `main` and builds preview deployments for pull requests.
- **Backend infrastructure and code**: defined with **AWS CDK** in [`infra/`](../infra), one stack per environment from the same code: `TrainWiseApi-staging` and `TrainWiseApi` (production). After the `CI` workflow succeeds on `main`, `.github/workflows/deploy-backend.yml` builds the Lambda package (`backend/scripts/build_lambda.sh`), deploys it to **staging** and calls `/health` as a smoke test. **Production changes only when you promote a release by hand** (see [Promote to production](#promote-to-production)).
- **Sign-in**: [Clerk](https://clerk.com). The Lambda only needs the Clerk instance's issuer URL (`clerkIssuer` in `infra/cdk.json`, not a secret) to verify session tokens. The Clerk secret key is used only by Vercel.
- **Secrets**: `DATABASE_URL` (pooled) and `DATABASE_URL_DIRECT` (direct) are SSM Parameter Store *SecureString* parameters under `/trainwise/prod/`. CloudFormation cannot create SecureStrings, so they are created by hand (step 3). The API role can only read `DATABASE_URL`; the migration role can only read `DATABASE_URL_DIRECT`. `ANTHROPIC_API_KEY` is readable only by the coach worker.
- **Database migrations**: [Alembic](https://alembic.sqlalchemy.org) (`backend/migrations/`). During each `cdk deploy`, a CDK trigger runs the environment's migrate Lambda (`trainwise-migrate-staging` / `trainwise-migrate-prod`) (`alembic upgrade head`) **before** the API function is updated. After the migrations it updates the built-in exercise catalog from `backend/catalog.py`, then the built-in templates from `backend/template_catalog.py`. If any step fails, the deploy fails and the API keeps its previous code. Migrations run on staging first: production only gets commits, and so migrations, that already deployed on staging.

The one-time setup below happens in your own AWS, Neon, Vercel and GitHub accounts. Keep every connection string and secret out of git and out of chat.

## What the CDK stack (`TrainWiseApi`) manages

This table is production. The staging stack `TrainWiseApi-staging` has the same resources with `-staging` instead of `-prod` in every name (`trainwise-api-staging`, `/trainwise/staging/…`, `trainwise-alarms-staging`, …), its coach metrics in `IronSage/Coach-staging`, and no budget (the budget covers the whole account). Its only allowed browser origin is `http://localhost:3000`. Each environment's settings are under `environments` in [`infra/cdk.json`](../infra/cdk.json); production's names never change, because CloudFormation would replace the resource.

| Resource | Notes |
|---|---|
| Lambda `trainwise-api-prod` | Python 3.11, x86_64, 512 MB, 15 s, handler `lambda_handler.handler` |
| Function URL | Auth `NONE` (the API verifies Clerk session tokens itself). No URL-level CORS, because FastAPI sends the headers |
| Execution role | Basic logging + `ssm:GetParameters` on `/trainwise/prod/DATABASE_URL` only |
| Lambda `trainwise-migrate-prod` | Same code package, handler `migrate_handler.handler`, 5-minute timeout. Its role may only read `/trainwise/prod/DATABASE_URL_DIRECT`. Log group kept for 30 days |
| Migration trigger | CDK trigger that invokes `trainwise-migrate-prod` whenever its code changes, before the API function is updated |
| Log group | `/aws/lambda/trainwise-api-prod`, kept for 30 days |
| Lambda `trainwise-coach-prod` | The AI coach worker: same code package, handler `coach_handler.handler`, 60 s. The API starts it without waiting (the API role may invoke it). Its role may read `/trainwise/prod/DATABASE_URL` and `/trainwise/prod/ANTHROPIC_API_KEY`, and invoke the function itself (one run per user for the weekly summary). No retries: a failure is stored on the recommendation or summary. Log group kept for 30 days |
| EventBridge Scheduler `trainwise-coach-prod-weekly-summaries` | Every Monday at 06:00 America/Los_Angeles, starts the coach worker with `{"job": "weekly_summaries"}`, which writes last week's summary for every user who has coach access and turned it on in the app. Scheduler retries delivering the event up to twice; a timeout inside the job is covered by the job itself (it hands over to a new run before its time runs out, and restarts summaries left pending). A user and week gets at most one summary. Its own role may only invoke the coach worker |
| SNS topic `trainwise-alarms-prod` | Every alarm and the budget notify it. The email subscriber is the `ALARM_EMAIL` variable of the GitHub `production` environment (step 5), so the address is not in the repository. Without it the topic has no subscriber |
| Alarms | Each one emails when it goes off and again when it clears. Coach worker: `trainwise-coach-prod-errors` (crashed or timed out), `trainwise-coach-prod-failed-answers` (5 or more failed answers in an hour, counted from the worker's log lines, weekly summaries included), `trainwise-coach-prod-daily-calls` (more than 300 calls in a day; on Mondays each subscriber's summary is one more, so raise it before about 250 subscribers), `trainwise-coach-prod-weekly-job-errors` (the weekly job itself failed or timed out: no summaries that week). API: `trainwise-api-prod-5xx` (3 or more 5xx responses in 5 minutes, from the Function URL, so it includes errors FastAPI turned into a 500, crashes and timeouts), `trainwise-api-prod-throttles` (any throttled request: the account's concurrency limit was reached), `trainwise-api-prod-slow` (p95 duration above 12 s, close to the 15 s timeout, for 15 minutes). `trainwise-migrate-prod-errors` (a migration failed; the deploy fails too) |
| AI token metrics | `IronSage/Coach` → `InputTokens` / `OutputTokens`, from the `input_tokens` / `output_tokens` the worker logs for each answer. CloudWatch → Metrics → `IronSage/Coach`, statistic *Sum*, period 1 day shows the tokens per day |
| Budget `TrainWiseApi-monthly-cost` | AWS Budgets, $10 a month for the whole account: notifies the topic at 80% of actual spend and when the forecast passes 100%. An account-level budget, like the zero-spend budget in step 0: it needs neither AWS Organizations nor "advanced features" (never turn those on: they remove the project spend limit). The AI provider bills separately and is not included: set a monthly spend limit in the Anthropic Console as well |

Settings that are not secret live in [`infra/cdk.json`](../infra/cdk.json) (account, Region and `clerkIssuer`, then per environment `frontendUrls`, `functionName`, `ssmParameterPrefix`, …). To change one, edit the file in a PR. The deploy after merge applies it to staging, and the next promotion to production.

Local commands (from `infra/`, after `backend/scripts/build_lambda.sh`):

```bash
python3.11 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest -q                                          # unit tests
PATH="$PWD/.venv/bin:$PATH" npx aws-cdk@2.1146.1 synth --quiet  # render both stacks' templates
```

---

## 0. AWS budget alert (do this first)

AWS Billing → **Budgets** → Create budget → *Zero spend budget* → your email. This account also has a $20/month project spend limit.

## 1. Neon

1. In the Neon console (project in **AWS US East 2**), open **Connect**.
2. Copy two connection strings:
   - **Pooled**: the host contains `-pooler`. The API function uses this one.
   - **Direct**: pooling turned off. The migration function uses this one, because schema changes should not go through the pooler.
3. In both, change the scheme `postgresql://` to `postgresql+psycopg://`. Keep `?sslmode=require`.

Both go into SSM in step 3. The first deploy creates the tables.

## 2. Bootstrap CDK (once per account and Region)

In **CloudShell** (region us-east-2):

```bash
npx --yes aws-cdk@2.1146.1 bootstrap aws://<ACCOUNT_ID>/us-east-2
```

This creates the `CDKToolkit` stack: an S3 bucket for deployment assets and the `cdk-hnb659fds-*` roles that CDK uses to deploy.

## 3. Secrets in SSM Parameter Store

In **CloudShell**. Each `read` prompt hides what you paste:

```bash
read -rsp "Neon POOLED url (postgresql+psycopg://...): " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/prod/DATABASE_URL --type SecureString --value "$V" --overwrite && unset V
```

```bash
read -rsp "Neon DIRECT url (postgresql+psycopg://...): " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/prod/DATABASE_URL_DIRECT --type SecureString --value "$V" --overwrite && unset V
```

The deploy fails (and changes nothing) if `DATABASE_URL_DIRECT` is missing, because migrations cannot run.

The AI coach's key (an Anthropic API key with a monthly spending limit set in the Anthropic console):

```bash
read -rsp "Anthropic API key: " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/prod/ANTHROPIC_API_KEY --type SecureString --value "$V" --overwrite && unset V
```

The coach is for subscribers (see [Subscriptions](architecture.md#subscriptions)). Test accounts can also be switched on by hand, without a subscription. In the Neon SQL editor:

```sql
UPDATE users SET coach_enabled = true WHERE email = 'you@example.com';
```

The weekly summary also needs the coach turned on in the app (`users.coach_consent`, set by the app). To write last week's summaries without waiting for Monday (safe to repeat: users who already have one are skipped), in CloudShell:

```bash
aws lambda invoke --region us-east-2 --function-name trainwise-coach-prod --cli-binary-format raw-in-base64-out --payload '{"job": "weekly_summaries"}' /dev/stdout
```

`/trainwise/prod/SECRET_KEY` was used by the old password sign-in and is no longer read. It can be deleted.

## 4. Deploy user for GitHub Actions (IAM)

In AWS's simplified "projects" mode, IAM OpenID Connect providers are not available. They would need "advanced features", and activating those removes project spend limits. So GitHub Actions signs in with access keys of a dedicated IAM user. That user may **only assume the CDK bootstrap roles**, and those roles perform the deployment.

In **CloudShell**:

```bash
aws iam create-user --user-name trainwise-github-deploy
```

```bash
aws iam put-user-policy --user-name trainwise-github-deploy --policy-name TrainWiseCdkDeploy --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Resource":"arn:aws:iam::<ACCOUNT_ID>:role/cdk-hnb659fds-*-<ACCOUNT_ID>-us-east-2"}]}'
```

Create an access key only once the GitHub environment from step 5 exists, because the secret is shown only once:

```bash
aws iam create-access-key --user-name trainwise-github-deploy
```

To rotate a key, create a new key, update both secrets in both GitHub environments (`staging` and `production`), deploy staging and promote to production, then run `aws iam delete-access-key --user-name trainwise-github-deploy --access-key-id <old id>`.

## 5. GitHub environments

Repository → **Settings → Environments**. Two environments, `staging` and `production`, each with:

- Deployment branches and tags: *Selected branches* → `main`.
- **Environment secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from step 4; the same key pair in both).
- **Environment variables**: `ALARM_EMAIL`, the address that receives that environment's alarm (and, for production, budget) emails. The deploy passes it to CDK as `-c alarmEmail=...`.

`production` also has **Required reviewers** → you. Every promotion then waits for your approval. Leave *Prevent self-review* off, since you start promotions yourself.

These protect against a deploy by mistake, not against someone with write access to the repository: both environments use the same IAM user, which can deploy either stack.

### Confirm the alarm email

After the first deploy of each environment with `ALARM_EMAIL` set, AWS sends *AWS Notification - Subscription Confirmation* from `no-reply@sns.amazonaws.com` to that address. Open it and click **Confirm subscription**. Until you do, no alarm email arrives. Check the spam folder if it is not there within a few minutes. To check, open **SNS → Topics → `trainwise-alarms-prod` → Subscriptions**: the email row should say *Confirmed*, not *Pending confirmation*. (`trainwise-alarms-staging` for staging). The link expires after 3 days; if it did, delete the pending subscription there and deploy that environment again (staging: **Actions → Deploy backend to staging → Run workflow**; production: promote again) to send a new one.

To change the address, update `ALARM_EMAIL` and deploy that environment again. CloudFormation replaces the subscription, and the new address gets its own confirmation email.

To test the notification, in **CloudShell**:

```bash
aws cloudwatch set-alarm-state --region us-east-2 --alarm-name trainwise-api-prod-throttles --state-value ALARM --state-reason "Testing the alarm email"
```

An *ALARM* email arrives, then an *OK* email once the alarm is evaluated again (within about 5 minutes).

A deploy that adds or renames an alarm also sends an *OK* email for it a few minutes later, when the new alarm leaves *INSUFFICIENT_DATA*. That is expected.

Deploy staging with **Actions → Deploy backend to staging → Run workflow** (branch `main`), then production with [Promote to production](#promote-to-production). The job summary shows the Function URL, and the smoke test prints `{"status":"ok"}`.

## 6. Vercel

1. **Add New → Project** → import `MuscleShark/trainwise`.
2. **Root Directory**: `frontend` (framework preset: Next.js).
3. **Environment Variables**:
   - `NEXT_PUBLIC_API_URL` = the Function URL **without the trailing slash**, type **Config**.
   - `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` = Clerk publishable key, type **Config**.
   - `CLERK_SECRET_KEY` = Clerk secret key, type **Secret**.

   Do not make `NEXT_PUBLIC_*` variables *Secret*. They are public by design, and Vercel will not inject a Secret into the browser bundle.
4. Deploy. The production domain must be listed in `frontendUrls` in `infra/cdk.json`, written exactly as the browser shows it (`https://…`, no trailing slash).
5. Custom domain: the site is served at `https://ironsage.app` (bought on Cloudflare Registrar). In Vercel → **Settings → Domains**, add `ironsage.app` and `www.ironsage.app`, then add the DNS records Vercel shows in Cloudflare as **DNS only** (grey cloud): Cloudflare's proxy breaks Vercel's certificates. Make `ironsage.app` the primary domain and redirect the others to it.

`NEXT_PUBLIC_*` values are baked in at build time, so redeploy on Vercel after changing them.

Pull-request preview deployments get their own `*.vercel.app` URLs. The API rejects those origins on purpose, so previews never write to the production database. Vercel's production site follows `main` and talks to the production API, so a frontend change that needs a new API should be merged after that API is promoted.

## 7. Check it

Open the Vercel URL → sign up with an email code (and with Google / Apple) → sign out → sign in again → add a profile and a workout → reload and confirm the data is still there.

## 8. App Store subscriptions (once the Apple Developer account exists)

The API verifies App Store transactions against Apple's root certificate, so it needs no App Store Connect key. What is left is in App Store Connect:

1. Under the app (bundle id `app.ironsage.IronSage`) › Subscriptions, create the group **IronSage Coach** with two auto-renewable subscriptions, matching `ios/IronSage.storekit`:
   - `app.ironsage.coach.yearly`: 1 year, $39.99, level 1.
   - `app.ironsage.coach.monthly`: 1 month, $4.99, level 2.
   - On both, an introductory offer for new subscribers: free, 1 week, United States.
   - English and Chinese display names, and a review screenshot of the paywall.
2. Join the App Store Small Business Program (15% commission).
3. Under App Information › App Store Server Notifications, set both the **Production** and the **Sandbox** URL to the API's notification endpoint, **Version 2**:

   ```
   https://po2uvflgp2hps4adjpwjerzeca0jtxjn.lambda-url.us-east-2.on.aws/v1/app-store/notifications
   ```

   Then send a test notification from App Store Connect; the API answers 200 and logs `App Store notification TEST` in CloudWatch.
4. Offer codes (promotions): under each subscription › Offer Codes, create an offer (for example half off the first year) and generate one-time or custom codes. Nothing changes in the app or the API: users redeem them with "Redeem code", and the API records the offer on the subscription.
5. Test on a real iPhone with a Sandbox account (Settings › Developer › Sandbox Apple Account). Sandbox renews monthly plans every 5 minutes, so expiry is quick to see.
6. In the App Store listing, put the Terms of Use (Apple's standard EULA is used) and the privacy policy links in the description or the EULA field, as Guideline 3.1.2 asks.

## 9. Staging environment (one-time)

Do this **before merging the PR that adds staging**: after that merge, every merge to `main` deploys to staging, and a deploy without the parameters below fails (production is not touched).

1. **Neon branch.** Neon console → your project → **Branches** → **Create branch**: name `staging`, parent `main` (production's branch), *Current data*. Then **Connect** with the branch `staging` selected and copy the **pooled** and the **direct** connection strings, changing `postgresql://` to `postgresql+psycopg://` as in step 1.
   - The branch starts as a copy of production's data, and staging shares production's Clerk instance, so every production account can sign in to staging and see its copy. Today that is only test accounts. Once real users sign up, create the branch *Schema only* (or delete user rows after a reset), so staging doesn't hold their data or write weekly summaries for them on the staging key.
   - On Neon's Free plan a project has 10 branches and the branches share its compute hours; staging's compute suspends when idle, so it costs little or nothing. Check your plan under **Billing**.
2. **Anthropic key for staging.** In the Anthropic Console create a separate API key (for example *ironsage-staging*) and give it a low monthly limit (for example $5 in a separate workspace), so staging can never spend production's budget.
3. **SSM parameters**, in **CloudShell** (us-east-2). Each `read` prompt hides what you paste:

   ```bash
   read -rsp "Neon STAGING pooled url (postgresql+psycopg://...): " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/staging/DATABASE_URL --type SecureString --value "$V" --overwrite && unset V
   ```

   ```bash
   read -rsp "Neon STAGING direct url (postgresql+psycopg://...): " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/staging/DATABASE_URL_DIRECT --type SecureString --value "$V" --overwrite && unset V
   ```

   ```bash
   read -rsp "Anthropic STAGING API key: " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/staging/ANTHROPIC_API_KEY --type SecureString --value "$V" --overwrite && unset V
   ```

   Check all three exist (names only, no values):

   ```bash
   aws ssm describe-parameters --region us-east-2 --parameter-filters Key=Name,Option=BeginsWith,Values=/trainwise/staging/ --query 'Parameters[].Name'
   ```
4. **GitHub environments** (step 5): create `staging` with the AWS keys and `ALARM_EMAIL`, and add yourself as required reviewer on `production`.
5. **Merge the PR.** The merge deploys staging for the first time (creating `TrainWiseApi-staging` and its tables). Confirm the staging alarm subscription email. The job summary shows the staging Function URL.
6. Clerk: staging uses the same Clerk development instance as production, so the same accounts sign in to both; nothing to do.

The staging API is the URL in the job summary (or CloudShell: `aws lambda get-function-url-config --region us-east-2 --function-name trainwise-api-staging --query FunctionUrl`). To try the iPhone app against it, set `API_BASE_URL` of the Debug configuration to that URL. To give a test account the coach on staging, run the `UPDATE users SET coach_enabled = true …` from step 3 in the Neon SQL editor with the `staging` branch selected.

## Promote to production

Every merge to `main` goes to staging only. When staging looks right:

1. **Actions → Promote to production → Run workflow**, branch `main`.
   - Leave **Commit** blank to promote the newest commit that passed on staging (normally what staging runs now; if a later staging deploy failed its smoke test, the one before it), or paste the SHA of a commit on `main` that passed on staging (its checks on GitHub include a green `deploy/staging`).
   - The first job refuses a commit that isn't on `main` or never passed on staging, and writes in its summary the commits and migrations production is about to get.
2. Open the run, read that summary, and **Review deployments → Approve**. The infrastructure diff (`cdk diff TrainWiseApi`) needs the production keys, so it shows only after approval, in the deploy job's *Show changes* step; the summary covers the code and migrations.
3. The deploy uses the **same Lambda package** staging ran (kept as an artifact of the staging run for 90 days; the first job refuses a commit whose package expired). It runs `cdk diff`, migrations, `cdk deploy TrainWiseApi`, and the `/health` smoke test.
4. Once it passes, the commit gets a tag `prod-YYYYMMDD-N` (for example `prod-20261026-1`). `git tag --list 'prod-*'` is the history of what production ran.

**Rollback**: promote an earlier `prod-*` commit (paste its SHA), if it is less than 90 days old. Otherwise, or in general to go forward, revert on `main` and promote the revert once it passed on staging. Migrations are not undone: if a migration ran in between, the old code doesn't know the newer revision, the migration step fails and production keeps the current code. Then fix forward instead.

**Staging's database falls behind production's data.** To refresh it, Neon → Branches → `staging` → **Reset from parent** (this drops staging's own changes). Its schema then matches production; if `main` has migrations production doesn't have yet, run them again with CloudShell:

```bash
aws lambda invoke --region us-east-2 --function-name trainwise-migrate-staging /dev/stdout
```

## Day-to-day

- Merge a PR into `main`. Vercel redeploys the frontend, CI runs, and if CI passes the backend is deployed to **staging**. Promote to production when you're ready ([above](#promote-to-production)).
- Infrastructure changes (memory, timeout, allowed origins, permissions) are code changes in `infra/`. Each deploy log shows a `cdk diff` before deploying.
- Rotate the Clerk secret key in the Clerk dashboard, then update it in Vercel and the `CLERK_SECRET_KEY` repository secret.
- Schema changes: edit `backend/models.py`, generate an Alembic migration (see the README), review it and merge it with the code. The staging deploy applies it first, the promotion then to production. To run migrations by hand (for example to check a migration against a Neon branch), use `DATABASE_URL=<direct url> alembic upgrade head` from `backend/`.
