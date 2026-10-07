# Changelog

## 0.7.1 — 2026-10-07

Nox floor **1.142.24**.

- `AETHER_IPV6=1` listens with `nox.http.listen_v6` and `serve_fd` (`AETHER_IPV6_ONLY` sets `v6_only`). `AETHER_WORKERS>1` and `AETHER_WS` reject that mode because `serve_multicore` still binds IPv4
- `client_ip()` returns the host from `peer_addr` (`a.b.c.d:port` and `[ipv6]:port`)
- Route lists use chained `append` (`table.routes.append`, `app.route_table.routes.append`)
- `--release` decorator metadata is available from Nox 1.142.7. No Aether API change

## 0.7.0 — 2026-10-06

Nox floor **1.142.2**. Adopt stdlib that closed the Aether limitation list in Nox 1.125–1.142. Unpublished 0.6.6 drain and peer work ships here.

- CI / release install `NOX_VERSION=v1.142.2`
- `aether.jwt` signs and verifies with `nox.jwt` and still enforces exp, nbf, and iat
- `aether.base64` delegates to `nox.base64`
- `error_json` includes `Exception.line`
- `DtoSchema` registers nested objects, typed arrays, min/max, and email/uuid format on `nox.validate.Schema`. `uri` stays in Aether
- Query schemas accept string, number, and bool (`nox.url.query_float` / `query_bool`). Headers stay strings
- Multi-key `encode_str_map` uses `nox.json.JsonWriter`. One key stays a concatenation
- `run_pipes` / `run_guards` call `list[i](ctx)`. Bound methods are valid handlers (`m.get(path, ctl.show)`)
- `is_stopping` caches the drain stat for `AETHER_STOP_POLL_MS` (default 200). `begin_shutdown` / `clear_shutdown` publish on the calling worker immediately
- `dispatch_from_parts` takes `peer_addr`. `HttpContext.client_ip()` uses it unless trusted `X-Forwarded-For` is set
- Bench harness adds **Axum** (`benchmarks/axum`)
- Still open: dotted type annotations; `serve_multicore*` closures; object sharing beyond `nox.atomic`. See `docs/NOX_LIMITATIONS.md`

## 0.6.5 — 2026-08-14

Serve entrypoints + coordinated graceful drain.

- `boot_for_serve(cfg, build)`: validate once; when `workers>1` `release_bound()` so no idle parent AppBind (siblings still boot via `dispatch_ensure`)
- `finalize_serve(cfg)`: set process drain flag + `release_bound` after `serve*` returns
- `shutdown_bound()`: slot-local hooks, keeps closed Application bound (no rebuild during drain); `release_bound()` clears AppBind
- `aether.lifecycle`: file-backed stopping flag + per-worker registry (`/tmp/aether-life-<port>/…` or `AETHER_LIFECYCLE_DIR/<port>/…`)
- While stopping: request traffic → **503** then slot-local `on_shutdown`; `/health` → 503
- Opt-in `POST /__aether/shutdown` (`AETHER_SHUTDOWN_ROUTE=1`); `await_workers_drained`
- Scaffolds / hello_api / benches use `boot_for_serve` + `finalize_serve`; see `docs/SCOPE.md`


## 0.6.4 — 2026-08-14

Worker-local Application semantics (proven) + boot correctness.

- Document **Application / Worker / Request** scopes (`docs/SCOPE.md`); fix AppBind comments that claimed `--release` shared Application
- `build()` must be idempotent; parent boot does not fill sibling worker slots; `shutdown_bound` is slot-local
- `Metrics.to_json` includes `"scope":"worker"`; rate-limit docs describe N×max effective cap
- Boot rejects param **route-shape** collisions (`GET /users/:id` vs `GET /users/:name`)
- Recompute `route_key` / `is_static` after pattern normalize
- Worker AppBind probe (`benchmarks/worker_probe`, `scripts/smoke_worker_bind.sh`) in CI

## 0.6.3 — 2026-08-14

Nox 1.29.8 floor; restore `--release` `serve_multicore`; close remaining Aether echo tax (G2 + A1–A7).

- Floor Nox **1.29.8** (1.29.5 steal; 1.29.6 TLS; 1.29.8 `nox.json.decode` threadlocal arena)
- Remove `AETHER_LLVM`: `workers>1` → `serve_multicore` on QBE and `--release`
- Still export `NOX_POOL_WORKERS=$AETHER_WORKERS` before exec
- **G2 Aether path:** `ValidatedBody` keeps decoded `JsonValue` (no parallel-array re-walk); skip `validate_value` extra field pass when `schema.flat()` suffices; single-field `encode_str_map` fast path
- **A1:** Static routes match with exact `pattern == path` (no `split`) before param patterns
- **A2:** Path normalized once in `dispatch`; passed into `find_route_indexed` + `HttpContext`
- **A3:** `ValidatedBody` lazy via shared `_EMPTY_BODY` sentinel (ping allocates none)
- **A4:** TaskLocal `begin`/`finish` only when `request_id` or `log_requests`; `EMPTY_VALUES` + COW `set_request_value`
- **A5:** `Config.metrics` + `AETHER_METRICS` (bench/smokes set `0`; status counters opt-out)
- **A6:** `RouteDef.route_key` / `is_static` computed at route construction
- **A7:** Shared `_JSON_HEADERS` for `json()`; `apply_headers` copy-on-write
- Echo microbench (`--release`, isolated): ~114k → ~170k (G2) → **~177k** (A1–A7) req/s; ping **~224k**

## 0.6.2 — 2026-08-13

Nox 1.29.4 floor + `--release` listen path.

- Floor Nox **1.29.4** (CI `NOX_VERSION=v1.29.4`; SO_REUSEPORT per `serve_multicore` worker)
- `--release` never calls `serve_multicore`: `AETHER_LLVM=1` (`./run-release.sh`) uses a single `nox.http.serve` so the M:N pool can steal. 1.29.4 flatten + SO_REUSEPORT opened N accept loops inside the pool (8-worker ping collapsed)
- QBE `workers>1` still uses `serve_multicore` (`aether.server.use_os_workers`)

## 0.6.1 — 2026-08-13

Aether-side PERF_GAPS (G1–G3) + Nox 1.29.3 floor.

- Floor Nox **1.29.3** (CI `NOX_VERSION=v1.29.3`; 1.29.2 TCP_NODELAY + 1.29.3 lock-free ARC free-lists under `--release` multicore)
- `NOX_POOL_WORKERS` must be in the **process environment before exec** (`scripts/aether_env.sh`, scaffold `run.sh`). `apply_pool_workers` / `set_var` cannot resize the `--release` `$main` pool
- Validation pipe hands the decoded `JsonValue` to `ValidatedBody` (one `nox.json.decode` per body)
- `json_ok_str` / `encode_str_map` via `nox.strings.join`; finalize mutates headers in place (`apply_headers`)
- `dispatch_from_parts` + optional `handle_bare` so Nox can skip `iterateHeaders` when `AETHER_REQUEST_HEADERS=0`
- `AETHER_REQUEST_ID=0` skips `uuid4` + `X-Request-Id`

## 0.6.0 — 2026-08-13

Nox ≥ 1.29.0 dual runtime.

- Floor Nox **1.29.0** (CI `NOX_VERSION=v1.29.0`)
- `apply_pool_workers(cfg)` maps `AETHER_WORKERS` → `NOX_POOL_WORKERS` (`serve_multicore` flatten under `--release`)
- Production path: `noxc build --release` (macOS/arm64 LLVM M:N); `noxc run` remains QBE / shared-nothing
- macOS CI job: `scripts/smoke_http_release.sh`
- In-memory `RateStore` documented as not thread-safe under `--release` multicore
- Bench table: QBE vs `--release` vs Nest vs Gin

## 0.5.0 — 2026-07-31

Supported multicore via per-worker ensure-boot.

- `ensure_bound` / `dispatch_ensure(req, cfg, build)` — each `serve_multicore` worker boots its own `AppBind`
- Scaffolds / examples / bench use `dispatch_ensure` (safe for workers=1 and workers>1)
- Multicore HTTP smoke (`scripts/smoke_http_multicore.sh`, `AETHER_WORKERS=2`)
- Docs: multicore is opt-in supported (default still 1); in-memory state remains worker-local

## 0.4.4 — 2026-07-31

Hardening follow-up (fingerprint, reclaim batching, release smoke).

- DTO fingerprint is field-order independent; nested shapes included; nested always queued for collision checks
- `reclaim_stale_batch(db, stale_ms, limit)` (default 500) + broader rollback on reclaim errors
- Two-connection file-backed queue contention + batch-limit tests
- Route patterns normalized at boot (`/users` vs `/users/` → duplicate)
- `docs/RELEASE.md` lock-commit rule; tag-triggered remote install/scaffold workflow

## 0.4.3 — 2026-07-31

Production hardening (queue reclaim + boot validation + release refs).

- `reclaim_stale` under `BEGIN IMMEDIATE`; UPDATE requires matching `lease_token` + `updated_at_ms < cutoff` + `changes == 1`
- Boot mounts framework routes **before** duplicate validation (user `/health` etc. collide at boot)
- Duplicate DTO schema names with different shapes raise at boot
- `scripts/check_release_refs.sh` + package-install smoke; tag only after `nox.lock` matches `VERSION`

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
