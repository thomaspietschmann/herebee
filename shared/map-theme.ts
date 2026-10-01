import { namedFlavor, type Flavor } from "@protomaps/basemaps";

export type MapTheme = "light" | "dark";
export const MAP_THEMES: readonly MapTheme[] = ["light", "dark"];

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

export function themeFlavor(theme: MapTheme): Flavor {
  return theme === "dark" ? night() : namedFlavor("light");
}

export function themeSprite(theme: MapTheme): string {
  return theme === "dark" ? "dark" : "light";
}
