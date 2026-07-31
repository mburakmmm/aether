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
- Aether runs with `AETHER_OPENAPI=0`, `AETHER_LOG_REQUESTS=0`, production CORS default off, route metrics off.
- Default `AETHER_WORKERS=1`: multicore workers do not re-run module init (`AppBind` empty on workers). See `NOX_LIMITATIONS` §12 + §19.
- Query/header validation and JWT are **not** on the ping/echo hot path.

## Results

### 0.4.1 hot-path (local probe, `wrk -t4 -c40 -d5s`, darwin arm64)

| Target | GET /ping req/s | Notes |
|--------|----------------:|-------|
| Bare Nox `HttpResponse` | ~240k | No framework |
| Aether production defaults (CORS off) | ~162k+ | After 0.4.1 opts; re-run for exact |
| Aether `AETHER_CORS_ORIGINS=*` | ~90k | CORS header copy cost |

### 0.4.0 published cross-stack (`wrk -t4 -c40 -d8s`)

| Target | GET /ping req/s | POST /echo req/s | Notes |
|--------|----------------:|-----------------:|-------|
| Aether (`AETHER_WORKERS=1`, CORS `*` default then) | ~90k | ~48k | Pre-0.4.1 |
| NestJS Express | ~67k | ~52k | |
| Gin | ~191k | ~181k | |

Re-run `./benchmarks/run.sh` after upgrading to 0.4.1 for updated cross-stack numbers (production CORS off should lift Aether ping toward ~150–170k on this machine).

## What the bench exposes about Nox / Aether

See `docs/NOX_LIMITATIONS.md` §§16–19 and `docs/PERF.md`.
