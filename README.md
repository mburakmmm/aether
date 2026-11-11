# Aether

[English](README.md) · [Türkçe](README.tr.md)

**NestJS-inspired API / backend framework for [Nox](https://github.com/mburakmmm/nox-lang).**  
Pythonic modules, closure-based DI, guards / pipes / interceptors, typed DTOs, OpenAPI + Swagger UI, WebSocket gateways, and SQLite job queues.

**Version:** 0.10.0 · **License:** MIT · **Requires Nox ≥ 2.1.52**  
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
      "ref": "v0.10.0"
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
noxc install github.com/mburakmmm/aether@v0.10.0
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
# Validates once. workers>1 clears parent AppBind; make_handle boots each worker.
aether.application.boot_for_serve(cfg, build)

def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch_from_parts(
        req.method, req.target, req.body, req.headers, req.peer_addr, cfg, build, req.conn
    )

def make_handle() -> (HttpRequest) -> HttpResponse:
    aether.application.boot_with_config(cfg, build)
    def bound(req: HttpRequest) -> HttpResponse:
        return aether.application.dispatch_from_parts(
            req.method, req.target, req.body, req.headers, req.peer_addr, cfg, build, req.conn
        )
    return bound

aether.server.print_listen(cfg, aether.server.serve_mode(cfg, False))
try:
    workers: int = aether.server.effective_workers(cfg)
    if aether.server.use_os_workers(cfg):
        nox.http.serve_multicore(cfg.port, make_handle, workers)
    else:
        nox.http.serve(cfg.port, handle)
finally:
    aether.application.finalize_serve(cfg)
```

Dogfood example: `examples/hello_api` (`GET/POST/PUT/DELETE /api/users…`).

---

## What’s new in 0.10.0

Nox floor **2.1.52**. This revision is local until it is tagged. Multicore entrypoints pass `make_handle` to `serve_multicore*`; each worker builds its own `Application` before accept. `AETHER_IPV6=1` with `AETHER_WORKERS>1` sets `nox.http.configure` `ip_family` (`1` dual-stack, `2` with `AETHER_IPV6_ONLY`). A single worker still uses `listen_v6` + `serve_fd`. Request ids and `boot_id` are UUID v7. Rate-limit windows and request-log elapsed time use a monotonic clock. Queue leases stay on wall time and UUID v4.

## What’s new in 0.9.0

Nox floor **2.0.186**. `boot_for_serve` applies `nox.http.configure` and `set_http2`. The full `handle` passes `req.conn`, so a handler can `ctx.sse()` / `ctx.stream()` and the bytes go out on that connection. `with_cookie` / `expire_cookie` emit one `Set-Cookie` per cookie. Production responses gain `nosniff`, `DENY`, and `no-referrer` unless the handler already set them. `POST /__aether/shutdown` keeps listening and answers 503. `request_shutdown` writes the drain file and stops accept. SIGTERM stops accept without the file; `finalize_serve` writes it when `serve*` returns. Benchmarks stay on HTTP/1.1.

## What’s new in 0.8.2

Nox floor **2.0.63**. A `uri` field is parsed with `nox.url.parse` (`http`/`https`, host required, IPv6 literals allowed). Query numbers accept surrounding ASCII space. String schemas accept `pattern`, `min_length`, and `max_length` (`nox.regex`). Structured logs mask secret fields. Serve signatures are unchanged.

## What’s new in 0.8.1

Nox floor **2.0.7**. Stdlib errors are English since 2.0.1. Aether’s single-field body check uses the same `nox.validate` sentences, so a scalar schema and a nested schema report the same 422 detail.

## What’s new in 0.8.0

Nox floor **2.0.0**. LLVM is the default backend. `AETHER_WORKERS>1` calls `serve_multicore` on LLVM and on QBE. On LLVM the process pool is fixed at startup, so the process must be started with `NOX_POOL_WORKERS` equal to `AETHER_WORKERS`. A mismatch is an error.

## What’s new in 0.7.2

Nox floor **1.171.2**. `nox.json.decode` / `encode` / `encode_string` are gone. Aether uses `parse`, `dump`, and `dump_string`.

## What’s new in 0.7.1

Nox floor **1.142.24**. `AETHER_IPV6=1` listens with `listen_v6` and `serve_fd` (single worker; `serve_multicore` stays IPv4). `client_ip()` strips the port from `peer_addr`, including `[ipv6]:port`.

## What’s new in 0.7.0

Nox floor **1.142.2**. JWT and base64 go through `nox.jwt` / `nox.base64` (exp, nbf, and iat stay in Aether). Query schemas accept number and bool. Error JSON includes `line`. Bound methods work as handlers: `m.get("/ping", ctl.show)`.

`HttpRequest` takes `peer_addr`. `client_ip()` uses it unless trusted `X-Forwarded-For` is set. Drain checks cache the stopping file for `AETHER_STOP_POLL_MS` (default 200). `begin_shutdown` / `clear_shutdown` still publish on the calling worker immediately.

## What’s new in 0.6.5

`boot_for_serve` / `finalize_serve` entrypoints; no idle parent Application
when `workers>1`. Coordinated graceful drain (`aether.lifecycle`): process
stopping flag, per-worker registry, 503 + `on_shutdown` per slot, opt-in
`POST /__aether/shutdown` (`AETHER_SHUTDOWN_ROUTE=1`). See `docs/SCOPE.md`.

## What’s new in 0.6.4

Worker-local Application scope proven and documented (`docs/SCOPE.md`).
`build()` must be idempotent; metrics/rate-limit are per-worker; route param
shapes (`/:id` vs `/:name`) collide at boot; `route_key` recomputed after
normalize. AppBind probe smoke in CI.

## What’s new in 0.6.3

Nox ≥ 1.29.8. `workers>1` → `serve_multicore` on `--release` (1.29.5 steal).
Dropped `AETHER_LLVM`. JSON decode arena (1.29.8) + Aether G2 path
(`ValidatedBody` keeps `JsonValue`, flat validate short-circuit, single-field
encode) + A1–A7 hot-path. Echo ≈ Gin on this microbench.

## What’s new in 0.6.2

Nox ≥ 1.29.4. `--release` used a single `nox.http.serve` (`AETHER_LLVM=1`) as a
workaround for 1.29.4 SO_REUSEPORT + non-stealable connection fibers. Superseded
by 0.6.3 / Nox 1.29.5.

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
queue lease docs, Aether vs NestJS vs Gin vs Axum benchmarks (`docs/BENCHMARKS.md`).

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
| DTO validation (`pattern`, length) | `aether.dto` |
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
| `AETHER_REQUEST_ID` | on | `0` skips `uuid4` + `X-Request-Id` |
| `AETHER_REQUEST_HEADERS` | on | `0` uses `handle_bare` (Nox skips copying request headers) |
| `AETHER_OPENAPI` | on (off in prod) | `/openapi.json`, `/docs` |
| `AETHER_RATE_LIMIT` | off | Opt-in; requires identifiable client IP (`AETHER_TRUST_X_FORWARDED_FOR` today) |
| `AETHER_CORS_ORIGINS` | `*` (dev/test); **empty in production** | Opt-in CORS: `*` or comma-separated allowlist |
| `AETHER_METRICS` | on | `0` skips status counters in `/metrics` (fair bench / hot path) |
| `AETHER_METRICS_ROUTES` | on (dev/test); **off in production** | Per-route hit counters in `/metrics` |
| `AETHER_TRUST_X_FORWARDED_FOR` | `false` | Enable only behind a trusted proxy |
| `AETHER_JOBS_DB` | `db/jobs.sqlite` | Queue SQLite path |
| `AETHER_JOB_STALE_MS` | `300000` | Stuck `running` reclaim window |
| `AETHER_MAX_BODY_BYTES` | `1048576` | Passed to `nox.http.configure`. A larger socket body is Nox’s plain-text 413 and the handler does not run. `0` keeps Nox’s 10 MiB |
| `AETHER_MAX_HEADER_BYTES` | `16384` | Request line + headers. `0` keeps the Nox default |
| `AETHER_READ_TIMEOUT_MS` | `30000` | Silence before Nox closes the read |
| `AETHER_MAX_CONNECTIONS` | `4096` | Extra connections get Nox’s 503 |
| `AETHER_DRAIN_TIMEOUT_MS` | `10000` | How long `nox.http.shutdown` waits for in-flight requests |
| `AETHER_HTTP2` | on | `0` in benchmarks (wrk is HTTP/1.1) |
| `AETHER_SECURITY_HEADERS` | off (on in production) | `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer` |
| `AETHER_LOG_LEVEL` | empty | `DEBUG` \| `INFO` \| `WARN` \| `ERROR` \| `OFF`. Empty does not call `nox.log.set_level` |

Built-in routes: `GET /health`, `GET /metrics`, and when OpenAPI is on: `GET /openapi.json`, `GET /docs`.

---

## Docs

- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Scopes (Application / Worker / Request): [docs/SCOPE.md](docs/SCOPE.md)
- Nox limitations (upstream evidence): [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md)
- Queue leases / at-least-once: [docs/QUEUE.md](docs/QUEUE.md)
- Benchmarks (Aether vs NestJS vs Gin vs Axum): [docs/BENCHMARKS.md](docs/BENCHMARKS.md)
- Perf notes: [docs/PERF.md](docs/PERF.md)

## Serve note

A single worker passes a **bare top-level** `handle` to `serve`. `workers>1` passes a bare top-level `make_handle` to `serve_multicore*`. That name has to live in the application entry. Do not wrap `dispatch` inside `aether.server.listen(...)`.

Do **not** close over `Application` (`dispatch(app, req)`). The factory calls `boot_with_config`, then the closure it returns calls
`dispatch_from_parts(method, target, body, headers, peer_addr, cfg, build, conn)`. Pass `""` instead of `req.peer_addr` on a throughput
handle so Nox skips the peer-string retain. `dispatch_ensure` still boots an empty slot when the entry used a bare `handle`. See [docs/SCOPE.md](docs/SCOPE.md).

Production: `AETHER_WORKERS=4 NOX_POOL_WORKERS=4 noxc build -o app && ./app`
(Nox ≥ 2.1.52, macOS/arm64). `--release` aynı LLVM backend’inin optimize halidir. Dev: `./run.sh`. `AETHER_IPV6=1` with one worker uses `listen_v6`. With `AETHER_WORKERS>1` the same flag is `ip_family` on `serve_multicore*`. Pass `req.conn` from the full `handle`. `handle_bare` leaves `conn` at 0.

## License

MIT
