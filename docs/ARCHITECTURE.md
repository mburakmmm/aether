# Aether Architecture

Aether is a NestJS-inspired API/backend framework for [Nox](https://github.com/mburakmmm/nox-lang) (≥ 1.26.0).
It is independent of Nyx (the Rails-style full-stack framework).

## Design

- **Pythonic modules:** `class UsersModule: def configure(self, m: ModuleBuilder)`
- **Official DI = closures:** `m.provide("Name")` is a **name registry only**. Hold service instances in module fields/locals and capture them when registering handlers (`m.get(..., self._show(svc))`). Cross-module `class X(Injectable)` is impossible in Nox today.
- **Module import:** `app.import_module(configure)` / `app.import_configure(configure)`; `m.prefix("/api")` for path prefixes
- **Top-level route decorators** (optional): `@get` / `@post` + `mount_decorators` (still run through `dispatch` pipeline)
- **Custom pipeline:** Guard → Pipe → Interceptor (before may short-circuit) → Handler → Interceptor after → exception filters

## Request flow

1. Bare `handle(req)` (Nox `serve*` requirement)
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

See README for the full module table.

## Performance

- Boot-time route/guard/pipe binding
- OpenAPI built once at boot
- Prefer `serve_multicore` in production
- Per-worker memory (Nox multicore does not share ARC heaps)
