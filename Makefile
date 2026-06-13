# Reactive Resume — Colima-based dev environment
# Usage: make dev (starts everything), make stop (tears down)

SHELL := /bin/bash

COLIMA_PROFILE := default
DOCKER_CTX := colima
COMPOSE := docker --context $(DOCKER_CTX) compose -f compose.dev.yml
DOTENVX := pnpm dlx @dotenvx/dotenvx
ENV_FILE := .env.local

# ─── One command to rule them all ────────────────────────────────────────────

.PHONY: dev
dev: ensure-colima ensure-env infra wait-healthy migrate kill-stale app ## Start full dev stack

# ─── Colima ──────────────────────────────────────────────────────────────────

.PHONY: ensure-colima
ensure-colima:
	@if ! colima status --profile $(COLIMA_PROFILE) 2>/dev/null | grep -q "is running"; then \
		echo "▶ Starting Colima (profile: $(COLIMA_PROFILE))..."; \
		colima start --profile $(COLIMA_PROFILE) --cpu 4 --memory 8 --disk 60 --vm-type vz --mount-type virtiofs; \
	else \
		echo "✓ Colima ($(COLIMA_PROFILE)) running"; \
	fi

# ─── Environment ─────────────────────────────────────────────────────────────

.PHONY: ensure-env
ensure-env:
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "▶ Creating $(ENV_FILE) from template..."; \
		cp .env.example $(ENV_FILE); \
		sed -i '' 's|postgresql://postgres:postgres@postgres:5432/postgres|postgresql://postgres:postgres@localhost:5432/postgres|' $(ENV_FILE); \
		sed -i '' 's|http://seaweedfs:8333|http://localhost:8333|' $(ENV_FILE); \
		echo "AUTH_SECRET=$$(openssl rand -hex 32)" >> $(ENV_FILE); \
		echo "✓ Created $(ENV_FILE) — review and adjust if needed"; \
	else \
		echo "✓ $(ENV_FILE) exists"; \
	fi

# ─── Infrastructure (containers) ─────────────────────────────────────────────

.PHONY: infra
infra:
	@echo "▶ Starting infra containers (postgres, redis, seaweedfs)..."
	@$(COMPOSE) up -d postgres redis seaweedfs seaweedfs_create_bucket

.PHONY: wait-healthy
wait-healthy:
	@echo "▶ Waiting for services to be healthy..."
	@timeout=60; while [ $$timeout -gt 0 ]; do \
		pg=$$(docker --context $(DOCKER_CTX) inspect --format='{{.State.Health.Status}}' reactive_resume-postgres-1 2>/dev/null); \
		rd=$$(docker --context $(DOCKER_CTX) inspect --format='{{.State.Health.Status}}' reactive_resume-redis-1 2>/dev/null); \
		sw=$$(docker --context $(DOCKER_CTX) inspect --format='{{.State.Health.Status}}' reactive_resume-seaweedfs-1 2>/dev/null); \
		if [ "$$pg" = "healthy" ] && [ "$$rd" = "healthy" ] && [ "$$sw" = "healthy" ]; then \
			echo "✓ All services healthy"; \
			break; \
		fi; \
		printf "  postgres=$$pg redis=$$rd seaweedfs=$$sw (waiting...)\r"; \
		sleep 2; \
		timeout=$$((timeout - 2)); \
	done; \
	if [ $$timeout -le 0 ]; then echo "✗ Timeout waiting for services"; exit 1; fi

# ─── Database ─────────────────────────────────────────────────────────────────

.PHONY: migrate
migrate:
	@echo "▶ Running database migrations..."
	@$(DOTENVX) run -f $(ENV_FILE) -- pnpm db:migrate

# ─── Application ──────────────────────────────────────────────────────────────

.PHONY: kill-stale
kill-stale:
	@lsof -ti :4000 | xargs kill -9 2>/dev/null || true
	@lsof -ti :3001 | xargs kill -9 2>/dev/null || true
	@sleep 1

.PHONY: app
app:
	@echo "▶ Starting dev server (web + server)..."
	@ulimit -n 65536 2>/dev/null; $(DOTENVX) run -f $(ENV_FILE) -- pnpm exec turbo run dev --filter=web --filter=server

# ─── Utilities ────────────────────────────────────────────────────────────────

.PHONY: stop
stop: ## Stop all infra containers
	@echo "▶ Stopping containers..."
	@$(COMPOSE) down

.PHONY: clean
clean: stop ## Stop containers and remove volumes
	@echo "▶ Removing volumes..."
	@$(COMPOSE) down -v

.PHONY: logs
logs: ## Tail infra container logs
	@$(COMPOSE) logs -f postgres redis seaweedfs

.PHONY: ps
ps: ## Show container status
	@$(COMPOSE) ps

.PHONY: reset-db
reset-db: ## Drop and recreate database
	@docker --context $(DOCKER_CTX) exec reactive_resume-postgres-1 psql -U postgres -c "DROP DATABASE IF EXISTS postgres;" 2>/dev/null || true
	@docker --context $(DOCKER_CTX) exec reactive_resume-postgres-1 psql -U postgres -c "CREATE DATABASE postgres;" 2>/dev/null || true
	@$(MAKE) migrate

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
