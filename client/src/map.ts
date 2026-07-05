/**
 * MapLibre setup with a fully self-hosted Protomaps basemap: a single .pmtiles
 * archive read via HTTP range, plus self-hosted glyphs and sprites. No tile CDN,
 * no API key, no third-party requests — so no one can profile which areas a
 * user pans across.
 */
import maplibregl, { type Map as MlMap, type StyleSpecification } from "maplibre-gl";
import { Protocol } from "pmtiles";
import { layers, namedFlavor } from "@protomaps/basemaps";

const DACH_CENTER: [number, number] = [10.5, 50.6];

function buildStyle(): StyleSpecification {
  const origin = location.origin;
  return {
    version: 8,
    glyphs: `${origin}/basemaps/fonts/{fontstack}/{range}.pbf`,
    sprite: `${origin}/basemaps/sprites/v4/light`,
    sources: {
      protomaps: {
        type: "vector",
        url: `pmtiles://${origin}/tiles/basemap.pmtiles`,
        attribution:
          '<a href="https://protomaps.com">Protomaps</a> © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>',
      },
    },
    layers: layers("protomaps", namedFlavor("light"), { lang: "de" }),
  };
}

export function initMap(container: HTMLElement): MlMap {
  const protocol = new Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  const map = new maplibregl.Map({
    container,
    style: buildStyle(),
    center: DACH_CENTER,
    zoom: 5.2,
    attributionControl: { compact: true },
    // Location comes from us via markers; keep the canvas gesture-friendly.
    dragRotate: false,
    pitchWithRotate: false,
  });
  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
  return map;
}
