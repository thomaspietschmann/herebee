#!/bin/bash
set -euo pipefail

SNAPSHOT="${SNAPSHOT:?set SNAPSHOT to a Geofabrik date, e.g. 260929}"
WORK="${WORK:?set WORK to an empty directory with room for the largest country extract}"
PLANETILER_VERSION="${PLANETILER_VERSION:-0.10.2}"
JAVA="${JAVA:-java}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SKIP='alps|britain-and-ireland|dach|great-britain'

md5of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }
sha256of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }

mkdir -p "$WORK/filtered"
cd "$WORK"
[ -s planetiler.jar ] || curl -fsSL -o planetiler.jar "https://github.com/onthegomap/planetiler/releases/download/v${PLANETILER_VERSION}/planetiler.jar"

countries=$(curl -fsSL -A "Mozilla/5.0" https://download.geofabrik.de/europe.html \
  | grep -oE 'href="europe/[a-z-]+-latest\.osm\.pbf"' | sed -E 's#href="europe/([a-z-]+)-latest.*#\1#' \
  | sort -u | grep -vxE "$SKIP")

for c in $countries; do
  [ -s "filtered/$c.osm.pbf" ] && continue
  url="https://download.geofabrik.de/europe/$c-$SNAPSHOT.osm.pbf"
  ok=0
  for _ in 1 2 3; do
    if curl -fsSL -A "Mozilla/5.0" -o "$c.osm.pbf" "$url" && curl -fsSL -A "Mozilla/5.0" -o "$c.md5" "$url.md5" \
       && [ "$(md5of "$c.osm.pbf")" = "$(cut -d' ' -f1 "$c.md5")" ]; then
      ok=1; break
    fi
    sleep 20
  done
  [ "$ok" = 1 ] || { echo "download failed: $c" >&2; exit 1; }
  osmium tags-filter "$c.osm.pbf" nwr/addr:housenumber -o "filtered/$c.osm.pbf" --overwrite
  rm -f "$c.osm.pbf" "$c.md5"
  echo "filtered $c"
done

osmium merge filtered/*.osm.pbf -o europe-addr.osm.pbf --overwrite
cp "$HERE/addresses.yml" addresses.yml
out="addresses-europe-20${SNAPSHOT}.pmtiles"
"$JAVA" -Xmx24g -jar planetiler.jar generate-custom --schema=addresses.yml --output="$out" --maxzoom=14 --force
sha256of "$out" > "$out.sha256"
echo "built $WORK/$out"
