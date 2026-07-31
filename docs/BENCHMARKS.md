# Benchmarks: Aether vs NestJS vs Gin

Same workload, same machine, `wrk` load generator.

## Workload

| Route | Behavior |
|-------|----------|
| `GET /ping` | `{"pong":true}` |
| `POST /echo` | body `{"msg":"..."}` → `{"msg":"..."}` (validated where the stack supports it) |

Implementations:

- **Aether** — `benchmarks/aether/main.nox` (`dispatch_bound`; default `AETHER_WORKERS=1`)
- **NestJS** — `@nestjs/platform-express` (`benchmarks/nestjs`)
- **Gin** — `github.com/gin-gonic/gin` release mode (`benchmarks/gin`)

## How to run

```sh
chmod +x benchmarks/run.sh
# optional: DURATION=30s CONNECTIONS=100
./benchmarks/run.sh
```

Requires: `wrk`, `curl`, `noxc`, Go, Node/npm.

Raw wrk logs land in `benchmarks/results/*.txt` (gitignored).

## Fairness notes

- Nest uses the default Express adapter (common Nest production path).
- Aether runs with `AETHER_OPENAPI=0` and `AETHER_LOG_REQUESTS=0`.
- Default `AETHER_WORKERS=1`: multicore workers do not re-run module init, so `AppBind` is empty on worker threads (see `NOX_LIMITATIONS` §12 + §19). Scale-out needs per-worker boot support from Nox.
- Query/header validation and JWT are **not** on the ping/echo hot path.

## Results (local run)

Machine: darwin arm64 · Date: 2026-07-31 · `wrk -t4 -c40 -d8s`

| Target | GET /ping req/s | POST /echo req/s | Notes |
|--------|-----------------|------------------|-------|
| Aether (`AETHER_WORKERS=1`) | **90 383** | **48 350** | Some socket read errors under load |
| NestJS Express | **66 773** | **51 696** | |
| Gin | **190 588** | **181 159** | |

Relative ranking on this machine: **Gin ≫ Aether ≳ Nest on ping**; **Gin ≫ Nest ≳ Aether on echo** (DTO validation path on Aether/Nest-ish JSON body).

## What the bench exposes about Nox

See `docs/NOX_LIMITATIONS.md` §§16–19: no stdlib base64/JWT, string-only query maps, hot-path string JSON building, bare `serve` handlers, **serve cannot close over `Application`**, multicore isolation vs `AppBind`.
