#!/bin/sh
# Runtime entrypoint. The DACH PMTiles archive lives on a persistent volume, not
# in the image, so it is fetched exactly ONCE (first boot) and survives every
# rebuild/redeploy. To refresh it later, delete the file on the volume and redeploy.
set -e

TILES_DIR="${ASSETS_DIR:-/app/server/assets}/tiles"
TILE_FILE="$TILES_DIR/dach.pmtiles"
BBOX="${BBOX:-5.5,45.5,17.2,55.1}"
MAXZOOM="${MAXZOOM:-14}"

mkdir -p "$TILES_DIR"

if [ ! -s "$TILE_FILE" ]; then
  echo "[entrypoint] tiles missing — extracting DACH once (bbox=$BBOX maxzoom=$MAXZOOM)…"
  PLANET="${PLANET_URL:-https://build.protomaps.com/$(curl -s https://build-metadata.protomaps.dev/builds.json | jq -r 'sort_by(.uploaded)[-1].key')}"
  echo "[entrypoint] planet: $PLANET"
  pmtiles extract "$PLANET" "$TILE_FILE.tmp" --bbox="$BBOX" --maxzoom="$MAXZOOM"
  mv "$TILE_FILE.tmp" "$TILE_FILE"
  echo "[entrypoint] tiles ready ($(ls -lh "$TILE_FILE" | awk '{print $5}'))"
else
  echo "[entrypoint] tiles present on volume, skipping extract"
fi

# Make the volume writable by the unprivileged user, then drop privileges.
chown -R node:node "$TILES_DIR" 2>/dev/null || true
exec su-exec node:node npm run start
