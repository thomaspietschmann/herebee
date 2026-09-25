#!/usr/bin/env bash
# Fetch the self-hosted map assets:
#   - a worldwide PMTiles extract (default: whole world, maxzoom 12) from the
#     latest Protomaps planet build, read via HTTP range (the planet is never
#     fully downloaded)
#   - the Protomaps basemap fonts (glyphs) and sprites, for zero third-party calls
#
# Env overrides:
#   BBOX     minLon,minLat,maxLon,maxLat   (default whole world)
#   MAXZOOM  max zoom level                (default 12; was 14 for the old DACH-only extract)
#   OUT      output pmtiles path           (default server/assets/tiles/dach.pmtiles)
#   PLANET   explicit planet URL           (default: resolve latest build)
set -euo pipefail

PMTILES_VERSION="${PMTILES_VERSION:-1.30.3}"
BBOX="${BBOX:--180,-85,180,85}"   # old default: 5.5,45.5,17.2,55.1 (DACH)
MAXZOOM="${MAXZOOM:-12}"          # old default: 14
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/server/assets/tiles/basemap.pmtiles}"
ASSETS="$ROOT/server/assets/basemaps"
BIN_DIR="$ROOT/.bin"

mkdir -p "$(dirname "$OUT")" "$ASSETS" "$BIN_DIR"

# --- resolve pmtiles CLI ---------------------------------------------------
PMTILES_BIN="$(command -v pmtiles || true)"
if [ -z "$PMTILES_BIN" ]; then
  PMTILES_BIN="$BIN_DIR/pmtiles"
  if [ ! -x "$PMTILES_BIN" ]; then
    OS="$(uname -s)"; ARCH="$(uname -m)"
    case "$OS/$ARCH" in
      Linux/x86_64)   ASSET="go-pmtiles_${PMTILES_VERSION}_Linux_x86_64.tar.gz"; KIND=tar ;;
      Darwin/arm64)   ASSET="go-pmtiles-${PMTILES_VERSION}_Darwin_arm64.zip";    KIND=zip ;;
      Darwin/x86_64)  ASSET="go-pmtiles-${PMTILES_VERSION}_Darwin_x86_64.zip";   KIND=zip ;;
      *) echo "unsupported platform $OS/$ARCH" >&2; exit 1 ;;
    esac
    URL="https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/${ASSET}"
    echo "→ downloading pmtiles CLI: $ASSET"
    if [ "$KIND" = tar ]; then
      curl -sSL "$URL" | tar -xz -C "$BIN_DIR" pmtiles
    else
      curl -sSL -o "$BIN_DIR/pmtiles.zip" "$URL"
      unzip -o "$BIN_DIR/pmtiles.zip" pmtiles -d "$BIN_DIR" >/dev/null
      rm -f "$BIN_DIR/pmtiles.zip"
    fi
    chmod +x "$PMTILES_BIN"
  fi
fi

# --- resolve latest planet build ------------------------------------------
if [ -n "${PLANET:-}" ]; then
  PLANET_URL="$PLANET"
else
  KEY="$(curl -s https://build-metadata.protomaps.dev/builds.json | \
    (command -v jq >/dev/null && jq -r 'sort_by(.uploaded)[-1].key' || \
     grep -oE '"key":"[0-9]+\.pmtiles"' | tail -1 | sed 's/.*:"//;s/"//'))"
  PLANET_URL="https://build.protomaps.com/${KEY}"
fi
echo "→ planet: $PLANET_URL"

# --- extract region --------------------------------------------------------
echo "→ extracting bbox=$BBOX maxzoom=$MAXZOOM → $OUT"
"$PMTILES_BIN" extract "$PLANET_URL" "$OUT" --bbox="$BBOX" --maxzoom="$MAXZOOM"

# --- fonts + sprites -------------------------------------------------------
if [ ! -d "$ASSETS/fonts" ] || [ ! -d "$ASSETS/sprites" ]; then
  echo "→ fetching fonts + sprites (protomaps/basemaps-assets)"
  TMP="$(mktemp -d)"
  git clone --depth 1 https://github.com/protomaps/basemaps-assets.git "$TMP/assets"
  cp -R "$TMP/assets/fonts" "$ASSETS/fonts"
  cp -R "$TMP/assets/sprites" "$ASSETS/sprites"
  rm -rf "$TMP"
fi

echo "✓ assets ready in $ROOT/server/assets"
ls -lh "$OUT"
