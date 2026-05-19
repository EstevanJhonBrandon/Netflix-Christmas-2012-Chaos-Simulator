# 🎄 Netflix Christmas 2012 — Chaos Simulator

> Simulación completa del incidente de infraestructura de Netflix del 24 de diciembre de 2012.
> Recrea la degradación en cascada de una base de datos Cassandra multi-DC bajo inyección de fallos
> controlada, con frontend React/Vite estilo Netflix 2012 y un dashboard de caos en tiempo real.

---

## ⚡ Inicio Rápido

```bash
git clone <repo>
cd netflix-chaos-simulator

cp .env.example .env
make up          # levanta los 22 servicios + smoke test automático
make urls        # muestra todas las URLs
```

**→ Abrir http://localhost:5173**  |  Dashboard: http://localhost:5173/simulator

> **Requisitos:** Docker Engine 24+, Docker Compose v2, 8 GB RAM, 10 GB disco

---

## 🗂 Estructura del Proyecto

```
netflix-chaos-simulator/
├── docker-compose.yml          ← 22 servicios orquestados
├── Makefile                    ← make up / make chaos-full / make recover ...
├── .env.example                ← credenciales y flags
│
├── frontend/                   React 18 + Vite 5 + Zustand
│   ├── src/
│   │   ├── api/client.js         Axios → FastAPI + Chaos Engine
│   │   ├── store/useSimStore.js  Estado central (nodos, métricas, caos)
│   │   ├── hooks/
│   │   │   ├── useSimTick.js     Reloj 1s + idle logs
│   │   │   ├── useSSE.js         SSE desde Node.js
│   │   │   └── useMetricsPoller  Polling /health cada 5s
│   │   ├── components/
│   │   │   ├── netflix/          Navbar · Hero · MovieRow · Footer (UI 2012)
│   │   │   └── simulator/        NodePanel · MetricsPanel · ChaosPanel
│   │   └── pages/
│   │       ├── NetflixPage.jsx   Interfaz Netflix 2012
│   │       └── SimulatorPage.jsx Dashboard de caos
│   ├── Dockerfile                nginx multi-stage (ARG VITE_*)
│   └── nginx.conf                SPA + proxy SSE (chunked, sin buffer)
│
└── backend/
    ├── services/
    │   ├── api/                  FastAPI (Python 3.11)
    │   │   ├── main.py             Lifespan: Cassandra + Kafka prod+cons + CB
    │   │   ├── db/cassandra.py     Multi-DC, tunable consistency, NetflixRetryPolicy
    │   │   ├── kafka/
    │   │   │   ├── producer.py     Idempotente, retry ×3, DLQ
    │   │   │   └── consumer.py     CQRS projection + chaos event handler
    │   │   ├── resilience/
    │   │   │   ├── circuit_breaker.py  CLOSED/HALF_OPEN/OPEN + Prometheus
    │   │   │   ├── saga.py             5 pasos + compensating transactions
    │   │   │   └── vault_client.py     Cache TTL, degradación graceful
    │   │   ├── grpc/
    │   │   │   ├── streaming.proto     NegotiateQuality + WatchQuality (streaming)
    │   │   │   └── grpc_server.py      Implementación del servicer
    │   │   └── routes/
    │   │       ├── subscriptions.py    CQRS write+read, fallback DC-EAST-2
    │   │       ├── streams.py          Playback tracking
    │   │       ├── chaos.py            Delegación → Chaos Engine
    │   │       └── health.py           /health completo (todos los subsistemas)
    │   ├── streaming/            Node.js 20
    │   │   └── index.js            Kafka consumer → SSE fan-out, latency injection
    │   └── chaos/                Chaos Engine (FastAPI)
    │       └── main.py             docker pause/unpause, auto-recovery, Kafka events
    ├── cassandra/init.cql        Schema NetworkTopologyStrategy + seed data
    ├── monitoring/
    │   ├── prometheus.yml          Scrape: api · streaming · chaos · traefik · kafka
    │   └── grafana/
    │       ├── dashboards/         11 panels auto-provisionados
    │       └── datasources/        Prometheus datasource
    ├── airflow/dags/
    │   └── christmas_2012_chaos.py DAG secuencial + DAG full incident
    ├── terraform/
    │   ├── main.tf                 Redes Docker + outputs
    │   └── recovery.tf             Recovery step-by-step (Vault→DC-EAST-1→repair→app)
    └── scripts/
        ├── vault-init.sh           Seed: encryption keys por plan
        └── smoke-test.sh           ~30 checks (containers, HTTP, TCP, funcionales)
```

---

## 🎛 Comandos

```bash
# Infraestructura
make up               # arrancar todo
make down             # parar todo
make reset            # parar + borrar volúmenes
make logs svc=api     # logs de un servicio
make ps               # estado de contenedores

# Escenarios de caos (también disponibles desde el dashboard React)
make chaos-partition  # Escenario 1: DC-EAST-1 aislado
make chaos-exhaust    # Escenario 2: Node.js saturado
make chaos-vault      # Escenario 3: Vault caído
make chaos-full       # 🎄 Christmas 2012 — los tres simultáneos
make recover          # Auto-recuperación vía Terraform

# Cassandra
make cassandra-status     # nodetool status (6 nodos UN esperado)
make cassandra-repair     # nodetool repair (reconciliar datos post-incidente)
make cassandra-shell      # cqlsh interactivo en cass-e1-n1

# Consistencia (Tunable Consistency)
make consistency-quorum   # LOCAL_QUORUM — consistencia fuerte
make consistency-one      # ONE — alta disponibilidad, datos eventualmente consistentes

# gRPC
make proto            # genera *_pb2.py y *_pb2_grpc.py desde streaming.proto

# Verificación
make smoke-test       # ~30 checks de salud
make urls             # imprime todas las URLs
```

---

## 🌐 URLs y Accesos

| Servicio           | URL                                  | Credenciales                      |
|--------------------|--------------------------------------|-----------------------------------|
| **Frontend**       | http://localhost:5173                |                                   |
| **Simulator**      | http://localhost:5173/simulator      |                                   |
| **API + Swagger**  | http://localhost:8000/docs           |                                   |
| **Chaos Engine**   | http://localhost:8001                |                                   |
| **Grafana**        | http://localhost:3001                | admin / netflix2012               |
| **Prometheus**     | http://localhost:9090                |                                   |
| **Jaeger**         | http://localhost:16686               |                                   |
| **Vault**          | http://localhost:8200                | token: `netflix-sim-root-token`   |
| **Consul**         | http://localhost:8500                |                                   |
| **Traefik**        | http://localhost:8080                |                                   |
| **Airflow**        | http://localhost:8088                | admin / netflix2012               |

---

## 📊 Métricas Clave (Grafana)

| Métrica                          | Panel | Descripción                              |
|----------------------------------|-------|------------------------------------------|
| `http_requests_total`            | 1     | Error rate por status code               |
| `http_request_duration_seconds`  | 2     | P50/P95/P99 latency                      |
| `circuit_breaker_state`          | 3     | 0=CLOSED · 1=HALF_OPEN · 2=OPEN         |
| `saga_rolled_back_total`         | 4     | Sagas en rollback (fallo de Vault)       |
| `vault_available`                | 9     | 1=disponible · 0=caído                  |
| `nodejs_event_loop_lag_ms`       | 10    | Lag del event loop Node.js               |
| `streaming_active_connections`   | 11    | Clientes SSE conectados                  |
| `kafka_dead_letter_received_total`| -    | Mensajes en DLQ (máximos reintentos)     |

---

## 🔄 Flujo del Saga Pattern (Suscripción)

```
POST /subscriptions/
     │
     ▼
[1] VAULT_SECRET_FETCHED  ← Si Vault cae → falla aquí → rollback total
     │
     ▼
[2] PAYMENT_PENDING / PAYMENT_OK
     │
     ▼
[3] CASSANDRA_WRITTEN     ← Si DC-EAST-1 caído + LOCAL_QUORUM → falla aquí
     │                      Con ONE → escribe en DC-EAST-2 (eventual consistency)
     ▼
[4] KAFKA_PUBLISHED       → topic: subscriptions
     │
     ▼
[5] COMPLETED
     │
     ▼
Kafka Consumer (FastAPI) → actualiza proyección CQRS en Cassandra
```

---

## 🔌 SSE en Tiempo Real

```bash
# Conectar al stream de eventos de Kafka vía SSE
curl -N "http://localhost:3000/events?user_id=mi-usuario"

# Eventos que llegarán:
# - streams: { event: "stream.started", user_id, content_id }
# - subscriptions: { event: "subscription.activated", plan }
# - chaos: { type: "latency_injection", latency_ms: 2000 }
# - recovery: { type: "streaming_recovered" }
```

---

## 📝 Notas de Diseño

**¿Por qué LOCAL_QUORUM y no QUORUM?**
Netflix usó `LOCAL_QUORUM` para que las escrituras y lecturas sólo esperen quorum dentro del DC local, evitando la latencia cross-DC en operaciones normales. Cuando el DC cae, `LOCAL_QUORUM` falla (como en el incidente de 2012), mientras que `ONE` mantiene disponibilidad a costa de potencial inconsistencia.

**¿Por qué Saga y no 2PC?**
El two-phase commit bloquea recursos hasta que todos los participantes confirman, lo que en un sistema distribuido con múltiples DCs introduce latencia inaceptable y el riesgo de bloqueo indefinido si un coordinador cae. El Saga Pattern usa transacciones locales con compensaciones explícitas, que es exactamente cómo Netflix diseñó su flujo de suscripciones.

**¿Por qué el Chaos Engine usa `docker pause`?**
`docker pause` envía `SIGSTOP` al proceso, congelando el contenedor sin matarlo — simula una partición de red desde la perspectiva del resto del cluster (el nodo existe pero no responde), que es el comportamiento exacto de una partición real donde TCP connections time out pero no se terminan limpiamente.
