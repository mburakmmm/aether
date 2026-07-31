#!/usr/bin/env bash
# Cross-framework HTTP microbenchmark: Aether (Nox) vs NestJS vs Gin.
# Requires: wrk, curl, noxc, go, node/npm
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$ROOT/benchmarks"
OUT="$BENCH/results"
mkdir -p "$OUT"

DURATION="${DURATION:-15s}"
CONNECTIONS="${CONNECTIONS:-50}"
THREADS="${THREADS:-4}"
AETHER_PORT="${AETHER_PORT:-3001}"
NEST_PORT="${NEST_PORT:-3002}"
GIN_PORT="${GIN_PORT:-3003}"
AETHER_WORKERS="${AETHER_WORKERS:-1}"

PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

wait_http() {
  local url="$1"
  local i=0
  while [[ $i -lt 60 ]]; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  echo "timeout waiting for $url" >&2
  return 1
}

run_wrk() {
  local name="$1"
  local url="$2"
  local extra="${3:-}"
  local file="$OUT/${name}.txt"
  echo "=== wrk $name $url ===" | tee "$file"
  # shellcheck disable=SC2086
  wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" $extra "$url" | tee -a "$file"
}

echo "Building NestJS..."
(
  cd "$BENCH/nestjs"
  npm install --silent
  npm run build --silent
)

echo "Building Gin..."
(
  cd "$BENCH/gin"
  go mod tidy
  go build -o "$OUT/gin-bench" .
)

echo "Starting Gin on :$GIN_PORT"
PORT="$GIN_PORT" "$OUT/gin-bench" >/tmp/gin-bench-server.log 2>&1 &
PIDS+=($!)

echo "Starting NestJS on :$NEST_PORT"
(
  cd "$BENCH/nestjs"
  PORT="$NEST_PORT" node dist/main.js >/tmp/nestjs-bench-server.log 2>&1
) &
PIDS+=($!)

echo "Starting Aether on :$AETHER_PORT workers=$AETHER_WORKERS"
(
  cd "$ROOT"
  AETHER_ENV=production \
  AETHER_PORT="$AETHER_PORT" \
  AETHER_WORKERS="$AETHER_WORKERS" \
  AETHER_LOG_REQUESTS=0 \
  AETHER_OPENAPI=0 \
  noxc run benchmarks/aether/main.nox >/tmp/aether-bench-server.log 2>&1
) &
PIDS+=($!)

wait_http "http://127.0.0.1:$GIN_PORT/ping"
wait_http "http://127.0.0.1:$NEST_PORT/ping"
wait_http "http://127.0.0.1:$AETHER_PORT/ping"

echo "Warmup..."
curl -fsS "http://127.0.0.1:$AETHER_PORT/ping" >/dev/null
curl -fsS "http://127.0.0.1:$NEST_PORT/ping" >/dev/null
curl -fsS "http://127.0.0.1:$GIN_PORT/ping" >/dev/null

run_wrk "aether_ping" "http://127.0.0.1:$AETHER_PORT/ping"
run_wrk "nestjs_ping" "http://127.0.0.1:$NEST_PORT/ping"
run_wrk "gin_ping" "http://127.0.0.1:$GIN_PORT/ping"

LUA="$OUT/echo.lua"
cat >"$LUA" <<'EOF'
wrk.method = "POST"
wrk.body   = '{"msg":"hello"}'
wrk.headers["Content-Type"] = "application/json"
EOF

run_wrk "aether_echo" "http://127.0.0.1:$AETHER_PORT/echo" "-s $LUA"
run_wrk "nestjs_echo" "http://127.0.0.1:$NEST_PORT/echo" "-s $LUA"
run_wrk "gin_echo" "http://127.0.0.1:$GIN_PORT/echo" "-s $LUA"

echo "Results written under $OUT"
