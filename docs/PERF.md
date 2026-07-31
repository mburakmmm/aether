# Aether performance notes

## Defaults

- Development / test: `AETHER_WORKERS=1` (single `nox.http.serve`)
- Production: set `AETHER_WORKERS=0` (auto → 2) or an explicit count and use `nox.http.serve_multicore`
- Prefer bare `handle` at the call site (Nox intrinsic requirement)

## Hot path

- Route/guard/pipe/interceptor lists are bound at boot (via `RouteTable` / `HookState`)
- OpenAPI document is built once at boot; `GET /openapi.json` returns the cached string
- One `HttpContext` allocation per request; `TaskLocal` request bag cleared in `finish()`
- Response helpers copy bodies with `+ ""` where module-global strings might otherwise UAF under ARC

## Multicore

Each `serve_multicore` worker gets a **fresh** module-global copy (non-atomic ARC). In-memory gateway hubs and containers are process-local. Use `aether.queue` (SQLite) for cross-worker background work.

## Bench

```sh
AETHER_ENV=production AETHER_WORKERS=4 AETHER_PORT=3000 noxc run examples/hello_api/main.nox
# then point nox-bench / wrk at GET /health and GET /users/1
```
