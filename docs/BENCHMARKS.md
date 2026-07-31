# Benchmarks: Aether vs NestJS vs Gin

Same workload, same machine, `wrk` load generator.

## Workload

| Route | Behavior |
|-------|----------|
| `GET /ping` | `{"pong":true}` |
| `POST /echo` | body `{"msg":"..."}` → `{"msg":"..."}` (validated where the stack supports it) |

Implementations:

- **Aether** — `benchmarks/aether/main.nox` (`AETHER_WORKERS` multicore)
- **NestJS** — `@nestjs/platform-express` (`benchmarks/nestjs`)
- **Gin** — `github.com/gin-gonic/gin` release mode (`benchmarks/gin`)

## How to run

```sh
chmod +x benchmarks/run.sh
# optional: DURATION=30s CONNECTIONS=100 AETHER_WORKERS=4
./benchmarks/run.sh
```

Requires: `wrk`, `curl`, `noxc`, Go, Node/npm.

Raw wrk logs land in `benchmarks/results/*.txt`.

## Fairness notes

- Nest uses the default Express adapter (common Nest production path). Fastify would be faster; this harness prioritizes Nest’s default stack.
- Aether production defaults enable OpenAPI in some envs — the bench app sets `log_requests=false` and disables CORS; OpenAPI still registers unless `AETHER_OPENAPI=0`.
- Nox `serve*` needs a bare top-level `handle` (see limitation §4); multicore workers do not share in-memory state (§12).
- Query/header validation and JWT are **not** on the ping/echo hot path (measured separately in unit tests).

## Results (fill after local run)

Machine / date: _(runner fills)_

| Target | GET /ping req/s | POST /echo req/s | Notes |
|--------|-----------------|------------------|-------|
| Aether (`AETHER_WORKERS=4`) | | | |
| NestJS Express | | | |
| Gin | | | |

Interpret relative ranking, not absolute numbers across machines.

## What the bench exposes about Nox

See `docs/NOX_LIMITATIONS.md` §§16–18: no stdlib base64/JWT, string-only query maps, hot-path string JSON building, bare `serve` handlers, multicore isolation.
