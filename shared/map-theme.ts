import { namedFlavor, type Flavor } from "@protomaps/basemaps";

export type MapTheme = "light" | "dark" | "synthwave";
export const MAP_THEMES: readonly MapTheme[] = ["light", "dark", "synthwave"];

const roads = (casing: string, minor: string, major: string, highway: string) => ({
  minor_service_casing: casing,
  minor_casing: casing,
  link_casing: casing,
  major_casing_late: casing,
  highway_casing_late: casing,
  major_casing_early: casing,
  highway_casing_early: casing,
  bridges_other_casing: casing,
  bridges_minor_casing: casing,
  bridges_link_casing: casing,
  bridges_major_casing: casing,
  bridges_highway_casing: casing,
  other: minor,
  minor_service: minor,
  minor_a: minor,
  minor_b: minor,
  bridges_other: minor,
  bridges_minor: minor,
  link: major,
  major,
  bridges_link: major,
  bridges_major: major,
  highway,
  bridges_highway: highway,
});

function night(): Flavor {
  const base = namedFlavor("dark");
  const earth = "#141920";
  const buildings = "#1d242d";
  const park = "#15261f";
  const park2 = "#1a3327";
  const label = "#e8edf2";
  const label2 = "#8a94a6";
  const halo = "#0e1116";
  const rail = "#3a4452";
  return {
    ...base,
    background: "#0b0e12",
    earth,
    buildings,
    pedestrian: earth,
    park_a: park,
    park_b: park2,
    wood_a: park,
    wood_b: park2,
    scrub_a: park,
    scrub_b: park2,
    zoo: park,
    school: earth,
    hospital: earth,
    industrial: buildings,
    aerodrome: buildings,
    sand: earth,
    beach: earth,
    water: "#0f3a3c",
    railway: rail,
    boundaries: rail,
    ...roads("#0e1217", "#262e38", "#343d49", "#c4922f"),
    roads_label_minor: label2,
    roads_label_minor_halo: halo,
    roads_label_major: "#a3adbd",
    roads_label_major_halo: halo,
    city_label: label,
    city_label_halo: halo,
    subplace_label: label2,
    subplace_label_halo: halo,
    state_label: label2,
    state_label_halo: halo,
    country_label: label2,
    address_label: "#7d8797",
    address_label_halo: halo,
    ocean_label: "#34e1b4",
  };
}

/**
 * Synthwave ("Grid Toxic"): a near-black ground with a glowing neon-green
 * street wireframe, hot-pink arteries and teal-black water. Labels are pale
 * tints on near-black halos so they stay legible over the bright lines.
 */
function synthwave(): Flavor {
  const base = namedFlavor("dark");
  const ground = "#010403";
  const earth = "#020705";
  const buildings = "#08140f";
  const park = "#03110a";
  const park2 = "#04180e";
  const minor = "#2fd85a";
  const pink = "#ff2bd6";
  const tunnel = "#0c3f24";
  const label = "#eefff2";
  const label2 = "#8fd8a6";
  const roadLabel = "#d2ffde";
  return {
    ...base,
    background: ground,
    earth,
    buildings,
    pedestrian: earth,
    park_a: park,
    park_b: park2,
    wood_a: park,
    wood_b: park2,
    scrub_a: park,
    scrub_b: park2,
    zoo: park,
    glacier: earth,
    school: earth,
    hospital: earth,
    military: earth,
    industrial: buildings,
    aerodrome: buildings,
    runway: minor,
    pier: minor,
    sand: earth,
    beach: earth,
    water: "#03262a",
    railway: "#3a1a4a",
    boundaries: pink,
    tunnel_other_casing: ground,
    tunnel_minor_casing: ground,
    tunnel_link_casing: ground,
    tunnel_major_casing: ground,
    tunnel_highway_casing: ground,
    tunnel_other: tunnel,
    tunnel_minor: tunnel,
    tunnel_link: tunnel,
    tunnel_major: tunnel,
    tunnel_highway: tunnel,
    ...roads(ground, minor, pink, "#ff4fe0"),
    roads_label_minor: roadLabel,
    roads_label_minor_halo: ground,
    roads_label_major: roadLabel,
    roads_label_major_halo: ground,
    city_label: label,
    city_label_halo: ground,
    subplace_label: label2,
    subplace_label_halo: ground,
    state_label: label2,
    state_label_halo: ground,
    country_label: label2,
    address_label: label2,
    address_label_halo: ground,
    ocean_label: "#39ff14",
    landcover: {
      grassland: park,
      barren: earth,
      urban_area: buildings,
      farmland: earth,
      glacier: earth,
      scrub: park,
      forest: park2,
    },
  };
}

export function themeFlavor(theme: MapTheme): Flavor {
  if (theme === "dark") return night();
  if (theme === "synthwave") return synthwave();
  return namedFlavor("light");
}

export function themeSprite(theme: MapTheme): string {
  return theme === "light" ? "light" : "dark";
}
