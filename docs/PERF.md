# Aether performance notes

## Defaults

- Development / test: `AETHER_WORKERS=1` (single `nox.http.serve`), `noxc run` (QBE)
- Production: `AETHER_WORKERS` defaults to **1**. Set `AETHER_WORKERS>1` for multicore.
- Production binary (Nox 1.29.8+, macOS/arm64): `NOX_POOL_WORKERS=$AETHER_WORKERS noxc build --release -o app && ./app`
- Prefer `handle` that reads `req.method/target/body/headers` and calls `dispatch_from_parts` (do not pass `req` — that disables Nox header-skip)
- Export `NOX_POOL_WORKERS` **before** exec (`scripts/aether_env.sh`, `./run.sh`). `apply_pool_workers` cannot resize the `--release` `$main` pool.
- Production CORS is **off** unless `AETHER_CORS_ORIGINS` is set (largest hot-path win)
- Production route metrics off unless `AETHER_METRICS_ROUTES=1`; status counters off with `AETHER_METRICS=0`

## Dual runtime (Nox 1.29+)

| Path | Command | Scheduler | AppBind |
|------|---------|-----------|---------|
| QBE (default) | `noxc run` / `noxc test` / `noxc build` | M:1 fiber per OS thread; shared-nothing | Fresh per worker → `dispatch_ensure` boots |
| LLVM `--release` | `noxc build --release` | Shared M:N work-stealing + atomic ARC | Shared `rt`; `dispatch_ensure` is a no-op after main boot |

`--release` is comprehensively supported on **macOS/arm64**. Linux/Windows LLVM is not a production claim.

Under `--release`, `serve_multicore(port, handle, N)` flattens into `$nox_pool_serve`.
Nox **1.29.5+** pushes accepted connection fibers onto the work-stealing deque
(SO_REUSEPORT imbalance can be corrected by steal). Size the pool with process-env
`NOX_POOL_WORKERS=$AETHER_WORKERS`. QBE and `--release` both use
`aether.server.use_os_workers` → `serve_multicore` when `workers>1`.

## Hot path (0.6.3+)

- Route lists indexed by method at boot (`rebuild_route_index`)
- Static routes: exact `pattern == path` before param `split` (A1)
- Path normalized once in `dispatch`, reused by match + `HttpContext` (A2)
- Empty guard/pipe/interceptor lists short-circuit
- Query string parsed lazily (`ensure_query` / first `query_param`)
- Shared JSON `Content-Type` map; `apply_headers` copy-on-writes (A7); `AETHER_REQUEST_ID=0` skips uuid
- Validated body: lazy until first use; one `nox.json.decode` when pipe hands `JsonValue` (A3/G2)
- TaskLocal `begin`/`finish` only when request-id or access log is on (A4)
- `json_ok_str` / `encode_str_map` via `nox.strings.join` (+ single-field fast path)
- `cors_origins=*` does not read the `Origin` request header
- Status metrics opt-out (`AETHER_METRICS=0`); per-route hits optional (`AETHER_METRICS_ROUTES`)

## Multicore

```nox
def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch_from_parts(
        req.method, req.target, req.body, req.headers, cfg, build
    )

workers: int = aether.server.effective_workers(cfg)
if aether.server.use_os_workers(cfg):
    nox.http.serve_multicore(cfg.port, handle, workers)
else:
    nox.http.serve(cfg.port, handle)
```

- **QBE:** in-memory `RateStore` / `Metrics` / WS hubs are **worker-local** (safe).
- **`--release`:** they share one heap and are **not mutex-protected**. Keep production rate-limit off; use SQLite queue / external store for cross-core work.

Default remains `AETHER_WORKERS=1`.

## Bench

See [BENCHMARKS.md](BENCHMARKS.md) for Aether vs NestJS vs Gin (`benchmarks/run.sh`).

```sh
# QBE (dev / CI) — pool env required for apples-to-apples --release later
AETHER_ENV=production AETHER_WORKERS=1 NOX_POOL_WORKERS=1 AETHER_PORT=3000 \
  AETHER_OPENAPI=0 AETHER_CORS_ORIGINS= AETHER_METRICS=0 AETHER_METRICS_ROUTES=0 \
  AETHER_REQUEST_ID=0 AETHER_REQUEST_HEADERS=0 \
  noxc run benchmarks/aether/main.nox

# LLVM --release (macOS/arm64 production path)
AETHER_ENV=production AETHER_WORKERS=1 NOX_POOL_WORKERS=1 \
  AETHER_PORT=3000 \
  AETHER_OPENAPI=0 AETHER_CORS_ORIGINS= AETHER_METRICS=0 AETHER_METRICS_ROUTES=0 \
  AETHER_REQUEST_ID=0 AETHER_REQUEST_HEADERS=0 \
  noxc build --release -o /tmp/aether-bench benchmarks/aether/main.nox
/tmp/aether-bench
```
