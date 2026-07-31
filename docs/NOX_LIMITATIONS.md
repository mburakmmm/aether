# Nox limitations (Aether evidence)

Aether targets **Nox ≥ 1.26.0**. This document lists language/runtime gaps that block NestJS-identical ergonomics. Each item has **impact**, **evidence in nox-lang**, **desired Nox change**, and **Aether workaround**.

Status legend: `blocked` | `workaround` | `resolved in nox X.Y`

Nox tree referenced: local `/Users/melihburakmemis/Documents/nox-lang` (and https://github.com/mburakmmm/nox-lang).

---

## 1. Class and method decorators

**Status:** `workaround`

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

**Status:** `workaround`

**Impact:** Cannot write `@get(status=201)` or `@http(methods=["GET","HEAD"])`. Path/prefix must be string literals for reflect metadata.

**Evidence:**
- `tests/golden/typecheck_cases/err_decorator_non_literal_arg.nox`
- CHANGELOG `[1.21.0]`: non-string / non-literal args rejected; int/bool/list deferred (v2 note in spec)

**Desired Nox change:** Allow int/bool/list literal decorator args (at least).

**Aether workaround:** Extra route metadata set in `ModuleBuilder` (`summary`, schemas, status helpers in response layer).

---

## 3. `decorator_handler` only for `(Context) -> HttpResponse`

**Status:** `workaround`

**Impact:** No param decorators (`@Body()`, `@Param()`). Reflect cannot expose handlers with custom signatures for DI.

**Evidence:**
- `stdlib/nox/reflect.nox`: `decorator_is_handler` / `decorator_handler` require exact `(Context) -> HttpResponse`
- Codegen decorator table: `compiler/codegen_qbe/decorators.zig`

**Desired Nox change:** Broader handler shapes and/or parameter type metadata for frameworks.

**Aether workaround:** Handlers always take `HttpContext`; body/params via context + pipes.

---

## 4. `serve*` requires bare top-level function names

**Status:** `workaround`

**Impact:** Cannot pass `app.dispatch` method or lambda to `nox.http.serve`. Templates must define `def handle(req): ...`.

**Evidence:**
- `stdlib/nox/router.nox` header comments (serve handle is compile-time intrinsic)
- Nyx `docs/NOX_LIMITATIONS.md` / `server.nox` (same constraint)
- HTTP intrinsic codegen: `compiler/codegen_qbe/http_intrinsics.zig` (`genHttpServe`)

**Desired Nox change:** Allow first-class function values (or bound methods) as serve handlers.

**Aether workaround:** Call `nox.http.serve*` with a bare top-level `handle` / `ws_handle` in the app entry (see `aether.server` comments + scaffolds).

---

## 5. No constructor / parameter type reflection

**Status:** `workaround`

**Impact:** Automatic constructor DI (`__init__(self, svc: UserService)`) cannot be inferred by the framework.

**Evidence:**
- `nox.reflect` only exposes decorator metadata (name, string args, handler trampoline) — `stdlib/nox/reflect.nox`
- No field/param type registry in stdlib or codegen

**Desired Nox change:** Optional compile-time export of constructor parameter types (names + type ids) for DI containers.

**Aether workaround:** Official DI is **closure injection**. `m.provide("UserService")` registers a **name only** (duplicate names rejected at boot). Hold the instance in a local/module field and capture it when registering handlers: `m.get("/users/:id", self._show(svc))`.

---

## 6. Generic methods on classes are rejected

**Status:** `workaround`

**Impact:** Cannot implement `Container.get[T](name) -> T`.

**Evidence:**
- `tests/golden/typecheck_cases/err_generic_method_rejected.nox`
- Checker: `compiler/typecheck/checker.zig` — `"metodlar generic olamaz"`
- Spec Faz 10: only free functions may be generic — `nox-teknik-spesifikasyon.md` (~line 670)

**Desired Nox change:** Generic methods, or a sanctioned downcast/`as` for DI.

**Aether workaround:** No cross-package `Injectable` base (see §15). Name registry via `Container.register_name` / `has`; typed services via **closures** only. Free generic helpers where useful.

---

## 7. `nox.validate` is flat object-only (no nested/format API)

**Status:** `workaround`

**Impact:** Nested DTO and format/min/max/pattern need framework code.

**Evidence:**
- `stdlib/nox/validate.nox` module docs: flat fields only; nested via manual recursive `validate`
- Kinds: `string|number|bool|array|object|null` only — no format constraints

**Desired Nox change:** Nested schema API + format/min/max/pattern rules.

**Aether workaround:** `aether.dto` recursive validation + OpenAPI field metadata (`format`, `minimum`, …) owned by Aether.

---

## 8. Router has no `next()` middleware chain

**Status:** `workaround`

**Impact:** Nest-style interceptor onion cannot be built on `Router.use_before/after` alone.

**Evidence:**
- `stdlib/nox/router.nox`: intentional before/after hooks; comments state next-chain composition is unverified in language

**Desired Nox change:** Optional next-based middleware (or document supported dynamic closure patterns).

**Aether workaround:** Full Guard/Pipe/Interceptor pipeline inside `aether.pipeline` / `application.dispatch`.

---

## 9. Caught `Exception` has no source line field

**Status:** `blocked` (partial)

**Impact:** Structured 500 responses cannot include file:line for caught errors in production debugging.

**Evidence:**
- CHANGELOG `[1.25.0]`: unhandled exceptions report class + line; caught `Exception` has no line field
- Nyx `docs/NOX_REQUESTS.md` — still open (“Exception source span”)

**Desired Nox change:** `Exception.line` / span on caught instances.

**Aether workaround:** Error JSON includes `code`, `message`, `details`, and in development `kind` (exception class name via our hierarchy); no source line until Nox provides it.

---

## 10. `HttpRequest` has no peer / remote address

**Status:** `blocked`

**Impact:** Trusted-proxy and IP rate limiting cannot verify connecting peer.

**Evidence:**
- `stdlib/nox/http.nox` — `HttpRequest` fields: `method`, `target`, `body`, `headers` only
- Nyx `docs/NOX_REQUESTS.md` — peer IP still open

**Desired Nox change:** `HttpRequest.peer_addr` (or similar) populated by serve runtime.

**Aether workaround:** Optional `X-Forwarded-For` / `X-Real-IP` helpers with explicit trust flag (`AETHER_TRUST_X_FORWARDED_FOR`); document insecurity without peer IP.

---

## 11. Qualified type names not allowed in annotations

**Status:** `workaround`

**Impact:** Must `from aether.context import HttpContext` instead of annotating `aether.context.HttpContext`.

**Evidence:**
- `stdlib/nox/router.nox` comments: `typeExprToType` expects a single identifier
- Checker `typeExprToType` / `parseBaseTypeExpr`

**Desired Nox change:** Allow dotted type annotations.

**Aether workaround:** Import discipline in docs and scaffolds.

---

## 12. Multicore workers do not share in-memory singletons

**Status:** `workaround`

**Impact:** In-memory DI singletons, WS hubs, and rate stores are per OS worker thread.

**Evidence:**
- `stdlib/nox/router.nox` multicore note: each worker gets a fresh module-global copy; ARC refcounts are non-atomic
- CHANGELOG / runtime thread model

**Desired Nox change:** Documented shared-memory primitives for selected framework state (or atomic ARC).

**Aether workaround:** SQLite-backed job queue for cross-process work; document that in-memory gateway hubs are process-local; prefer external store for multi-worker broadcast.

---

## 13. Cross-module class inheritance

**Status:** `workaround`

**Impact:** User app classes cannot subclass framework bases (`Injectable`, `Guard`, `ModuleBase`, …) defined in the `aether` package. Nest-style `class X(Injectable)` across package boundaries fails typecheck (`UndefinedClass` base).

**Evidence:**
- Reproduced: `class Svc(Injectable)` with `from aether.container import Injectable` → `sınıf 'Svc' bilinmeyen bir taban sınıfa sahip: Injectable`
- Same-module inheritance works (stdlib / intra-file); package import + subclass does not

**Desired Nox change:** Allow imported classes as inheritance bases (mangled name resolution for bases).

**Aether workaround:** Closure DI; guards/pipes as first-class functions; `app.module()` + `UsersModule().configure(m)`; provider **name** registry only.

## 14. `name[i](...)` parsed as generic type

**Status:** `workaround`

**Impact:** Calling a function stored in a list via `guards[i](ctx)` fails typecheck (`bilinmeyen generic kurucu: guards`). Subscript+call on a bare name is parsed as `Type[Args]`.

**Evidence:**
- Minimal repro: `guards[i](x)` → UnknownType generic constructor
- Works: `fn: (T) -> U = guards[i]; fn(x)`

**Desired Nox change:** Disambiguate value subscript from generic type syntax (e.g. only allow generics on type names / uppercase, or require `list[i]` vs call form).

**Aether workaround:** Always bind `fn = xs[i]` before `fn(...)`.

---

## 15. List assignment copies; class fields required for empty `[]`

**Status:** `workaround`

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

**Status:** `workaround`

**Impact:** Frameworks cannot verify Bearer JWTs or emit OpenAPI security without shipping codecs. Nest/Go ecosystems rely on mature std/third-party JWT stacks.

**Evidence:**
- Nox stdlib exposes `nox.crypto.hmac_sha256` + `constant_time_eq` but no `nox.base64` / `nox.jwt`
- Aether `benchmarks/` and `aether.jwt` require `aether.base64` (hex→base64url bridge for HMAC)

**Desired Nox change:** Stdlib `nox.base64` (std + url) and preferably `nox.jwt` HS256 helpers.

**Aether workaround:** Ship `aether.base64` + `aether.jwt` (HS256 only); `jwt_bearer(secret)` guard stores claims in TaskLocal.

---

## 17. Query / header maps are string-only

**Status:** `workaround`

**Impact:** Typed query/header validation cannot coerce `?page=2` to number without framework encoding round-trips. Nest pipes / Gin binders coerce natively.

**Evidence:**
- `HttpContext.query: dict[str, str]` / headers as strings (`aether.context`)
- Bench + `query_validation_pipe` encode maps to JSON strings then run `aether.dto`

**Desired Nox change:** Optional typed query decode, or richer URL value types in `nox.url`.

**Aether workaround:** Document string-oriented query/header schemas; validate via JSON object rebuild + DTO.

---

## 18. Hot-path string building (JSON responses)

**Status:** `workaround` (perf)

**Impact:** Handlers and OpenAPI builders concatenate JSON with `+` / `encode_string`. Under wrk this shows as CPU in string alloc vs Gin’s `encoding/json` / Nest buffers — see `docs/BENCHMARKS.md`.

**Evidence:**
- Cross-stack microbench harness in `benchmarks/` (Aether vs NestJS Express vs Gin)
- No binary JSON writer / response builder in Nox stdlib

**Desired Nox change:** Efficient JSON object builder / response buffer API for hot paths.

**Aether workaround:** Keep validation/OpenAPI correctness first; document multicore (`AETHER_WORKERS`) and compare apples-to-apples in BENCHMARKS.

---

## 19. `serve*` handlers cannot close over `Application`

**Status:** `workaround`

**Impact:** The idiomatic Nest/Express pattern `def handle(req): return dispatch(app, req)` fails codegen when `app: Application` is a free variable of the serve handler (`desteklenmeyen yapı`). Config and simple values are fine; capturing the framework Application graph is not.

**Evidence:**
- Minimal repro: boot + `handle` referencing `app` + `nox.http.serve` → codegen error
- Works: store app in `list[Application]` / `AppBind` and read `APPS[0]` inside handle
- Bench harness + `examples/hello_api` require this pattern

**Desired Nox change:** Allow serve handlers to close over complex package class instances (or document free-variable restrictions for serve intrinsics).

**Aether workaround:** `boot_with_config` calls `bind(app)`; entrypoints use `dispatch_bound` / `shutdown_bound`.

---

## Priority asks for Nox (Aether ranking)

0. Cross-module class inheritance
0b. List reference sharing / empty-list codegen
1. Class + method decorators + bound methods
2. Constructor/param type metadata (real DI)
3. Generic methods or safe downcast
4. Caught Exception source span
5. `HttpRequest` peer address
6. Richer `nox.validate` / nested schemas
7. Non-string decorator literal args
8. First-class serve handlers
9. Disambiguate `name[i](...)` from generics
10. Stdlib base64 (+ JWT HS256)
11. Typed / coercing query values
12. Hot-path JSON / response buffers
13. Serve-handler free vars over complex package objects

When an item is fixed upstream, update its **Status** to `resolved in nox X.Y` and tighten Aether APIs accordingly.
