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

**Aether workaround:** `aether.server.listen(app, handle)` documents bare-name requirement; scaffolds emit `handle` / `ws_handle`.

---

## 5. No constructor / parameter type reflection

**Status:** `workaround`

**Impact:** Automatic constructor DI (`__init__(self, svc: UserService)`) cannot be inferred by the framework.

**Evidence:**
- `nox.reflect` only exposes decorator metadata (name, string args, handler trampoline) — `stdlib/nox/reflect.nox`
- No field/param type registry in stdlib or codegen

**Desired Nox change:** Optional compile-time export of constructor parameter types (names + type ids) for DI containers.

**Aether workaround:** Explicit `m.provide("UserService", svc)` + **closure injection** in route factories (fully typed).

---

## 6. Generic methods on classes are rejected

**Status:** `workaround`

**Impact:** Cannot implement `Container.get[T](name) -> T`.

**Evidence:**
- `tests/golden/typecheck_cases/err_generic_method_rejected.nox`
- Checker: `compiler/typecheck/checker.zig` — `"metodlar generic olamaz"`
- Spec Faz 10: only free functions may be generic — `nox-teknik-spesifikasyon.md` (~line 670)

**Desired Nox change:** Generic methods, or a sanctioned downcast/`as` for DI.

**Aether workaround:** `Injectable` base + `container.get(name) -> Injectable`; typed access via closures. Free generic helpers where useful.

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

## Priority asks for Nox (Aether ranking)

1. Class + method decorators + bound methods (Nest DX)
2. Constructor/param type metadata (real DI)
3. Generic methods or safe downcast (`Container.get[T]`)
4. Caught Exception source span
5. `HttpRequest` peer address
6. Richer `nox.validate` / nested schemas
7. Non-string decorator literal args
8. First-class serve handlers

When an item is fixed upstream, update its **Status** to `resolved in nox X.Y` and tighten Aether APIs accordingly.
