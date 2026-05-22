# ══════════════════════════════════════════════════════════════════
#  Netflix Christmas 2012 — Chaos Simulator
#  Makefile — run from the project root
# ══════════════════════════════════════════════════════════════════

.DEFAULT_GOAL := help
.PHONY: help up down restart logs ps build reset \
        frontend-dev frontend-build \
        chaos-partition chaos-exhaust chaos-vault chaos-full recover \
        cassandra-status cassandra-repair cassandra-shell \
        consistency-quorum consistency-one \
        proto smoke-test urls

# ── Colours ────────────────────────────────────────────────────────
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RESET  := \033[0m

# ── Help ───────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  $(GREEN)Netflix Christmas 2012 — Chaos Simulator$(RESET)"
	@echo ""
	@echo "  $(YELLOW)Stack$(RESET)"
	@echo "    make up              Start all 22 services"
	@echo "    make down            Stop all services"
	@echo "    make reset           Stop + remove volumes"
	@echo "    make build           Rebuild all images"
	@echo "    make logs svc=api    Follow logs for a service"
	@echo "    make ps              Container status"
	@echo ""
	@echo "  $(YELLOW)Frontend (dev)$(RESET)"
	@echo "    make frontend-dev    Vite dev server → :5173"
	@echo "    make frontend-build  Production build"
	@echo ""
	@echo "  $(YELLOW)Chaos scenarios$(RESET)"
	@echo "    make chaos-partition  Escenario 1 — Partición de red DC-EAST-1"
	@echo "    make chaos-exhaust    Escenario 2 — Agotamiento recursos Node.js"
	@echo "    make chaos-vault      Escenario 3 — Fallo de Vault"
	@echo "    make chaos-full       🎄 Christmas 2012 — todos simultáneos"
	@echo "    make recover          Auto-recuperación via Terraform"
	@echo ""
	@echo "  $(YELLOW)Cassandra$(RESET)"
	@echo "    make cassandra-status   nodetool status"
	@echo "    make cassandra-repair   nodetool repair"
	@echo "    make cassandra-shell    cqlsh interactivo"
	@echo ""
	@echo "  $(YELLOW)Consistency$(RESET)"
	@echo "    make consistency-quorum  Restaurar LOCAL_QUORUM"
	@echo "    make consistency-one     Cambiar a ONE (alta disponibilidad)"
	@echo ""
	@echo "  $(YELLOW)Utils$(RESET)"
	@echo "    make proto           Generar stubs gRPC"
	@echo "    make smoke-test      Verificar todos los servicios"
	@echo "    make urls            Mostrar todas las URLs"
	@echo ""

# ── Permissions ────────────────────────────────────────────────────
_chmod:
	@chmod +x backend/scripts/smoke-test.sh
	@chmod +x backend/scripts/vault-init.sh

# ── Docker Compose ─────────────────────────────────────────────────
up: _chmod
	@echo "🔍 Checking Docker Compose version (need ≥2.4 for service_completed_successfully)..."
	@docker compose version | grep -oP '[\d]+\.[\d]+' | head -1 | awk -F. '$$1<2 || ($$1==2 && $$2<4) {print "ERROR: Docker Compose ≥2.4 required. Run: docker compose version"; exit 1}'
	@echo "🚀 Starting all services..."
	docker compose up -d
	@echo "$(YELLOW)⏳ Waiting 90s for Cassandra cluster to form...$(RESET)"
	@sleep 90
	@$(MAKE) smoke-test

down:
	docker compose down

reset:
	@echo "$(YELLOW)⚠️  Removing ALL containers and volumes...$(RESET)"
	docker compose down -v --remove-orphans

# purge-state: elimina solo los volúmenes de datos persistentes
# (Prometheus WAL, Cassandra SSTables, Grafana state, Consul data)
# sin borrar imágenes descargadas. Úsalo cuando:
#   - Prometheus muestre "Unknown series references" al arrancar
#   - Cassandra tarde más de lo normal en unirse al ring
#   - Grafana no cargue dashboards correctamente
purge-state:
	@echo "$(YELLOW)🗑  Purgando volúmenes de estado (WAL, SSTables, Consul)...$(RESET)"
	docker compose down --remove-orphans
	docker volume rm -f 		$$(docker volume ls -q | grep -E "cassandra_e[12]_n[123]|prometheus_data|grafana_data|consul_data") 		2>/dev/null || true
	@echo "$(GREEN)✓ Estado purgado. El próximo 'make up' arranca desde cero.$(RESET)"
	@echo "$(YELLOW)  Nota: Cassandra tardará ~3 min en reconstruir el ring completo.$(RESET)"

restart:
	docker compose restart $(svc)

logs:
	docker compose logs -f $(or $(svc), --tail=50)

ps:
	docker compose ps

build:
	docker compose build --no-cache

# ── Frontend dev ───────────────────────────────────────────────────
frontend-dev:
	cd frontend && npm install && npm run dev

frontend-build:
	cd frontend && npm install && npm run build

# ── Chaos injection ────────────────────────────────────────────────
chaos-partition:
	@echo "$(YELLOW)⚡ Injecting: Network Partition (DC-EAST-1)$(RESET)"
	curl -s -X POST http://localhost:8001/inject \
		-H "Content-Type: application/json" \
		-d '{"scenario":"network_partition","duration_seconds":60}' | python3 -m json.tool

chaos-exhaust:
	@echo "$(YELLOW)🔥 Injecting: Resource Exhaustion (Node.js)$(RESET)"
	curl -s -X POST http://localhost:8001/inject \
		-H "Content-Type: application/json" \
		-d '{"scenario":"resource_exhaustion","duration_seconds":90}' | python3 -m json.tool

chaos-vault:
	@echo "$(YELLOW)🔑 Injecting: Vault Failure$(RESET)"
	curl -s -X POST http://localhost:8001/inject \
		-H "Content-Type: application/json" \
		-d '{"scenario":"vault_failure","duration_seconds":120}' | python3 -m json.tool

chaos-full:
	@echo "$(YELLOW)💀 CHRISTMAS 2012 — Full incident$(RESET)"
	curl -s -X POST http://localhost:8001/inject \
		-H "Content-Type: application/json" \
		-d '{"scenario":"full_incident","duration_seconds":180}' | python3 -m json.tool

recover:
	@echo "$(GREEN)↺ Triggering auto-recovery...$(RESET)"
	curl -s -X POST http://localhost:8001/recover | python3 -m json.tool

# ── Cassandra ──────────────────────────────────────────────────────
cassandra-status:
	docker exec cass-e1-n1 nodetool status

cassandra-repair:
	@echo "$(YELLOW)🔧 Running Cassandra repair on dc-east-1...$(RESET)"
	docker exec cass-e1-n1 nodetool repair netflix_sim

cassandra-shell:
	docker exec -it cass-e1-n1 cqlsh

cassandra-migrate:
	@echo "$(YELLOW)🔧 Applying Cassandra migrations...$(RESET)"
	@for f in backend/cassandra/v0*.cql; do \
	  echo "  Applying $$f..."; \
	  docker exec cass-e1-n1 cqlsh -f /dev/stdin < $$f && echo "  OK: $$f" || echo "  SKIP (may already be applied): $$f"; \
	done

cassandra-seed-video:
	@echo "$(YELLOW)🎬 Seeding video URLs into projections...$(RESET)"
	docker exec -i cass-e1-n1 cqlsh < backend/cassandra/v009_projection_video_columns.cql
	@echo "$(GREEN)✓ Video URLs seeded$(RESET)"

# ── Consistency ────────────────────────────────────────────────────
consistency-quorum:
	@echo "$(GREEN)🔒 Switching to LOCAL_QUORUM$(RESET)"
	curl -s -X POST http://localhost:8000/subscriptions/consistency \
		-H "Content-Type: application/json" \
		-d '{"level":"LOCAL_QUORUM"}' | python3 -m json.tool

consistency-one:
	@echo "$(YELLOW)⚡ Switching to ONE (high availability mode)$(RESET)"
	curl -s -X POST http://localhost:8000/subscriptions/consistency \
		-H "Content-Type: application/json" \
		-d '{"level":"ONE"}' | python3 -m json.tool

# ── gRPC stubs ─────────────────────────────────────────────────────
proto:
	@echo "$(YELLOW)Generating gRPC stubs...$(RESET)"
	pip install grpcio-tools --quiet
	python -m grpc.tools.protoc \
		-I backend/services/api/grpc \
		--python_out=backend/services/api/grpc \
		--grpc_python_out=backend/services/api/grpc \
		backend/services/api/grpc/streaming.proto
	@echo "$(GREEN)✓ Stubs generated$(RESET)"

# ── Smoke test ─────────────────────────────────────────────────────
smoke-test: _chmod
	@bash backend/scripts/smoke-test.sh

# ── URLs ───────────────────────────────────────────────────────────
urls:
	@echo ""
	@echo "  $(GREEN)Frontend$(RESET)     → http://localhost:5173"
	@echo "  $(GREEN)Simulator$(RESET)    → http://localhost:5173/simulator"
	@echo "  $(GREEN)API docs$(RESET)     → http://localhost:8000/docs"
	@echo "  Chaos Engine → http://localhost:8001"
	@echo "  Grafana      → http://localhost:3001  $(YELLOW)(admin / netflix2012)$(RESET)"
	@echo "  Prometheus   → http://localhost:9090"
	@echo "  Jaeger       → http://localhost:16686"
	@echo "  Vault        → http://localhost:8200  $(YELLOW)(token: netflix-sim-root-token)$(RESET)"
	@echo "  Consul       → http://localhost:8500"
	@echo "  Traefik      → http://localhost:8080"
	@echo "  Airflow      → http://localhost:8088  $(YELLOW)(admin / netflix2012)$(RESET)"
	@echo ""
