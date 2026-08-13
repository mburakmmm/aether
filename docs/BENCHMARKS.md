# Benchmarks: Aether vs NestJS vs Gin

Same workload, same machine, `wrk` load generator.

## Workload

| Route | Behavior |
|-------|----------|
| `GET /ping` | `{"pong":true}` |
| `POST /echo` | body `{"msg":"..."}` → `{"msg":"..."}` (validated where the stack supports it) |

Implementations:

- **Aether QBE** — `noxc run benchmarks/aether/main.nox` (`dispatch_ensure`; `AETHER_WORKERS=1`)
- **Aether `--release`** — `noxc build --release` (Nox 1.29 LLVM M:N, macOS/arm64)
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
- Default `AETHER_WORKERS=1` for fair single-process comparison. See `docs/PERF.md` for QBE vs `--release`.
- Query/header validation and JWT are **not** on the ping/echo hot path.
- `--release` is measured **after** stopping the QBE server (two Aether processes on one machine can SIGSEGV the LLVM binary).

## Results

### 0.6.0 re-measure (`wrk -t4 -c40 -d8s`, darwin arm64, Nox 1.29.0)

Same flags as 0.4.1. Absolute numbers are below the quieter 0.4.1 run (machine load); use them for **relative** QBE vs `--release` vs Nest vs Gin.

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| **Aether QBE** (`workers=1`) | **57 050** | **49 420** |
| Aether `--release` (`workers=1`) | 48 528 | 34 573 |
| NestJS Express | 40 602 | 48 242 |
| Gin | 51 773 | 95 664 |

Notes:

- QBE still beats Nest on ping; Gin still leads echo.
- LLVM `--release` M:N is **not** a free win on this single-worker JSON ping/echo path (pool overhead). It remains the supported production binary path on macOS/arm64 for shared-heap multicore, not the default bench winner.
- Aether rows showed `wrk` socket read errors (QBE ping 440, `--release` ping 360); Nest/Gin did not.

### 0.4.1 cross-stack (`wrk -t4 -c40 -d8s`, darwin arm64) — historical, quieter machine

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
