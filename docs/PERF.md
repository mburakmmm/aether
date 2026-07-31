# Aether performance notes

## Defaults

- Development / test: `AETHER_WORKERS=1` (single `nox.http.serve`)
- Production: `AETHER_WORKERS` defaults to **1** (`effective_workers`). Multicore requires an explicit `AETHER_WORKERS>1` and is experimental until per-worker boot exists for `AppBind`.
- Prefer bare `handle` + `dispatch_bound` (do not close over `Application`)
- Production CORS is **off** unless `AETHER_CORS_ORIGINS` is set (largest hot-path win)
- Production route metrics off unless `AETHER_METRICS_ROUTES=1`

## Hot path (0.4.1+)

- Route lists indexed by method at boot (`rebuild_route_index`)
- Empty guard/pipe/interceptor lists short-circuit
- Query string parsed lazily (`ensure_query` / first `query_param`)
- Finalize writes `X-Request-Id` (+ CORS when enabled) in **one** `with_headers` copy
- `cors_origins=*` does not read the `Origin` request header
- Status metrics always; per-route hits optional

## Multicore

Each `serve_multicore` worker gets a **fresh** module-global copy (non-atomic ARC). `AppBind` / in-memory hubs are process-local per worker and may be empty unless each worker re-boots. Prefer `AETHER_WORKERS=1` until Nox provides per-worker init; use `aether.queue` (SQLite) for cross-worker work.

## Bench

See [BENCHMARKS.md](BENCHMARKS.md) for Aether vs NestJS vs Gin (`benchmarks/run.sh`).

```sh
AETHER_ENV=production AETHER_WORKERS=1 AETHER_PORT=3000 AETHER_OPENAPI=0 \
  AETHER_CORS_ORIGINS= AETHER_METRICS_ROUTES=0 \
  noxc run benchmarks/aether/main.nox
```
