# Aether performance notes

## Defaults

- Development / test: `AETHER_WORKERS=1` (single `nox.http.serve`)
- Production: `AETHER_WORKERS` defaults to **1** (`effective_workers`). Set `AETHER_WORKERS>1` for
  supported multicore via `serve_multicore` + `dispatch_ensure(req, cfg, build)`.
- Prefer bare `handle` + `dispatch_ensure` (do not close over `Application`)
- Production CORS is **off** unless `AETHER_CORS_ORIGINS` is set (largest hot-path win)
- Production route metrics off unless `AETHER_METRICS_ROUTES=1`

## Hot path (0.4.1+)

- Route lists indexed by method at boot (`rebuild_route_index`)
- Empty guard/pipe/interceptor lists short-circuit
- Query string parsed lazily (`ensure_query` / first `query_param`)
- Finalize writes `X-Request-Id` (+ CORS when enabled) in **one** `with_headers` copy
- `cors_origins=*` does not read the `Origin` request header
- Status metrics always; per-route hits optional

## Multicore (supported, 0.5.0+)

Each `serve_multicore` worker gets a **fresh** module-global copy (non-atomic ARC). Main-thread
`AppBind` is not visible to workers. Entrypoints must use:

```nox
def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch_ensure(req, cfg, build)
```

so each worker boots its own `Application` on first use. In-memory rate limits, metrics, and WS
hubs stay **worker-local**. Use `aether.queue` (SQLite file) for cross-worker work.

Default remains `AETHER_WORKERS=1`; multicore is opt-in, not experimental.

## Bench

See [BENCHMARKS.md](BENCHMARKS.md) for Aether vs NestJS vs Gin (`benchmarks/run.sh`).

```sh
AETHER_ENV=production AETHER_WORKERS=1 AETHER_PORT=3000 AETHER_OPENAPI=0 \
  AETHER_CORS_ORIGINS= AETHER_METRICS_ROUTES=0 \
  noxc run benchmarks/aether/main.nox
```
