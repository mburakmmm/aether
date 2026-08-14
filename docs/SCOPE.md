# Aether scopes: Application / Worker / Request

Proven against Nox ≥ 1.29.8 (`globals_blocks[g_worker_slot]` + `scripts/smoke_worker_bind.sh`).

## Scopes

| Scope | Lifetime | Examples |
|-------|----------|----------|
| **Process** | Whole OS process | Listen sockets, env, SQLite files, external DBs |
| **Worker** | One Nox worker slot (OS thread / pool member) | `AppBind`, `Application`, in-memory services, `Metrics`, `RateStore`, WS hubs |
| **Request** | Single HTTP dispatch | `HttpContext`, TaskLocal values, validated body |

**Singleton in Aether ≠ process singleton.** A closure-captured `UserService` is **worker-local**: two workers can hold two independent instances.

## AppBind under QBE and `--release`

Nox isolates **module globals per worker slot** on both runtimes (shared heap under `--release` does **not** share `_bind`).

Consequences:

1. `boot_with_config` on the main thread only fills **that** slot’s `AppBind`.
2. Sibling workers start empty → `dispatch_ensure` / `dispatch_from_parts` call `boot_with_config` again on first request.
3. Docs that claimed “`--release` → ensure_bound is a no-op after main boot” were **wrong**; probe evidence shows multiple `build()` runs and multiple live `boot_id`s when traffic hits multiple slots.

Probe: `benchmarks/worker_probe/main.nox` + `scripts/smoke_worker_bind.sh`  
(`AETHER_PROBE_SKIP_PARENT_BOOT=1` forces every serving worker through `ensure_bound`).

## `build()` contract

`build(app)` **must be idempotent** and safe to run once per worker:

- **Allowed:** register routes, capture worker-local services, open *per-worker* resources you intend to duplicate.
- **Forbidden (process-once side effects):** migrations, seed scripts, starting cron/background schedulers, binding extra listen ports, assuming a single in-memory database of users.

Put process-level work in the launching shell / supervisor **before** `serve*`, or behind an external system that is safe under concurrent callers.

Parent `boot_with_config` before `serve_multicore` is optional convenience for worker 0; it does **not** replace per-worker ensure-boot and can create an idle Application that never serves.

## Metrics

`GET /metrics` returns **`scope: "worker"`** counters for the Application that handled that request. It is **not** a process aggregate. With `workers>1`, prefer `AETHER_METRICS=0` and scrape an external backend, or accept per-worker scrapes.

## Rate limit

In-memory `RateStore` is **worker-local**. Effective process capacity ≈ `workers × max` (skewed by accept affinity). Keep `AETHER_RATE_LIMIT` off for global quotas; use Redis/Postgres/API gateway.

## Shutdown

`shutdown_bound()` only runs hooks for the **current** worker slot’s Application. Coordinated graceful shutdown across siblings is not provided — prefer `workers=1` for simple lifecycle, or external orchestration.

## Recommended production defaults

- `AETHER_WORKERS=1` unless you need multicore throughput **and** all mutable state is external.
- Export `NOX_POOL_WORKERS=$AETHER_WORKERS` before exec.
- External DB/queue for anything that must be process-wide.
- `AETHER_RATE_LIMIT=0`; `AETHER_METRICS=0` or per-worker scrape understanding.
