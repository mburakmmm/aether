#!/usr/bin/env bash
# aether new from outside the package tree must pin this VERSION, then fetch and check.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"
WORK="$(mktemp -d)"
cd "$WORK"
unset AETHER_ROOT || true
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${HOME}/.nox-lang/bin:${PATH:-}"
noxc run "$ROOT/cli.nox" -- new demo
python3 - "$VER" <<'PY'
import json, sys
ver = sys.argv[1]
data = json.load(open("demo/nox.json"))
ref = data["requires"][0]["ref"]
repo = data["requires"][0]["repo"]
if ref != "v" + ver:
    raise SystemExit("scaffold ref %s != v%s" % (ref, ver))
if repo != "github.com/mburakmmm/aether":
    raise SystemExit("scaffold repo " + repo)
if "v0.6.4" in open("demo/nox.json").read():
    raise SystemExit("old ref still present")
print("scaffold ref", ref)
PY
cd demo
noxc fetch
noxc check main.nox
echo "smoke scaffold ok"
