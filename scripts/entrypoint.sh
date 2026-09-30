#!/bin/sh
# Runtime entrypoint. The basemap PMTiles archive lives on a persistent volume,
# not in the image. It is (re-)extracted only when missing OR when the requested
# region/zoom (BBOX/MAXZOOM) changed. The extract runs in the BACKGROUND so the
# server always starts within seconds and the healthcheck passes immediately;
# the map simply fills in once the (rare) download completes.
#
# When BBOX/MAXZOOM changed from the last extract, the old file is removed
# before re-extracting rather than kept alongside the new one: a changed
# region/zoom can be an arbitrarily different size, and the volume is not
# guaranteed to have room for both at once. This trades a brief basemap gap
# (until the new extract lands) for never filling the disk on a config change.
#
# Both the extract and the server run UNPRIVILEGED as the `node` user. The extract
# pulls a remote planet file and writes the volume, so it must not run as root.
set -e

TILES_DIR="${ASSETS_DIR:-/app/server/assets}/tiles"
TILE_FILE="$TILES_DIR/basemap.pmtiles"
PARAMS_FILE="$TILES_DIR/.params"
BBOX="${BBOX:--180,-85,180,85}"   # old default: 5.5,45.5,17.2,55.1 (DACH)
MAXZOOM="${MAXZOOM:-12}"          # old default: 14
WANT="$BBOX@$MAXZOOM"

mkdir -p "$TILES_DIR"
# The tiles volume may mount root-owned; hand it to the unprivileged node user
# up front so both the extract and the server can write it without root.
chown -R node:node "$TILES_DIR" 2>/dev/null || true

HAVE=""
[ -f "$PARAMS_FILE" ] && HAVE="$(cat "$PARAMS_FILE")"

if [ ! -s "$TILE_FILE" ] || [ "$HAVE" != "$WANT" ]; then
  if [ -n "$HAVE" ] && [ "$HAVE" != "$WANT" ] && [ -s "$TILE_FILE" ]; then
    echo "[entrypoint] region/zoom changed ($HAVE -> $WANT) — removing old basemap to make room before re-extract"
    rm -f "$TILE_FILE"
  fi
  echo "[entrypoint] tiles need (re-)extract (bbox=$BBOX maxzoom=$MAXZOOM) — running in background as node…"
  export TILES_DIR TILE_FILE PARAMS_FILE BBOX MAXZOOM WANT
  # Drop root: the network fetch + extract runs as node and writes node-owned files.
  su-exec node:node sh -c '
    PLANET="${PLANET_URL:-https://build.protomaps.com/$(curl -s https://build-metadata.protomaps.dev/builds.json | jq -r "sort_by(.uploaded)[-1].key")}"
    echo "[entrypoint] planet: $PLANET"
    if pmtiles extract "$PLANET" "$TILE_FILE.tmp" --bbox="$BBOX" --maxzoom="$MAXZOOM"; then
      mv "$TILE_FILE.tmp" "$TILE_FILE"
      printf "%s" "$WANT" > "$PARAMS_FILE"
      echo "[entrypoint] basemap ready — region=$WANT"
      ls -lh "$TILE_FILE" || true
    else
      echo "[entrypoint] extract FAILED; basemap stays missing/stale until the next successful start"
      rm -f "$TILE_FILE.tmp"
    fi
  ' &
else
  echo "[entrypoint] basemap present ($WANT, $(ls -lh "$TILE_FILE" | awk '{print $5}')), skipping extract"
fi

ADDR_FILE="$TILES_DIR/addresses.pmtiles"
ADDR_PARAMS="$TILES_DIR/.addresses"
ADDRESSES_URL="${ADDRESSES_URL-https://github.com/thomaspietschmann/herebee/releases/download/addresses-europe-20260929/addresses-europe-20260929.pmtiles}"
ADDRESSES_SHA256="${ADDRESSES_SHA256-4b17203be05d6d8f17961308d7dee8256979ca4dca4ab996a3e43ab542058280}"
ADDR_HAVE=""
[ -f "$ADDR_PARAMS" ] && ADDR_HAVE="$(cat "$ADDR_PARAMS")"

if [ -z "$ADDRESSES_URL" ]; then
  echo "[entrypoint] ADDRESSES_URL empty — house numbers disabled"
elif [ ! -s "$ADDR_FILE" ] || [ "$ADDR_HAVE" != "$ADDRESSES_SHA256" ]; then
  echo "[entrypoint] house numbers need download — running in background as node…"
  export ADDR_FILE ADDR_PARAMS ADDRESSES_URL ADDRESSES_SHA256
  su-exec node:node sh -c '
    rm -f "$ADDR_FILE.tmp"
    if curl -fsSL -o "$ADDR_FILE.tmp" "$ADDRESSES_URL" \
       && echo "$ADDRESSES_SHA256  $ADDR_FILE.tmp" | sha256sum -c - >/dev/null; then
      mv "$ADDR_FILE.tmp" "$ADDR_FILE"
      printf "%s" "$ADDRESSES_SHA256" > "$ADDR_PARAMS"
      echo "[entrypoint] house numbers ready"
      ls -lh "$ADDR_FILE" || true
    else
      echo "[entrypoint] house number download FAILED or checksum mismatch; keeping the previous file"
      rm -f "$ADDR_FILE.tmp"
    fi
  ' &
else
  echo "[entrypoint] house numbers present ($(ls -lh "$ADDR_FILE" | awk '{print $5}')), skipping download"
fi

exec su-exec node:node npm run start
