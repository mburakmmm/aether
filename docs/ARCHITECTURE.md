# Aether Architecture

Aether is a NestJS-inspired API/backend framework for [Nox](https://github.com/mburakmmm/nox-lang) (≥ 2.1.186).
It is independent of Nyx (the Rails-style full-stack framework).

## Design

- **Pythonic modules:** `class UsersModule: def configure(self, m: ModuleBuilder)`
- **Official DI = closures:** `m.provide("Name")` is a **name registry only**. Hold service instances in module fields/locals and capture them when registering handlers (`m.get(..., self._show(svc))`). An imported class can be a base (`class Mine(HttpError)`), but `class_init_param_type` returns a mangled name, so Aether does not wire constructors from reflect.
- **Module import:** `app.import_module(configure)` / `app.import_configure(configure)`; `m.prefix("/api")` for path prefixes
- **Top-level route decorators** (optional): `@get` / `@post` + `mount_decorators` (still run through `dispatch` pipeline)
- **Custom pipeline:** Guard → Pipe → Interceptor (before may short-circuit) → Handler → Interceptor after → exception filters

## Request flow

1. A single worker passes a bare `handle` to `serve` / `serve_fd`. `workers>1` passes a top-level zero-arg `make_handle` to `serve_multicore*`; Nox calls it once inside each worker and the closure it returns calls `dispatch_from_parts`. Do not pass `req` through. Omit `peer_addr` (pass `""`) when the handler must not retain the peer string. `handle_bare` does not read headers, peer, or `conn` (`conn` stays 0). Streaming needs the full handle. The factory has to be a bare name in the application entry; `aether.server.something` is not a factory.
2. `application.dispatch` → normalize path → body limit / CORS OPTIONS / 405 → match → `HttpContext` + `TaskLocal`
3. Global + route guards
4. Input pipes / DTO validation (including format checks)
5. Interceptors (before; may return early)
6. Handler
7. Interceptors (after)
8. Exception filters, then structured `HttpError` / fallback JSON errors
9. Metrics + request log

## Package layout

Flat root `.nox` modules (`import aether.application`). Shared mutable route/hook state lives in `RouteTable` and `HookState` (list assignment does not share across holders in Nox).

## Optional C libraries

`nox.yyjson`, `nox.brotli`, `nox.lz4`, and `nox.zstd.compress` live in `noxclibs`. Nox links that archive only when the program imports the module. Aether’s core imports none of them.

The serve entry opts in:

```nox
import aether.engine_yyjson
import aether.engine_brotli
```

Module init arms a hook on that worker’s globals. `serve_multicore` re-runs init, so each worker arms its own hook. `AETHER_JSON` and `AETHER_BODY_CODECS` choose the hook per `Config`. The choice is not a process-wide mutable flag.

yyjson covers the scalar body path (one required string, or a flat string/number/bool object) and stores the fields in `ValidatedBody` caches. It does not become the framework’s JSON type. OpenAPI, JWT, the queue, and nested or pattern schemas stay on `nox.json` / `nox.validate` / `nox.regex`. `nox.pcre2` stays an application import for the same reason: a second pattern dialect would change 422 sentences and asks for the `dynamic_code` capability.

`AETHER_HTTP3=1` is `nox.http.set_http3` before TLS serve. It is one UDP socket, so `AETHER_WORKERS` stays 1. WebSocket is not carried on HTTP/3. `peer_addr` is empty on QUIC.

See README for the full module table.

## Performance

- Boot-time route/guard/pipe binding
- OpenAPI built once at boot
- `dispatch_from_parts(...)` when serving; export `NOX_POOL_WORKERS` before exec
- Default `AETHER_WORKERS=1`
- QBE (`noxc run`): shared-nothing `serve_multicore` (SO_REUSEPORT when `workers>1`)
- `--release` (`noxc build --release`, macOS/arm64): shared M:N heap + stealable connection fibers; **module globals / Application remain per worker slot**
- In-memory `RateStore` / `Metrics` / closure services are **worker-local** (not process-wide). See [SCOPE.md](SCOPE.md).
