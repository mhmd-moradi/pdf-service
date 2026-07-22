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

### 3. Set up one virtual environment for both services

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 -m playwright install chromium   # downloads the browser binary — only needs to run once
```

> Note: `api/requirements.txt` and `worker/requirements.txt` also exist
> separately — those are what each service's Dockerfile will use in Phase 2,
> once they become separate images. For now, one shared `venv` is simpler.

### 4. Run the API

```bash
cd api
source ../venv/bin/activate
python3 -m uvicorn main:app --reload --port 8000
```

Visit http://localhost:8000/health — should return `{"status": "ok"}`.

### 5. Run the worker

In a separate terminal:

```bash
cd worker
source ../venv/bin/activate
python3 worker.py
```

You should see a JSON log line: `"worker starting up"`, then `"browser launched, waiting for jobs"`.

### 6. Open the frontend

Just open `frontend/index.html` directly in your browser (no server needed —
it's a static file that talks to the API via `fetch`).

### 7. Try it end to end

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

## Phase 2: Running with Docker Compose

Once Phase 1 (running everything as bare processes) works, Docker Compose
packages the same 5 services (Postgres, Redis, API, worker, frontend) into
containers that all start together with one command.

### Prerequisites

- Docker Desktop installed and running (includes `docker compose` built in)

### Run it

```bash
docker compose up --build
```

First run will take a while — the worker image in particular is large
(~1-1.5GB) since it's based on the official Playwright image with Chromium
pre-installed. Subsequent runs are much faster since layers are cached.

Once it's up:
- API: http://localhost:8000
- Frontend: http://localhost:8080
- Postgres: localhost:5432 (same credentials as local dev)
- Redis: localhost:6379

Note the frontend's `index.html` still points `API_BASE` at
`http://localhost:8000` — that's correct even in Compose, since the
*browser* (not a container) is what calls the API, and port 8000 is
published to your host machine either way.

### Stop it

```bash
docker compose down
```

Add `-v` (`docker compose down -v`) if you also want to wipe the Postgres
data and start fresh next time — otherwise your job history persists across
restarts (it's in the `postgres_data` named volume).

### What's different from Phase 1's local setup

- No manual `CREATE USER`/`CREATE DATABASE`/`psql -f schema.sql` steps —
  Postgres's official image auto-applies `db/schema.sql` on first startup
  (see the `docker-entrypoint-initdb.d` mount in `docker-compose.yml`).
- No manual `playwright install chromium` — baked into the worker's base image.
- Service-to-service hostnames are Docker Compose **service names**
  (`postgres`, `redis`), not `localhost`. If you add new env vars, remember
  this distinction.

### Debugging

```bash
docker compose logs api       # just the API's logs
docker compose logs worker    # just the worker's logs
docker compose ps             # see status/health of all services
```

If the worker's image fails to build, or crashes with a Chromium-related
error, that's the main thing to watch closely on your first run — it's the
trickiest of the 5 services.

---

## Phase 3: Running on minikube with Helm

This deploys the same containers from Phase 2 onto a real (local) Kubernetes
cluster, using Helm charts instead of docker-compose.

### Prerequisites

- `minikube`, `kubectl`, `helm` installed
- Docker Desktop running (minikube can use it as its driver)

### 1. Start minikube

```bash
minikube start
kubectl get nodes   # should show one Ready node
```

### 2. Build images directly into minikube's Docker daemon

Minikube runs its own internal Docker daemon, separate from your Mac's.
Point your shell at it before building, so the images land where minikube
can actually find them (no registry push needed for local dev):

```bash
eval $(minikube docker-env)
docker build -t pdf-service-api:local ./api
docker build -t pdf-service-worker:local ./worker
docker build -t pdf-service-frontend:local ./frontend
```

> Important: this `eval` only affects your current terminal session. If you
> open a new terminal, run it again before rebuilding images.

### 3. Install Postgres and Redis (Bitnami charts)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install postgres bitnami/postgresql \
  --set auth.username=pdfapp \
  --set auth.password=pdfapp_dev_pw \
  --set auth.database=pdfservice \
  --set-file "primary.initdb.scripts.schema\.sql"=db/schema.sql

helm install redis bitnami/redis \
  --set architecture=standalone \
  --set auth.enabled=false
```

Wait for both to be ready:
```bash
kubectl get pods -w
```
(Ctrl+C once you see `postgres-postgresql-0` and `redis-master-0` both `Running`/`1/1`)

**Verify the service names match what the charts expect** (they should, but
confirm before moving on — chart versions change over time):
```bash
kubectl get svc
```
You're looking for something like `postgres-postgresql` (port 5432) and
`redis-master` (port 6379). If yours differ, update
`helm/api/values.yaml` and `helm/worker/values.yaml` (`env.postgresHost` /
`env.redisHost`) to match before the next step.

### 4. Install the shared storage and secret

```bash
helm install shared-storage ./helm/shared-storage
```

This creates the `pdf-results` PVC and the `postgres-credentials` Secret
that the api/worker charts both depend on — install this before them.

### 5. Install the app charts

```bash
helm install api ./helm/api
helm install worker ./helm/worker
helm install frontend ./helm/frontend
```

### 6. Check everything's running

```bash
kubectl get pods
kubectl get cronjob
```

You should see pods for api, worker, frontend, postgres, redis all
`Running`, plus the `worker-cleanup` CronJob listed (it won't have run yet
— it's scheduled for 3am).

### 7. Access the frontend

The service name depends on the release name you used
(`helm install frontend ./helm/frontend` → service `frontend-frontend`):
```bash
minikube service frontend-frontend --url
```
This prints a URL — open it in your browser.

### 8. Access the API directly (for curl testing)

```bash
kubectl port-forward svc/api-api 8000:8000
```
Then in another terminal, the same curl commands from Phase 1/2 work
against `http://localhost:8000`.

### 9. Test the CronJob without waiting for 3am

```bash
kubectl create job --from=cronjob/worker-cleanup manual-cleanup-test
kubectl logs job/manual-cleanup-test
```
Should show the same `"cleanup job starting"` / `"cleanup job finished"`
JSON log lines you saw testing it locally.

### Debugging

```bash
kubectl logs deployment/api-api
kubectl logs deployment/worker-worker
kubectl describe pod <pod-name>    # if a pod is stuck Pending or CrashLoopBackOff
```

A pod stuck in `Pending` almost always means the PVC hasn't bound —
check `kubectl get pvc` and confirm `shared-storage` was installed first.

### Tear down

```bash
helm uninstall api worker frontend shared-storage postgres redis
minikube stop
```

---

## Phase 4: GitOps (Flux CD) + CI (GitHub Actions)

Up to now you've been running `helm install` by hand. This phase hands that
job to **Flux CD**, which continuously watches this Git repo and makes the
cluster match whatever's committed — Git becomes the source of truth, not
your terminal history. On top of that, **GitHub Actions** builds and pushes
images automatically, and updates the chart values that Flux is watching.

### Important: this replaces your manual installs, it doesn't run alongside them

Your `postgres`, `redis`, `shared-storage`, `api`, `worker`, and `frontend`
releases from Phase 3 were installed manually into the `default` namespace.
The Flux manifests here manage releases with the **same names in the same
namespace** — but Flux needs a clean slate to take over correctly. Uninstall
the manual releases first:

```bash
helm uninstall api worker frontend shared-storage postgres redis
kubectl get pvc   # confirm PVCs are gone too (or delete manually if not)
```

### 1. Update the GitRepository URL

Edit `clusters/minikube/flux-system-config.yaml` and replace
`YOUR_GITHUB_USERNAME` with your actual GitHub username.

### 2. Push everything to GitHub

```bash
git add .
git commit -m "Phase 4: Flux GitOps manifests and GitHub Actions CI"
git push
```

### 3. Install Flux's controllers into the cluster

```bash
flux install
kubectl get pods -n flux-system   # wait for Flux's own controllers to be Running
```

### 4. Apply the GitRepository + Kustomization

This is the one manual `kubectl apply` you'll ever need — it tells Flux
where to look. After this, Flux takes over entirely.

```bash
kubectl apply -f clusters/minikube/flux-system-config.yaml
```

### 5. Watch Flux reconcile everything

```bash
flux get kustomizations
flux get helmreleases -A
kubectl get pods -w
```

Give it a few minutes — Flux needs to: pull the Bitnami charts, install
Postgres and Redis, wait for `dependsOn` conditions, then install
shared-storage, api, worker, frontend in order. If a HelmRelease shows
`False` under `READY`, check details with:

```bash
flux logs --level=error
kubectl describe helmrelease <name> -n flux-system
```

### 6. Verify the app still works

Same tests as Phase 3 — `kubectl port-forward svc/api-api 8000:8000` and
curl, or `minikube service frontend-frontend --url`.

### 7. Set up the GitHub Actions CI pipeline

The workflow at `.github/workflows/build-and-deploy.yml` needs no extra
secrets — it uses the automatically-provided `GITHUB_TOKEN`. But it does
need one manual setting:

**Make the GHCR packages public** (so minikube can pull them without
needing image pull credentials): after your first push triggers the
workflow and creates the packages, go to your GitHub profile → Packages →
select each `pdf-service-*` package → Package settings → change visibility
to Public.

### 8. Try the full CI → GitOps loop

Make a small change to, say, `frontend/index.html` (even just a comment),
then:
```bash
git add frontend/index.html
git commit -m "test CI/CD pipeline"
git push
```

Watch it happen:
1. **GitHub** → your repo → Actions tab — watch the workflow build and push
   images, then commit an updated `values.yaml` back to `main`
2. Flux notices that new commit within its polling interval and updates the
   `frontend` HelmRelease automatically
3. `kubectl get pods -w` — you should see a new `frontend` pod get created

That loop — **you push code, and a new pod appears with no `helm upgrade`
or `kubectl apply` from you at any point** — is the entire point of GitOps.

### Debugging

```bash
flux get all -A                          # overall Flux health
flux logs --follow                       # live Flux controller logs
kubectl get helmrelease -n flux-system   # per-release status
```

A HelmRelease stuck `False`/`Unknown` most often means either a values
typo (check `flux logs`) or GHCR image pull failure (check the package
visibility setting above).

### Tear down

```bash
kubectl delete -f clusters/minikube/flux-system-config.yaml
flux uninstall
```

---



**`psycopg2.errors.InsufficientPrivilege: permission denied for table jobs`**
Your app DB user doesn't own/have grants on the table. Re-run the GRANT
statements at the bottom of `db/schema.sql` against your database.

**Playwright browser download fails / times out**
Some corporate networks or sandboxed environments block the CDN Playwright
downloads from. Try again on a normal home/office network connection.

**Worker starts but jobs stay "pending" forever**
Check the worker's terminal for errors — most likely Redis isn't reachable,
or the queue name doesn't match between API and worker config.
