# TrainWise

TrainWise is an iOS-first strength-training log with Apple Health integration and, next, a paid AI coach that explains its suggestions. The product ships as **IronSage** ([ironsage.app](https://ironsage.app)); the repository and AWS resources keep the `trainwise` name.

See [docs/architecture.md](docs/architecture.md) for the design, decisions and roadmap.

## Current Features

The iPhone app covers milestones M1 (workout logging) and M2 (Apple Health and progress). The project is signed with the Apple Developer team `CY5V574249`; next are real-device testing and TestFlight.

**API** (`/v1`, built for an offline-first iPhone app)

- Sign-in with Clerk: email verification code, Google or Apple (no passwords); the API verifies Clerk session tokens
- Strength workouts: exercises, sets, reps, load (kg, 3 decimals so pounds round-trip), RIR, set types
- Cardio in the same workouts: an exercise of `kind` cardio lists what it logs besides time (`cardio_metrics`), and a session is one set with the time, distance, speed, incline, the machine's level, floors, average heart rate, active energy and, when an Apple Watch recorded it, that workout's id (migration 0011); the weekly summary counts it as minutes, not as workouts or sets
- Built-in exercise catalog (160 exercises, 9 of them cardio, English and Chinese, with search aliases such as "RDL" and "卧推") plus users' own exercises, such as a specific machine
- Training templates with rep ranges and target RIR, including four built-in programs (`backend/template_catalog.py`)
- Body measurements (weight, body fat, girths) and daily readiness (sleep, HRV, resting heart rate); body fat can be an estimated range (`value_low`/`value_high`, migration 0010) with its middle as the value
- Sync: client-generated UUIDs, soft deletes and `GET /v1/sync?since=N` for "changes since"
- Account deletion: removes all of the user's data and the Clerk user

**Web**

- Landing page, Clerk sign-in, and an account page (sign out, delete account)
- Privacy policy and support pages in English and Chinese (`frontend/app/components/legal-content.ts`); the app ships a copy of the same text (`npm run legal:export` writes `ios/IronSage/Settings/legal.json`, and a test fails until it is current)
- Training review after sign-in (read-only; the iPhone app is where things change), in English or Chinese following the browser:
  - Overview (`/review`): workouts in all, this week against the planned days, weeks in a row, body weight and body fat over a week, month, year or all time, and recent workouts
  - History (`/review/history`): workouts by week, each opening to its exercises and sets, cardio with its time and the machine's numbers
  - Exercises (`/review/exercises`): one exercise's records and estimated one-rep max over time
  - The numbers are worked out in `frontend/app/lib/training.ts` the same way as the app's IronSageCore; the charts are plain SVG with a readout on hover and keyboard focus and a table for screen readers

**iPhone app** (`ios/`)

- Clerk sign-in, five tabs (Today, History, Progress, Templates, Me), English and Chinese: the phone's language until one of the two is picked at the bottom of Me › Profile, which switches the app at once, text looked up in code included (`String(appLocalized:)` in `ios/IronSage/Shared/AppLanguage.swift`)
- Works offline: data is kept on the phone (SwiftData) and synced with the API when online
- Workout logging: exercise search (typos, English or Chinese, aliases such as "RDL", pinyin such as "wotui", and equipment or muscles such as "dumbbell", "哑铃胸", "back" or "腿", name matches first) with Equipment, Muscle and Type filter buttons under the search field, custom exercises, sets prefilled from last time (weight and reps; reps in reserve isn't asked for), a rest timer with a lock-screen notification ("Rest is over: get ready for your next set") and a Live Activity (the countdown and the next set on the lock screen, the Always-On display and in the Dynamic Island, with −15 s, +15 s and Skip; `ios/IronSageWidgets/RestLiveActivity.swift`), exercises marked done that fold to one row (sets checked off and the best one; a tap opens them again), finish and discard asked in a centered alert, and a summary with the sets and new records. No training volume (weight × reps) is shown anywhere. The keyboard closes on a tap outside a field, a number pad has Done above it (and Next on the workout screen: weight, reps, the next set), and checking a set off closes it
- Cardio: incline walk, treadmill run, stair climber, exercise bike, rowing machine, elliptical, and outdoor walks, runs and rides, each with a looping stick figure (`ios/IronSageKit/Sources/IronSageCore/CardioFigures.swift`). Added to a workout from what the Apple Watch recorded today or logged by hand with the machine's own numbers, starting from last time's; in templates with a time and settings to aim for. It isn't stepped up like sets, and isn't counted in sets per muscle, volume or records
- History by week: each workout's sets, editing and deleting
- Templates: fifteen built-in programs, five per experience level (English and Chinese), shown for the user's level (beginner until it is set) with a picker for the others; each program's page says who it suits and how to progress, and shows one day at a time with sets × reps and rest. The user's own templates are built from scratch, copied from a program or saved from a finished workout, with each exercise's sets, rep range and rest; programs can be hidden one by one, on all the user's devices, and the whole programs section can be hidden on the phone with Hide in its header; starting a template day fills in its exercises, sets and targets
- Profile (asked once after the first sign-in): units, experience, goal, training days, and optional height and birthday; the photo is changed from the library or camera, or removed, by tapping it
- Me tab: profile photo, name and email (opening the profile and the app's settings), workouts in all, this week against the planned training days, weeks in a row with training, the latest body weight and body fat with their trend, what IronSage Coach costs, and sign out and account deletion as quiet buttons at the bottom; the privacy policy and support open in a sheet four fifths of the screen high, from the text the app ships with, so they work offline; sync problems are shown only when changes can't reach the server
- Apple Health (optional; everything else works without it): reads sleep, HRV, resting heart rate, body weight and body fat (the last 90 days, then what changed), and cardio workouts another app or an Apple Watch recorded (walks, runs, rides, stairs, elliptical, rowing): one recorded during an IronSage workout joins it, any other becomes its own workout, and one removed in the app isn't imported again. Saves finished workouts as strength training (cardio on its own as that cardio), adds heart rate and active energy when an Apple Watch recorded the workout, and gives cardio logged by hand its heart rate from those minutes
- Progress tab: body weight (a weight from Apple Health is used once the user confirms it is current) and body fat, each typed in or from Apple Health (typed ones are written back to it); body fat is entered as a 5-point range by default (an estimate, shown as a band on the chart, with how many ranges it moved since the last estimate, and not written to Apple Health) or as an exact number; over a week, month, year or all time (averaged per week once the data spans more than 120 days), weekly sets per muscle as aligned rows (the muscle, a bar on a track running to 20 sets, the number; 10–20 a week is the reference, named in the footer), weekly cardio minutes against the WHO's 150–300 with this week's sessions, and each exercise's estimated one-rep max chart and records (heaviest weight, best estimated one-rep max, most reps at a weight)
- Widgets (`ios/IronSageWidgets/TrainingWidget.swift`): on the home screen, small (the next template day and this week), medium (its first exercises with the suggested top set, this week, last night's sleep and HRV) and large (also sets per muscle and a Start button that begins the day); on the lock screen, a ring for this week and the next day. The app writes what they show to the App Group `group.app.ironsage.IronSage` (`ios/Shared/WidgetSnapshot.swift`) when it goes to the background, after a workout and after syncing, in the app's language
- Today shows last night's sleep, HRV and resting heart rate, each compared with the user's own 28-day average
- Follows the iPhone's text size up to the largest accessibility size: rows put their value under the name, a set takes two lines from XXXL (its number fields stop growing at AX2 so they fit), and charts grow taller while their labels stop growing at AX1 (`ios/IronSage/Shared/AdaptiveLayout.swift`); a UI test logs a set at the largest size
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
- SwiftData (local store), Swift Charts, HealthKit
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
│   ├── template_catalog.py       # built-in training templates
│   ├── coach_access.py           # who may use the coach (API and coach worker)
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
├── brand/                        # logo, app icon sources and brand colors
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

Load the built-in exercise catalog and templates into a local database with `python catalog.py` and then `python template_catalog.py` (deploys do this automatically).

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

On an iPhone: sign in to Xcode with an Apple ID in the team (Xcode → Settings → Accounts), turn on Developer Mode on the phone (Settings → Privacy & Security), connect it and run. The project is signed automatically with team `CY5V574249` (`DEVELOPMENT_TEAM`); the first run registers the bundle id `app.ironsage.IronSage` with its HealthKit capability and makes a development profile. A build from Xcode calls staging.

To try the screens without an account, run a Debug build with the launch argument `-demo` (Xcode: Product → Scheme → Edit Scheme → Arguments): sample exercises, workouts and Apple Health data in memory, no sign-in and no network.

The app picks its API by how it was installed (`AppConfig.Server` in `ios/IronSageKit/Sources/IronSageCore/AppConfig.swift`): a build run from Xcode and a TestFlight install call staging, the App Store's calls production. So one build is tried on staging in TestFlight and goes to the App Store unchanged once the backend is promoted. Both addresses are build settings (`STAGING_API_URL`, `PRODUCTION_API_URL`), as is `CLERK_PUBLISHABLE_KEY` (both servers use the Clerk development instance); all are public, and the publishable key also ships in the web app. Staging's database is a copy of production's, so the same account signs in to both. When the app finds it now talks to the other server, it empties the phone's copy and downloads the user's data again.

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

GitHub Actions runs the following checks on every push to `main`. On a pull request, a first job looks at the changed files and runs only the affected checks: `backend/` runs the backend, infrastructure and E2E checks, `frontend/` the frontend and E2E checks, `infra/` the infrastructure checks, and a change to `api/openapi.json` or `.github/` runs everything. A skipped check counts as passed. The iOS job is its own workflow (`ios.yml`), so the backend deploy doesn't wait for the macOS runner; it runs on pull requests and pushes to `main` that change `ios/`, `api/openapi.json` or `.github/`, with a 45-minute limit (macOS runners vary a lot in speed).

- Frontend ESLint
- Frontend unit tests (`npm test`: Node's own test runner on `app/lib/*.test.ts`)
- Frontend production build and TypeScript validation
- Backend linting with Ruff (`ruff check .` in `backend/`; `ruff check --fix .` fixes most issues)
- Backend Python syntax compilation
- Backend API tests (pytest) with a coverage report in the job summary; CI fails below 90% coverage (`pytest --cov` locally); the same tests run again on PostgreSQL (`TEST_DATABASE_URL=postgresql+psycopg://… pytest` locally)
- Infrastructure checks: CDK unit tests and `cdk synth`
- iOS (macOS runner): `swift test` for IronSageKit, then UI tests on a simulator (`ios/IronSageUITests`) that click through the main flows in demo mode. The simulator boots while the app builds. The StoreKit tests (`ios/IronSageTests`) only run in Xcode: StoreKit's local test service returns no products on GitHub's runners
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

The frontend is hosted on Vercel and the backend runs on AWS Lambda (FastAPI via Mangum), with PostgreSQL on Neon. The AWS resources are defined as code with AWS CDK in `infra/`, and secrets live in SSM Parameter Store. After CI passes on `main`, the backend deploys to a staging stack automatically; production is updated only when you promote a release that passed on staging. See [docs/deployment.md](docs/deployment.md) for the architecture and one-time setup.

## Roadmap

The iPhone app's version 1 ships in three milestones ([details](docs/architecture.md#milestones)):

- [x] Backend foundation: Clerk sign-in, `/v1` API with offline sync, exercise catalog, templates, account deletion, privacy and support pages
- [x] **M1 Logging**: profile, workout logging that works offline, history, templates
- [x] **M2 Health and progress**: Apple Health import and workout export, progress charts, personal records, readiness card
- [x] **M3 AI coach**: next-session suggestion with its reason, weekly summary, StoreKit 2 subscription
- [ ] Real-device testing, TestFlight and App Store submission (Apple Developer team set up)

Next, after version 1:

- [x] Body fat from Apple Health, typed in or estimated as a range, with week, month, year and all-time ranges for body weight and body fat
- [x] The user's own templates built from scratch or copied from a program, and hiding built-in programs (synced across devices)
- [x] Reviewing training on the website (read-only)
- [x] Cardio: logged by hand or read from Apple Watch, with weekly minutes
- [ ] Sharing a template by link
- [ ] Apple Watch: the workout in progress on the wrist

Version 2: nutrition logging, and a coach that can chat and adjust plans with tools.

## Project Status

M1, M2 and M3 are merged and production runs them. The Apple Developer account exists; next are real-device testing, TestFlight and App Store submission.

## License

No license has been selected yet.
