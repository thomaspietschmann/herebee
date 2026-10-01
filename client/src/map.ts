/**
 * MapLibre setup with a fully self-hosted Protomaps basemap: a single .pmtiles
 * archive read via HTTP range, plus self-hosted glyphs and sprites. No tile CDN,
 * no API key, no third-party requests — so no one can profile which areas a
 * user pans across.
 */
import maplibregl, { type Map as MlMap, type StyleSpecification } from "maplibre-gl";
import { Protocol } from "pmtiles";
import { layers } from "@protomaps/basemaps";
import { ADDRESSES_SOURCE, withAddressLayer } from "../../shared/addresses.js";
import { themeFlavor, themeSprite, type MapTheme } from "../../shared/map-theme.js";

const DACH_CENTER: [number, number] = [10.5, 50.6];

function buildStyle(theme: MapTheme): StyleSpecification {
  const origin = location.origin;
  const flavor = themeFlavor(theme);
  return {
    version: 8,
    glyphs: `${origin}/basemaps/fonts/{fontstack}/{range}.pbf`,
    sprite: `${origin}/basemaps/sprites/v4/${themeSprite(theme)}`,
    sources: {
      protomaps: {
        type: "vector",
        url: `pmtiles://${origin}/tiles/basemap.pmtiles`,
        attribution:
          '<a href="https://protomaps.com">Protomaps</a> © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>',
      },
      [ADDRESSES_SOURCE]: {
        type: "vector",
        url: `pmtiles://${origin}/tiles/addresses.pmtiles`,
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>',
      },
    },
    layers: withAddressLayer(layers("protomaps", flavor, { lang: "de" }), flavor) as StyleSpecification["layers"],
  };
}

export function setMapTheme(map: MlMap, theme: MapTheme): void {
  map.setStyle(buildStyle(theme));
}

export function initMap(container: HTMLElement, theme: MapTheme): MlMap {
  const protocol = new Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  const map = new maplibregl.Map({
    container,
    style: buildStyle(theme),
    center: DACH_CENTER,
    zoom: 5.2,
    // No on-map attribution badge — it's shown in the "i" info sheet instead
    // (see ui.ts). No zoom buttons either: touch pinch / double-tap covers zoom.
    attributionControl: false,
    // Location comes from us via markers; keep the canvas gesture-friendly.
    dragRotate: false,
    pitchWithRotate: false,
  });
  return map;
}
