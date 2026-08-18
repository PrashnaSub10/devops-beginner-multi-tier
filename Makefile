# Local CI/CD mock — mirrors the three stages in .gitlab-ci.yml
# so beginners can simulate "git push triggers pipeline" without needing GitLab.
#
# Usage:
#   make          → full pipeline (build → push → deploy)
#   make build    → build images only
#   make deploy   → (re)start containers with latest images
#   make scale    → run 2 backend replicas
#   make test     → smoke-test all 3 tiers
#   make logs     → tail all container logs
#   make down     → stop and remove containers
#   make clean    → stop, remove containers + volumes (wipes db data)

PORT ?= 8181
COMPOSE = docker compose

# ── Stage 1: build ────────────────────────────────────────────────────────────
.PHONY: build
build:
	@echo "==> [build] building images..."
	$(COMPOSE) build

# ── Stage 2: push (local mock — just tags with a fake SHA) ────────────────────
.PHONY: push
push: build
	@echo "==> [push] tagging images with mock SHA: $(shell git rev-parse --short HEAD 2>/dev/null || echo local)"
	$(eval SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo local))
	docker tag devops-beginner-multi-tier-frontend:latest devops-beginner-multi-tier-frontend:$(SHA)
	docker tag devops-beginner-multi-tier-backend-service:latest devops-beginner-multi-tier-backend-service:$(SHA)
	@echo "==> images tagged :$(SHA) (in a real pipeline these would be pushed to the registry)"

# ── Stage 3: deploy ───────────────────────────────────────────────────────────
.PHONY: deploy
deploy:
	@echo "==> [deploy] starting stack on port $(PORT)..."
	$(COMPOSE) up -d
	@echo "==> waiting for backend to be ready..."
	@for i in $$(seq 1 20); do \
		curl -sf http://localhost:$(PORT)/api/health > /dev/null 2>&1 && echo "==> backend ready" && break; \
		echo "  waiting... ($$i/20)"; sleep 2; \
	done
	$(COMPOSE) ps

# ── Full pipeline ─────────────────────────────────────────────────────────────
.PHONY: all
all: push deploy test
	@echo "==> pipeline complete — app at http://localhost:$(PORT)"

# ── Scale ─────────────────────────────────────────────────────────────────────
.PHONY: scale
scale:
	@echo "==> scaling backend to 2 replicas..."
	$(COMPOSE) up -d --scale backend-service=2
	$(COMPOSE) ps

# ── Smoke tests ───────────────────────────────────────────────────────────────
.PHONY: test
test:
	@echo "==> [test] health check..."
	@curl -sf http://localhost:$(PORT)/api/health | python3 -m json.tool
	@echo "==> [test] read users..."
	@curl -sf http://localhost:$(PORT)/api/users | python3 -m json.tool
	@echo "==> [test] write user..."
	@curl -sf -X POST http://localhost:$(PORT)/api/users \
		-H "Content-Type: application/json" \
		-d '{"name":"CI Bot","email":"ci-bot-$(shell date +%s)@example.com"}' | python3 -m json.tool
	@echo "==> [test] network isolation (db must NOT be reachable from host)..."
	@curl -m 3 http://localhost:5432 2>/dev/null && echo "FAIL: db is exposed" || echo "PASS: db is private"
	@echo "==> all tests passed"

# ── Helpers ───────────────────────────────────────────────────────────────────
.PHONY: logs
logs:
	$(COMPOSE) logs -f --tail=50

.PHONY: down
down:
	$(COMPOSE) down

.PHONY: clean
clean:
	$(COMPOSE) down -v
	@echo "==> containers and volumes removed"
