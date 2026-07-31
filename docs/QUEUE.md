# Aether queue delivery semantics
#
# `aether.queue` is an SQLite-backed job queue. Delivery is **at-least-once**.
# Workers must treat payloads as idempotent.

## Lease token

1. `reserve()` moves a job to `running` and returns JSON including `lease_token`.
2. `complete(db, id, lease_token)` and `fail(db, id, lease_token, err)` succeed only when the
   token matches the current lease **and** status is still `running`.
3. After a successful complete/fail, the lease token is cleared.

If another worker reclaims the job, the old token is invalidated. Calling `complete` with a
stale token raises `QueueError` — this prevents double-ack races.

## Reclaim and lease failures

- `reclaim_stale(db, stale_ms)` finds `running` rows whose `updated_at_ms` is older than the window.
- Each reclaim increments `lease_failures` and either:
  - returns the job to `queued` (with a reclaim error note), or
  - marks it `failed` / dead when `lease_failures >= max_lease_failures()` (default 5).
- Prefer `work_with_reclaim` / `work_loop` so reclaim runs before each batch.

## Attempts vs lease failures

| Counter | Meaning |
|---------|---------|
| `attempts` | Handler ran and called `fail` (or exhausted retries) |
| `lease_failures` | Lease expired / reclaim without a successful complete |

A job can be reclaimed without the handler having finished; that is why handlers must be idempotent.

## Worker checklist

1. Decode payload; derive a stable idempotency key (job id or business key).
2. Apply side effects once (upsert / skip if already applied).
3. Call `complete` with the **exact** `lease_token` from `reserve`.
4. On handler errors, call `fail` with the same token (backoff / DLQ via attempt limits).
5. Never assume exactly-once; design for retries and reclaim.

## DLQ

Dead / failed jobs: `list_dead`, `requeue_dead`, `mark_dead`. Use after ops review — requeue resets
attempts/lease_failures and returns the job to `queued`.
