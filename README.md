# URL-to-PDF Service

A small service that takes a URL, renders it to a PDF using a headless browser,
and lets you download the result. Built as infrastructure-learning scaffolding
(EKS, Helm, GitOps, KEDA, CronJobs, observability) — the app itself is
deliberately simple so the _infrastructure_ is where the learning happens.

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

| Variable            | Default            | Used by                                               |
| ------------------- | ------------------ | ----------------------------------------------------- |
| `POSTGRES_HOST`     | `localhost`        | API, worker                                           |
| `POSTGRES_PORT`     | `5432`             | API, worker                                           |
| `POSTGRES_DB`       | `pdfservice`       | API, worker                                           |
| `POSTGRES_USER`     | `pdfapp`           | API, worker                                           |
| `POSTGRES_PASSWORD` | `pdfapp_dev_pw`    | API, worker                                           |
| `REDIS_HOST`        | `localhost`        | API, worker                                           |
| `REDIS_PORT`        | `6379`             | API, worker                                           |
| `REDIS_QUEUE_NAME`  | `pdf_jobs`         | API, worker                                           |
| `RESULTS_DIR`       | `./results` (path) | API, worker — must be the _same_ path/volume for both |
| `RENDER_TIMEOUT_MS` | `30000`            | worker                                                |

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
_browser_ (not a container) is what calls the API, and port 8000 is
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

## Phase 5: AWS Foundation (Terraform: VPC + EKS)

This is where real AWS costs begin. Read the cost section below before
running anything.

### Cost estimate

| Resource                         | Cost while running   |
| -------------------------------- | -------------------- |
| EKS control plane                | ~$0.10/hr flat       |
| 2x t3.small spot nodes           | ~$0.01-0.02/hr total |
| NAT Gateway (single, not per-AZ) | ~$0.045/hr + data    |
| **Total while running**          | **~$0.15-0.20/hr**   |

If you `terraform destroy` at the end of every session and only run this a
few hours a week, expect **$5-15/month**. Left running 24/7, expect
**~$110-150/month** — mainly the EKS control plane's flat fee and the NAT
Gateway, both billed whether you're using them or not.

**The rule from here on: `terraform destroy` when you're done for the
session.** This isn't optional — treat it the same as closing your laptop.

### 1. Create the state backend (one-time)

```bash
cd infra/bootstrap
terraform init
terraform apply -var="state_bucket_name=pdf-service-tfstate-YOUR_INITIALS_OR_RANDOM"
```

Pick a genuinely unique bucket name — S3 bucket names are global across
_all_ AWS accounts, not just yours. Write down the exact name it accepts.

This creates the S3 bucket + DynamoDB table and stores **its own** state
locally (`infra/bootstrap/terraform.tfstate`) — don't delete that file, and
don't run `terraform destroy` here later unless you want to tear down your
entire state backend along with everything it's tracking.

### 2. Point envs/dev at that backend

Edit `infra/envs/dev/backend.tf` and replace both
`REPLACE_WITH_YOUR_STATE_BUCKET_NAME` occurrences with the exact bucket
name from step 1.

### 3. Apply the VPC + EKS

```bash
cd ../envs/dev
terraform init
terraform plan    # review what it's about to create before applying
terraform apply
```

This takes **10-15 minutes** — EKS cluster creation is slow, that's normal,
not a hang.

### 4. Connect kubectl to the new cluster

```bash
terraform output configure_kubectl
```

Copy and run the command it prints (something like
`aws eks update-kubeconfig --region eu-central-1 --name pdf-service-dev`),
then confirm:

```bash
kubectl get nodes
```

Should show 2 nodes, `Ready`, after a minute or two.

### What's deliberately NOT here yet (later phases)

- ECR repositories (Phase 6)
- Anything deploying your actual app to this cluster (Phase 6)
- IRSA/OIDC provider resource (Phase 8 — the module already outputs the
  OIDC issuer URL you'll need, but doesn't create the IAM role yet)
- RDS (Phase 7)

### Tear down (do this every session)

**First, always clean up any Ingress resources** — once Phase 6 is set up,
the AWS Load Balancer Controller creates real ALBs, target groups, and
security groups directly in AWS, completely outside Terraform's state. If
you skip this step, `terraform destroy` can get stuck for 15+ minutes (or
fail outright) trying to delete subnets/the VPC while orphaned security
groups or network interfaces from those leftover ALBs are still attached.

```bash
kubectl delete ingress --all
```

Wait ~30-60 seconds for the controller to actually tear down the ALB and
its security groups in AWS before proceeding.

```bash
cd infra/envs/dev
terraform destroy -var="github_repo=YOUR_GITHUB_USERNAME/pdf-service"
```

Confirm with `yes` when prompted. This removes the EKS cluster, node
group, NAT Gateway, VPC, ECR repos, and IAM/OIDC resources — the expensive
stuff. It does **not** touch the S3 state bucket/DynamoDB table from step
1 (that's a separate Terraform config, untouched by this destroy).

**If destroy still gets stuck** (forgot the `kubectl delete ingress` step,
or a security group didn't finish cleaning up in time), find and remove
the leftovers manually in a second terminal while destroy is still running
— it'll pick back up once they're gone:

```bash
aws ec2 describe-security-groups --region eu-central-1 \
  --filters "Name=vpc-id,Values=<your-vpc-id-from-terraform-output>" \
  --query "SecurityGroups[].{ID:GroupId,Name:GroupName}" --output table
```

Delete anything that isn't named `default` (typically named like
`k8s-default-<service>-...` or `k8s-traffic-<cluster>-...`):

```bash
aws ec2 delete-security-group --group-id sg-XXXXXXXX --region eu-central-1
```

Also worth checking for orphaned EBS volumes (from Postgres/Redis's PVCs —
these don't block the VPC destroy, but they're real cost sitting there
unnecessarily if left behind):

```bash
aws ec2 describe-volumes --region eu-central-1 \
  --filters "Name=tag:kubernetes.io/cluster/pdf-service-dev,Values=owned" \
  --query "Volumes[].{ID:VolumeId,State:State}" --output table
```

Delete any showing `available` (meaning detached, not in use):

```bash
aws ec2 delete-volume --volume-id vol-XXXXXXXX --region eu-central-1
```

**After any destroy, confirm AWS is genuinely clean:**

```bash
aws eks list-clusters --region eu-central-1
aws ec2 describe-vpcs --region eu-central-1 --filters "Name=tag:Name,Values=pdf-service-dev-vpc"
```

Both should return empty.

Next session, `terraform apply` again from `envs/dev` — same config, same
state backend, cluster comes back identical.

---

## Phase 6: Real workloads on EKS (ECR, ALB, Flux against the real cluster)

This deploys the app for real: ECR for images, a real AWS Application Load
Balancer for traffic, and Flux managing this cluster the same way it
managed minikube — just pointed at `clusters/eks-dev/` instead of
`clusters/minikube/`.

### What's new here that minikube didn't need

- **ECR repositories** for api/worker/frontend images
- **EBS CSI driver + a `gp3` StorageClass** — EKS has no default storage
  provisioner; every PVC would stay `Pending` forever without this
- **AWS Load Balancer Controller** — watches Ingress resources and
  provisions real ALBs
- **GitHub Actions → AWS via OIDC** — no static AWS keys stored in GitHub
- Both **api** and **frontend** now get their own Ingress/ALB (frontend's
  JS can't call `localhost:8000` anymore once this isn't your laptop)

### 1. Re-apply Terraform with the new resources

The `iam_policy.json` for the Load Balancer Controller is already included
(fetched from AWS's official source). You do need to provide your GitHub
repo:

```bash
cd infra/envs/dev
terraform apply -var="github_repo=YOUR_GITHUB_USERNAME/pdf-service"
```

This adds: 3 ECR repos, the cluster's OIDC provider, the EBS CSI driver
addon + its IAM role, the Load Balancer Controller's IAM role, and the
GitHub Actions OIDC provider + IAM role. Review the plan before confirming
— it should be entirely new additions, nothing destructive to what Phase 5
already created.

### 2. Capture the outputs you'll need

```bash
terraform output ecr_repository_urls
terraform output lb_controller_role_arn
terraform output github_actions_role_arn
terraform output vpc_id
```

Keep these visible — you'll paste them into two places in the next steps.

### 3. Configure GitHub Actions with the role ARN

GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
**Variables** tab → **New repository variable**:

- Name: `AWS_GITHUB_ACTIONS_ROLE_ARN`
- Value: the `github_actions_role_arn` output from step 2

(This is a repo **variable**, not a secret — an IAM role ARN isn't
sensitive by itself; what matters is that only your repo's `main` branch
can assume it, which the Terraform trust policy already restricts.)

### 4. Fill in the two placeholders in the Load Balancer Controller manifest

Edit `clusters/eks-dev/apps/aws-lb-controller-release.yaml`:

- `vpcId`: replace with the `vpc_id` output
- `eks.amazonaws.com/role-arn`: replace with the `lb_controller_role_arn` output

### 5. Update the GitHub repo URL for this cluster's Flux config

Edit `clusters/eks-dev/flux-system-config.yaml`, replace
`YOUR_GITHUB_USERNAME` with your actual username (same as the minikube one
was).

### 6. Commit and push everything

```bash
git add .
git commit -m "Phase 6: EKS workloads, ECR, ALB, GitOps for eks-dev"
git push
```

This push will trigger the GitHub Actions workflow — watch the **Actions**
tab. It should build all 3 images, push to ECR (via OIDC, no stored keys),
and commit updated `values.yaml` files back to `main`.

### 7. Confirm kubectl is pointed at the EKS cluster (not minikube)

```bash
kubectl config current-context
```

Should show something with `pdf-service-dev` in it. If it shows minikube,
switch:

```bash
kubectl config use-context $(kubectl config get-contexts -o name | grep pdf-service-dev)
```

### 8. Install Flux on this cluster and point it at the repo

```bash
flux install
kubectl apply -f clusters/eks-dev/flux-system-config.yaml
```

### 9. Watch everything reconcile

```bash
flux get helmreleases -A
kubectl get pods -w
```

Expect this to take longer than minikube did — Postgres/Redis need EBS
volumes provisioned (not instant like minikube's hostPath), and the Load
Balancer Controller needs to actually create ALBs in AWS (takes a couple
minutes each). If `api` or `frontend` HelmReleases sit waiting, check
`dependsOn` — both wait for `aws-load-balancer-controller` to be ready
first.

### 10. Get your ALB URLs

```bash
kubectl get ingress
```

This shows the `ADDRESS` column with each ALB's public DNS name (something
like `k8s-default-api-xxxx.eu-central-1.elb.amazonaws.com`). Give AWS a
few minutes after the Ingress is created for DNS to actually resolve.

### 11. Point the frontend at the real API URL

The frontend's `frontend/index.html` still has `API_BASE` hardcoded to
`http://localhost:8000` — that was fine for local dev and port-forwarding,
but the frontend now runs somewhere that isn't your laptop. Update it:

```js
const API_BASE = "http://YOUR_API_ALB_DNS_NAME_FROM_STEP_10";
```

Commit and push this change — it'll flow through the same CI → GitOps loop
from Phase 4, rebuilding and redeploying the frontend automatically.

### 12. Verify end to end

Visit the frontend's ALB URL in your browser, submit a job, confirm it
completes and the PDF downloads — the full pipeline, for real, on AWS.

### Debugging

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
kubectl describe ingress api-api
kubectl get pvc                    # confirm Bound, not Pending
kubectl describe pvc <name>        # if Pending, this shows why
```

A PVC stuck `Pending` almost always means the EBS CSI addon isn't healthy
yet — check `kubectl get pods -n kube-system | grep ebs`.

### Cost note

ALBs cost ~$0.0225/hr + a small per-LCU charge each, and you now have two
(api + frontend) instead of zero. Factor this into your `terraform destroy`
discipline — this phase raises the hourly cost a bit further.

---

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

## Phase 7: Migrate to RDS

Moves Postgres out of the cluster entirely, onto AWS's managed database
service. This also happens to remove one whole class of problem you hit in
Phase 6 — RDS isn't a Pod, so it can never collide with EBS Multi-Attach or
node-affinity scheduling the way the in-cluster Postgres StatefulSet did.

### 1. Add the RDS resources and apply

Copy `rds.tf` into `infra/envs/dev/`, merge the `vpc_cidr` output into
`infra/modules/vpc/outputs.tf`, and merge the `rds_endpoint` output into
`infra/envs/dev/outputs.tf`.

```bash
cd infra/envs/dev
terraform apply -var="github_repo=YOUR_GITHUB_USERNAME/pdf-service"
```

This provisions a `db.t4g.micro` Postgres instance — review the plan
before confirming, same habit as always.

### 2. Get the endpoint

```bash
terraform output rds_endpoint
```

### 3. Apply the schema to RDS (one-time, manual)

RDS doesn't have Bitnami's automatic `initdb.scripts` convenience, and it's
not publicly reachable (deliberately — `publicly_accessible = false`), so
this has to run from _inside_ the VPC. Easiest way: a short-lived pod using
the official Postgres image, piping `schema.sql` in over stdin:

```bash
cat db/schema.sql | kubectl run psql-client --rm -i --tty=false \
  --image=postgres:16 --restart=Never \
  --env="PGPASSWORD=pdfapp_dev_pw" -- \
  psql -h $(terraform output -raw rds_endpoint) -U pdfapp -d pdfservice
```

Confirm it worked:

```bash
kubectl run psql-client --rm -it --image=postgres:16 --restart=Never \
  --env="PGPASSWORD=pdfapp_dev_pw" -- \
  psql -h $(terraform output -raw rds_endpoint) -U pdfapp -d pdfservice -c "\dt"
```

Should show the `jobs` table.

### 4. Point api/worker at RDS instead of the in-cluster Postgres

Replace `clusters/eks-dev/apps/api-release.yaml` and
`clusters/eks-dev/apps/worker-release.yaml` with the updated versions —
each now has an `env.postgresHost` override and no longer lists `postgres`
under `dependsOn`. Fill in the real endpoint from step 2 in both files.

### 5. Remove the in-cluster Postgres

Delete `clusters/eks-dev/apps/postgres-release.yaml` entirely. Since
`prune: true` is set on the Kustomization, Flux will uninstall the
in-cluster Postgres release automatically once this file is gone from Git.

**Note on your existing job history:** any jobs recorded in the old
in-cluster Postgres are on a different database now — this migration
starts fresh, it doesn't copy old data over. For a learning project that's
fine; if you cared about the old rows, you'd `pg_exec` a `pg_dump` from
the old pod before deleting its release, then `pg_restore` into RDS. Not
needed here.

### 6. Push and reconcile

```bash
git add infra/ clusters/eks-dev/apps/
git commit -m "Phase 7: migrate to RDS"
git push

flux reconcile source git pdf-service
flux reconcile helmrelease api -n flux-system
flux reconcile helmrelease worker -n flux-system
flux get helmreleases -A
kubectl get pods
```

You should see the `postgres-postgresql-0` pod disappear entirely, and
`api-api`/`worker-worker` come up pointed at RDS.

### 7. Verify end to end

```bash
kubectl port-forward svc/api-api 8000:8000
```

```bash
curl -X POST http://localhost:8000/jobs \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
curl http://localhost:8000/jobs
```

Confirm a job actually completes. Then also test via the real ALB URL in
your browser, same as Phase 6.

### 8. Clean up the orphaned EBS volume

The old in-cluster Postgres's PVC is **not** automatically deleted when
its HelmRelease is removed (same "protect stateful data" default you saw
in Phase 6's teardown) — it'll sit there as orphaned, billable storage
unless removed manually:

```bash
kubectl get pvc
```

If `data-postgres-postgresql-0` still shows up, delete it:

```bash
kubectl delete pvc data-postgres-postgresql-0
```

### Cost note

`db.t4g.micro` runs roughly $0.016/hr (~$12/month if left running
constantly) — on top of everything else, this is one more thing
`terraform destroy` needs to tear down between sessions. It's included in
the same `envs/dev` destroy/apply cycle, nothing extra to remember.

---
