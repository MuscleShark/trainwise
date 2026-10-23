# Deployment

TrainWise runs in production as:

```text
Browser ──► Vercel (Next.js frontend, root directory: frontend/)
   │
   └──────► AWS Lambda + Function URL (FastAPI via Mangum, us-east-1)
                 │
                 └──► Neon PostgreSQL (us-east-1, pooled connection)
```

- **Frontend**: Vercel's Git integration deploys every push to `main` and builds preview deployments for pull requests.
- **Backend**: `.github/workflows/deploy-backend.yml` runs after the `CI` workflow succeeds on `main`. It builds a Lambda zip from `backend/requirements.txt` and the backend source, uploads it with short-lived AWS credentials (GitHub OIDC, no stored AWS keys), and calls `/health` as a smoke test.
- **Database**: tables are created with `backend/create_tables.py`. It only creates missing tables. It does not alter existing ones.

The one-time setup below happens in your own AWS, Neon, Vercel and GitHub accounts. Keep every connection string and secret out of git and out of chat.

---

## 0. AWS budget alert (do this first)

AWS Billing → **Budgets** → Create budget → *Zero spend budget* (or a monthly cost budget of e.g. $1) → your email.

## 1. Neon

1. In the Neon console, open the project → **Connect**.
2. Copy two connection strings:
   - **Pooled**: the host contains `-pooler`. The Lambda function uses this one.
   - **Direct**: pooling turned off. Use it to create tables.
3. In both, change the scheme `postgresql://` to `postgresql+psycopg://`. Keep `?sslmode=require` (and any other query parameters).

Create the tables once from your machine using the **direct** string, without it ending up in your shell history:

```bash
cd backend
read -rs "NEON_DIRECT_URL?Neon direct URL: " && echo
DATABASE_URL="$NEON_DIRECT_URL" SECRET_KEY=unused .venv/bin/python create_tables.py
unset NEON_DIRECT_URL
```

## 2. Lambda function (AWS console, region **us-east-1**)

1. Lambda → **Create function** → Author from scratch
   - Name: `trainwise-api`
   - Runtime: **Python 3.11**
   - Architecture: **x86_64**
2. **Configuration → General configuration** → Memory `512 MB`, Timeout `15 sec`.
3. **Code → Runtime settings** → Handler: `main.handler`.
4. **Configuration → Environment variables**:

   | Key | Value |
   |---|---|
   | `DATABASE_URL` | Neon **pooled** string (with `postgresql+psycopg://`) |
   | `SECRET_KEY` | A new random value, e.g. from `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` (do not reuse your local one) |
   | `FRONTEND_URL` | Your Vercel production URL, e.g. `https://trainwise.vercel.app` (fill in after step 5; comma-separate several origins) |

5. **Configuration → Function URL** → Create
   - Auth type: **NONE**. The API does its own JWT authentication.
   - **Do not** enable CORS here. FastAPI already sends the CORS headers, and enabling both produces duplicate headers.
   - Copy the Function URL (`https://<id>.lambda-url.us-east-1.on.aws/`).

The function still contains AWS's placeholder code until the first deploy in step 4.

## 3. Let GitHub Actions deploy (IAM, OIDC)

1. IAM → **Identity providers** → Add provider → *OpenID Connect*
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
2. IAM → **Roles** → Create role → *Custom trust policy*, replacing `<ACCOUNT_ID>`:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
             "token.actions.githubusercontent.com:sub": "repo:MuscleShark/trainwise:environment:production"
           }
         }
       }
     ]
   }
   ```

   Only jobs that run in this repository's `production` environment can assume the role.

3. Name the role `trainwise-github-deploy`, then add this **inline policy** (least privilege, only this one function):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "lambda:UpdateFunctionCode",
           "lambda:GetFunction",
           "lambda:GetFunctionConfiguration"
         ],
         "Resource": "arn:aws:lambda:us-east-1:<ACCOUNT_ID>:function:trainwise-api"
       }
     ]
   }
   ```

4. Copy the role ARN (`arn:aws:iam::<ACCOUNT_ID>:role/trainwise-github-deploy`).

## 4. GitHub environment

Repository → **Settings → Environments → New environment** → `production`.

- Deployment branches and tags: *Selected branches* → `main`.
- **Environment variables** (these are not secrets):

  | Name | Value |
  |---|---|
  | `AWS_DEPLOY_ROLE_ARN` | role ARN from step 3 |
  | `API_URL` | Lambda Function URL from step 2 |
  | `LAMBDA_FUNCTION_NAME` | `trainwise-api` (optional; this is the default) |

After this branch is merged, run the first deploy manually: **Actions → Deploy backend → Run workflow** (branch `main`). The smoke test should print `{"status":"ok"}`. That proves Lambda can reach Neon.

## 5. Vercel

1. **Add New → Project** → import `MuscleShark/trainwise`.
2. **Root Directory**: `frontend` (framework preset: Next.js).
3. **Environment Variables**: `NEXT_PUBLIC_API_URL` = the Lambda Function URL **without the trailing slash**. The frontend builds URLs as `${API_URL}/login`.
4. Deploy, then copy the production domain into the Lambda `FRONTEND_URL` variable (step 2.4).

`NEXT_PUBLIC_*` values are baked in at build time, so redeploy on Vercel after changing them.

Pull-request preview deployments get their own `*.vercel.app` URLs. The API rejects those origins on purpose, so previews never write to the production database.

## 6. Check it

Open the Vercel URL → register → sign in → add a profile and a workout → reload and confirm the data is still there.

## Day-to-day

- Merge a PR into `main`. Vercel redeploys the frontend, CI runs, and if CI passes the backend redeploys.
- Rotate `SECRET_KEY` by editing the Lambda environment variable. Every user is signed out.
- New tables: rerun `create_tables.py` against the direct URL. Changes to existing tables need a migration tool (Alembic), which is not set up yet.
