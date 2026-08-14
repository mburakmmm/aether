# Aether scopes: Application / Worker / Request

Proven against Nox ≥ 1.29.8 (`globals_blocks[g_worker_slot]` + `scripts/smoke_worker_bind.sh`).

## Scopes

| Scope | Lifetime | Examples |
|-------|----------|----------|
| **Process** | Whole OS process | Listen sockets, env, SQLite files, external DBs, lifecycle drain flag |
| **Worker** | One Nox worker slot (OS thread / pool member) | `AppBind`, `Application`, in-memory services, `Metrics`, `RateStore`, WS hubs |
| **Request** | Single HTTP dispatch | `HttpContext`, TaskLocal values, validated body |

**Singleton in Aether ≠ process singleton.** A closure-captured `UserService` is **worker-local**: two workers can hold two independent instances.

## AppBind under QBE and `--release`

Nox isolates **module globals per worker slot** on both runtimes (shared heap under `--release` does **not** share `_bind`).

Consequences:

1. `boot_for_serve(cfg, build)` validates routes once, then **clears** this slot when `workers>1` so no idle parent Application remains.
2. Sibling workers start empty → `dispatch_ensure` / `dispatch_from_parts` call `boot_with_config` again on first request.
3. `workers=1` keeps the bound Application after `boot_for_serve`.

Probe: `benchmarks/worker_probe/main.nox` + `scripts/smoke_worker_bind.sh`.

## `build()` contract

`build(app)` **must be idempotent** and safe to run once per worker:

- **Allowed:** register routes, capture worker-local services, open *per-worker* resources you intend to duplicate.
- **Forbidden (process-once side effects):** migrations, seed scripts, starting cron/background schedulers, binding extra listen ports, assuming a single in-memory database of users.

Put process-level work in the launching shell / supervisor **before** `serve*`, or behind an external system that is safe under concurrent callers.

## Graceful shutdown (coordinated drain)

Because hooks cannot be invoked across worker slots, Aether uses a **shared filesystem drain flag** (`aether.lifecycle`):

1. `begin_shutdown(port)` or `POST /__aether/shutdown` (opt-in: `AETHER_SHUTDOWN_ROUTE=1`) sets `/tmp/aether-life-<port>/stopping`.
2. Each worker that still handles a request returns **503** and runs **its own** `on_shutdown` hooks via `shutdown_bound()`.
3. `GET /health` also returns 503 while stopping (load balancer drain).
4. Entrypoint `finally: finalize_serve(cfg)` sets the flag and `release_bound()` after `serve*` returns.
5. `await_workers_drained(port, timeout_ms)` polls until worker registry files are gone.
6. `shutdown_bound()` runs hooks but keeps the closed Application bound (no rebuild during drain).
   `release_bound()` clears AppBind (parent clear / process exit).

Process-once cleanup that is not per-Application still belongs in the supervisor (migrations, shared cron).

## Metrics

`GET /metrics` returns **`scope: "worker"`** counters for the Application that handled that request. It is **not** a process aggregate. With `workers>1`, prefer `AETHER_METRICS=0` and scrape an external backend, or accept per-worker scrapes.

## Rate limit

In-memory `RateStore` is **worker-local**. Effective process capacity ≈ `workers × max` (skewed by accept affinity). Keep `AETHER_RATE_LIMIT` off for global quotas; use Redis/Postgres/API gateway.

## Recommended production defaults

- `AETHER_WORKERS=1` unless you need multicore throughput **and** all mutable state is external.
- Export `NOX_POOL_WORKERS=$AETHER_WORKERS` before exec.
- Use `boot_for_serve` + `finalize_serve` in entrypoints (scaffolds do).
- External DB/queue for anything that must be process-wide.
- `AETHER_RATE_LIMIT=0`; `AETHER_METRICS=0` or per-worker scrape understanding.
- Enable `AETHER_SHUTDOWN_ROUTE=1` only behind a trusted network / admin path.
