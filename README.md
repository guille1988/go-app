# Go-App — Distributed Microservices Platform

A production-grade, event-driven microservices system built in **Go 1.25**, designed around clean architecture, asynchronous messaging, and Kubernetes-native autoscaling.

The system models a real-world user lifecycle — registration, authentication, transactional email, and real-time notifications — split across three independently deployable services that communicate exclusively through Kafka, never through direct HTTP calls to each other.

---

## System Architecture Overview

```
                    Client
                       │
                       ▼
        ┌─────────────────────────────┐
        │   Reverse Proxy / Gateway    │   Traefik (local) · nginx-ingress (prod)
        │  public:    /api/auth, /api/stress ──────────────┐
        │  protected: /api/ws  (forward-auth via auth)      │
        └───────────────┬─────────────────────────┬────────┘
                         │                         │
                         ▼                         ▼
                  ┌─────────────┐          ┌───────────────┐
                  │    auth     │◀──gRPC───│  broadcasting │
                  │ (Gin API)   │ :9090    │ (consumer+WS) │
                  │ MySQL+Redis │ validate │  in-memory    │
                  └──────┬──────┘  token   └───────┬───────┘
                         │ publishes to Kafka       ▲
              ┌──────────┼───────────────────────────┘
              ▼          ▼ consumes
     topic: user.created │  topic: user.logged_in
              │          └────────────────────────┐
              ▼                                    │
       ┌─────────────┐                             │
       │    email    │                             │
       │  (consumer) │                             │
       │   MySQL     │                             │
       └─────────────┘                             │
                                            WebSocket clients
                                          (ws://.../api/ws/:uuid)
```

| Service | Role | Storage | Protocol |
|---|---|---|---|
| **[auth](./microservices/auth)** | Registration, login, JWT issuance, refresh rotation, email verification, session-aware token validation | MySQL + Redis | HTTP (Gin) + gRPC server → Kafka producer |
| **[email](./microservices/email)** | Sends transactional email asynchronously | MySQL | Kafka consumer → SMTP |
| **[broadcasting](./microservices/broadcasting)** | Pushes real-time notifications to connected clients, revalidates their tokens periodically | In-memory (WebSocket hub) | Kafka consumer → WebSocket, gRPC client |
| **[go-app-shared](https://github.com/guille1988/go-app-shared)** | Versioned cross-service contracts — Kafka DTOs/routing keys and gRPC protos (with committed generated code) — checked out as a git submodule at `internal/shared` inside each service | — | — |

**Design principle:** state changes flow asynchronously. All events travel via Kafka, published from `auth` and consumed independently by `email` and `broadcasting` — so those consumers can go down, restart, or scale without `auth` ever noticing, and the only coupling is the shape of the event, defined once in `go-app-shared`. The system has exactly **two synchronous couplings**, both deliberate and both *queries*, never commands: the gateway's forward-auth call at the WebSocket handshake (a gateway-level concern, see [Infrastructure Architecture](#infrastructure-architecture)), and `broadcasting`'s periodic gRPC call asking `auth` "is this token still valid?" — which fails open by design, so an `auth` outage degrades token revalidation instead of dropping live connections. The gRPC contract lives in `go-app-shared` under `rpc/<owning-service>/<version>/`, the same compile-time-safety idea as the Kafka DTOs.

---

## Communication Flows

**1. Registration → Welcome Email**
1. Client calls `POST /api/auth/register` on `auth`.
2. `auth` persists the user (MySQL) and issues an email-verification JWT (see `auth`'s own README for the token `purpose` claim).
3. `auth` publishes a `WelcomeEmail` event to topic `user.created`.
4. `email` consumes it, renders `welcome_user.html`, and sends it via SMTP — deduplicated by event ID so Kafka redelivery never double-sends (see `email`'s own README for the idempotency model).

**2. Login → Real-time Notification**
1. Client calls `POST /api/auth/login`.
2. `auth` validates credentials, issues access + refresh tokens (refresh token stored in Redis, rotated via atomic `GETDEL` on every refresh).
3. `auth` publishes a `UserLoggedIn` event (with the user's UUID) to topic `user.logged_in`.
4. `broadcasting` consumes it and pushes a notification **only to that user's own WebSocket connections** via `Hub.SendToUser(uuid, ...)` — not a blind broadcast to every connected client.

**3. Logout → WebSocket Revocation**
1. Client calls `DELETE /api/auth/logout`; `auth` deletes the refresh session and removes it from the per-user session index in Redis.
2. Every N minutes, `broadcasting`'s revalidation job asks `auth` over gRPC (`AuthService/ValidateToken`) whether each open connection's token is still valid — a check that is session-aware, not just JWT-aware.
3. Once the user has no live sessions left, their connections are closed with application close code `4401` and reason `REVOKED` — within one job tick of the logout, even though the JWT itself is still cryptographically valid. Expired tokens close the same way with reason `EXPIRED`.
4. If `auth` is unreachable, the job **fails open**: connections are kept and re-checked on the next tick — an infrastructure outage never mass-disconnects users.

**4. Load testing (both flows, on demand)**
Both `auth` and `email` expose a `/api/stress` endpoint that publishes synthetic load onto a dedicated `stress.test` topic, driving the same consumer/producer code paths used in production. See [Load Testing & Autoscaling](#load-testing--autoscaling).

---

## Architecture

This section documents the architectural conventions shared by **all three services** — split into how the *application code* is organized (`Application Architecture`) and how it's *deployed and operated* (`Infrastructure Architecture`). Each service's own README documents what it does; this section documents how, so it's written once, here, instead of three times.

## Application Architecture

### Layered structure inside each domain module

Every business capability (`auth`, `user`, `email`, `notification`, `stress`, `health`) is a self-contained module under `internal/domain/<feature>/`, built from up to five sub-layers:

| Layer | Responsibility | Depends on |
|---|---|---|
| `data/` | Request structs with Gin `binding` validation tags (e.g. `binding:"required,email"`) | nothing |
| `handlers/` | Orchestration only: validate → run business rule checks → call the action → shape the response. No business logic lives here. | `actions`, `responses`, `validator` |
| `actions/` | The actual use case / business logic. Framework-agnostic — never touches `*gin.Context` or Kafka directly, only interfaces (`MessagePublisher`, repositories) | `model`/`services`, interfaces only |
| `responses/` | Shapes the HTTP response, including side effects tied to the response itself (e.g. setting the refresh-token cookie) | nothing above it |
| `services/` or `model/` | Domain services (e.g. `JWTService`) or entities + their `Repository` interface + GORM implementation | infrastructure (DB) |

The rule of thumb: **if you're asking "where does this business rule live," the answer is always `actions/`.** Handlers are intentionally thin so the same business logic can be unit-tested without spinning up Gin or Kafka at all.

### Module Pattern (route registration & dependency injection)

Each domain module exposes a constructor and a `Register` method:

```go
type Module struct { /* its own dependencies */ }
func NewModule(deps...) *Module { ... }
func (m *Module) Register(group *gin.RouterGroup) { /* wires its own routes */ }
```

All modules for a service are assembled in one place, `internal/infrastructure/providers/route.go`:

```go
registers := []RouteRegister{
    health.NewModule(),
    auth.NewModule(db, redisClient, publisher, authConfig, env),
    user.NewModule(db, config),
    stress.NewModule(publisher, env),
}
for _, register := range registers {
    register.Register(api)
}
```

Adding a feature means adding one entry to this list — existing modules are never touched. This is effectively **Vertical Slice Architecture** layered inside a **Clean Architecture** boundary (`domain/` never imports `infrastructure/` types directly — only interfaces it defines itself).

### Repository Pattern

Every entity (`User` in `auth`, `Email` in `email`) is accessed through a `Repository` **interface** defined next to the entity, with a GORM-backed struct implementing it:

```go
type Repository interface {
    FindByEmail(email string) (*User, error)
    ExistByEmail(email string) (bool, error)
    Create(user *User) error
    // ...
}
```

Actions and handlers depend on the interface, never on `*gorm.DB` directly — the ORM is a swappable implementation detail, and this is what makes actions testable with an in-memory fake if needed.

### Factory Pattern (test data seeding)

`user/model/factory.go` generates realistic fake users (via `gofakeit`) for `make seed`, reusing the **real** `Repository.Create`/`CreateMany` — seed data goes through the exact same persistence path as production writes, so seeding can never silently diverge from what the app actually does when it creates a user.

### Container & manual Dependency Injection

`internal/infrastructure/container/container.go` assembles every shared dependency exactly once at boot — DB connection, Redis client, Kafka publisher — and `internal/infrastructure/app/app.go` holds the resulting `App` plus a stack of `closer` functions:

```go
app.AddCloser(func() error { return db.Close() }, func() error { return redis.Close() })
...
app.CloseAll() // executed in reverse order on graceful shutdown
```

There is no DI framework/reflection magic — dependencies are plain constructor arguments, wired explicitly in `bootstrap/`. This is deliberate: `grep`-ing for a struct's dependencies always works, because they're just function parameters.

### Configuration

Configuration is a typed Go struct tree (`AppConfig`, `DatabaseConfig`, `AuthConfig`, `KafkaConfig`, ...), populated once at boot from environment variables with sensible defaults, never read ad-hoc from `os.Getenv` elsewhere in the codebase.

**Database driver is a config value, not a code branch.** `DatabaseConnection.Driver` accepts `mysql`, `postgres`, or `sqlite`; the connection layer picks the matching GORM dialector at startup. Switching a service's database engine is a one-line environment variable change (`DB_DRIVER=postgres`), with zero changes to any repository, action, or handler — they only ever see `*gorm.DB`.

### Exception Handling

A single `exceptions.Exception` type throws HTTP errors consistently across every handler, and is **environment-aware**: in `production`, the real Go error is never leaked to the client (`isWithoutPayload` returns true), while in `local`/`staging` the actual error message is included to speed up debugging. One line change in `APP_ENV` controls this everywhere at once.

### Graceful Shutdown

Both the HTTP server (`auth`) and the Kafka consumers (`email`, `broadcasting`) follow the same shape on `SIGTERM`/`SIGINT`: stop accepting new work → drain what's in flight → flush/commit → close infrastructure connections in reverse order of acquisition. See each service's own README for the specifics of its shutdown sequence.

### Messaging: symmetric Publisher/Consumer pattern

- **Publishing** (`auth` only) is reflection-based: a DTO is `Register`ed once against a routing key at boot, and `Publisher.Publish(dto)` resolves the destination topic by the DTO's Go type — no `switch` statement to maintain as event types grow.
- **Consuming** (`email`, `broadcasting`) follows the same registration idea in reverse: a topic + consumer group is registered once against a `Handle(body []byte, eventID string) error` function.

Both patterns mean **adding a new event never requires touching the Kafka client setup code itself** — only adding a DTO, and registering it. See the "Messaging" section in each service's own README for the exact steps.

### How to Add a New HTTP Endpoint (worked example)

Using `auth` as the example, adding `POST /api/auth/password-reset` end to end:

1. **Request shape** — add `internal/domain/auth/data/password_reset.go` with binding tags for validation.
2. **Business logic** — add `internal/domain/auth/actions/password_reset.go`; it depends only on interfaces (`userModel.Repository`, `MessagePublisher`), never on Gin.
3. **Response shape** (only if the response needs custom shaping/side effects, e.g. a cookie) — add `internal/domain/auth/responses/password_reset.go`.
4. **Handler** — add `internal/domain/auth/handlers/password_reset.go`: validate → call the action → respond via the exceptions/responses helpers.
5. **Wire the route** — one line inside `auth.Module.Register`: `auth.POST("/password-reset", handlers.NewPasswordReset(...).Handle)`.
6. **Test** — add `tests/integration/auth/password_reset_test.go` (see below — the test tree mirrors the domain tree).

No existing file is modified except the one `Register` method — this is the same guarantee the Module Pattern gives at the service level, applied at the endpoint level.

### Testing Tree Mirrors the Source Tree

Tests never live next to the implementation — everything is under `tests/`, split by kind:

- **`tests/integration/<module>/`** is organized **by domain module**, not by technical layer — one package for each entry in `internal/domain/`. Each test package spins up its own Testcontainers-backed dependencies (MySQL/Redis/Kafka) via a shared `setup.go`, exercising the module through its real HTTP routes or Kafka consumer — black-box integration tests, not unit tests mocking the repository.
- **`tests/unit/`** mirrors the `internal/` tree exactly (`tests/unit/domain/auth/grpc/` tests `internal/domain/auth/grpc/`, and so on) — black-box unit tests against each package's exported API, with hand-written fakes instead of a mock framework.

```
internal/domain/          tests/integration/         internal/                tests/unit/
├── auth/          ──▶    ├── auth/                  ├── domain/...    ──▶    ├── domain/...
├── user/          ──▶    ├── users/                 └── infrastructure/ ─▶   └── infrastructure/...
├── health/        ──▶    ├── health/
└── stress/        ──▶    └── stress/
```

Because `make test` runs `go test ./tests/...`, both kinds run on every invocation.

---

## Infrastructure Architecture

The application code is identical between environments; what changes is **how it's fronted and orchestrated**. Both environments implement the exact same gateway pattern with different tools.

### The Gateway Pattern: Traefik (local) / nginx-ingress (production)

Every route in the system falls into one of two buckets, enforced at the gateway — not duplicated as auth logic inside `broadcasting`:

- **Public routes** (`auth`'s own `/api/auth/*`, `/api/stress`) are forwarded straight to `auth`, which does its own JWT validation internally.
- **Protected routes** (`broadcasting`'s `/api/ws`) are gated by a **forward-auth** step: the gateway first calls `auth`'s own `GET /api/auth/validate` endpoint, and only if that returns 200 does it forward the original request on — carrying the `X-User-UUID` response header downstream as a request header. This is how `broadcasting` learns which user a WebSocket connection belongs to without ever validating a JWT itself; it trusts the gateway to have already done that.

**Locally**, this is Traefik, configured via Docker Compose labels:
```yaml
labels:
  - "traefik.http.middlewares.forward-auth.forwardauth.address=http://auth:8080/api/auth/validate"
  - "traefik.http.middlewares.forward-auth.forwardauth.authResponseHeaders=X-User-UUID"
  - "traefik.http.routers.broadcasting.middlewares=forward-auth"
```

**In production**, this is `nginx-ingress`, configured via annotations on a dedicated *protected* Ingress (`infrastructure/production/k8s/services/ingress-protected.yaml`) — kept separate from the *public* Ingress that fronts `auth` directly:
```yaml
annotations:
  nginx.ingress.kubernetes.io/auth-url: "http://auth.go-app.svc.cluster.local:8080/api/auth/validate"
  nginx.ingress.kubernetes.io/auth-response-headers: "X-User-UUID"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"   # WebSocket connections are long-lived
  nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

Same security model, same mechanism, two different implementations — proof the auth boundary is a gateway-level concern, not something re-implemented per environment.

### Local Stack (Docker Compose)

`infrastructure/local/docker-compose.yml` brings up the full system as containers:

| Container | Role |
|---|---|
| `traefik` | Gateway / reverse proxy (see above) |
| `auth`, `email`, `broadcasting` | The three services, hot-reloading via `air` (`.air.toml` per service) |
| `mysql_auth`, `mysql_email` | One MySQL instance per service — no shared database |
| `redis_auth` | Session storage for `auth` |
| `kafka` | The message broker |
| `mailpit` | Local SMTP catcher — `email` sends here instead of a real provider |
| `loki` + `promtail` | Log aggregation (Promtail ships each container's logs into Loki) |
| `grafana` | Dashboards over Loki (logs) — same tool used for metrics in production |

### Production Stack (Kubernetes)

```
infrastructure/production/k8s/
├── namespace.yaml
├── infra/
│   ├── kafka.yaml, mysql-auth.yaml, mysql-email.yaml, redis.yaml, mailpit.yaml
│   ├── prometheus.yaml, grafana.yaml, loki.yaml, promtail.yaml
│   └── kube-state-metrics.yaml      # cluster-level pod/deployment state, feeds Grafana dashboards
├── services/
│   ├── auth.yaml, email.yaml, broadcasting.yaml   # Deployment + Service per microservice
│   ├── hpa.yaml                       # KEDA ScaledObjects for auth (RPS) and email (Kafka lag)
│   ├── ingress-public.yaml            # fronts auth directly (/api/auth, /api/stress)
│   └── ingress-protected.yaml         # forward-auth gated, fronts broadcasting (/api/ws)
├── secrets/           # one Secret manifest per service + shared MySQL/Redis credentials
├── keda/              # KEDA operator installation (CRDs)
└── k6/                # Job manifest that runs the load test in-cluster
```

### Load Testing & Autoscaling

Both `auth` and `email` scale via **KEDA `ScaledObject`s**, each on a metric that matches how that service is actually stressed:

- **`auth`** scales on **request rate**: a Prometheus query over its own `http_requests_total` metric (`sum(rate(...[30s])) > 500`), since it's a synchronous HTTP service.
- **`email`** scales on **Kafka consumer lag**: `lagThreshold: 50` on the `stress.test` topic for its `email.service` consumer group — because it's a queue consumer, the right autoscaling signal is backlog, not CPU.

The `/api/stress` endpoints on `auth`/`email` and the k6 script (`infrastructure/production/k6/stress.js`, run via `make production-stress` as a Kubernetes Job) exist specifically to exercise these two scaling paths under controlled, repeatable load — this is not leftover debug code, it's the harness that validates the autoscaling configuration actually works.

### Observability Pipeline

- **Metrics**: every service exposes `/metrics` (Prometheus format), including a `grpc_requests_total{method,code}` counter on both ends of the `auth`↔`broadcasting` gRPC call (server-side interceptor in `auth`, client-side in `broadcasting`). Prometheus scrapes it directly; `kube-state-metrics` additionally exposes cluster-level object state (pod restarts, deployment replica counts) for the same Grafana dashboards.
- **Logs**: structured (`slog`) container logs are shipped by **Promtail** into **Loki** — identical pipeline in both Docker Compose and Kubernetes, just running as a container vs. a DaemonSet-style deployment.
- **Dashboards**: **Grafana** is the single pane of glass over both Prometheus (metrics) and Loki (logs).
- **Health**: every service exposes `/api/health` for liveness checks (used by Kubernetes readiness/liveness probes in production).

---

## Shared Contract: `go-app-shared`

Cross-service contracts are **not duplicated by hand** across services — they live in a single versioned module, [`go-app-shared`](https://github.com/guille1988/go-app-shared), checked out identically as a git submodule at `<service>/internal/shared` in all three services. It holds two kinds of contract:

- **Kafka events** (`messaging/kafka/`): the DTOs and routing keys. This is what lets `auth` change the shape of `WelcomeEmail` and have `email` fail to compile instead of silently breaking at runtime on a JSON mismatch.
- **gRPC APIs** (`rpc/<owning-service>/<version>/`): the `.proto` definitions plus their committed generated code, so consumers build without needing protoc. Versioned packages (`auth.v1`) mean a future breaking change ships as `v2` alongside `v1` instead of forcing a lockstep deploy.

The Makefile enforces this contract stays in sync and regenerates the gRPC code:
```bash
make check-shared-drift        # read-only: fails if the 3 services point to different commits
make sync-shared FROM=auth     # propagates a change made in one service to the other two
make proto                     # regenerates gRPC code from the .proto files (protoc in docker, pinned versions)
```

---

## Tech Stack

| Concern | Choice |
|---|---|
| Language | Go 1.25 |
| HTTP framework | [Gin](https://github.com/gin-gonic/gin) |
| Messaging | [Kafka](https://kafka.apache.org/) via [`twmb/franz-go`](https://github.com/twmb/franz-go) |
| Internal RPC | [gRPC](https://grpc.io/) (`auth` serves, `broadcasting` calls; contract in `go-app-shared`) |
| ORM | [GORM](https://gorm.io/) (MySQL, PostgreSQL, or SQLite per environment) |
| Cache / sessions | [Redis](https://redis.io/) (`go-redis/v9`) |
| WebSockets | [Gorilla WebSocket](https://github.com/gorilla/websocket) |
| Auth | JWT (`golang-jwt/v5`) |
| Testing | [Testify](https://github.com/stretchr/testify) + [Testcontainers](https://testcontainers.com/) (real MySQL/Redis/Kafka in CI, not mocks) |
| Gateway | Traefik (local) / nginx-ingress (production) |
| Observability | Prometheus, Grafana, Loki + Promtail, kube-state-metrics |
| Local orchestration | Docker Compose |
| Production orchestration | Kubernetes + KEDA |
| Load testing | [k6](https://k6.io/) |

---

## Quick Start — Local Development

```bash
make init          # copies .env, starts Docker Compose, migrates, seeds, runs tests
make up             # start MySQL, Redis, Kafka, Promtail, and all 3 services
make migrate        # run DB migrations for auth + email
make seed           # populate with fake data (auth users via gofakeit)
make test           # run the full test suite (Testcontainers spins up real deps)
make logs           # tail logs for all services
make down           # stop everything
```

Run `make help` for the full command list. Local and production targets are namespaced (`local-*` / `production-*`); the short names above (`up`, `down`, `test`, etc.) are aliases to the local ones for convenience.

---

## Production — Kubernetes

See [Infrastructure Architecture](#infrastructure-architecture) above for the full manifest layout, the gateway setup, and the autoscaling/load-testing design. Day-to-day commands:

```bash
make production-init      # setup + build + up + migrate
make production-stress    # run the k6 load test as a Kubernetes Job
make production-logs
```

---

## Testing Strategy

Every service ships its own integration test suite using **Testcontainers** — tests run against real, ephemeral MySQL/Redis/Kafka containers rather than mocks, so a green test suite means the service actually talks to the real protocols correctly (message framing, SQL constraints, Redis semantics included). See [Testing Tree Mirrors the Domain Tree](#testing-tree-mirrors-the-domain-tree) above for how these are organized.

```bash
make test          # runs all 3 suites from the root
```

---

## Project Structure

```text
.
├── microservices/
│   ├── auth/            # HTTP API — registration, login, JWT, Redis sessions
│   │   └── internal/shared/   # go-app-shared submodule
│   ├── email/           # Kafka consumer — transactional email
│   │   └── internal/shared/
│   └── broadcasting/    # Kafka consumer + WebSocket server — real-time notifications
│       └── internal/shared/
├── infrastructure/
│   ├── local/           # Docker Compose, Dockerfiles, Promtail config, .air.toml (hot reload)
│   └── production/      # Kubernetes manifests, Dockerfiles, k6 script
└── Makefile             # single entry point for local + production workflows
```
