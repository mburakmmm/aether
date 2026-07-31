# Changelog

## 0.4.2 — 2026-07-31

Production correctness (no new feature surface).

- `effective_workers` / production default **1** (AppBind unsafe under multicore until per-worker boot)
- Queue `complete`/`fail` require UPDATE changes == 1 (no false success after another worker completes)
- Route metrics keys use `METHOD + pattern` (not raw path) to bound cardinality
- `RateStore` is per-interceptor instance (not process-global)
- `ValidatedBody` parses once; `HttpContext.validated_body()` caches per request
- Query/header pipes reject non-string schema fields at registration
- Bearer / API key / JWT guards use constant-time compare + generic 401 messages
- CI HTTP smoke (`scripts/smoke_http.sh`)

## 0.4.1 — 2026-07-31

Hot-path performance (production-safe).

- Production CORS default **off** (empty); set `AETHER_CORS_ORIGINS` to enable (`*` or allowlist). Dev/test still default `*`
- `*` CORS skips `Origin` header read; finalize applies `X-Request-Id` + CORS in **one** header copy (`with_headers`)
- Lazy query parse (`HttpContext.ensure_query`)
- Route hit metrics opt-in via `AETHER_METRICS_ROUTES` (off in production by default; status counters always on)
- Method-bucket route index + empty guard/pipe/interceptor short-circuit
- Dispatch no longer allocates a dummy 500 on every request

## 0.4.0 — 2026-07-31

Query/header validation, JWT HS256 primitives, queue docs, cross-stack benchmarks.

- Query + header DTO pipes via `RouteOptions` (`has_query` / `has_headers`) + OpenAPI `parameters`
- `aether.base64` + `aether.jwt` (HS256); `jwt_bearer(secret)` guard; `ctx.jwt_claims()`
- `ctx.query_json` / `ctx.header_json` after validation pipes
- `bind` / `dispatch_bound` / `shutdown_bound` — serve handlers must not close over `Application` (Nox codegen)
- Queue at-least-once / lease semantics: [docs/QUEUE.md](docs/QUEUE.md)
- Benchmarks: Aether vs NestJS vs Gin — [docs/BENCHMARKS.md](docs/BENCHMARKS.md), `benchmarks/`
- Nox limitations §§16–19 (base64/JWT, string query maps, hot-path JSON, serve+Application capture)

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
