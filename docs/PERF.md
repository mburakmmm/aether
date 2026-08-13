# Aether performance notes

## Defaults

- Development / test: `AETHER_WORKERS=1` (single `nox.http.serve`), `noxc run` (QBE)
- Production: `AETHER_WORKERS` defaults to **1**. Set `AETHER_WORKERS>1` for multicore.
- Production binary (Nox 1.29+, macOS/arm64): `noxc build --release -o app && ./app`
- Prefer bare `handle` + `dispatch_ensure` (do not close over `Application`)
- Production CORS is **off** unless `AETHER_CORS_ORIGINS` is set (largest hot-path win)
- Production route metrics off unless `AETHER_METRICS_ROUTES=1`

## Dual runtime (Nox 1.29+)

| Path | Command | Scheduler | AppBind |
|------|---------|-----------|---------|
| QBE (default) | `noxc run` / `noxc test` / `noxc build` | M:1 fiber per OS thread; shared-nothing | Fresh per worker → `dispatch_ensure` boots |
| LLVM `--release` | `noxc build --release` | Shared M:N work-stealing + atomic ARC | Shared `rt`; `dispatch_ensure` is a no-op after main boot |

`--release` is comprehensively supported on **macOS/arm64**. Linux/Windows LLVM is not a production claim.

Under `--release`, `serve_multicore(port, handle, N)` **flattens** into `$main`'s pool and may ignore `N`. Call `aether.server.apply_pool_workers(cfg)` so `NOX_POOL_WORKERS` matches `AETHER_WORKERS`.

## Hot path (0.4.1+)

- Route lists indexed by method at boot (`rebuild_route_index`)
- Empty guard/pipe/interceptor lists short-circuit
- Query string parsed lazily (`ensure_query` / first `query_param`)
- Finalize writes `X-Request-Id` (+ CORS when enabled) in **one** `with_headers` copy
- `cors_origins=*` does not read the `Origin` request header
- Status metrics always; per-route hits optional

## Multicore

```nox
def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch_ensure(req, cfg, build)

workers: int = aether.server.effective_workers(cfg)
aether.server.apply_pool_workers(cfg)
if workers > 1:
    nox.http.serve_multicore(cfg.port, handle, workers)
```

- **QBE:** in-memory `RateStore` / `Metrics` / WS hubs are **worker-local** (safe).
- **`--release`:** they share one heap and are **not mutex-protected**. Keep production rate-limit off; use SQLite queue / external store for cross-core work.

Default remains `AETHER_WORKERS=1`.

## Bench

See [BENCHMARKS.md](BENCHMARKS.md) for Aether vs NestJS vs Gin (`benchmarks/run.sh`).

```sh
# QBE (dev / CI)
AETHER_ENV=production AETHER_WORKERS=1 AETHER_PORT=3000 AETHER_OPENAPI=0 \
  AETHER_CORS_ORIGINS= AETHER_METRICS_ROUTES=0 \
  noxc run benchmarks/aether/main.nox

# LLVM --release (macOS/arm64 production path)
AETHER_ENV=production AETHER_WORKERS=1 AETHER_PORT=3000 AETHER_OPENAPI=0 \
  AETHER_CORS_ORIGINS= AETHER_METRICS_ROUTES=0 \
  noxc build --release -o /tmp/aether-bench benchmarks/aether/main.nox
/tmp/aether-bench
```
