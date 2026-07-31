#!/usr/bin/env bash
# Package-install smoke: consume Aether as a dependency and typecheck an importer.
# Uses the local checkout (path + HEAD SHA) so it works before the GitHub tag exists.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHA="$(git -C "$ROOT" rev-parse HEAD)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aether-pkg-smoke.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/src"
cat > "$TMP/nox.json" <<EOF
{
  "name": "aether-pkg-smoke",
  "entry": "src/main.nox",
  "requires": [
    {
      "alias": "aether",
      "repo": "$ROOT",
      "ref": "master"
    }
  ]
}
EOF
cat > "$TMP/nox.lock" <<EOF
{
  "packages": [
    {
      "alias": "aether",
      "repo": "$ROOT",
      "ref": "master",
      "resolved": "$SHA"
    }
  ]
}
EOF
cat > "$TMP/src/main.nox" <<'EOF'
import aether.config
import aether.application
from aether.config import Config
from aether.application import Application
from aether.module import ModuleBuilder
from aether.context import HttpContext
from aether.response import json_ok
from nox.http import HttpResponse

def build(app: Application) -> None:
    m: ModuleBuilder = app.module()
    def ping(ctx: HttpContext) -> HttpResponse:
        return json_ok("{\"pong\":true}")
    m.get("/ping", ping)

cfg: Config = aether.config.defaults("test")
cfg.log_requests = False
app: Application = aether.application.boot_with_config(cfg, build)
aether.application.shutdown(app)
print("package smoke ok")
EOF

# Sync working tree into the lock-resolved cache (uncommitted edits included).
CACHE="$HOME/.nox/pkg/mod${ROOT}/${SHA}"
mkdir -p "$(dirname "$CACHE")"
rsync -a --delete \
  --exclude '.git' --exclude '.nox' \
  "$ROOT/" "$CACHE/"

cd "$TMP"
noxc fetch
noxc check src/main.nox
noxc run src/main.nox
echo "smoke package ok"
