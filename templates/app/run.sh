#!/usr/bin/env bash
# Launch with NOX_POOL_WORKERS set *before* noxc (required for --release $main pool).
set -euo pipefail
cd "$(dirname "$0")"
export AETHER_ENV="${AETHER_ENV:-development}"
export AETHER_WORKERS="${AETHER_WORKERS:-1}"
export NOX_POOL_WORKERS="${NOX_POOL_WORKERS:-$AETHER_WORKERS}"
exec noxc run main.nox
