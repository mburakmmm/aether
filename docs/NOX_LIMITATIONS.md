# Nox limitations (Aether evidence)

Aether targets **Nox ≥ 1.171.2**. This document lists language/runtime gaps that block NestJS-identical ergonomics. Each item has **impact**, **evidence in nox-lang**, **desired Nox change**, and **Aether workaround**.

Rechecked **2026-10-08** against nox-lang **1.171.2**. Nox 1.143–1.170 added language features (`in`, `break`, comprehensions, `set`, f-strings, dunder methods, NNI). Aether does not rewrite onto them. The required change is Nox **1.171.0**: `nox.json` dropped `decode`/`encode`/`encode_string` in favor of `parse`/`dump`/`dump_string`. `HttpRequest.peer_addr` now defaults to `""`.

Still open in Nox: qualified type names in annotations (item 11). Partial: `serve_multicore*` still rejects closures and still binds IPv4 itself (items 4 and 19); `nox.atomic` is int/bool only (item 12); `decorator_handler` still only returns top-level `(Context) -> HttpResponse` (item 3). List assignment still copies (item 15); chained `append` does not.

Status legend: `blocked` | `workaround` | `partial` | `closed`

Nox tree referenced: local `/Users/melihburakmemis/Documents/nox-lang` (https://github.com/mburakmmm/nox-lang).

## Runtime contracts (not open asks)

These landed after 1.29.8. Aether code already matches them.

| Contract | Since | Aether |
|---|---|---|
| `nox.json.parse` nesting deeper than **32** raises `JsonError` | 1.47.0 | One parse per body; API payloads stay under the limit. Nox 1.171 removed the `decode`/`encode`/`encode_string` aliases; Aether calls `parse`/`dump`/`dump_string` |
| `from nox.sqlite import Statement` is the `nox.db.Statement` re-export; `bind_*` / `execute() -> int` / `query() -> list[Row]` unchanged | 1.89.1 (chain fix) | `aether.queue` only calls `Connection.prepare` |
| `--release` accept loops are pinned to the worker that owns them | 1.93.0 | `workers>1` still boots via `dispatch_ensure`; probe in CI |
| Stolen tasks read the globals block of the slot that started them | 1.80.4 | Worker-local `AppBind` (`docs/SCOPE.md`) |
| `serveImpl` stack-local connection counter (Linux `serve_multicore` SEGV) | 1.142.3 | Floor is 1.142.24, which includes this fix. Nox CI dropped aarch64 `allow_failure` in 1.142.21 |
| `@capability.requires` and `nox.reflect` tables compile under `--release` | 1.142.7 / 1.142.9 | `import nox.time` no longer rejects LLVM decorator metadata |
| `a.b.c.xs.append` mutates a nested list field | 1.142.8 | `app.route_table.routes.append` and `route.guards.append` |
| `nox.http.listen_v6(port, v6_only)` + bracketed IPv6 `peer_addr` | 1.142.10 | `AETHER_IPV6=1` uses `serve_fd`. `serve_multicore` stays IPv4. `client_ip()` strips the port |
| `s = s + x` grows in place | 1.142.17 | JSON and error builders benefit without an API change |

`spawn` of a function that mutates a shared `list` / `dict` / `class` is a compile error on `--release` (1.30.0, deepened through 1.46.0). Aether does not call `spawn`. HTTP handlers are not spawn targets.

---

## 1. Class and method decorators

**Status:** `closed` (Nox 1.138 decorators, 1.139 bound methods). `mount_decorators` still mounts only top-level functions. Register methods with `m.get("/ping", ctl.show)`.

**Impact:** Nest-style `@Controller` / method `@Get` on class methods cannot compile. Forces module `configure` + top-level function decorators.

**Evidence:**
- Checker rejects class decorators: `tests/golden/typecheck_cases/err_decorator_on_class.nox` (`@controller("/users") class UserController`)
- CHANGELOG `[1.21.0]`: class decorators are parsed but rejected; v1 only top-level functions
- Spec note: class + method decorators deferred (bound-method prerequisite) — `nox-teknik-spesifikasyon.md` §3.79 / CHANGELOG decorator section

**Desired Nox change:**
1. Allow class decorators with metadata table (prefix, tags, …)
2. Allow method decorators
3. Bound method values so instance methods are callable as `(Context) -> HttpResponse` (or trampoline)

**Aether workaround:** `ModuleBuilder.get/post/...` + optional top-level `@get` via `aether.reflect_mount`.

---

## 2. Decorator arguments are string literals only

**Status:** `closed` (Nox 1.130: string, int, bool, string list via `decorator_arg_kind` / `decorator_arg_int` / `decorator_arg_bool` / `decorator_arg_list_*`). Aether route decorators still pass a string path.

**Impact:** Cannot write `@get(status=201)` or `@http(methods=["GET","HEAD"])`. Path/prefix must be string literals for reflect metadata.

**Evidence:**
- `tests/golden/typecheck_cases/err_decorator_non_literal_arg.nox`
- CHANGELOG `[1.21.0]`: non-string / non-literal args rejected; int/bool/list deferred (v2 note in spec)

**Desired Nox change:** Allow int/bool/list literal decorator args (at least).

**Aether workaround:** Extra route metadata set in `ModuleBuilder` (`summary`, schemas, status helpers in response layer).

---

## 3. `decorator_handler` only for `(Context) -> HttpResponse`

**Status:** `partial` (Nox 1.134 adds param/return metadata; `decorator_handler` is still kind 0 only). Method routes use bound methods, not `decorator_handler`.

**Impact:** No param decorators (`@Body()`, `@Param()`). Reflect cannot expose handlers with custom signatures for DI.

**Evidence:**
- `stdlib/nox/reflect.nox`: `decorator_is_handler` / `decorator_handler` require exact `(Context) -> HttpResponse`
- Codegen decorator table: `compiler/codegen_qbe/decorators.zig`

**Desired Nox change:** Broader handler shapes and/or parameter type metadata for frameworks.

**Aether workaround:** Handlers always take `HttpContext`; body/params via context + pipes.

---

## 4. `serve*` requires bare top-level function names

**Status:** `partial` (Nox 1.133: `serve` / `serve_fd` accept closures, including closures over class instances. `serve_multicore*` still rejects closures at compile time). Templates keep a top-level `handle`.

**Impact:** Cannot pass `app.dispatch` method or lambda to `nox.http.serve`. Templates must define `def handle(req): ...`.

**Evidence:**
- `stdlib/nox/router.nox` header comments (serve handle is compile-time intrinsic)
- Nyx `docs/NOX_LIMITATIONS.md` / `server.nox` (same constraint)
- HTTP intrinsic codegen: `compiler/codegen_qbe/http_intrinsics.zig` (`genHttpServe`)

**Desired Nox change:** Allow first-class function values (or bound methods) as serve handlers.

**Aether workaround:** Call `nox.http.serve*` with a bare top-level `handle` / `ws_handle` in the app entry (see `aether.server` comments + scaffolds).

---

## 5. No constructor / parameter type reflection

**Status:** `closed` in Nox 1.134 (`class_init_param_*`, `decorator_param_*`). Aether `Container` is still a name registry; wiring stays in `configure` because annotations cannot name imported types (item 11).

**Impact:** Automatic constructor DI (`__init__(self, svc: UserService)`) cannot be inferred by the framework.

**Evidence:**
- `nox.reflect` only exposes decorator metadata (name, string args, handler trampoline) — `stdlib/nox/reflect.nox`
- No field/param type registry in stdlib or codegen

**Desired Nox change:** Optional compile-time export of constructor parameter types (names + type ids) for DI containers.

**Aether workaround:** Official DI is **closure injection**. `m.provide("UserService")` registers a **name only** (duplicate names rejected at boot). Hold the instance in a local/module field and capture it when registering handlers: `m.get("/users/:id", self._show(svc))`.

---

## 6. Generic methods on classes are rejected

**Status:** `closed` (Nox 1.140: one type parameter, `obj.method[int](x)` or inferred). Aether does not expose a generic container method; providers are names.

**Impact:** Cannot implement `Container.get[T](name) -> T`.

**Evidence:**
- `tests/golden/typecheck_cases/err_generic_method_rejected.nox`
- Checker: `compiler/typecheck/checker.zig` — `"metodlar generic olamaz"`
- Spec Faz 10: only free functions may be generic — `nox-teknik-spesifikasyon.md` (~line 670)

**Desired Nox change:** Generic methods, or a sanctioned downcast/`as` for DI.

**Aether workaround:** No cross-package `Injectable` base (see §15). Name registry via `Container.register_name` / `has`; typed services via **closures** only. Free generic helpers where useful.

---

## 7. `nox.validate` is flat object-only (no nested/format API)

**Status:** `closed` (Nox 1.135). `DtoSchema` writes nested objects, typed arrays, `min`/`max`, and email/uuid `format` onto `Schema`. `uri` stays in Aether.

**Impact:** Nested DTO and format/min/max/pattern need framework code.

**Evidence:**
- `stdlib/nox/validate.nox` module docs: flat fields only; nested via manual recursive `validate`
- Kinds: `string|number|bool|array|object|null` only — no format constraints

**Desired Nox change:** Nested schema API + format/min/max/pattern rules.

**Aether workaround:** `aether.dto` recursive validation + OpenAPI field metadata (`format`, `minimum`, …) owned by Aether.

---

## 8. Router has no `next()` middleware chain

**Status:** `closed` in Nox 1.136 (`Router.use`). Aether keeps Guard / Pipe / Interceptor on `Application.dispatch`.

**Impact:** Nest-style interceptor onion cannot be built on `Router.use_before/after` alone.

**Evidence:**
- `stdlib/nox/router.nox`: intentional before/after hooks; comments state next-chain composition is unverified in language

**Desired Nox change:** Optional next-based middleware (or document supported dynamic closure patterns).

**Aether workaround:** Full Guard/Pipe/Interceptor pipeline inside `aether.pipeline` / `application.dispatch`.

---

## 9. Caught `Exception` has no source line field

**Status:** `closed` (Nox 1.126 `Exception.line`). `error_json` includes `"line"`.

**Impact:** Structured 500 responses cannot include file:line for caught errors in production debugging.

**Evidence:**
- CHANGELOG `[1.25.0]`: unhandled exceptions report class + line; caught `Exception` has no line field
- Nyx `docs/NOX_REQUESTS.md` — still open (“Exception source span”)

**Desired Nox change:** `Exception.line` / span on caught instances.

**Aether:** `error_json` includes `"line"` from `Exception.line`.

---

## 10. `HttpRequest` has no peer / remote address

**Status:** `closed` (Nox 1.127.0)

**Impact:** Was: trusted-proxy and IP rate limiting could not see the connecting peer.

**Evidence:** `stdlib/nox/http.nox` — `HttpRequest.__init__(method, target, body, headers, peer_addr)`. The serve wrapper retains the peer string only when the handle reads `req.peer_addr`.

**Aether:** `dispatch_from_parts(..., peer_addr, ...)`. `client_ip()` returns `peer_host(peer_addr)` (strips `:port` and `[ipv6]:port`) unless trusted `X-Forwarded-For` is set. `AETHER_IPV6=1` listens with `listen_v6` and `serve_fd` (`AETHER_IPV6_ONLY=1` sets `v6_only`). Bench handles pass `""` and do not read the field.

---

## 11. Qualified type names not allowed in annotations

**Status:** `workaround` (still open on 1.142.2). Annotations stay unqualified (`HttpContext`, `HttpResponse`).

**Impact:** Must `from aether.context import HttpContext` instead of annotating `aether.context.HttpContext`.

**Evidence:**
- `stdlib/nox/router.nox` comments: `typeExprToType` expects a single identifier
- Checker `typeExprToType` / `parseBaseTypeExpr`

**Desired Nox change:** Allow dotted type annotations.

**Aether workaround:** Import discipline in docs and scaffolds.

---

## 12. Multicore workers do not share in-memory singletons

**Status:** `partial` (Nox 1.131 `nox.atomic` `AtomicInt` / `AtomicBool` only). Application, route tables, and closures stay slot-local. Metrics stay worker-local.

**Impact:** Both QBE `serve_multicore` and `--release` M:N keep **module globals per worker slot** (`RuntimeState.globals_blocks[g_worker_slot]`). Aether `AppBind` / `Application` / closure services / `Metrics` / `RateStore` are **worker-local**. Shared heap under `--release` does **not** imply a shared Application. Parent `boot_with_config` before serve does not populate sibling slots; `dispatch_ensure` boots each empty slot on first request.

**Evidence:**
- Nox `runtime/alloc/asap.zig` `globals_blocks` / `nox_globals_get`
- Aether `scripts/smoke_worker_bind.sh` (multiple `build()` markers under `workers>1`)
- `docs/SCOPE.md`

**Desired Nox change:** Optional process-wide atomic counters / documented shared-mutable collections when frameworks need aggregate metrics.

**Aether workaround:** Document worker-local scope; require idempotent `build()`; keep in-memory rate-limit / metrics opt-in with external backends for process-wide truth; default `AETHER_WORKERS=1`. Export `NOX_POOL_WORKERS=$AETHER_WORKERS` before exec.

---

## 13. Cross-module class inheritance

**Status:** `closed` (Nox 1.125). Aether modules still use `configure` closures and bound methods.

**Impact:** User app classes cannot subclass framework bases (`Injectable`, `Guard`, `ModuleBase`, …) defined in the `aether` package. Nest-style `class X(Injectable)` across package boundaries fails typecheck (`UndefinedClass` base).

**Evidence:**
- Reproduced: `class Svc(Injectable)` with `from aether.container import Injectable` → `sınıf 'Svc' bilinmeyen bir taban sınıfa sahip: Injectable`
- Same-module inheritance works (stdlib / intra-file); package import + subclass does not

**Desired Nox change:** Allow imported classes as inheritance bases (mangled name resolution for bases).

**Aether workaround:** Closure DI; guards/pipes as first-class functions; `app.module()` + `UsersModule().configure(m)`; provider **name** registry only.

## 14. `name[i](...)` parsed as generic type

**Status:** `closed` (Nox 1.137). `run_pipes` and `run_guards` call `pipes[i](ctx)` / `guards[i](ctx)`. `Box[int](3)` stays a generic constructor.

**Impact:** Calling a function stored in a list via `guards[i](ctx)` fails typecheck (`bilinmeyen generic kurucu: guards`). Subscript+call on a bare name is parsed as `Type[Args]`.

**Evidence:**
- Minimal repro: `guards[i](x)` → UnknownType generic constructor
- Works: `fn: (T) -> U = guards[i]; fn(x)`

**Desired Nox change:** Disambiguate value subscript from generic type syntax (e.g. only allow generics on type names / uppercase, or require `list[i]` vs call form).

**Aether workaround:** Always bind `fn = xs[i]` before `fn(...)`.

---

## 15. List assignment copies; class fields required for empty `[]`

**Status:** `partial` (Nox 1.132 one field, 1.142.8 any `a.b.c.xs.append` chain). Aether route registration uses that. Assigning a list still copies, so shared tables stay objects, not copied lists.

**Impact:**
- `xs: list[T] = []; self.xs = xs` without a class-level `xs: list[T]` field → codegen rejects the program
- Assigning lists between holders does not share mutations → `ModuleBuilder` appends were invisible on `Application` until shared `RouteTable` / `HookState`
- `obj.field.append(x)` is rejected: `append` only allowed on a bare variable (`xs.append(v)` then `obj.field = xs`)

**Evidence:**
- Minimal local empty-list field init → codegen "desteklenmeyen yapı"
- Works: class field + `self.names = []` (Nyx `JobRegistry` pattern)
- Debug: `after_builder=1` / `after_app=0` before `RouteTable` fix

**Desired Nox change:** Documented list reference semantics; allow empty list init without class fields.

**Aether workaround:** Class-level fields; shared `RouteTable` / `HookState` objects.

---

## 16. No stdlib base64 / JWT

**Status:** `closed` (Nox 1.126). `aether.base64` calls `nox.base64`. `aether.jwt.encode` / `decode` call `nox.jwt.sign` / `verify` and still enforce exp, nbf, and iat.

**Impact:** Frameworks cannot verify Bearer JWTs or emit OpenAPI security without shipping codecs. Nest/Go ecosystems rely on mature std/third-party JWT stacks.

**Evidence:**
- Nox stdlib exposes `nox.crypto.hmac_sha256` + `constant_time_eq` but no `nox.base64` / `nox.jwt`
- Aether `benchmarks/` and `aether.jwt` require `aether.base64` (hex→base64url bridge for HMAC)

**Desired Nox change:** Stdlib `nox.base64` (std + url) and preferably `nox.jwt` HS256 helpers.

**Aether workaround:** Ship `aether.base64` + `aether.jwt` (HS256 only); `jwt_bearer(secret)` guard stores claims in TaskLocal.

---

## 17. Query / header maps are string-only

**Status:** `closed` for query coercion (Nox 1.129 `query_int` / `query_float` / `query_bool`). Query schemas accept string, number, and bool. Header schemas stay strings. The map type is still `dict[str, str]`.

**Impact:** Typed query/header validation cannot coerce `?page=2` to number without framework encoding round-trips. Nest pipes / Gin binders coerce natively.

**Evidence:**
- `HttpContext.query: dict[str, str]` / headers as strings (`aether.context`)
- Bench + `query_validation_pipe` encode maps to JSON strings then run `aether.dto`

**Desired Nox change:** Optional typed query decode, or richer URL value types in `nox.url`.

**Aether workaround:** `query_validation_pipe` / `header_validation_pipe` call `_require_string_schema` at registration (non-string field kinds raise). Validate via JSON object rebuild + DTO; document string-only schemas.

---

## 18. Hot-path string building (JSON responses)

**Status:** `closed` in the stdlib (Nox 1.128 `JsonWriter`, 1.142.1 `dump_string` in Zig). Single-field `encode_str_map` stays a concatenation. Two or more keys use `JsonWriter`. Nox 1.142.0 skips the cycle detector for acyclic trees such as `ValidatedBody`.

**Impact:** Handlers and OpenAPI builders concatenate JSON with `+` / `encode_string`. Under wrk this shows as CPU in string alloc vs Gin’s `encoding/json` / Nest buffers — see `docs/BENCHMARKS.md`.

**Evidence:**
- Cross-stack microbench harness in `benchmarks/` (Aether vs NestJS Express vs Gin)
- No binary JSON writer / response builder in Nox stdlib

**Desired Nox change:** Efficient JSON object builder / response buffer API for hot paths.

**Aether workaround:** Keep validation/OpenAPI correctness first; document multicore (`AETHER_WORKERS`) and compare apples-to-apples in BENCHMARKS.

---

## 19. `serve*` handlers cannot close over `Application`

**Status:** `partial` (Nox 1.133 closures work for `serve` / `serve_fd`, not `serve_multicore*`). Multicore entrypoints still use a top-level `handle` and `boot_for_serve`.

**Impact:** The idiomatic Nest/Express pattern `def handle(req): return dispatch(app, req)` fails codegen when `app: Application` is a free variable of the serve handler (`desteklenmeyen yapı`). Config and simple values are fine; capturing the framework Application graph is not.

**Evidence:**
- Minimal repro: boot + `handle` referencing `app` + `nox.http.serve` → codegen error
- Works: store app in `list[Application]` / `AppBind` and read `APPS[0]` inside handle
- Bench harness + `examples/hello_api` require this pattern

**Desired Nox change:** Allow serve handlers to close over complex package class instances (or document free-variable restrictions for serve intrinsics).

**Aether workaround:** Prefer `boot_for_serve(cfg, build)` in entrypoints: validate once,
then clear this slot’s AppBind when `workers>1` so no idle parent Application remains.
Serving handlers use `dispatch_ensure` / `dispatch_from_parts` so every empty worker slot
boots from `cfg`+`build` without closing over `Application`. Sibling slots are **not** filled
by a parent boot (QBE and `--release`). `build()` must be idempotent. `shutdown_bound` /
`finalize_serve` only close the current slot; process drain uses `aether.lifecycle`.
See `docs/SCOPE.md`.

---

## Still open

1. Qualified / dotted type annotations (item 11). Blocks a reflect-driven DI container that names imported classes.
2. `serve_multicore*` closure handlers, and multicore listen is still IPv4-only (items 4 and 19). IPv6 is single-worker `serve_fd`.
3. Shared objects across workers beyond `AtomicInt` / `AtomicBool` (item 12).
4. List-assignment copy semantics (item 15). Chained `append` is closed.

Nox 1.143–1.170 (syntax, `set`, f-strings, dunder methods, NNI) and 1.142.25–1.142.26 (string primitives, error-block layout) do not add a stdlib call Aether should switch to. Nox **1.171.0** removed the old `nox.json` names; Aether now calls `parse` / `dump` / `dump_string`.
