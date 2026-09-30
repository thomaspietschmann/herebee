#!/bin/bash
set -euo pipefail

SNAPSHOT="${SNAPSHOT:?set SNAPSHOT to a Geofabrik date, e.g. 260929}"
WORK="${WORK:?set WORK to an empty directory with room for the largest extract}"
REGIONS="${REGIONS:-europe north-america north-america/us central-america south-america}"
PLANETILER_VERSION="${PLANETILER_VERSION:-0.10.2}"
JAVA="${JAVA:-java}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SKIP='alps|britain-and-ireland|dach|great-britain|us|us-midwest|us-northeast|us-pacific|us-south|us-west'
BASE=https://download.geofabrik.de

md5of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }
sha256of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi; }

mkdir -p "$WORK/filtered"
cd "$WORK"
[ -s planetiler.jar ] || curl -fsSL -o planetiler.jar "https://github.com/onthegomap/planetiler/releases/download/v${PLANETILER_VERSION}/planetiler.jar"

for region in $REGIONS; do
  leaf="${region##*/}"
  children=$(curl -fsSL -A "Mozilla/5.0" "$BASE/$region.html" \
    | grep -oE "href=\"$leaf/[a-z-]+-latest\.osm\.pbf\"" | sed -E "s#href=\"$leaf/([a-z-]+)-latest.*#\1#" \
    | sort -u | grep -vxE "$SKIP" || true)
  [ -n "$children" ] || { echo "no extracts found for $region" >&2; exit 1; }
  for c in $children; do
    name="${region//\//-}-$c"
    [ -s "filtered/$name.osm.pbf" ] && continue
    url="$BASE/$region/$c-$SNAPSHOT.osm.pbf"
    ok=0
    for _ in 1 2 3; do
      if curl -fsSL -A "Mozilla/5.0" -o "$name.osm.pbf" "$url" && curl -fsSL -A "Mozilla/5.0" -o "$name.md5" "$url.md5" \
         && [ "$(md5of "$name.osm.pbf")" = "$(cut -d' ' -f1 "$name.md5")" ]; then
        ok=1; break
      fi
      sleep 20
    done
    [ "$ok" = 1 ] || { echo "download failed: $region/$c" >&2; exit 1; }
    osmium tags-filter "$name.osm.pbf" nwr/addr:housenumber -o "filtered/$name.osm.pbf" --overwrite
    rm -f "$name.osm.pbf" "$name.md5"
    echo "filtered $region/$c"
  done
done

osmium merge filtered/*.osm.pbf -o addr.osm.pbf --overwrite
sed "s#local_path: .*#local_path: addr.osm.pbf#" "$HERE/addresses.yml" > addresses.yml
out="addresses-20${SNAPSHOT}.pmtiles"
"$JAVA" ${JAVA_OPTS:--Xmx24g} -jar planetiler.jar generate-custom --schema=addresses.yml --output="$out" --maxzoom=14 --force
sha256of "$out" > "$out.sha256"
echo "built $WORK/$out"
