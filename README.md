# Aether

[English](README.md) · [Türkçe](README.tr.md)

**NestJS-inspired API / backend framework for [Nox](https://github.com/mburakmmm/nox-lang).**  
Pythonic modules, closure-based DI, guards / pipes / interceptors, typed DTOs, OpenAPI + Swagger UI, WebSocket gateways, and SQLite job queues.

**Version:** 0.4.0 · **License:** MIT · **Requires Nox ≥ 1.26.0**  
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
      "ref": "v0.4.0"
    }
  ]
}
```

```sh
noxc fetch
AETHER_ENV=development noxc run main.nox
```

### Local path (development)

```json
{ "alias": "aether", "repo": "/absolute/path/to/aether", "ref": "master" }
```

### CLI scaffold

```sh
noxc install github.com/mburakmmm/aether@v0.4.0
aether new myapi
cd myapi && noxc fetch && AETHER_ENV=development noxc run main.nox
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
    return aether.application.dispatch(app, req)

aether.server.print_listen(cfg, aether.server.serve_mode(cfg, False))
try:
    workers: int = aether.server.effective_workers(cfg)
    if workers > 1:
        nox.http.serve_multicore(cfg.port, handle, workers)
    else:
        nox.http.serve(cfg.port, handle)
finally:
    aether.application.shutdown(app)
```

Dogfood example: `examples/hello_api` (`GET/POST/PUT/DELETE /api/users…`).

---

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
| `AETHER_OPENAPI` | on (off in prod) | `/openapi.json`, `/docs` |
| `AETHER_RATE_LIMIT` | off | Opt-in; requires identifiable client IP (`AETHER_TRUST_X_FORWARDED_FOR` today) |
| `AETHER_CORS_ORIGINS` | `*` | `*` or comma-separated allowlist (reflects request `Origin`, sets `Vary`) |
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

## License

MIT
