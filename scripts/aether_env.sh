# Source-able launch env for Aether.
# Nox --release reads NOX_POOL_WORKERS at $main init; in-process set_var is too late.
aether_export_pool_workers() {
  export AETHER_WORKERS="${AETHER_WORKERS:-1}"
  if [[ -z "${NOX_POOL_WORKERS:-}" ]]; then
    export NOX_POOL_WORKERS="$AETHER_WORKERS"
  fi
}
