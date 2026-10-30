# Dollor web platform (backend API + web frontend)

FastAPI backend (`backend/`) and Vite/React frontend (`frontend/`) for Dollor rideshare.

## Production

| Item | Value |
|---|---|
| API | `https://api.dollor.ai` (ECS service `dollor-api-service`, image built from `backend/Dockerfile.optimized`) |
| Web app | `https://dollor.ai` (S3 bucket `dollar-ai-frontend` behind CloudFront `E1TL8YTTU1SF3A`) |
| Deploy | `.github/workflows/deploy-dollar-ai.yml` on push to `main`; runbook in `../../DEPLOYMENT.md` and `../../docs/CUTOVER.md` |
| Secrets | injected by ECS from AWS Secrets Manager (see `../../docs/SECRETS.md`); nothing is read from `.env` in production |

The mobile apps and the web frontend only talk to `https://api.dollor.ai`. Do not add local or staging hosts to
application code or configuration.

## Tech stack

- Backend: FastAPI, SQLAlchemy, Alembic, PostgreSQL, Redis (optional cache / WebSocket fan-out), Stripe
- Frontend: React 18, TypeScript, Vite, TailwindCSS, Ant Design

## Development (local development only)

Everything in this section runs on a developer machine or CI and never touches production.

### Option A: docker compose (recommended for integration tests)

From the repository root:

```bash
docker compose -f docker-compose.integration.yml up -d postgres redis backend
./scripts/run-integration-tests.sh          # backend API, iOS contract, e2e and Playwright suites
docker compose -f docker-compose.integration.yml down -v
```

The compose file publishes the backend on port 8001 and the frontend on port 5174 of the developer machine.

### Option B: virtualenv

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # fill in DATABASE_URL, JWT_SECRET_KEY, ENVIRONMENT=development
alembic upgrade head
uvicorn main_new:app --reload --port 8080
```

```bash
cd frontend
npm ci
VITE_API_URL=http://<backend-host>:8080 npm run dev
```

With `ENVIRONMENT=development` the backend allows CORS from the usual Vite dev ports; in production that list is
limited to the Dollor domains (`backend/main_new.py`, `PRODUCTION_ORIGINS`). OpenAPI docs are served at `/docs` and
`/redoc` outside production only.

### Tests

```bash
cd backend
JWT_SECRET_KEY=<any-32+-char-string> DATABASE_URL=sqlite:///./test.db python -m pytest tests --ignore=tests/smoke -q
```

`tests/smoke` runs against a live environment (`pytest tests/smoke --env=production`). The frontend has `npm run
test:run`, `npm run typecheck` and `npm run lint`.

## Layout

```
backend/
  main_new.py          FastAPI application (routes, middleware, CORS)
  models.py            SQLAlchemy models
  database.py          engine/session (DATABASE_URL required)
  alembic/             migrations
  tests/               pytest suites (unit, api, e2e, security, smoke)
  Dockerfile.optimized production image (target "production")
frontend/
  src/                 React application
  .env.production      public build-time values (API URL, OAuth client ids)
```
