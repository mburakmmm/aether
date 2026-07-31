# Aether Architecture

Aether is a NestJS-inspired API/backend framework for [Nox](https://github.com/mburakmmm/nox-lang) (≥ 1.26.0).
It is independent of Nyx (the Rails-style full-stack framework).

## Design

- **Pythonic modules:** `class UsersModule: def configure(self, m: ModuleBuilder)`
- **Closure DI:** providers via `m.provide(name, injectable)`; handlers capture services
- **Top-level route decorators** (optional): `@get` / `@post` + `mount_decorators`
- **Custom pipeline:** Guard → Pipe → Interceptor → Handler (owned by Aether, not `nox.router` next-chains)

## Request flow

1. Bare `handle(req)` (Nox `serve*` requirement)
2. `application.dispatch` → path match → `HttpContext` + `TaskLocal`
3. Global + route guards
4. Input pipes / DTO validation
5. Interceptors (before)
6. Handler
7. Interceptors (after)
8. Structured `HttpError` / fallback JSON errors

## Package layout

Flat root `.nox` modules (`import aether.application`). Shared mutable route/hook state lives in `RouteTable` and `HookState` (list assignment does not share across holders in Nox).

See README for the full module table.

## Performance

- Boot-time route/guard/pipe binding
- OpenAPI built once at boot
- Prefer `serve_multicore` in production
- Per-worker memory (Nox multicore does not share ARC heaps)
