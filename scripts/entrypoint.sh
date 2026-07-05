#!/bin/sh
# Runtime entrypoint. The basemap PMTiles archive lives on a persistent volume,
# not in the image, so it is fetched only when needed and survives rebuilds.
# It is (re-)extracted when the file is missing OR the requested region/zoom
# (BBOX/MAXZOOM) changed since last time — otherwise the existing file is kept.
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
  echo "[entrypoint] extracting basemap (bbox=$BBOX maxzoom=$MAXZOOM)…"
  PLANET="${PLANET_URL:-https://build.protomaps.com/$(curl -s https://build-metadata.protomaps.dev/builds.json | jq -r 'sort_by(.uploaded)[-1].key')}"
  echo "[entrypoint] planet: $PLANET"
  pmtiles extract "$PLANET" "$TILE_FILE.tmp" --bbox="$BBOX" --maxzoom="$MAXZOOM"
  mv "$TILE_FILE.tmp" "$TILE_FILE"
  printf '%s' "$WANT" > "$PARAMS_FILE"
  echo "[entrypoint] basemap ready — region=$WANT size=$(ls -lh "$TILE_FILE" | awk '{print $5}')"
else
  echo "[entrypoint] basemap present ($WANT, $(ls -lh "$TILE_FILE" | awk '{print $5}')), skipping extract"
fi

chown -R node:node "$TILES_DIR" 2>/dev/null || true
exec su-exec node:node npm run start
