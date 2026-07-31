# Changelog

## 0.3.0 — 2026-07-31

API ergonomics and safer gateway defaults.

- `ValidatedBody` / `ctx.input_str|int|bool` / `ctx.validated_body()`
- `RouteOptions` + `m.route(method, path, handler, opts)`
- Guards: `api_key_header`, `require_header` (plus existing bearer)
- `aether.logx` structured JSON logs
- Metrics include per-route hit counts
- OpenAPI: standard 4xx/5xx responses + `bearerAuth` / `apiKeyAuth` schemes
- WebSocket rooms opt-in (`enable_rooms` + `set_room_auth`); message size limit

## 0.2.1 — 2026-07-31

Correctness hardening (no new feature surface).

- Response finalizers always apply `X-Request-Id` + CORS (error and success)
- Interceptor early-return unwinds only entered frames (`entered_count`)
- Request-scoped values moved to TaskLocal `RequestState` (Container is names-only)
- Production rate-limit default **off**; empty client IP skips limiting; bucket eviction
- CORS allowlist + `Vary: Origin`; single OPTIONS path in `dispatch`
- Metrics are per-`Application` (not process-global)
- Boot rejects duplicate routes; provider name duplicates rejected
- Queue lease tokens on reserve/complete/fail; reclaim increments lease failures → DLQ
- Docs: DI/`provide(name)` wording aligned in `NOX_LIMITATIONS.md`

## 0.2.0 — 2026-07-31

Hardening and Nest-shaped API surface for production HTTP services.

- Modules: `prefix`, `import_module`, `put_body` / `delete_documented`, exception filters
- HTTP: CORS, body limit (413), rate limit (429), 405, trailing-slash normalize, interceptor short-circuit
- Context: case-insensitive headers, query helpers, opt-in `trust_x_forwarded_for` → `client_ip`
- DTO: runtime `email` / `uuid` / `uri` formats and number ranges
- OpenAPI: nested `$ref`, success status codes, Swagger UI at `/docs`
- Queue: stale `running` reclaim, DLQ list / requeue / `mark_dead`
- Gateway: rooms, broadcast, token auth helper; template `ws.nox`
- Metrics at `/metrics`; CLI reads `VERSION`; hello_api CRUD under `/api`

## 0.1.0

Initial Aether release: application boot, modules, closure DI, guards/pipes/interceptors, DTO, OpenAPI, gateway, queue, CLI scaffold.
