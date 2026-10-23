# TrainWise

TrainWise is a full-stack fitness tracking application designed to help users record their training, manage personal fitness data, and eventually receive personalized, explainable AI coaching.

The project is currently in active development. Its first milestone focuses on building a reliable full-stack foundation before adding analytics and AI-powered features.

## Current Features

- User registration
- Secure password hashing
- JWT-based authentication
- Protected current-user endpoint
- Personal fitness profile creation, retrieval, and updates
- Workout creation, retrieval, updates, and deletion
- Responsive registration and login pages
- Protected dashboard with authentication checks
- Sign-out flow

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
- JWT authentication
- Pydantic

## Project Structure

```text
trainwise/
├── backend/
│   ├── routers/
│   │   ├── auth.py
│   │   ├── profiles.py
│   │   └── workouts.py
│   ├── create_tables.py
│   ├── database.py
│   ├── main.py
│   ├── models.py
│   ├── schemas.py
│   └── security.py
└── frontend/
    ├── app/
    │   ├── dashboard/
    │   ├── login/
    │   ├── register/
    │   ├── globals.css
    │   ├── layout.tsx
    │   └── page.tsx
    └── package.json
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
SECRET_KEY=replace-with-a-secure-random-secret
FRONTEND_URL=http://localhost:3000
```

Create the database tables:

```bash
python create_tables.py
```

Start the API:

```bash
uvicorn main:app --reload
```

The API will be available at `http://localhost:8000`. Interactive API documentation is available at `http://localhost:8000/docs`.

### 3. Configure the frontend

In a separate terminal:

```bash
cd frontend
npm install
npm run dev
```

The application will be available at `http://localhost:3000`.

By default, the frontend connects to `http://localhost:8000`. To use a different API URL, create `frontend/.env.local`:

```env
NEXT_PUBLIC_API_URL=http://localhost:8000
```

## Authentication Flow

```text
Register → Sign in → Store JWT → Open protected dashboard → Sign out
```

The registration endpoint accepts JSON. The login endpoint follows the OAuth2 password form format and uses the user's email as the `username` field.

## Quality Checks

GitHub Actions runs the following checks for every pull request and every push to `main`:

- Frontend ESLint
- Frontend production build and TypeScript validation
- Backend linting with Ruff (`ruff check .` in `backend/`; `ruff check --fix .` fixes most issues)
- Backend Python syntax compilation
- Backend API tests (pytest) with a coverage report in the job summary (`pytest --cov` locally)
- End-to-end browser tests (Playwright) against a real FastAPI backend and PostgreSQL database
- CodeQL security analysis for Python and TypeScript (also runs weekly)

Dependabot checks backend, frontend and GitHub Actions dependencies weekly and opens pull requests for updates.

### Running the E2E tests locally

The E2E tests start their own backend on port 8001 and frontend on port 3001, and need an empty PostgreSQL database. One way to get one is Docker:

```bash
docker run -d --rm --name trainwise-e2e-db -e POSTGRES_USER=trainwise -e POSTGRES_PASSWORD=trainwise -e POSTGRES_DB=trainwise_e2e -p 5433:5432 postgres:16
```

Then, with the backend virtual environment in `backend/.venv`:

```bash
cd frontend
npx playwright install chromium
E2E_DATABASE_URL=postgresql+psycopg://trainwise:trainwise@localhost:5433/trainwise_e2e npx playwright test
```

Each feature should include tests for its important behavior before it is merged. Backend API tests must use an isolated test database and cover successful requests, authentication and authorization failures, validation errors, missing resources, and user data isolation. Frontend tests should focus on user-visible behavior rather than styling details.

## Deployment

The frontend is hosted on Vercel and the backend runs on AWS Lambda (FastAPI via Mangum), with PostgreSQL on Neon. After CI passes on `main`, the backend is deployed automatically. See [docs/deployment.md](docs/deployment.md) for the architecture and one-time setup.

## Roadmap

### Phase 1 — Full-Stack Foundation

- [x] User authentication
- [x] Fitness profiles
- [x] Workout API
- [x] Registration and login UI
- [x] Protected dashboard foundation
- [x] Profile management UI
- [x] Workout management UI
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
