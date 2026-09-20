#!/usr/bin/env bash
# Cross-implementation interop: a Node "browser" peer and the Flutter app's real
# NetClient join ONE room through a real relay and must decrypt each other.
#
# The unit vectors (npm run test:vectors, flutter test) prove each side matches a
# recorded expectation. This proves the two sides actually talk, over a live
# socket, with the production-shaped origin policy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
DART="${DART:-$HOME/development/flutter/bin/dart}"
PORT="${PORT:-3110}"
WS_URL="ws://127.0.0.1:${PORT}/ws"
TMP="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

cd "$ROOT"

# Production-shaped: the app origin must be explicitly allowed, exactly as it
# will be in Coolify. Running with an empty list would hide a misconfiguration.
ALLOWED_ORIGINS="https://herebee.app,app://herebee" PORT="$PORT" \
  npx tsx server/src/index.ts > "$TMP/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 60); do
  curl -sf "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -sf "http://127.0.0.1:${PORT}/healthz" >/dev/null || { echo "relay did not start"; cat "$TMP/server.log"; exit 1; }

SECRET="$(npx tsx -e 'import("./client/src/crypto.js").then(m=>process.stdout.write(m.generateSecret()))')"
echo "→ room secret minted; starting both peers"

npx tsx test/interop-web-peer.ts "$SECRET" "$WS_URL" "$TMP/web.json" > "$TMP/web.log" 2>&1 &
WEB_PID=$!

( cd "$ROOT/mobile" && "$DART" run tool/interop_app_peer.dart "$SECRET" "$WS_URL" "$TMP/app.json" ) > "$TMP/app.log" 2>&1 &
APP_PID=$!

APP_RC=0; WEB_RC=0
wait "$APP_PID" || APP_RC=$?
wait "$WEB_PID" || WEB_RC=$?

echo "--- web peer ---"; cat "$TMP/web.log" || true
echo "--- app peer ---"; cat "$TMP/app.log" || true

if [ "$APP_RC" -ne 0 ] || [ "$WEB_RC" -ne 0 ]; then
  echo "✗ interop FAILED (web=$WEB_RC app=$APP_RC)"
  echo "--- relay log ---"; cat "$TMP/server.log" || true
  exit 1
fi

# Both must have landed in the SAME room. A mismatch here is the exact failure
# the room derivation could otherwise hide: two valid ids, two empty rooms.
WEB_ROOM="$(node -e 'console.log(require(process.argv[1]).roomId)' "$TMP/web.json")"
APP_ROOM="$(node -e 'console.log(require(process.argv[1]).roomId)' "$TMP/app.json")"
if [ "$WEB_ROOM" != "$APP_ROOM" ]; then
  echo "✗ room ids differ: web=$WEB_ROOM app=$APP_ROOM"
  exit 1
fi

echo "✓ interop passed — both peers decrypted each other in room $WEB_ROOM"
