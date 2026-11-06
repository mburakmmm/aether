# Nox limitations

Aether **0.9.0** requires **Nox ≥ 2.0.186**. This note is the recheck of the gaps that still shape Aether. Each open item has the command that was run and the output that command printed.

Checked **2026-11-06** with the published archive `nox-lang-v2.0.186-macos-arm64` (`noxc 2.0.186`, git tag `v2.0.186`, commit `7446d015a20109932cded48a01d93f4d75ba90f2`). The compiler proofs below used that binary, not a newer local build. The IPv4 listen fact is the same tag’s `runtime/stdlib_shims/http_server.zig`, because `serve_multicore` has no address-family argument to reject.

LLVM is the default backend. QBE is `noxc --backend qbe`. `AETHER_WORKERS>1` calls `serve_multicore` on both. On LLVM the pool size is `NOX_POOL_WORKERS`, read once at process start, and `require_pool_env` refuses a mismatch.

## Still open

### 1. `serve_multicore` rejects a closure

`nox.http.serve` and `nox.http.serve_fd` accept a closure. `serve_multicore` does not. Multicore entrypoints stay a bare top-level `handle`. That handle must not close over `Application`; it calls `dispatch_from_parts`.

`serve` of a local function typechecks:

```sh
noxc check serve_closure.nox
```

```nox
import nox.http
from nox.http import HttpRequest, HttpResponse

def go() -> None:
    def handle(req: HttpRequest) -> HttpResponse:
        return HttpResponse(200, req.method, {})
    nox.http.serve(1, handle)
```

```text
no type errors: serve_closure.nox
```

The same closure passed to `serve_multicore` does not:

```text
type error (NotCallable): line 7: 'nox.http.serve_multicore': 'handle' must be a plain function name (a closure handler is NOT supported in this variant: in the default build the multicore workers use a SEPARATE RuntimeState, so a closure from the main runtime cannot be passed to them)
```

Checker at that tag: `validateHttpHandler(..., true)` for `serve` / `serve_fd`, and `validateHttpHandler(..., false)` for `serve_multicore` (`compiler/typecheck/checker.zig`).

### 2. Multicore listen is IPv4

`serve_multicore` takes a port, a function name, a thread count, and an optional integer literal `max_connections`. There is no address family.

```text
type error (ArgumentCountMismatch): line 8: 'nox.http.serve_multicore' takes 3 or 4 arguments: (port, handle, num_threads[, max_connections])
```

`bindAndListen` in tag `v2.0.186` opens `AF_INET` and binds `sockaddr.in` (`runtime/stdlib_shims/http_server.zig`, `nox_http_server_listen` passes `reuse_port=false`; the multicore worker path uses the same helper with `reuse_port=true`). The stdlib shipped in the 2.0.186 archive says the same thing: `listen` stays IPv4, and `listen_v6` returns an fd for `serve_fd`.

Aether: `AETHER_IPV6=1` is `listen_v6` + `serve_fd`, and `require_ipv6_listen` rejects `AETHER_WORKERS>1` and `AETHER_WS`.

### 3. Shared worker state is `AtomicInt` and `AtomicBool`

A program that imports `nox.atomic` and prints every reflected class whose name contains `Atomic` or `Shared` printed only:

```text
nox_atomic_AtomicError
nox_atomic_AtomicInt
nox_atomic_AtomicBool
```

`nox.sharedmem` is in the same archive and does not close this. Its header says it is `shm_open` + `mmap(MAP_SHARED)` for **separate OS processes**, and the values it moves are bytes and `i64`s. Worker slots in one process still do not share an `Application`, a `list`, or a `dict`.

Aether keeps `AppBind`, closure services, `Metrics`, and `RateStore` worker-local. `build()` stays idempotent. `dispatch_ensure` boots an empty slot on first request. In-memory rate limits are not a process quota.

### 4. Assigning a list copies it

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

`b.append` did not change `a`. `ys.append` did not change `box.xs`. Chained `obj.field.append` on a field the program already owns is a separate, older fix; Aether route tables still live in a shared `RouteTable` object, not in a list that gets assigned between holders.

### 5. `decorator_handler` is only a top-level `(Context) -> HttpResponse`

Class and method decorators typecheck and show up in `nox.reflect`. `decorator_is_handler` is true only for kind 0.

```text
1
False
2
False
0
True
```

Those three lines are `decorator_kind` then `decorator_is_handler` for `@controller` on a class (kind 1), `@get` on a method (kind 2), and `@route` on a top-level `(nox.router.Context) -> HttpResponse` (kind 0). The method took a `Context` and returned `HttpResponse`; it is still not a handler trampoline. The stdlib comment in the 2.0.186 archive says `decorator_handler` is for `kind == 0` only.

Aether still registers routes with `ModuleBuilder.get/post/...` and bound methods (`m.get("/ping", ctl.show)`). It does not mount `@Controller` classes.

## Closed on this recheck

### Qualified annotations

The 2026-10-29 note still listed dotted annotations as open. On 2.0.186 they typecheck.

```nox
import nox.http
def f(req: nox.http.HttpRequest) -> int:
    return len(req.method)
```

```text
no type errors
```

Inside the Aether package, `aether.context.HttpContext` and `aether.application.Application` annotations also typecheck.

This does not make a reflect-driven container. `class_init_param_type` returns the compiler’s mangled name:

```text
req
nox_http_HttpRequest
```

and, for a class whose constructor takes `aether.context.HttpContext`:

```text
aether_context_HttpContext
```

Aether DI stays closure injection. `m.provide` is a name registry.

### Imported classes can be bases

`from aether.errors import HttpError` then `class Mine(HttpError)` typechecks. A dotted base is still a syntax error:

```text
syntax error: unexpected '.' (expected ')')
    class Mine(nox.http.HttpError):
```

Aether does not grow a Nest-style base-class hierarchy on top of this.

## Workarounds that stay

- Serve with a bare top-level `handle`. Pass `req.conn` into `dispatch_from_parts` when the handler is the full `handle`. `handle_bare` stays seven arguments and does not read `req.headers` or `req.peer_addr`.
- Do not close over `Application`. `boot_for_serve` validates once and clears the parent slot when `workers>1`. Each slot boots through `dispatch_ensure`.
- `POST /__aether/shutdown` calls `begin_shutdown` and keeps listening, so clients observe 503. `request_shutdown(port)` writes the drain file and then calls `nox.http.shutdown()`, which refuses new connections and returns from `serve*` after the drain timeout. SIGTERM stops accept without the file; `finalize_serve` writes it when `serve*` returns.
- CORS, rate limit, and request id stay in Aether. They are worker-scoped, honor trusted `X-Forwarded-For`, and production CORS stays off unless configured. `nox.web` is used for cookie encoding and the security-header trio, not as a replacement router.
- `AETHER_MAX_BODY_BYTES` (default 1 MiB) is passed to `nox.http.configure`. A socket body over that limit is Nox’s plain-text 413 and the handler does not run. Aether’s own length check still covers `dispatch` when the body is already in memory. `0` leaves Nox’s 10 MiB default.

## Already in the language, and what Aether does with it

These are not open asks. Aether 0.9.0 calls them from `boot_for_serve` / `request_shutdown` / the response path.

| Nox | Since | Aether |
|---|---|---|
| `nox.http.configure` / `shutdown` / `set_http2` | 2.0.118, 2.0.127 | `apply_http_server`. Bench forces HTTP/1.1 (`AETHER_HTTP2=0`) because wrk is HTTP/1.1 |
| `ResponseStream`, `HttpRequest.conn` | 2.0.124 | `HttpContext.stream` / `sse` / `finish_stream`. `conn == 0` keeps chunks in `stream.sent` for unit tests |
| `nox.http.multi` | 2.0.120 | several `Set-Cookie` lines |
| `nox.web.cookie` / `expire_cookie` | 2.0.122 | `with_cookie` / `expire_cookie`. A `ValueError` becomes 400 |
| `nox.log.set_level` | 2.0.93 | only when `AETHER_LOG_LEVEL` is non-empty |

Generators, mixins, `@property`, and `*args` still do not replace an Aether API. There is no outbound HTTP client wrapper.
