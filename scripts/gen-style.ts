/**
 * Generate the MapLibre style JSON that the NATIVE apps load.
 *
 * The web client builds its style in the browser (client/src/map.ts) because it
 * can read `location.origin` and import @protomaps/basemaps from the bundle.
 * The native apps can do neither, so they fetch a ready-made style from
 * `/style/{lang}.json`. This script emits those files at build time, one per
 * supported UI language (Protomaps' `layers()` bakes the label language into
 * the layer definitions, so it cannot be switched at runtime).
 *
 * Origins are written as the placeholder `__HEREBEE_ORIGIN__`; the server
 * substitutes the real one per request (see serveStyle in server/src/index.ts).
 * Baking an absolute origin in here would mean a rebuild per domain and would
 * hand dev builds the production host — the same reason index.html's OG tags are
 * localized at request time rather than at build time.
 *
 * Runs from `npm run build`, AFTER vite (which empties client/dist).
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { layers, namedFlavor } from "@protomaps/basemaps";
import type { OgLang } from "../shared/og.js";

/** Keep in sync with client/src/i18n.ts's SUPPORTED. */
const LANGS: readonly OgLang[] = ["de", "en", "es", "it", "fr", "pt"];

/** Replaced per request by the server. Must not appear in any real URL. */
const ORIGIN = "__HEREBEE_ORIGIN__";

/**
 * Replaced per request with a token tied to the current basemap.pmtiles (see
 * tilesVersion() in server/src/index.ts). Busts native apps' ambient HTTP
 * cache whenever the archive is swapped for a different region/zoom — without
 * it, a client that already has a cached "no tile here" response for some area
 * keeps trusting it until the "week" Cache-Control lifetime runs out, even
 * though the server is now serving a completely different archive.
 */
const TILES_VERSION = "__HEREBEE_TILES_VERSION__";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "..", "client", "dist", "style");

// Identical to client/src/map.ts's buildStyle(), except for the absolute origin,
// the per-language `lang`, and the tiles URL's `?v=` cache-buster (the browser
// doesn't need one: it never persists a cross-session ambient cache the way the
// native apps' MapLibre runtime does). If that function changes, change this
// too — the apps and the browser must render the same map.
function buildStyle(lang: OgLang): unknown {
  return {
    version: 8,
    glyphs: `${ORIGIN}/basemaps/fonts/{fontstack}/{range}.pbf`,
    sprite: `${ORIGIN}/basemaps/sprites/v4/light`,
    sources: {
      protomaps: {
        type: "vector",
        url: `pmtiles://${ORIGIN}/tiles/basemap.pmtiles?v=${TILES_VERSION}`,
        attribution:
          '<a href="https://protomaps.com">Protomaps</a> © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>',
      },
    },
    layers: layers("protomaps", namedFlavor("light"), { lang }),
  };
}

mkdirSync(OUT_DIR, { recursive: true });
for (const lang of LANGS) {
  const file = join(OUT_DIR, `${lang}.json`);
  writeFileSync(file, JSON.stringify(buildStyle(lang)) + "\n", "utf8");
}
console.log(`wrote ${LANGS.length} style files to ${OUT_DIR}`);
