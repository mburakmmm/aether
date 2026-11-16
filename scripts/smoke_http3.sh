#!/usr/bin/env bash
# Live HTTP/3 handshake. Skips with exit 0 when the HTTP/3 client is missing,
# unless AETHER_HTTP3_REQUIRED=1. OpenSSL >= 3.5 is loaded by Nox at run time.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${AETHER_PORT:-34733}"
cd "$ROOT"

CURL_BIN="${AETHER_CURL:-}"
if [[ -z "$CURL_BIN" ]]; then
  if [[ -x /opt/homebrew/opt/curl/bin/curl ]]; then
    CURL_BIN=/opt/homebrew/opt/curl/bin/curl
  else
    CURL_BIN="$(command -v curl)"
  fi
fi

if ! "$CURL_BIN" -V | tr ' ' '\n' | grep -qx HTTP3; then
  echo "http3 client missing ($CURL_BIN)"
  if [[ "${AETHER_HTTP3_REQUIRED:-0}" == "1" ]]; then
    exit 1
  fi
  echo "smoke http3 skipped"
  exit 0
fi

OPENSSL_BIN="${OPENSSL_BIN:-}"
if [[ -z "$OPENSSL_BIN" ]]; then
  if [[ -x /opt/homebrew/opt/openssl@3/bin/openssl ]]; then
    OPENSSL_BIN=/opt/homebrew/opt/openssl@3/bin/openssl
  else
    OPENSSL_BIN="$(command -v openssl)"
  fi
fi

OUT="${TMPDIR:-/tmp}/aether-http3"
rm -rf "$OUT"
mkdir -p "$OUT"
LOG="$OUT/server.log"
CERT="$OUT/cert.pem"
KEY="$OUT/key.pem"

"$OPENSSL_BIN" req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 1 -nodes \
  -subj "/CN=localhost" >/dev/null 2>&1

kill_port() {
  local pids
  pids="$(lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
  local upids
  upids="$(lsof -nP -tiUDP:"$PORT" 2>/dev/null || true)"
  if [[ -n "$upids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $upids 2>/dev/null || true
  fi
}

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  kill_port
}
trap cleanup EXIT
kill_port

export AETHER_ENV=production
export AETHER_PORT="$PORT"
export AETHER_WORKERS=1
export NOX_POOL_WORKERS=1
export AETHER_HTTP3=1
export AETHER_WS=0
export AETHER_RATE_LIMIT=0
export AETHER_TLS_CERT="$CERT"
export AETHER_TLS_KEY="$KEY"
export AETHER_OPENAPI=0
export AETHER_LOG_REQUESTS=0
export AETHER_REQUEST_ID=0
export AETHER_METRICS=0
export AETHER_CORS_ORIGINS=
export AETHER_REQUEST_HEADERS=1

noxc run benchmarks/http3_probe/main.nox >"$LOG" 2>&1 &
PID=$!

ok=0
for _ in $(seq 1 120); do
  if "$CURL_BIN" -fsS -k "https://127.0.0.1:${PORT}/who" >/dev/null 2>&1; then
    ok=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "http3 server exited" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  sleep 0.5
done
if [[ "$ok" != "1" ]]; then
  echo "http3 server did not become ready" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

if grep -q "HTTP/3 requested but OpenSSL" "$LOG"; then
  echo "OpenSSL >= 3.5 was not loaded" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

headers="$("$CURL_BIN" -sS -D - -o /dev/null -k "https://127.0.0.1:${PORT}/who")"
echo "$headers" | grep -i 'alt-svc:' | grep -q 'h3'

marked="$("$CURL_BIN" -sS --http3 -k -H 'X-Mark: 1' "https://127.0.0.1:${PORT}/who")"
echo "$marked" | grep -q '"saw":""'
second="$("$CURL_BIN" -sS --http3 -k "https://127.0.0.1:${PORT}/who")"
echo "$second" | grep -q '"saw":""'
if echo "$second" | grep -q 'secret-token'; then
  echo "http3 request saw the previous token: $second" >&2
  exit 1
fi
echo "$second" | grep -q '"peer":""'

echo "smoke http3 ok"
