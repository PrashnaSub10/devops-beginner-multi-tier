# DevOps Beginner Multi-Tier Demo

A minimal, production-shaped three-tier application you can run locally with Docker Compose **and** deploy to a K3s cluster via GitLab CI/CD — with every decision explained so you can defend it, not just copy it.

---

## What "three-tier" actually means

| Tier | Folder | Job | Why separate? |
|---|---|---|---|
| Presentation | `frontend/` | Nginx serves static HTML; proxies `/api/` to the backend | Swap the UI without touching business logic or data |
| Logic | `backend/` | Flask REST API reads/writes the database | Scale independently; database engine is invisible to the frontend |
| Data | `db/` (local) or external Postgres (K3s) | Postgres stores state | Lives on its own failure domain — a crashed app pod never corrupts the database |

The key insight: **a change in one tier should not require a change in another.** This project is structured to make that concrete.

---

## Architecture

```
Host browser
    │  :8080
    ▼
┌─────────────┐   public_net (10.10.0.0/24)
│  frontend   │   Nginx — only service reachable from outside
└──────┬──────┘
       │  app_net (10.20.0.0/24, internal — no host route)
       ▼
┌─────────────────┐
│ backend-service │   Flask API  (scale with --scale backend=2)
└────────┬────────┘
         │
         ▼
┌────────────┐
│     db     │   Postgres — no host port, unreachable from outside app_net
└────────────┘
```

In K3s the same shape is preserved: `frontend` and `backend` run as Deployments inside the cluster; Postgres runs on an external host and is reached via a `Service + Endpoints` object (see `k8s/external-db-service.yaml`).

---

## Project structure

```
devops_beginner_multi_tier/
├── frontend/           Tier 1 — Nginx + static HTML
│   ├── index.html
│   ├── nginx.conf
│   ├── Dockerfile
│   └── .dockerignore
├── backend/            Tier 2 — Flask REST API
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
├── db/                 Tier 3 — Postgres schema
│   ├── Dockerfile
│   └── init.sql
├── k8s/                K3s manifests (one file per concern)
│   ├── namespace.yaml
│   ├── backend-secret.yaml
│   ├── external-db-service.yaml
│   ├── backend.yaml
│   ├── frontend.yaml
│   └── ingress.yaml
├── .gitlab-ci.yml      CI/CD pipeline (build → push → deploy)
├── .gitignore
├── .env.example
└── docker-compose.yml
```

The old `app/` and `app2/` folders were identical code in two directories. That is not how you scale — you run one image with `--scale`. Duplicate folders were removed.

---

## Quick start (Docker Compose)

```bash
cp .env.example .env
docker compose up --build
```

Open http://localhost:8080 — click "Load Users" to verify the full three-tier path works.

Run two backend replicas (Docker Compose load-balances automatically by service name):

```bash
docker compose up --build --scale backend-service=2
```

Verify health:

```bash
curl http://localhost:8080/api/health
curl http://localhost:8080/api/users
```

---

## K3s deployment

### 1. Install K3s (on your Linux VM)

```bash
curl -sfL https://get.k3s.io | sh -
sudo cat /etc/rancher/k3s/k3s.yaml   # copy to ~/.kube/config on your laptop
# Replace "127.0.0.1" with the VM's real IP — the most common first-time mistake.
```

K3s ships Traefik (ingress), local-path-provisioner (storage), and containerd — nothing else to install.

### 2. Start external Postgres (on a separate host or VM)

```bash
# Any Postgres 16 instance works. Simplest option:
docker run -d --name pg \
  -e POSTGRES_DB=appdb -e POSTGRES_USER=appuser -e POSTGRES_PASSWORD=secretpassword \
  -p 5432:5432 postgres:16-alpine
```

Update `k8s/external-db-service.yaml` with that host's IP.

### 3. Apply manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-secret.yaml      # edit DB_PASSWORD first
kubectl apply -f k8s/external-db-service.yaml # edit IP first
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml
kubectl apply -f k8s/ingress.yaml
kubectl get pods -n three-tier -w
```

### 4. Test from inside the cluster

```bash
# Verify the external-db Service resolves and the backend can reach it:
kubectl run curl-test --rm -it --image=curlimages/curl --restart=Never -n three-tier -- \
  curl http://backend-service.three-tier.svc.cluster.local:8080/api/health
```

---

## GitLab CI/CD

Every `git push` to `main` triggers `.gitlab-ci.yml`:

1. **build** — `docker build` for frontend and backend, saves tarballs as artifacts
2. **push** — loads tarballs, logs in to GitLab Container Registry, pushes images tagged with the commit SHA (never `:latest`)
3. **deploy** — `kubectl apply` all manifests, then `kubectl set image` to roll out the new SHA tag

Required GitLab CI/CD Variables (Settings → CI/CD → Variables):

| Variable | Type | Notes |
|---|---|---|
| `KUBECONFIG` | File | Content of `~/.kube/config` for the K3s cluster |
| `KUBE_CONTEXT` | Variable | Context name inside that kubeconfig |
| `DB_PASSWORD` | Variable (Masked) | Injected into the K8s Secret at deploy time |

GitLab's built-in `$CI_REGISTRY_USER` / `$CI_REGISTRY_PASSWORD` / `$CI_REGISTRY` handle container registry auth automatically — no extra variables needed for that.

---

## Why these choices (the short version)

**Docker Compose for local dev, K3s for "production-shaped" deployment** — Compose is the fastest way to verify the three tiers talk to each other. K3s is a single binary that gives you real Kubernetes semantics (Deployments, Services, Ingress, Secrets) without the overhead of a full cluster. Same concepts, right-sized tool.

**GitLab CI/CD instead of Jenkins** — the pipeline lives in `.gitlab-ci.yml` next to the code it builds. A `git blame` tells you when deployment logic changed. No separate server to install or patch.

**External database, not a pod** — a database pod that dies takes its data with it unless you've wired up PersistentVolumes correctly. Running Postgres outside the cluster means a bad deployment can never corrupt or lose the data tier. The `Service + Endpoints` pattern in `k8s/external-db-service.yaml` is how Kubernetes reaches it with a stable DNS name.

**Commit SHA image tags** — `:latest` is mutable. If a rollout goes wrong, `kubectl rollout undo` needs a previous, distinct, immutable tag to roll back to. `$CI_COMMIT_SHORT_SHA` gives you that for free.

**Resource requests and limits on every Deployment** — on a small K3s node, one runaway pod can starve the others. Limits contain the blast radius.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ImagePullBackOff` | Wrong registry path or missing pull secret | `kubectl describe pod <pod> -n three-tier` → read Events |
| `CrashLoopBackOff` | DB unreachable or wrong password | `kubectl logs deployment/backend -n three-tier` |
| Ingress 404 | `ingressClassName: nginx` instead of `traefik` | `kubectl get ingressclass` — K3s uses `traefik` |
| `Secret not found` | Applied `backend.yaml` before `backend-secret.yaml` | `kubectl apply -f k8s/backend-secret.yaml` first |
| `kubectl` can't connect | Kubeconfig still has `127.0.0.1` | Replace with the K3s node's real IP |
