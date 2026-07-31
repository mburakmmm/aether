# Changelog

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
