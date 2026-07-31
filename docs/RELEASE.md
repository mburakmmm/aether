# Release process (Aether)

## Version triad

Before tagging, these three must agree:

| Source | Value |
|--------|--------|
| `VERSION` | `X.Y.Z` (no `v` prefix) |
| `nox.json` `requires[0].ref` | `vX.Y.Z` |
| `nox.lock` `packages[0].ref` | `vX.Y.Z` |
| `nox.lock` `packages[0].repo` | `github.com/mburakmmm/aether` |

CI runs `scripts/check_release_refs.sh` on the committed tree **before** path overrides.

## Lock commit rule

Self-referencing package locks cannot store the final tag commit SHA inside that same
commit (changing the lock changes the SHA).

Required sequence:

1. Land the **code** commit (features, VERSION, docs, `nox.json` ref bump).
2. Land a **follow-up commit that only changes `nox.lock`**, with
   `resolved` = SHA of the code commit from step 1.
3. Tag **the lock commit** as `vX.Y.Z`.

Do not add application code to the lock commit.

## Local vs remote smoke

- `scripts/smoke_package.sh` — local consumer smoke (path + working tree → cache).
- `.github/workflows/release.yml` — on `v*` tags: remote `noxc install @tag`, CLI
  scaffold, generated-app check.

## Checklist

1. All unit tests + `scripts/smoke_http.sh` + `scripts/smoke_package.sh` green locally.
2. `./scripts/check_release_refs.sh` passes.
3. Push code commit, then lock commit.
4. `git tag -a vX.Y.Z` on the lock commit; push the tag.
5. Confirm release workflow + CI are green.
6. `noxc publish github.com/mburakmmm/aether` (awaits index approval).
7. `gh release create vX.Y.Z ...`
