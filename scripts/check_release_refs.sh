#!/usr/bin/env bash
# Fail if VERSION / nox.json ref / nox.lock ref disagree.
# Run on the committed tree before CI path overrides (and before tagging).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ -z "$VERSION" ]]; then
  echo "VERSION file empty" >&2
  exit 1
fi
EXPECT_REF="v${VERSION}"

JSON_REF="$(python3 - <<'PY'
import json
print(json.load(open("nox.json"))["requires"][0]["ref"])
PY
)"
LOCK_REF="$(python3 - <<'PY'
import json
print(json.load(open("nox.lock"))["packages"][0]["ref"])
PY
)"
LOCK_REPO="$(python3 - <<'PY'
import json
print(json.load(open("nox.lock"))["packages"][0]["repo"])
PY
)"

if [[ "$JSON_REF" != "$EXPECT_REF" ]]; then
  echo "nox.json ref=$JSON_REF expected $EXPECT_REF" >&2
  exit 1
fi
if [[ "$LOCK_REF" != "$EXPECT_REF" ]]; then
  echo "nox.lock ref=$LOCK_REF expected $EXPECT_REF" >&2
  exit 1
fi
if [[ "$LOCK_REPO" != "github.com/mburakmmm/aether" ]]; then
  echo "nox.lock repo=$LOCK_REPO expected github.com/mburakmmm/aether" >&2
  exit 1
fi

echo "release refs ok: VERSION=$VERSION ref=$EXPECT_REF"
