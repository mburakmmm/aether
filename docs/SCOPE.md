# Aether scopes: Application / Worker / Request

Proven against Nox ≥ 2.1.52 (`globals_blocks[g_worker_slot]` + `scripts/smoke_worker_bind.sh`). LLVM is the default backend. `serve_multicore` accept loops stay on the worker that opened them; stolen connection fibers keep that slot’s globals. Module globals are still per worker. Nox 2.1.120–2.1.140 shared module state is for programs that do not use `serve_multicore`. The factory model is unchanged, so `AppBind`, rate limit, metrics, and the engine hooks stay per worker.

## Scopes

| Scope | Lifetime | Examples |
|-------|----------|----------|
| **Process** | Whole OS process | Listen sockets, env, SQLite files, external DBs, lifecycle drain flag |
| **Worker** | One Nox worker slot (OS thread / pool member) | `AppBind`, `Application`, in-memory services, `Metrics`, `RateStore`, WS hubs, armed `aether.engine_*` hooks |
| **Request** | Single HTTP dispatch | `HttpContext`, TaskLocal values, validated body |

**Singleton in Aether ≠ process singleton.** A closure-captured `UserService` is **worker-local**: two workers can hold two independent instances.

## AppBind under QBE and `--release`

Nox isolates **module globals per worker slot** on both runtimes (shared heap under `--release` does **not** share `_bind`).

Consequences:

1. `boot_for_serve(cfg, build)` validates routes once, then **clears** this slot when `workers>1` so no idle parent Application remains.
2. The multicore entry calls `make_handle` / `make_handle_bare`. Nox runs that factory once in each worker. The factory calls `boot_with_config` and arms a drain fiber. `dispatch_ensure` still boots a slot that is empty, which is the `workers=1` `serve(handle)` path and any caller that does not use the factory.
3. `workers=1` keeps the bound Application after `boot_for_serve`.

Probe: `benchmarks/worker_probe/main.nox` + `scripts/smoke_worker_bind.sh`.

## `build()` contract

`build(app)` **must be idempotent** and safe to run once per worker:

- **Allowed:** register routes, capture worker-local services, open *per-worker* resources you intend to duplicate.
- **Forbidden (process-once side effects):** migrations, seed scripts, starting cron/background schedulers, binding extra listen ports, assuming a single in-memory database of users.

Put process-level work in the launching shell / supervisor **before** `serve*`, or behind an external system that is safe under concurrent callers.

## Graceful shutdown (coordinated drain)

Because hooks cannot be invoked across worker slots, Aether uses a **shared filesystem drain flag** (`aether.lifecycle`):

1. `begin_shutdown(port)` or `POST /__aether/shutdown` (opt-in: `AETHER_SHUTDOWN_ROUTE=1`) sets `/tmp/aether-life-<port>/stopping` and publishes that fact on the calling worker immediately. The process keeps accepting. That is the load-balancer 503 window.
2. Other workers notice the file within `AETHER_STOP_POLL_MS` (default **200**). Until then they may still return 200. `AETHER_STOP_POLL_MS=0` stats on every request. Each worker that has observed the flag returns **503** before the body is decompressed, then runs **its own** `on_shutdown` hooks via `shutdown_bound()`. A bad `Content-Encoding` during that window is 503, not 400 or 415. A factory-booted worker also polls from its own fiber, so a slot that never accepts still unregisters and runs its hooks.
3. `GET /health` also returns 503 while stopping (load balancer drain).
4. `request_shutdown(port)` writes the same file and then calls `nox.http.shutdown()`. New accepts stop. In-flight requests have `AETHER_DRAIN_TIMEOUT_MS` (default **10000**) to finish, then `serve*` returns. A later `serve*` in the same process returns immediately. This is process exit, not the 503 window.
5. SIGTERM and SIGINT are handled inside Nox. They stop accept and do not write the file. When `serve*` returns, `finally: finalize_serve(cfg)` sets the flag and `release_bound()`.
6. `await_workers_drained(port, timeout_ms)` polls until worker registry files are gone.
7. `shutdown_bound()` runs hooks but keeps the closed Application bound (no rebuild during drain).
   `release_bound()` clears AppBind (parent clear / process exit).

Process-once cleanup that is not per-Application still belongs in the supervisor (migrations, shared cron).

## Metrics

`GET /metrics` returns **`scope: "worker"`** counters for the Application that handled that request. It is **not** a process aggregate. With `workers>1`, prefer `AETHER_METRICS=0` and scrape an external backend, or accept per-worker scrapes.

## Rate limit

In-memory `RateStore` is **worker-local**. Effective process capacity ≈ `workers × max` (skewed by accept affinity). Aether does not add a shared quota: `serve_multicore` does not share that store, and a second database on the request path would not be a cluster limiter. Keep `AETHER_RATE_LIMIT` off when the cap must cover every worker. Use a proxy or gateway in front for that quota.

`AETHER_TRUST_X_FORWARDED_FOR` reads `X-Forwarded-For` only when the TCP peer is listed in `AETHER_TRUSTED_PROXIES`. An entry is one address or a CIDR (`198.51.100.0/24`, `2001:db8::/32`). A bad entry fails boot. Trust with an empty list fails boot. Trust with `AETHER_REQUEST_HEADERS=0` fails boot, because the bare handle does not pass the header and every client would share the proxy socket. The client is the rightmost hop that is a valid IP and is not itself on that list. `2001:0db8::1` and `2001:db8::1` are one key. `::ffff:203.0.113.9` is `203.0.113.9`. A hop that is not an IP is skipped. When none remain, the canonical socket peer is the key. When every hop is a trusted proxy, the leftmost valid address is the client. An empty client identity is 429 while the limiter is on. The built-in limiter runs before guards and pipes, so a 401 or 422 still spends the quota. A user interceptor stays after those stages. A missing route (404 or 405), a CORS preflight, and body decompression are answered before that stage, so they do not spend it. This limiter covers matched routes. A proxy or gateway is the control for unmatched traffic. `AETHER_HTTP3` and `AETHER_RATE_LIMIT` together fail boot: the QUIC peer is empty, so the forwarded header is not a client proof. `handle_bare` does not read headers. It still passes `req.peer_addr`. The store refuses a new key when it is full rather than dropping a live counter. Expired windows free their slots.

## Ecosystem adapters

Noxen, Pulse, Quartz, and a PostgreSQL reference application stay outside this package. Aether remains the HTTP framework. Those integrations are separate programs, not imports the core boots.

## Recommended production defaults

- `AETHER_WORKERS=1` unless you need multicore throughput **and** all mutable state is external.
- Export `NOX_POOL_WORKERS=$AETHER_WORKERS` before exec.
- Use `boot_for_serve` + `finalize_serve` in entrypoints (scaffolds do).
- External DB/queue for anything that must be process-wide.
- `AETHER_RATE_LIMIT=0`; `AETHER_METRICS=0` or per-worker scrape understanding.
- Enable `AETHER_SHUTDOWN_ROUTE=1` only behind a trusted network / admin path.
