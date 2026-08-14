# Aether

[English](README.md) · [Türkçe](README.tr.md)

**NestJS-inspired API / backend framework for [Nox](https://github.com/mburakmmm/nox-lang).**  
Pythonic modules, closure-based DI, guards / pipes / interceptors, typed DTOs, OpenAPI + Swagger UI, WebSocket gateways, and SQLite job queues.

**Version:** 0.6.2 · **License:** MIT · **Requires Nox ≥ 1.29.4**  
Package name: `aether` · Repo: [github.com/mburakmmm/aether](https://github.com/mburakmmm/aether)

> Independent of [Nyx](https://github.com/mburakmmm/nyx) (Rails-style full-stack). Use **Aether** for HTTP APIs; use **Nyx** for monolithic HTML apps.

---

## Install (Nox package)

Add to your app’s `nox.json`:

```json
{
  "name": "myapi",
  "entry": "main.nox",
  "requires": [
    {
      "alias": "aether",
      "repo": "github.com/mburakmmm/aether",
      "ref": "v0.6.2"
    }
  ]
}
```

```sh
noxc fetch
AETHER_ENV=development AETHER_WORKERS=1 NOX_POOL_WORKERS=1 noxc run main.nox
```

### Local path (development)

```json
{ "alias": "aether", "repo": "/absolute/path/to/aether", "ref": "master" }
```

### CLI scaffold

```sh
noxc install github.com/mburakmmm/aether@v0.6.2
aether new myapi
cd myapi && noxc fetch && chmod +x run.sh && ./run.sh
```

---

## Quick start

```nox
import nox.http
from nox.http import HttpRequest, HttpResponse
import aether.application
import aether.server
import aether.config
from aether.application import Application
from aether.config import Config
from aether.module import ModuleBuilder
from aether.context import HttpContext
from aether.response import json_ok

class HealthModule:
    def configure(self: HealthModule, m: ModuleBuilder) -> None:
        m.get("/healthz", self._health())

    def _health(self: HealthModule) -> (HttpContext) -> HttpResponse:
        def health(ctx: HttpContext) -> HttpResponse:
            return json_ok("{\"status\":\"ok\"}")
        return health

def build(app: Application) -> None:
    HealthModule().configure(app.module())

cfg: Config = aether.config.load()
app: Application = aether.application.boot_with_config(cfg, build)

def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch_from_parts(
        req.method, req.target, req.body, req.headers, cfg, build
    )

aether.server.print_listen(cfg, aether.server.serve_mode(cfg, False))
try:
    workers: int = aether.server.effective_workers(cfg)
    if aether.server.use_os_workers(cfg):
        nox.http.serve_multicore(cfg.port, handle, workers)
    else:
        nox.http.serve(cfg.port, handle)
finally:
    aether.application.shutdown_bound()
```

Dogfood example: `examples/hello_api` (`GET/POST/PUT/DELETE /api/users…`).

---

## What’s new in 0.6.2

Nox ≥ 1.29.4. `--release` uses a single `nox.http.serve` (`AETHER_LLVM=1` from
`./run-release.sh`); QBE `workers>1` keeps `serve_multicore` (SO_REUSEPORT).
Do not flatten `serve_multicore` into the M:N pool — N independent accept loops
destroy steal.

## What’s new in 0.6.1

Nox ≥ 1.29.3. Export `NOX_POOL_WORKERS=$AETHER_WORKERS` **before** exec (`./run.sh`).
One JSON decode per validated body. `dispatch_from_parts` + `handle_bare` for
header-skip. `AETHER_REQUEST_ID=0` / `AETHER_REQUEST_HEADERS=0` for ping benches.

## What’s new in 0.6.0

Nox ≥ 1.29.0 dual runtime: QBE (`noxc run`) stays shared-nothing; production
`noxc build --release` uses the LLVM M:N pool (macOS/arm64). In-memory rate-limit
is not thread-safe under `--release`.

## What’s new in 0.5.0

Supported multicore: `dispatch_ensure(req, cfg, build)` boots each `serve_multicore`
worker’s `AppBind`. Default `AETHER_WORKERS=1`; set `>1` for production multicore.
In-memory rate limits / metrics / WS hubs remain worker-local.

## What’s new in 0.4.4

Order-independent recursive DTO fingerprints, reclaim batch limit, two-connection
queue contention tests, trailing-slash route normalize, tag release remote smoke.

## What’s new in 0.4.3

Atomic stale reclaim, framework-route / DTO-name boot collisions, release-ref checks
and package-install smoke (tag only after `nox.lock` matches `VERSION`).

## What’s new in 0.4.2

Production correctness: workers default 1, queue lease affected-row checks, pattern
metrics keys, instance RateStore, body parse cache, string-only query/header schemas,
constant-time auth helpers, HTTP smoke CI.

## What’s new in 0.4.1

Hot-path speedups: production CORS opt-in, single header finalize copy, lazy query
parse, optional route metrics, method-indexed routes. See `docs/PERF.md`.

## What’s new in 0.4.0

Query/header schema validation + OpenAPI params, HS256 JWT (`aether.jwt` / `jwt_bearer`),
queue lease docs, Aether vs NestJS vs Gin benchmarks (`docs/BENCHMARKS.md`).

## What’s new in 0.3.0

API ergonomics: `ValidatedBody` / `RouteOptions`, structured logs, route metrics,
safer WS room defaults, OpenAPI 4xx/5xx + security schemes.

## What’s new in 0.2.0

- Path prefix, `import_module`, exception filters
- CORS, body size limit, rate limit, 405, trailing-slash normalize
- OpenAPI `$ref` + success statuses, Swagger UI at `/docs`
- DTO format checks (`email` / `uuid` / `uri`) and number ranges
- Trusted `X-Forwarded-For` → `client_ip` (opt-in)
- Queue stale reclaim + DLQ (`list_dead` / `requeue_dead` / `mark_dead`)
- WebSocket rooms / broadcast + token auth helper
- In-process metrics at `/metrics`

---

## Features

| Feature | Module |
|---------|--------|
| Boot / dispatch / filters | `aether.application` |
| Modules, routes, prefix | `aether.module` |
| Provider **name** registry | `aether.container` |
| Context (query / header / IP) | `aether.context` |
| Guards / pipes / interceptors | `aether.guard`, `pipe`, `interceptor` |
| JWT HS256 | `aether.jwt`, `jwt_bearer` |
| Base64 (URL) | `aether.base64` |
| DTO validation | `aether.dto` |
| Structured errors | `aether.errors` |
| OpenAPI 3 + Swagger UI | `aether.openapi`, `aether.swagger` |
| CORS / rate limit / metrics | `aether.cors`, `rate_limit`, `metrics` |
| WebSocket gateway + rooms | `aether.gateway` |
| Jobs + reclaim + DLQ | `aether.queue` |
| Testing helpers | `aether.testing` |
| CLI | `aether` (`cli.nox`) |

### DI (official)

Nox cannot subclass imported bases. Aether uses **closure injection** + a name registry:

```nox
svc: UserService = UserService()
m.provide("UserService")                 # names only
m.get("/users/:id", self._show(svc))     # capture in closure
```

---

## Configuration

| Env | Default (dev) | Notes |
|-----|---------------|--------|
| `AETHER_ENV` | `development` | `development` \| `test` \| `production` |
| `AETHER_HOST` / `AETHER_PORT` | `0.0.0.0` / `3000` | Bind |
| `AETHER_WORKERS` | `1` | Set `>1` for multicore. Also export `NOX_POOL_WORKERS` to the same value **before** launching (`./run.sh`) |
| `NOX_POOL_WORKERS` | (unset) | Nox `--release` `$main` pool size. Read at process start — `set_var` in `main` is too late |
| `AETHER_LLVM` | unset | `1` from `./run-release.sh`: single `serve()` + M:N pool. Unset on QBE so `workers>1` uses SO_REUSEPORT |
| `AETHER_REQUEST_ID` | on | `0` skips `uuid4` + `X-Request-Id` |
| `AETHER_REQUEST_HEADERS` | on | `0` uses `handle_bare` (Nox skips copying request headers) |
| `AETHER_OPENAPI` | on (off in prod) | `/openapi.json`, `/docs` |
| `AETHER_RATE_LIMIT` | off | Opt-in; requires identifiable client IP (`AETHER_TRUST_X_FORWARDED_FOR` today) |
| `AETHER_CORS_ORIGINS` | `*` (dev/test); **empty in production** | Opt-in CORS: `*` or comma-separated allowlist |
| `AETHER_METRICS_ROUTES` | on (dev/test); **off in production** | Per-route hit counters in `/metrics` |
| `AETHER_TRUST_X_FORWARDED_FOR` | `false` | Enable only behind a trusted proxy |
| `AETHER_JOBS_DB` | `db/jobs.sqlite` | Queue SQLite path |
| `AETHER_JOB_STALE_MS` | `300000` | Stuck `running` reclaim window |

Built-in routes: `GET /health`, `GET /metrics`, and when OpenAPI is on: `GET /openapi.json`, `GET /docs`.

---

## Docs

- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Nox limitations (upstream evidence): [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md)
- Queue leases / at-least-once: [docs/QUEUE.md](docs/QUEUE.md)
- Benchmarks (Aether vs NestJS vs Gin): [docs/BENCHMARKS.md](docs/BENCHMARKS.md)
- Perf notes: [docs/PERF.md](docs/PERF.md)

## Serve note

Nox `serve*` requires a **bare top-level** `handle` / `ws_handle` name — do not wrap `dispatch` inside `aether.server.listen(...)`.

Do **not** close over `Application` in that handle (`dispatch(app, req)`). Use
`dispatch_from_parts(method, target, body, headers, cfg, build)` so the serve
handle does not escape `req`. QBE workers re-boot `AppBind`; `--release`
(macOS/arm64) shares one M:N pool sized by **process-env** `NOX_POOL_WORKERS`.

Production: `NOX_POOL_WORKERS=$AETHER_WORKERS AETHER_LLVM=1 noxc build --release -o app && ./app`
(Nox ≥ 1.29.4, macOS/arm64). Dev: `./run.sh`. Prefer `./run-release.sh`.

## License

MIT
