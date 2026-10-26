# Deployment

TrainWise runs in production as:

```text
Browser ──► Vercel (Next.js frontend, root directory: frontend/)
   │
   └──────► AWS Lambda + Function URL (FastAPI via Mangum, us-east-2)
                 │          └── reads secrets from SSM Parameter Store at cold start
                 ├──► Neon PostgreSQL (us-east-2, pooled connection)
                 └──► starts the coach worker Lambda ──► Anthropic API (Claude Sonnet 5.5)
                                         └──► writes the advice back to Neon
```

- **Frontend**: Vercel's Git integration deploys every push to `main` and builds preview deployments for pull requests.
- **Backend infrastructure and code**: defined with **AWS CDK** in [`infra/`](../infra). After the `CI` workflow succeeds on `main`, `.github/workflows/deploy-backend.yml` builds the Lambda package (`backend/scripts/build_lambda.sh`), runs `cdk deploy` and calls `/health` as a smoke test.
- **Sign-in**: [Clerk](https://clerk.com). The Lambda only needs the Clerk instance's issuer URL (`clerkIssuer` in `infra/cdk.json`, not a secret) to verify session tokens. The Clerk secret key is used only by Vercel.
- **Secrets**: `DATABASE_URL` (pooled) and `DATABASE_URL_DIRECT` (direct) are SSM Parameter Store *SecureString* parameters under `/trainwise/prod/`. CloudFormation cannot create SecureStrings, so they are created by hand (step 3). The API role can only read `DATABASE_URL`; the migration role can only read `DATABASE_URL_DIRECT`. `ANTHROPIC_API_KEY` is readable only by the coach worker.
- **Database migrations**: [Alembic](https://alembic.sqlalchemy.org) (`backend/migrations/`). During each `cdk deploy`, a CDK trigger runs the `trainwise-migrate-prod` Lambda (`alembic upgrade head`) **before** the API function is updated. After the migrations it updates the built-in exercise catalog from `backend/catalog.py`, then the built-in templates from `backend/template_catalog.py`. If any step fails, the deploy fails and the API keeps its previous code.

The one-time setup below happens in your own AWS, Neon, Vercel and GitHub accounts. Keep every connection string and secret out of git and out of chat.

## What the CDK stack (`TrainWiseApi`) manages

| Resource | Notes |
|---|---|
| Lambda `trainwise-api-prod` | Python 3.11, x86_64, 512 MB, 15 s, handler `lambda_handler.handler` |
| Function URL | Auth `NONE` (the API verifies Clerk session tokens itself). No URL-level CORS, because FastAPI sends the headers |
| Execution role | Basic logging + `ssm:GetParameters` on `/trainwise/prod/DATABASE_URL` only |
| Lambda `trainwise-migrate-prod` | Same code package, handler `migrate_handler.handler`, 5-minute timeout. Its role may only read `/trainwise/prod/DATABASE_URL_DIRECT`. Log group kept for 30 days |
| Migration trigger | CDK trigger that invokes `trainwise-migrate-prod` whenever its code changes, before the API function is updated |
| Log group | `/aws/lambda/trainwise-api-prod`, kept for 30 days |
| Lambda `trainwise-coach-prod` | The AI coach worker: same code package, handler `coach_handler.handler`, 60 s. The API starts it without waiting (the API role may invoke it, nothing else). Its role may read `/trainwise/prod/DATABASE_URL` and `/trainwise/prod/ANTHROPIC_API_KEY`. No retries: a failure is stored on the recommendation. Log group kept for 30 days |
| Alarms | `trainwise-coach-prod-errors` (the worker crashed or timed out), `trainwise-coach-prod-failed-answers` (5 or more failed answers in an hour, counted from the worker's log lines) and `trainwise-coach-prod-daily-calls` (more than 300 calls in a day). Visible in the CloudWatch console; no notifications yet |

Settings that are not secret live in [`infra/cdk.json`](../infra/cdk.json) (`frontendUrls`, `clerkIssuer`, `functionName`, `ssmParameterPrefix`, account and Region). To change one, edit the file in a PR. The deploy after merge applies the change.

Local commands (from `infra/`, after `backend/scripts/build_lambda.sh`):

```bash
python3.11 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest -q                                          # unit tests
PATH="$PWD/.venv/bin:$PATH" npx aws-cdk@2.1146.1 synth --quiet  # render the CloudFormation template
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

To rotate a key, create a new key, update both GitHub secrets, run a deploy, then run `aws iam delete-access-key --user-name trainwise-github-deploy --access-key-id <old id>`.

## 5. GitHub environment

Repository → **Settings → Environments → New environment** → `production`.

- Deployment branches and tags: *Selected branches* → `main`.
- **Environment secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from step 4).

Run a deploy with **Actions → Deploy backend → Run workflow** (branch `main`). The job summary shows the Function URL, and the smoke test prints `{"status":"ok"}`.

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

Pull-request preview deployments get their own `*.vercel.app` URLs. The API rejects those origins on purpose, so previews never write to the production database.

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
4. Test on a real iPhone with a Sandbox account (Settings › Developer › Sandbox Apple Account). Sandbox renews monthly plans every 5 minutes, so expiry is quick to see.
5. In the App Store listing, put the Terms of Use (Apple's standard EULA is used) and the privacy policy links in the description or the EULA field, as Guideline 3.1.2 asks.

## Day-to-day

- Merge a PR into `main`. Vercel redeploys the frontend, CI runs, and if CI passes `cdk deploy` updates the backend infrastructure and code.
- Infrastructure changes (memory, timeout, allowed origins, permissions) are code changes in `infra/`. The deploy log shows a `cdk diff` before deploying.
- Rotate the Clerk secret key in the Clerk dashboard, then update it in Vercel and the `CLERK_SECRET_KEY` repository secret.
- Schema changes: edit `backend/models.py`, generate an Alembic migration (see the README), review it and merge it with the code. The deploy applies it. To run migrations by hand (for example to check a migration against a Neon branch), use `DATABASE_URL=<direct url> alembic upgrade head` from `backend/`.
