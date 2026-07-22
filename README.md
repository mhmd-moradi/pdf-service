# URL-to-PDF Service

A small service that takes a URL, renders it to a PDF using a headless browser,
and lets you download the result. Built as infrastructure-learning scaffolding
(EKS, Helm, GitOps, KEDA, CronJobs, observability) — the app itself is
deliberately simple so the *infrastructure* is where the learning happens.

## Architecture

```
Frontend (HTML/JS) --> API (FastAPI) --> Postgres (job records)
                            |
                            v
                       Redis (queue)
                            |
                            v
                    Worker (Playwright) --> writes PDF to disk, updates Postgres
```

- **API**: submit URL, check job status, list past jobs, download result
- **Worker**: pulls jobs off the Redis queue, renders to PDF via Playwright/Chromium, updates job status in Postgres
- **Frontend**: plain HTML/JS — no build step, no framework
- **Postgres**: one `jobs` table (see `db/schema.sql`)
- **Redis**: used as a simple queue (`RPUSH`/`BLPOP`) — this is what KEDA will later watch to scale the worker

## Prerequisites

- Python 3.10+
- PostgreSQL (running locally)
- Redis (running locally)
- Node.js is NOT required — Playwright's Python package bundles its own browser binaries

## Setup

### 1. Install Postgres and Redis

**macOS (Homebrew):**
```bash
brew install postgresql@16 redis
brew services start postgresql@16
brew services start redis
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install postgresql redis-server
sudo service postgresql start
sudo service redis-server start
```

### 2. Create the database and user

```bash
psql postgres -c "CREATE USER pdfapp WITH PASSWORD 'pdfapp_dev_pw';"
psql postgres -c "CREATE DATABASE pdfservice OWNER pdfapp;"
psql -d pdfservice -f db/schema.sql
```

> Note: `db/schema.sql` includes `GRANT` statements at the end so the `pdfapp`
> user has the right table privileges regardless of which Postgres user applies
> the schema. If you rename the DB user, update those two GRANT lines too.

### 3. Set up the API

```bash
cd api
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 -m uvicorn main:app --reload --port 8000
```

Visit http://localhost:8000/health — should return `{"status": "ok"}`.

### 4. Set up the worker

In a separate terminal:

```bash
cd worker
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 -m playwright install chromium   # downloads the browser binary — only needs to run once
python3 worker.py
```

You should see a JSON log line: `"worker starting up"`, then `"browser launched, waiting for jobs"`.

### 5. Open the frontend

Just open `frontend/index.html` directly in your browser (no server needed —
it's a static file that talks to the API via `fetch`).

### 6. Try it end to end

1. Paste a URL (e.g. `https://example.com`) into the form, submit
2. Watch the status box poll from "pending" → "processing" → "completed"
3. Click "download" in the job history table to get the PDF

## Environment variables (all optional — sensible localhost defaults)

| Variable | Default | Used by |
|---|---|---|
| `POSTGRES_HOST` | `localhost` | API, worker |
| `POSTGRES_PORT` | `5432` | API, worker |
| `POSTGRES_DB` | `pdfservice` | API, worker |
| `POSTGRES_USER` | `pdfapp` | API, worker |
| `POSTGRES_PASSWORD` | `pdfapp_dev_pw` | API, worker |
| `REDIS_HOST` | `localhost` | API, worker |
| `REDIS_PORT` | `6379` | API, worker |
| `REDIS_QUEUE_NAME` | `pdf_jobs` | API, worker |
| `RESULTS_DIR` | `./results` (path) | API, worker — must be the *same* path/volume for both |
| `RENDER_TIMEOUT_MS` | `30000` | worker |

This env-var-only config is intentional: moving to Kubernetes later means
setting these via ConfigMaps/Secrets, not touching code. Same story for the
later RDS migration — just new env var values, same code.

## Known limitations at this stage (fine for now, addressed in later phases)

- `RESULTS_DIR` is local disk — works fine for a single-node setup (minikube),
  but won't work correctly once the API and worker run as separate pods on
  different nodes in real EKS, since they won't share a filesystem. This gets
  fixed in Phase 9 (S3 for results).
- No auth on the API — fine for local/learning, not for anything public.
- CORS is wide open (`*`) — tighten before this goes anywhere real.
- Single Postgres connection per request (no pooling) — fine at this scale.

## Troubleshooting

**`psycopg2.errors.InsufficientPrivilege: permission denied for table jobs`**
Your app DB user doesn't own/have grants on the table. Re-run the GRANT
statements at the bottom of `db/schema.sql` against your database.

**Playwright browser download fails / times out**
Some corporate networks or sandboxed environments block the CDN Playwright
downloads from. Try again on a normal home/office network connection.

**Worker starts but jobs stay "pending" forever**
Check the worker's terminal for errors — most likely Redis isn't reachable,
or the queue name doesn't match between API and worker config.
