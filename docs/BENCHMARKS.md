# Benchmarks: Aether vs NestJS vs Gin

Same workload, same machine, `wrk` load generator.

## Workload

| Route | Behavior |
|-------|----------|
| `GET /ping` | `{"pong":true}` |
| `POST /echo` | body `{"msg":"..."}` → `{"msg":"..."}` (validated where the stack supports it) |

Implementations:

- **Aether QBE** — `noxc run benchmarks/aether/main.nox` (`dispatch_from_parts` / `handle_bare`; `AETHER_WORKERS=1`, `NOX_POOL_WORKERS=1`)
- **Aether `--release`** — `noxc build --release` (Nox 1.29.4 LLVM M:N, macOS/arm64; process-env `NOX_POOL_WORKERS` + `AETHER_LLVM=1`)
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

### 0.6.2 + Nox 1.29.4 (`wrk -t4 -c40 -d8s`, darwin arm64)

Same Aether hot path as 0.6.1. Nox **1.29.4** (`serve_multicore` SO_REUSEPORT). Fairness flags unchanged: `NOX_POOL_WORKERS=1`, `AETHER_REQUEST_ID=0`, `AETHER_REQUEST_HEADERS=0`. `--release` sets `AETHER_LLVM=1` so the process calls `serve()` (single listen fd).

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| Aether QBE (`workers=1`) | 206 199 | 89 096 |
| **Aether `--release` (`workers=1`)** | **209 364** | **90 908** |
| NestJS Express | 64 394 | 51 546 |
| Gin | 192 468 | 186 202 |

Extra rows (same wrk, **not** in the fairness table):

| Extra | GET /ping | POST /echo |
|-------|----------:|-----------:|
| QBE 8 workers (SO_REUSEPORT) | 204 055 | 86 467 |
| `--release` 8 workers (`AETHER_LLVM=1`, single `serve()` + pool=8) | 49 776 | 48 843 |

vs **0.6.1 / Nox 1.29.3** (same machine/flags): workers=1 within noise (QBE ping −1%, `--release` ping +1%). Gin/Nest within noise. 1.29.4 does **not** move G1/G2/G4.

Notes:

- `--release` ping now **beats Gin** (209k vs 192k) and matches QBE (~1.02×). Echo still ~2.0× behind Gin (91k vs 186k) — G2.
- QBE 8 workers at c=40 ≈ 1 worker (204k vs 206k). SO_REUSEPORT is the right QBE listen model; this microbench has too few connections to scale ping.
- `--release` 8 workers **collapses** (~50k ping, ~4.2× slower than 1 worker). Nox 1.29.4 flatten + SO_REUSEPORT opens N accept loops inside the M:N pool; Aether therefore uses `serve()` + `AETHER_LLVM=1`. Extra pool workers still tax this tiny non-yielding ping (G3). Default `AETHER_WORKERS=1`. Naive `serve_multicore` under `--release` is equally collapsed (~56k) — do not use it.
- `wrk` socket read errors remain Aether-only (QBE ping 1645 / echo 700; `--release` ping 1676 / echo 718). Nest/Gin 0.

### 0.6.1 + Nox 1.29.3 (`wrk -t4 -c40 -d8s`, darwin arm64) — historical

Same Aether code as 0.6.1. Nox **1.29.3** (lock-free ARC `pool_free_lists` under `--release`). Flags unchanged: `NOX_POOL_WORKERS=1`, `AETHER_REQUEST_ID=0`, `AETHER_REQUEST_HEADERS=0`.

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| **Aether QBE** (`workers=1`) | **209 226** | **94 342** |
| Aether `--release` (`workers=1`) | 206 284 | 89 782 |
| NestJS Express | 66 975 | 51 532 |
| Gin | 196 243 | 186 348 |

Aether `--release` **8 workers** (same wrk, `NOX_POOL_WORKERS=8`; not in the fairness table): ping **143 574**, echo **94 066**. Ping falls vs 1 worker at c=40 (tiny handler + steal tax). Echo ~+5% vs 1-worker `--release`.

vs **0.6.1 / Nox 1.29.2** (same machine/flags): QBE ping +3%, echo +7%; `--release` ping +10%, echo +3%; Gin ping +4%, echo +5%. QBE path is unchanged in 1.29.3 (changelog); workers=1 `--release` has no cross-worker free-list contention — treat the bump as noise except the 8-worker row, which is the 1.29.3 target.

Notes:

- QBE ping still **beats Gin** (209k vs 196k). Echo still ~2.0× behind Gin (94k vs 186k) — G2.
- `--release` workers=1 stays within ~1.01× of QBE ping. 1.29.3 does **not** require Aether code changes; it removes inverse scaling on `--release` JSON when `AETHER_WORKERS>1`.
- `wrk` socket read errors remain Aether-only (QBE ping 1678 / echo 749; `--release` ping 1648 / echo 712; w8 ping 1146 / echo 741). Nest/Gin 0.

### 0.6.1 (`wrk -t4 -c40 -d8s`, darwin arm64, Nox 1.29.2) — historical

Same flags as 0.6.0. Aether: `NOX_POOL_WORKERS=1`, `AETHER_REQUEST_ID=0`, `AETHER_REQUEST_HEADERS=0`.

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| **Aether QBE** (`workers=1`) | **203 263** | **88 057** |
| Aether `--release` (`workers=1`) | 188 075 | 86 937 |
| NestJS Express | 64 792 | 51 062 |
| Gin | 189 441 | 177 275 |

vs **0.6.0** (same machine/flags): QBE ping **+28%** (159k→203k), echo **+14%** (77k→88k); `--release` ping **+270%** (51k→188k), echo **+94%** (45k→87k). Nest/Gin within noise.

Notes:

- QBE ping now **beats Gin** on this run (203k vs 189k). Echo is still ~2.0× behind Gin (88k vs 177k) — remaining G2 (JSON/string vs Gin’s single encoder).
- `--release` with process-env `NOX_POOL_WORKERS=1` is no longer 3× slower than QBE (ping 1.08×). The 0.6.0 `--release` collapse was the too-late `set_var` (CPU-sized M:N pool on a `workers=1` microbench).
- `wrk` socket read errors remain Aether-only (QBE ping 1632 / echo 691; `--release` ping 1508 / echo 680). Nest/Gin 0. See G4 in `docs/PERF_GAPS.md`.

### 0.6.0 (`wrk -t4 -c40 -d8s`, darwin arm64, Nox 1.29.0) — historical

Quiet re-run (previous 0.6.0 table was contaminated by a concurrent bench). Same flags as 0.4.1.

| Target | GET /ping req/s | POST /echo req/s |
|--------|----------------:|-----------------:|
| **Aether QBE** (`workers=1`) | **159 233** | **77 223** |
| Aether `--release` (`workers=1`) | 50 900 | 44 752 |
| NestJS Express | 65 564 | 50 512 |
| Gin | 191 404 | 180 104 |

Notes:

- QBE ping/echo matches the 0.4.1 band (ping ~160k, echo ~77k) and still beats Nest; Gin still leads both.
- LLVM `--release` M:N is **not** a free win on this single-worker JSON ping/echo path (pool overhead). It remains the supported production binary path on macOS/arm64 for shared-heap multicore, not the default bench winner.
- Aether rows showed `wrk` socket read errors (QBE ping 1271 / echo 599; `--release` ping 400 / echo 348); Nest/Gin did not.

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

See `docs/NOX_LIMITATIONS.md` §§16–19, `docs/PERF.md`, and the gap report
[`docs/PERF_GAPS.md`](PERF_GAPS.md) (G1 ping / G2 echo / G3 `--release` / G4 sockets).
