# TrainWise

TrainWise is a full-stack fitness tracking application designed to help users record their training, manage personal fitness data, and eventually receive personalized, explainable AI coaching.

The project is currently in active development. Its first milestone focuses on building a reliable full-stack foundation before adding analytics and AI-powered features.

TrainWise is becoming an iOS-first strength-training log with a paid AI coach. See [docs/architecture.md](docs/architecture.md) for the target design, decisions and roadmap.

## Current Features

The product ships as **IronSage**. The iPhone app is in progress (milestone M1, workout logging); the backend is ready for it.

**API** (`/v1`, built for an offline-first iPhone app)

- Sign-in with Clerk: email verification code, Google or Apple (no passwords); the API verifies Clerk session tokens
- Strength workouts: exercises, sets, reps, load (kg, 3 decimals so pounds round-trip), RIR, set types
- Built-in exercise catalog (145 exercises, English and Chinese, with search aliases such as "RDL" and "卧推") plus users' own exercises, such as a specific machine
- Training templates with rep ranges and target RIR
- Body measurements (weight, body fat, girths) and daily readiness (sleep, HRV, resting heart rate)
- Sync: client-generated UUIDs, soft deletes and `GET /v1/sync?since=N` for "changes since"
- Account deletion: removes all of the user's data and the Clerk user

**Web**

- Landing page, Clerk sign-in, and an account page (sign out, delete account)

**iPhone app** (`ios/`, early)

- Clerk sign-in, four tabs (Today, History, Templates, Settings), English and Chinese
- Works offline: data is kept on the phone (SwiftData) and synced with the API when online
- Workout logging: exercise search (typos, English or Chinese, aliases such as "RDL", pinyin such as "wotui"), custom exercises, sets prefilled from last time, optional RIR, a rest timer with a lock-screen notification, and a summary with volume and new records
- API client generated from `api/openapi.json`

## Tech Stack

### Frontend

- Next.js 16
- React 19
- TypeScript
- Tailwind CSS

### Backend

- FastAPI
- SQLAlchemy
- PostgreSQL
- Clerk session token verification (JWKS)
- Pydantic

### iPhone app

- SwiftUI, iOS 18 or newer
- Clerk iOS SDK
- swift-openapi-generator

## Project Structure

```text
trainwise/
├── backend/
│   ├── routers/                  # /v1 endpoints (auth, profile, exercises, workouts,
│   │                             #   templates, body, sync)
│   ├── migrations/               # Alembic database migrations
│   ├── scripts/build_lambda.sh   # builds the Lambda package
│   ├── tests/
│   ├── catalog.py                # built-in exercise catalog
│   ├── database.py
│   ├── lambda_handler.py         # AWS Lambda entry point
│   ├── migrate_handler.py        # Lambda that runs migrations during deploys
│   ├── main.py
│   ├── models.py
│   ├── schemas.py
│   ├── security.py
│   └── sync.py                   # change counter and shared write helpers
├── frontend/
│   ├── app/
│   │   ├── account/
│   │   ├── login/
│   │   ├── register/
│   │   ├── globals.css
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── e2e/                      # Playwright tests
│   └── package.json
├── ios/
│   ├── IronSage.xcodeproj
│   ├── IronSage/                 # SwiftUI app (screens, Info.plist, strings)
│   └── IronSageKit/              # Swift package: generated API client (IronSageAPI),
│                                 #   app logic (IronSageCore), local data and sync
│                                 #   (IronSageStore), and their tests
├── api/openapi.json              # API contract; clients generate their code from it
├── infra/                        # AWS CDK app (Lambda, Function URL, IAM)
└── docs/deployment.md
```

## Getting Started

### Prerequisites

- Python 3.11 or newer
- Node.js
- PostgreSQL

### 1. Clone the repository

```bash
git clone https://github.com/MuscleShark/trainwise.git
cd trainwise
```

### 2. Configure the backend

Create and activate a Python virtual environment:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
```

Install the backend dependencies:

```bash
pip install -r requirements-dev.txt
```

`requirements.txt` holds the runtime dependencies that ship to production; `requirements-dev.txt` adds the local server, test and lint tools.

Create `backend/.env` and add your local configuration:

```env
DATABASE_URL=postgresql+psycopg://USERNAME:PASSWORD@localhost:5432/trainwise
CLERK_ISSUER=https://YOUR-INSTANCE.clerk.accounts.dev
FRONTEND_URL=http://localhost:3000
```

Create or update the database tables:

```bash
alembic upgrade head
```

To change the schema, edit `models.py`, then generate a migration, read it, and commit it with the change:

```bash
alembic revision --autogenerate -m "add exercises table"
alembic upgrade head
alembic check   # fails if models.py and the migrations differ
```

Migrations run automatically in production during each deploy (see [docs/deployment.md](docs/deployment.md)). Keep them backward compatible with the code that is still running: add columns and tables first, and remove old ones in a later release.

Start the API:

```bash
uvicorn main:app --reload
```

The API will be available at `http://localhost:8000`. Interactive API documentation is available at `http://localhost:8000/docs`.

Client endpoints are versioned under `/v1`. A breaking change ships as `/v2` so installed app versions keep working. `/health` stays unversioned.

How the iPhone app uses the API:

- The app creates records offline with its own UUIDs and saves them with `PUT` (for example `PUT /v1/workouts/{id}` with the whole workout, exercises and sets included). Sending the same request again gives the same result, so retries are safe.
- Deleting marks a record as deleted instead of removing it, so other devices learn about it.
- `GET /v1/sync?since=N` returns everything that changed after `N`, deletions included, plus the new `change_seq` to send next time.
- Times must include a time zone and are returned in UTC; a workout also stores its local `time_zone`.

Load the built-in exercise catalog into a local database with `python catalog.py` (deploys do this automatically).

### API contract

[`api/openapi.json`](api/openapi.json) is the API's contract, generated from the FastAPI code. Clients generate their code from it instead of writing requests by hand:

- Web: `npm run api:types` (in `frontend/`) regenerates `app/lib/api-types.ts`.
- iPhone app: Apple's swift-openapi-generator reads the same file when the app builds (`ios/IronSageKit/Sources/IronSageAPI/openapi.json` is a symlink to it).

The export rewrites FastAPI's optional fields (`anyOf [X, null]`) as `type: [X, "null"]`, because the Swift generator drops fields written the first way. Decimal values such as `weight_kg` are sent as JSON numbers.

After changing an endpoint or schema, regenerate and commit both files:

```bash
cd backend && python scripts/export_openapi.py
cd ../frontend && npm run api:types
```

Backend tests fail while `api/openapi.json` is out of date.

### 3. Configure the frontend

In a separate terminal:

```bash
cd frontend
npm install
npm run dev
```

The application will be available at `http://localhost:3000`.

Create `frontend/.env.local` with the keys from Clerk dashboard → **API keys** (development instance). The file is gitignored:

```env
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
# Optional; defaults to http://localhost:8000
NEXT_PUBLIC_API_URL=http://localhost:8000
```

`CLERK_ISSUER` in `backend/.env` is the instance's Frontend API URL, shown in Clerk dashboard → **API keys**. It is also the publishable key's base64 part decoded, without the trailing `$`.

### 4. Run the iPhone app

Needs Xcode 26 or newer. Open `ios/IronSage.xcodeproj`, pick an iPhone simulator and run. The first build asks you to trust the OpenAPIGenerator plugin; it generates the API client.

To try the screens without an account, run a Debug build with the launch argument `-demo` (Xcode: Product → Scheme → Edit Scheme → Arguments): sample exercises and workouts in memory, no sign-in and no network.

The app calls the production API and the Clerk development instance; both values are build settings (`API_BASE_URL`, `CLERK_PUBLISHABLE_KEY`) in the project. Both are public: the publishable key also ships in the web app.

From the command line:

```bash
cd ios/IronSageKit && swift test
cd .. && xcodebuild build -project IronSage.xcodeproj -scheme IronSage -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation
```

## Authentication Flow

```text
Clerk sign-in (email code / Google / Apple) → Clerk session token → API verifies it → dashboard
```

The web app uses Clerk's `<SignIn>` and `<SignUp>` components at `/login` and `/register`. Every API request carries the Clerk session token as `Authorization: Bearer …`. The backend verifies it locally against the instance's public keys (JWKS): signature, expiry, issuer, and, for browser requests, that it came from an allowed origin (`azp`). The token must carry an `email` claim, configured in Clerk dashboard → **Sessions → Customize session token**:

```json
{ "email": "{{user.primary_email_address}}" }
```

On first sign-in the backend links the Clerk user to an existing account with the same email (accounts created before Clerk), or creates a new one.

Clerk dashboard settings: email address with **verification code**, Google and Apple enabled, password off.

## Quality Checks

GitHub Actions runs the following checks for every pull request and every push to `main`:

- Frontend ESLint
- Frontend production build and TypeScript validation
- Backend linting with Ruff (`ruff check .` in `backend/`; `ruff check --fix .` fixes most issues)
- Backend Python syntax compilation
- Backend API tests (pytest) with a coverage report in the job summary; CI fails below 90% coverage (`pytest --cov` locally)
- Infrastructure checks: CDK unit tests and `cdk synth`
- iOS (macOS runner): `swift test` for IronSageKit, then a simulator build of the app
- End-to-end browser tests (Playwright) against a real FastAPI backend and PostgreSQL database, signing in through the Clerk development instance (repository variable `CLERK_PUBLISHABLE_KEY`, repository secret `CLERK_SECRET_KEY`)
- CodeQL security analysis for Python and TypeScript (also runs weekly)

Routine dependency version updates are not automated. Dependabot security alerts stay enabled in the repository settings. When a dependency has a known vulnerability, GitHub shows an alert and may open a security-fix pull request.

### Running the E2E tests locally

The E2E tests start their own backend on port 8001 and frontend on port 3001, and need an empty PostgreSQL database. One way to get one is Docker:

```bash
docker run -d --rm --name trainwise-e2e-db -e POSTGRES_USER=trainwise -e POSTGRES_PASSWORD=trainwise -e POSTGRES_DB=trainwise_e2e -p 5433:5432 postgres:16
```

The tests sign up through the Clerk development instance with `+clerk_test` emails, which accept the code `424242`. They read the Clerk keys from the environment, so load `frontend/.env.local` first. Then, with the backend virtual environment in `backend/.venv`:

```bash
cd frontend
npx playwright install chromium
set -a && source .env.local && set +a
E2E_DATABASE_URL=postgresql+psycopg://trainwise:trainwise@localhost:5433/trainwise_e2e npx playwright test
```

Each feature should include tests for its important behavior before it is merged. Backend API tests must use an isolated test database and cover successful requests, authentication and authorization failures, validation errors, missing resources, and user data isolation. Frontend tests should focus on user-visible behavior rather than styling details.

## Deployment

The frontend is hosted on Vercel and the backend runs on AWS Lambda (FastAPI via Mangum), with PostgreSQL on Neon. The AWS resources are defined as code with AWS CDK in `infra/`, and secrets live in SSM Parameter Store. After CI passes on `main`, `cdk deploy` runs automatically. See [docs/deployment.md](docs/deployment.md) for the architecture and one-time setup.

## Roadmap

### Phase 1 — Full-Stack Foundation

- [x] User authentication
- [x] Fitness profiles
- [x] Workout API
- [x] Registration and login UI (Clerk)
- [x] Protected dashboard foundation
- [x] Profile management UI
- [x] Workout management UI
- [x] Versioned API (`/v1`) and account deletion
- [ ] Nutrition tracking
- [ ] Body-weight tracking
- [ ] Sleep tracking
- [ ] Progress dashboard and charts

### Phase 2 — AI Features

- [ ] Personalized workout recommendations
- [ ] Explainable recommendations
- [ ] AI fitness chat
- [ ] Weekly progress reports
- [ ] Recovery scoring
- [ ] Goal progress predictions

### Phase 3 — Fitness Coach Agent

- [ ] Connect workout, nutrition, sleep, progress, and goal tools
- [ ] Allow the coach to select and call tools based on each request
- [ ] Generate and adjust personalized fitness plans over time

## Project Status

TrainWise is currently completing Phase 1. The authentication flow and core backend APIs are in place. The next development milestone is connecting profile and workout management to the frontend dashboard.

## License

No license has been selected yet.
