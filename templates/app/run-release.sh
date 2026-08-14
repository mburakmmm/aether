#!/usr/bin/env bash
# Production binary: export pool size before exec (Nox 1.29.5+ --release).
set -euo pipefail
cd "$(dirname "$0")"
export AETHER_ENV="${AETHER_ENV:-production}"
export AETHER_WORKERS="${AETHER_WORKERS:-1}"
export NOX_POOL_WORKERS="${NOX_POOL_WORKERS:-$AETHER_WORKERS}"
BIN="${AETHER_BIN:-./app}"
if [[ ! -x "$BIN" ]]; then
  noxc build --release -o "$BIN" main.nox
fi
exec "$BIN"
