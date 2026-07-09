#!/bin/sh
# Runtime entrypoint. The basemap PMTiles archive lives on a persistent volume,
# not in the image. It is (re-)extracted only when missing OR when the requested
# region/zoom (BBOX/MAXZOOM) changed. The extract runs in the BACKGROUND so the
# server always starts within seconds and the healthcheck passes immediately;
# the map simply fills in once the (rare) download completes.
set -e

TILES_DIR="${ASSETS_DIR:-/app/server/assets}/tiles"
TILE_FILE="$TILES_DIR/basemap.pmtiles"
PARAMS_FILE="$TILES_DIR/.params"
BBOX="${BBOX:-5.5,45.5,17.2,55.1}"
MAXZOOM="${MAXZOOM:-14}"
WANT="$BBOX@$MAXZOOM"

mkdir -p "$TILES_DIR"

HAVE=""
[ -f "$PARAMS_FILE" ] && HAVE="$(cat "$PARAMS_FILE")"

if [ ! -s "$TILE_FILE" ] || [ "$HAVE" != "$WANT" ]; then
  echo "[entrypoint] tiles need (re-)extract (bbox=$BBOX maxzoom=$MAXZOOM) — running in background…"
  (
    PLANET="${PLANET_URL:-https://build.protomaps.com/$(curl -s https://build-metadata.protomaps.dev/builds.json | jq -r 'sort_by(.uploaded)[-1].key')}"
    echo "[entrypoint] planet: $PLANET"
    if pmtiles extract "$PLANET" "$TILE_FILE.tmp" --bbox="$BBOX" --maxzoom="$MAXZOOM"; then
      mv "$TILE_FILE.tmp" "$TILE_FILE"
      printf '%s' "$WANT" > "$PARAMS_FILE"
      chown -R node:node "$TILES_DIR" 2>/dev/null || true
      echo "[entrypoint] basemap ready — region=$WANT size=$(ls -lh "$TILE_FILE" | awk '{print $5}')"
    else
      echo "[entrypoint] extract FAILED; leaving any existing basemap in place"
      rm -f "$TILE_FILE.tmp"
    fi
  ) &
else
  echo "[entrypoint] basemap present ($WANT, $(ls -lh "$TILE_FILE" | awk '{print $5}')), skipping extract"
fi

chown -R node:node "$TILES_DIR" 2>/dev/null || true
exec su-exec node:node npm run start
