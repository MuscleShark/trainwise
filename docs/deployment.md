# Deployment

TrainWise runs in production as:

```text
Browser ──► Vercel (Next.js frontend, root directory: frontend/)
   │
   └──────► AWS Lambda + Function URL (FastAPI via Mangum, us-east-2)
                 │          └── reads secrets from SSM Parameter Store at cold start
                 └──► Neon PostgreSQL (us-east-2, pooled connection)
```

- **Frontend**: Vercel's Git integration deploys every push to `main` and builds preview deployments for pull requests.
- **Backend infrastructure and code**: defined with **AWS CDK** in [`infra/`](../infra). After the `CI` workflow succeeds on `main`, `.github/workflows/deploy-backend.yml` builds the Lambda package (`backend/scripts/build_lambda.sh`), runs `cdk deploy` and calls `/health` as a smoke test.
- **Secrets**: `DATABASE_URL` and `SECRET_KEY` are SSM Parameter Store *SecureString* parameters under `/trainwise/prod/`. CloudFormation cannot create SecureStrings, so they are created by hand (step 3). Only the Lambda role can read them.
- **Database**: tables are created with `backend/create_tables.py`. It only creates missing tables. It does not alter existing ones.

The one-time setup below happens in your own AWS, Neon, Vercel and GitHub accounts. Keep every connection string and secret out of git and out of chat.

## What the CDK stack (`TrainWiseApi`) manages

| Resource | Notes |
|---|---|
| Lambda `trainwise-api-prod` | Python 3.11, x86_64, 512 MB, 15 s, handler `lambda_handler.handler` |
| Function URL | Auth `NONE` (the API does its own JWT auth). No URL-level CORS, because FastAPI sends the headers |
| Execution role | Basic logging + `ssm:GetParameters` on `/trainwise/prod/DATABASE_URL` and `/trainwise/prod/SECRET_KEY` only |
| Log group | `/aws/lambda/trainwise-api-prod`, kept for 30 days |

Settings that are not secret live in [`infra/cdk.json`](../infra/cdk.json) (`frontendUrls`, `functionName`, `ssmParameterPrefix`, account and Region). To change one, edit the file in a PR. The deploy after merge applies the change.

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
   - **Pooled**: the host contains `-pooler`. The Lambda function uses this one.
   - **Direct**: pooling turned off. Use it to create tables.
3. In both, change the scheme `postgresql://` to `postgresql+psycopg://`. Keep `?sslmode=require`.

Create the tables from your machine using the **direct** string:

```bash
cd backend
read -rs "NEON_DIRECT_URL?Neon direct URL: " && echo
DATABASE_URL="$NEON_DIRECT_URL" SECRET_KEY=unused .venv/bin/python create_tables.py
unset NEON_DIRECT_URL
```

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
read -rsp "Production SECRET_KEY: " V && echo && aws ssm put-parameter --region us-east-2 --name /trainwise/prod/SECRET_KEY --type SecureString --value "$V" --overwrite && unset V
```

Reuse the existing production `SECRET_KEY` from your password manager so users stay signed in. A new value signs everyone out. Generate one with `python3 -c "import secrets; print(secrets.token_urlsafe(48))"`.

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
3. **Environment Variables**: `NEXT_PUBLIC_API_URL` = the Function URL **without the trailing slash**, type **Config**. Do not use *Secret*. `NEXT_PUBLIC_*` values are public by design, and Vercel will not inject a Secret into the browser bundle.
4. Deploy. The production domain must be listed in `frontendUrls` in `infra/cdk.json`, written exactly as the browser shows it (`https://…`, no trailing slash).

`NEXT_PUBLIC_*` values are baked in at build time, so redeploy on Vercel after changing them.

Pull-request preview deployments get their own `*.vercel.app` URLs. The API rejects those origins on purpose, so previews never write to the production database.

## 7. Check it

Open the Vercel URL → register → sign in → add a profile and a workout → reload and confirm the data is still there.

## Day-to-day

- Merge a PR into `main`. Vercel redeploys the frontend, CI runs, and if CI passes `cdk deploy` updates the backend infrastructure and code.
- Infrastructure changes (memory, timeout, allowed origins, permissions) are code changes in `infra/`. The deploy log shows a `cdk diff` before deploying.
- Rotate `SECRET_KEY` with step 3, then redeploy so new Lambda instances read it. Every user is signed out.
- New tables: rerun `create_tables.py` against the direct URL. Changes to existing tables need a migration tool (Alembic), which is not set up yet.
