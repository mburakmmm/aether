# Nox limitations

Aether **0.10.1** requires **Nox ≥ 2.1.52**. This note is the recheck of the gaps that still shape Aether. Each item has the command that was run and the output that command printed.

Checked **2026-11-11** with the installed compiler `noxc 2.1.52`. GitHub release `v2.1.52` has `nox-lang-v2.1.52-macos-arm64.tar.gz`, the Linux archives, and the Windows archives. The local clone’s tag `v2.1.52` is `b1debe1e7af0a83c720b6c465c3e29d00fcd5a27`. Tags `v2.1.53`–`v2.1.55` do not change this surface (freestanding, WASM import notes, FFI notes).

LLVM is the default backend. QBE is `noxc --backend qbe`. `AETHER_WORKERS>1` calls `serve_multicore*` on both. On LLVM the pool size is `NOX_POOL_WORKERS`, read once at process start, and `require_pool_env` refuses a mismatch. A program that contains `serve_multicore` anywhere, including a dead branch, makes the default pool the CPU count. QBE ignores the pool variable.

## Closed on this recheck

### Multicore IPv6

`nox.http.configure` takes a sixth argument, `ip_family`: `0` IPv4, `1` dual-stack `::`, `2` IPv6 only. `0` keeps Nox’s default. Windows ignores the value.

```sh
noxc check configure6.nox
```

```nox
import nox.http

def go() -> None:
    nox.http.configure(0, 0, 0, 0, 0, 1)
```

```text
no type errors: configure6.nox
```

Aether passes `http_ip_family(cfg)` from `apply_http_server`. `AETHER_IPV6=1` with `AETHER_WORKERS>1` then calls `serve_multicore*`, which opens one `SO_REUSEPORT` socket per worker. A single worker still uses `listen_v6` + `serve_fd`, because `serve_fd` does not read `ip_family`. `AETHER_IPV6` with `AETHER_WS` and one worker is rejected: single-worker `serve_ws` is still IPv4. `serve_multicore_ws` follows `ip_family`.

This session did not open a live `::` socket. Nox’s `scripts/http_ipv6_probe.py` is the runtime proof for the family values. Aether’s `tests/net_test.nox` checks the `0` / `1` / `2` mapping and the single-worker WebSocket rejection.

### Handler factory

`serve` and `serve_fd` still accept a closure. `serve_multicore` still rejects a closure that was built in the main runtime. Since Nox 2.1.20 it accepts a top-level function with no parameters that returns `(HttpRequest) -> HttpResponse`. Each worker calls that factory once in its own runtime.

```text
type error (NotCallable): line 7: 'nox.http.serve_multicore': 'handle' must be a plain function name (a closure handler is NOT supported in this variant: in the default build the multicore workers use a SEPARATE RuntimeState, so a closure from the main runtime cannot be passed to them; pass a FACTORY instead: a top-level function with no parameters that returns the handler closure, called once per worker)
```

The same compiler accepts the factory:

```nox
def make_handler() -> (HttpRequest) -> HttpResponse:
    def handle(req: HttpRequest) -> HttpResponse:
        return HttpResponse(200, req.method, {})
    return handle

nox.http.serve_multicore(1, make_handler, 2)
```

```text
no type errors: serve_factory.nox
```

The checker only treats a bare name in that compilation unit as a factory. `aether.server.something` is not one. Aether’s template, `examples/hello_api`, and the two benchmarks define `make_handle` / `make_handle_bare` in the entry file. The factory calls `boot_with_config` and returns a closure. It does not call `boot_for_serve`: that path clears the bind when `workers>1` and would wipe a drain that is already in progress. The parent still calls `boot_for_serve` before `serve*`, so a bad config fails before listen. `dispatch_ensure` remains for `workers=1` and for a bare `handle`.

`tests/factory_boot_test.nox` calls the factory and dispatches `/ping`. It does not prove that `serve_multicore` invokes the factory. That invocation is the Nox checker above, plus `scripts/smoke_http_multicore.sh` and `scripts/smoke_worker_bind.sh`.

The factory also starts one fiber per worker. The fiber polls the drain file and calls `shutdown_bound`, so a worker that never accepts still runs its hooks and drops its registry file. `sleep_ms` inside that fiber yields, and the accept loop keeps running. `scripts/smoke_shutdown.sh` saw 4 registry files before `POST /__aether/shutdown` and 0 after, on QBE and on `--release`.

### Qualified annotations

Dotted annotations typecheck.

```nox
import nox.http
def f(req: nox.http.HttpRequest) -> int:
    return len(req.method)
```

```text
no type errors: qualified.nox
```

`class_init_param_type` still returns the compiler’s mangled name:

```text
req
nox_http_HttpRequest
```

A constructor parameter annotated `aether.context.HttpContext` prints:

```text
aether_context_HttpContext
```

Aether DI stays closure injection. `m.provide` is a name registry.

### Clocks and ids that Aether now calls

`nox.time.monotonic_ns` has existed since 2.1.13. Request-log elapsed time and the in-memory rate-limit window use `monotonic_ns() // 1000000`. Queue lease times and the lifecycle drain poll stay on `now_ms`: those numbers are written down and compared after a restart.

`nox.uuid.uuid7` has existed since 2.1.7. Request ids and `boot_id` use it. Queue lease tokens and gateway connection ids stay `uuid4`, because a time-ordered id leaks when the token was minted.

`nox.jwt.verify_claims` skips a missing `exp` and applies one leeway to every time claim. Aether requires `exp`, allows 60 seconds of future `iat`, and does not widen `exp`, so `decode` does not call `verify_claims`.

Returning a module global no longer double-frees (Nox 2.1.30). That was a compiler fix. Aether did not change for it.

## Still the design

These are not defects to patch inside Aether. The guide’s D group says a doc note is the work. E4 and E5 are out of scope by decision.

### 1. Assigning a list copies it

```nox
class Box:
    xs: list[int]
    def __init__(self: Box) -> None:
        self.xs = []

def go() -> None:
    a: list[int] = []
    a.append(1)
    b: list[int] = a
    b.append(2)
    print(len(a))
    box: Box = Box()
    ys: list[int] = box.xs
    ys.append(3)
    print(len(box.xs))
```

```text
1
0
```

`b.append` did not change `a`. `ys.append` did not change `box.xs`. Sharing goes through a class field that is not reassigned, or through `AtomicRef` when the value is an immutable string. Aether route tables stay on a `RouteTable` object.

### 2. Mutable `list` / `dict` are not shared across workers

Importing `nox.atomic` and printing every reflected class whose name contains `Atomic` or `Shared` printed:

```text
nox_atomic_AtomicError
nox_atomic_AtomicInt
nox_atomic_AtomicBool
nox_atomic_AtomicRef
```

`AtomicRef` stores an immutable string snapshot. It is not a shared mutable list or dict. That sharing is out of scope (worker-local copy, factory, `AtomicRef`). `nox.sharedmem` is `shm_open` + `mmap` for separate OS processes and moves bytes and `i64`s.

Aether keeps `AppBind`, closure services, `Metrics`, and `RateStore` worker-local. The drain flag stays a file. The factory takes no parameters, so a handle created in the parent cannot be passed in, and each worker re-inits module globals. `build()` stays idempotent. In-memory rate limits are not a process quota.

### 3. `decorator_handler` is only a top-level `(Context) -> HttpResponse`

Class and method decorators typecheck. `decorator_is_handler` is true only for kind 0. Making them handlers is out of scope (decision 2026-11-10).

```text
1
False
2
False
0
True
```

Those pairs are `decorator_kind` then `decorator_is_handler` for `@controller` on a class, `@get` on a method that takes `Context` and returns `HttpResponse`, and `@route` on a top-level function of that same signature. The stdlib comment still says `decorator_handler` is for `kind == 0` only.

Aether registers routes with `ModuleBuilder.get/post/...` and bound methods (`m.get("/ping", ctl.show)`).

### 4. Module globals stay per worker

That is still the language rule. The factory and `AtomicRef` are how a program deals with it. Aether uses the factory for boot and does not put `AppBind` on `AtomicRef`.

## Not integrated

Aether stays an HTTP API framework. These Nox modules exist and an application can call them beside Aether. They are not an Aether router or a second lifecycle.

| Nox | Since | Why Aether leaves it |
|---|---|---|
| `nox.grpc` / `nox.grpc_server` | 2.1.33–2.1.44 | A second protocol. An app that wants gRPC calls `nox.grpc_server` itself |
| `nox.signal` | 2.1.6 | `serve*` already owns SIGTERM and SIGINT. A second handler would fight the drain |
| `nox.redis`, `nox.postgres`, `nox.protobuf`, `nox.terminal`, `nox.udp`, time zones, `TaskGroup` | 2.1.x | Application libraries. Aether’s queue stays the SQLite lease queue |

There is no outbound HTTP client wrapper. Generators, mixins, `@property`, and `*args` still do not replace an Aether API.

## Workarounds that stay

- One worker: bare `handle` / `handle_bare`. Several workers: bare `make_handle` / `make_handle_bare` in the entry file. Pass `req.conn` from the full handle. `handle_bare` does not read `req.headers` or `req.peer_addr`.
- Do not close over `Application`. `boot_for_serve` validates once and clears the parent slot when `workers>1`. The factory boots that slot again, and it boots the others.
- `POST /__aether/shutdown` calls `begin_shutdown` and keeps listening, so clients observe 503. `request_shutdown(port)` writes the drain file and then calls `nox.http.shutdown()`, which refuses new connections and returns from `serve*` after the drain timeout. SIGTERM stops accept without the file; `finalize_serve` writes it when `serve*` returns.
- CORS, rate limit, and request id stay in Aether. They are worker-scoped, honor trusted `X-Forwarded-For`, and production CORS stays off unless configured. `nox.web` is used for cookie encoding and the security-header trio, not as a replacement router.
- `AETHER_MAX_BODY_BYTES` (default 1 MiB) is passed to `nox.http.configure`. A socket body over that limit is Nox’s plain-text 413 and the handler does not run. Aether’s own length check still covers `dispatch` when the body is already in memory. `0` leaves Nox’s 10 MiB default.

## Already in the language, and what Aether does with it

| Nox | Since | Aether |
|---|---|---|
| `nox.http.configure` / `shutdown` / `set_http2` | 2.0.118, 2.0.127 | `apply_http_server`. The sixth argument is `ip_family` (2.1.32). Bench forces HTTP/1.1 (`AETHER_HTTP2=0`) because wrk is HTTP/1.1 |
| Handler factory | 2.1.20 | `make_handle` / `make_handle_bare` on `serve_multicore*` |
| `ResponseStream`, `HttpRequest.conn` | 2.0.124 | `HttpContext.stream` / `sse` / `finish_stream`. `conn == 0` keeps chunks in `stream.sent` for unit tests |
| `nox.http.multi` | 2.0.120 | several `Set-Cookie` lines |
| `nox.web.cookie` / `expire_cookie` | 2.0.122 | `with_cookie` / `expire_cookie`. A `ValueError` becomes 400 |
| `nox.log.set_level` | 2.0.93 | only when `AETHER_LOG_LEVEL` is non-empty |
| `monotonic_ns` | 2.1.13 | request log and rate-limit windows. Queue and lifecycle stay on `now_ms` |
| `uuid7` | 2.1.7 | request id and `boot_id`. Lease tokens and gateway ids stay `uuid4` |
