# devops-beginner-multi-tier

A minimal, production-shaped three-tier application you can run on your laptop with Docker Compose and deploy to a real Kubernetes cluster (K3s) through a fully automated GitLab CI/CD pipeline — with every decision explained so you understand it, not just copy it.

---

## Table of Contents

- [What you will learn](#what-you-will-learn)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick start — Docker Compose](#quick-start--docker-compose)
- [GitLab CE setup](#gitlab-ce-setup)
- [CI/CD pipeline](#cicd-pipeline)
- [K3s deployment](#k3s-deployment)
- [Environment variables](#environment-variables)
- [Port map](#port-map)
- [Why these choices](#why-these-choices)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## What you will learn

| Topic | Where it shows up |
|---|---|
| Three-tier application design | `frontend/` `backend/` `db/` separation |
| Docker & Docker Compose | `docker-compose.yml`, per-service Dockerfiles |
| Self-hosted GitLab CE | `docker-compose.yml` gitlab + gitlab-runner services |
| CI/CD pipeline (build → push → deploy) | `.gitlab-ci.yml` |
| Kubernetes manifests | `k8s/` folder |
| External database pattern | `k8s/external-db-service.yaml` |
| Secret management | GitLab CI variables + K8s Secret |
| Immutable image tags | `$CI_COMMIT_SHORT_SHA` instead of `:latest` |

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │              Developer laptop            │
                        │                                          │
                        │   VS Code ──► git push ──► GitHub        │
                        └──────────────────┬──────────────────────┘
                                           │ webhook / push
                                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          Linux VM  (172.16.10.214)                   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │                    Docker Compose stack                      │     │
│  │                                                              │     │
│  │  ┌──────────┐  public_net   ┌─────────────────┐             │     │
│  │  │ frontend │◄──:8181───────│   Host browser  │             │     │
│  │  │  Nginx   │               └─────────────────┘             │     │
│  │  └────┬─────┘                                               │     │
│  │       │ app_net (internal)                                   │     │
│  │  ┌────▼──────────┐                                          │     │
│  │  │ backend-service│                                          │     │
│  │  │  Flask API     │                                          │     │
│  │  └────┬───────────┘                                          │     │
│  │       │                                                      │     │
│  │  ┌────▼───┐  :5433 (host)                                   │     │
│  │  │   db   │◄────────────────── K3s external-db endpoint     │     │
│  │  │Postgres│                                                  │     │
│  │  └────────┘                                                  │     │
│  │                                                              │     │
│  │  ┌──────────┐  gitlab_net   ┌────────────────┐              │     │
│  │  │  GitLab  │◄──────────────│ gitlab-runner  │              │     │
│  │  │  CE      │  :8929        └────────────────┘              │     │
│  │  │ Registry │  :5051                                         │     │
│  │  └──────────┘                                               │     │
│  └─────────────────────────────────────────────────────────────┘     │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │                     K3s cluster                              │     │
│  │  namespace: three-tier                                       │     │
│  │                                                              │     │
│  │  ┌─────────────┐     ┌──────────────┐     ┌─────────────┐  │     │
│  │  │  frontend   │────►│   backend    │────►│ external-db │  │     │
│  │  │ Deployment  │     │  Deployment  │     │   Service   │  │     │
│  │  │  (Nginx)    │     │  (Flask)     │     │ + Endpoints │  │     │
│  │  └─────────────┘     └──────────────┘     └──────┬──────┘  │     │
│  │         ▲                                         │         │     │
│  │    Traefik Ingress                         :5433 on host    │     │
│  └─────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
```

### CI/CD flow

```
git push gitlab main
        │
        ▼
┌───────────────┐     ┌───────────────┐     ┌─────────────────────────┐
│  build stage  │────►│  push stage   │────►│      deploy stage       │
│               │     │               │     │                         │
│ docker build  │     │ docker login  │     │ kubectl apply manifests  │
│ frontend      │     │ docker push   │     │ kubectl set image        │
│ backend       │     │ frontend:SHA  │     │ kubectl rollout status   │
│               │     │ backend:SHA   │     │                         │
│ saves .tar    │     │               │     │ injects DB_PASSWORD      │
│ artifacts     │     │ to GitLab     │     │ injects VM IP            │
└───────────────┘     │ registry      │     └─────────────────────────┘
                      │ :5051         │
                      └───────────────┘
```

---

## Project structure

```
devops-beginner-multi-tier/
│
├── frontend/                        # Tier 1 — Presentation
│   ├── index.html                   # Single-page UI (Load Users, Add User)
│   ├── nginx.conf                   # Reverse proxy /api/ → backend-service
│   ├── Dockerfile                   # FROM nginx:alpine
│   └── .dockerignore
│
├── backend/                         # Tier 2 — Logic
│   ├── app.py                       # Flask: GET /api/users, POST /api/users, GET /api/health
│   ├── requirements.txt             # flask, gunicorn, psycopg2-binary
│   ├── Dockerfile                   # FROM python:3.12-slim, runs gunicorn
│   └── .dockerignore
│
├── db/                              # Tier 3 — Data
│   ├── init.sql                     # CREATE TABLE users; INSERT seed row (Alice)
│   └── Dockerfile                   # FROM postgres:16-alpine
│
├── k8s/                             # Kubernetes manifests (K3s)
│   ├── namespace.yaml               # namespace: three-tier
│   ├── backend-secret.yaml          # Secret: DB_PASSWORD (injected by pipeline)
│   ├── external-db-service.yaml     # Service + Endpoints → host:5433 (Postgres)
│   ├── backend.yaml                 # Deployment + Service for Flask API
│   ├── frontend.yaml                # Deployment + Service for Nginx
│   └── ingress.yaml                 # Traefik Ingress → frontend Service
│
├── .gitlab-ci.yml                   # Pipeline: build → push → deploy
├── docker-compose.yml               # Local stack: frontend + backend + db + gitlab + runner
├── register-runner.sh               # One-time GitLab Runner registration helper
├── .env.example                     # Copy to .env — all tuneable values live here
├── .gitignore                       # Excludes .env, *.tar, __pycache__
├── Makefile                         # Convenience targets: up, down, logs, clean
├── LICENSE
└── README.md
```

---

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| Docker | 24 | Build and run containers |
| Docker Compose | v2 (plugin) | Local multi-service stack |
| Git | any | Version control |
| K3s | v1.31+ | Lightweight Kubernetes (Linux VM only) |
| kubectl | matching K3s | Apply manifests, check rollouts |

No Helm, no cloud account, no paid tooling required.

---

## Quick start — Docker Compose

```bash
# 1. Clone
git clone https://github.com/<your-org>/devops-beginner-multi-tier.git
cd devops-beginner-multi-tier

# 2. Configure
cp .env.example .env
# Edit .env — set GITLAB_HOST to your VM's IP if running GitLab

# 3. Start
docker compose up --build

# 4. Open in browser
#    http://localhost:8181
#    Click "Load Users" → Alice appears from the database
#    Click "Add Sample User" → new row inserted, click Load again to confirm

# 5. Health check
curl http://localhost:8181/api/health
```

Scale the backend to two replicas (Docker Compose load-balances by service name):

```bash
docker compose up --build --scale backend-service=2
```

---

## GitLab CE setup

GitLab CE and its runner are included in `docker-compose.yml` — no separate install needed.

```bash
docker compose up -d gitlab gitlab-runner
# First boot takes ~3 minutes. Watch progress:
docker compose logs -f gitlab | grep "gitlab Reconfigured"
```

Then open `http://<your-vm-ip>:8929` and sign in as `root` / `Password1234!`.

Register the runner (one time only):

```bash
chmod +x register-runner.sh
GITLAB_HOST=<your-vm-ip> ./register-runner.sh
```

Set these CI/CD variables in **GitLab → Project → Settings → CI/CD → Variables**:

| Variable | Type | Value |
|---|---|---|
| `GITLAB_HOST` | Variable | your VM IP, e.g. `172.16.10.214` |
| `GITLAB_REGISTRY_PORT` | Variable | `5051` |
| `DB_PASSWORD` | Variable (Masked) | value from your `.env` |
| `KUBECONFIG` | File | contents of `/etc/rancher/k3s/k3s.yaml` (replace `127.0.0.1` with VM IP) |
| `KUBE_CONTEXT` | Variable | `default` |

---

## CI/CD pipeline

Every `git push` to `main` triggers `.gitlab-ci.yml`:

```
build ──► push ──► deploy
```

| Stage | Image | What it does |
|---|---|---|
| build | `docker:26` | `docker build` for frontend and backend; saves `.tar` artifacts |
| push | `docker:26` | Loads tarballs, pushes `image:$CI_COMMIT_SHORT_SHA` to GitLab registry |
| deploy | `alpine/k8s:1.31.2` | `kubectl apply` all manifests; `kubectl set image` to roll out new SHA |

The deploy stage substitutes two placeholders at runtime:
- `REPLACE_AT_DEPLOY_TIME` in `backend-secret.yaml` → `$DB_PASSWORD`
- `<your-vm-ip>` in `external-db-service.yaml` → `$GITLAB_HOST`

This keeps real credentials and IPs out of the repository.

---

## K3s deployment

### Install K3s

```bash
curl -sfL https://get.k3s.io | sh -
# Verify
sudo kubectl get nodes
```

### Configure the registry (insecure, self-hosted)

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "<your-vm-ip>:5051":
    endpoint:
      - "http://<your-vm-ip>:5051"
auths:
  "<your-vm-ip>:5051":
    username: root
    password: "<your-gitlab-root-password>"
EOF
sudo systemctl restart k3s
```

### Apply manifests manually (first time)

```bash
sed 's/<your-vm-ip>/172.16.10.214/' k8s/external-db-service.yaml | sudo kubectl apply -f -
sudo kubectl apply -f k8s/namespace.yaml
sudo kubectl apply -f k8s/backend-secret.yaml   # pipeline handles this on every push
sudo kubectl apply -f k8s/backend.yaml
sudo kubectl apply -f k8s/frontend.yaml
sudo kubectl apply -f k8s/ingress.yaml
sudo kubectl -n three-tier get pods -w
```

After the first manual apply, every subsequent deployment is handled by the pipeline.

---

## Environment variables

All values are set in `.env` (copy from `.env.example`). Never commit `.env`.

| Variable | Default | Description |
|---|---|---|
| `LB_PORT` | `8181` | Host port for the frontend |
| `DB_PORT` | `5433` | Host port for Postgres (avoids collision with system Postgres on 5432) |
| `DB_NAME` | `appdb` | Postgres database name |
| `DB_USER` | `appuser` | Postgres user |
| `DB_PASSWORD` | `secretpassword` | Postgres password — also set as a masked GitLab CI variable |
| `GITLAB_HOST` | _(required)_ | VM IP address — used in GitLab external URL and registry URL |
| `GITLAB_PORT` | `8929` | GitLab web UI port |
| `GITLAB_SSH_PORT` | `2224` | GitLab SSH port (2222 is often taken) |
| `GITLAB_REGISTRY_PORT` | `5051` | GitLab container registry port (5050 is often taken) |
| `GITLAB_ROOT_PASSWORD` | `Password1234!` | GitLab initial root password |

---

## Port map

| Port | Service | Reachable from |
|---|---|---|
| `8181` | Frontend (Nginx) | Host browser |
| `5433` | Postgres (Docker Compose db) | Host + K3s pods via external-db Service |
| `8929` | GitLab CE web UI | Host browser |
| `2224` | GitLab SSH | Git clients |
| `5051` | GitLab Container Registry | Docker daemon, K3s containerd |
| `6443` | K3s API server | kubectl, GitLab CI pipeline |

---

## Why these choices

**Docker Compose for local dev, K3s for deployment** — Compose is the fastest way to verify the three tiers talk to each other. K3s gives you real Kubernetes semantics (Deployments, Services, Ingress, Secrets) in a single binary. Same mental model, right-sized tool for each environment.

**Self-hosted GitLab instead of GitHub Actions** — the pipeline, the registry, and the runner all live on the same VM. Nothing leaves your network. You can inspect every layer.

**External database, not a DB pod** — a database pod that dies takes its data with it unless PersistentVolumes are configured correctly. Running Postgres outside the cluster means a bad deployment can never corrupt the data tier. The `Service + Endpoints` pattern in `k8s/external-db-service.yaml` gives it a stable DNS name inside the cluster: `external-db.three-tier.svc.cluster.local`.

**Commit SHA image tags** — `:latest` is mutable. `kubectl rollout undo` needs a previous, distinct, immutable tag to roll back to. `$CI_COMMIT_SHORT_SHA` provides that automatically.

**No hardcoded IPs in committed files** — `<your-vm-ip>` placeholders are substituted at deploy time by the pipeline using `sed`. The repository stays portable.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ImagePullBackOff` | Registry credentials missing in K3s | Check `/etc/rancher/k3s/registries.yaml`, restart k3s |
| `CrashLoopBackOff` on backend | DB unreachable or wrong password | `kubectl logs -n three-tier deployment/backend` |
| `CrashLoopBackOff` on frontend | nginx can't resolve `backend-service` | Check `resolver` directive in `frontend/nginx.conf` |
| Backend `/api/health` returns 500 | Secret has empty `DB_PASSWORD` | Re-apply secret: `kubectl create secret generic backend-db-secret --from-literal=DB_PASSWORD=<value> --dry-run=client -o yaml \| kubectl apply -f -` |
| Pipeline deploy times out | Pods not becoming Ready | `kubectl -n three-tier describe pod -l app=backend` → check Events |
| CoreDNS `CrashLoopBackOff` | rp_filter blocking pod egress | `sudo sysctl -w net.ipv4.conf.all.rp_filter=0` |
| `git push gitlab` says "Everything up-to-date" | Local branch already matches GitLab | `git commit --allow-empty -m "ci: retrigger"` then push |
| Port 5432 already in use | Host has its own Postgres | Use `DB_PORT=5433` in `.env` (already the default) |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-topic`
3. Commit with a clear message: `git commit -m "feat: describe what and why"`
4. Push and open a Merge Request against `main`
5. The pipeline must pass before merge

Please keep each change focused — one concern per MR.

---

## License

[MIT](LICENSE)
