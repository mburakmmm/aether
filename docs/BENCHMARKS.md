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

### 0.4.1 cross-stack (`wrk -t4 -c40 -d8s`, darwin arm64)

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| **Aether** (`workers=1`, prod CORS off) | **166 506** | **79 147** |
| NestJS Express | 64 905 | 51 538 |
| Gin | 185 836 | 179 314 |

Same machine micro-probe (`-d5s`): bare Nox ~231k; Aether CORS off ~163k; Aether `cors=*` ~158k.

vs **0.4.0** Aether ping ~90k / echo ~48k under the old always-on CORS header path (~**+85%** ping, **+65%** echo).

### 0.4.0 published (historical)

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| Aether (old CORS path) | ~90k | ~48k |
| NestJS Express | ~67k | ~52k |
| Gin | ~191k | ~181k |

## What the bench exposes about Nox / Aether

See `docs/NOX_LIMITATIONS.md` §§16–19 and `docs/PERF.md`.
