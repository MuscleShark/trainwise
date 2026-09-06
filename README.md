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
pip install fastapi uvicorn sqlalchemy psycopg python-dotenv python-jose pwdlib python-multipart
```

Create `backend/.env` and add your local configuration:

```env
DATABASE_URL=postgresql+psycopg://USERNAME:PASSWORD@localhost:5432/trainwise
SECRET_KEY=replace-with-a-secure-random-secret
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

## Roadmap

### Phase 1 — Full-Stack Foundation

- [x] User authentication
- [x] Fitness profiles
- [x] Workout API
- [x] Registration and login UI
- [x] Protected dashboard foundation
- [x] Profile management UI
- [ ] Workout management UI
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
