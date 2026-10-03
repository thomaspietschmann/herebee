import { namedFlavor, type Flavor } from "@protomaps/basemaps";

/** The neon map styles; each also restyles the app chrome. "synthwave" is Grid Toxic. */
export const NEON_THEMES = ["synthwave", "outrun", "miami", "tron", "vapor", "amber"] as const;
export type NeonTheme = (typeof NEON_THEMES)[number];
export type MapTheme = "light" | "dark" | NeonTheme;
export const MAP_THEMES: readonly MapTheme[] = ["light", "dark", ...NEON_THEMES];

/** Display names of the neon styles. Proper names, so not translated. */
export const NEON_NAMES: Record<NeonTheme, string> = {
  synthwave: "Grid Toxic",
  outrun: "Outrun",
  miami: "Miami Vice",
  tron: "Tron",
  vapor: "Vaporwave",
  amber: "Blade Runner",
};

export function isNeon(theme: string): theme is NeonTheme {
  return (NEON_THEMES as readonly string[]).includes(theme);
}

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

type NeonPalette = {
  ground: string;
  earth: string;
  buildings: string;
  park: string;
  park2: string;
  water: string;
  minor: string;
  major: string;
  highway: string;
  railway: string;
  tunnel: string;
  label: string;
  label2: string;
  roadLabel: string;
  accent: string;
};

/**
 * The neon styles: a dark ground with a glowing street wireframe whose minor,
 * major and motorway lines each get their own colour, dark parks and water,
 * and pale labels on ground-coloured halos so they stay legible over the lines.
 */
const NEON: Record<NeonTheme, NeonPalette> = {
  synthwave: {
    ground: "#030507",
    earth: "#05090a",
    buildings: "#0d1614",
    park: "#0b2616",
    park2: "#0e2f1b",
    water: "#072c36",
    minor: "#5a2856",
    major: "#c24aa8",
    highway: "#62e04a",
    railway: "#2b1838",
    tunnel: "#0d2a1c",
    label: "#f0fff4",
    label2: "#8fbf9c",
    roadLabel: "#d4e6d9",
    accent: "#62e04a",
  },
  outrun: {
    ground: "#0f0620",
    earth: "#140828",
    buildings: "#1f0f3a",
    park: "#1a1238",
    park2: "#21164a",
    water: "#0a1f4a",
    minor: "#7a2a7a",
    major: "#ff4f9a",
    highway: "#ffb03b",
    railway: "#3b2266",
    tunnel: "#2a1446",
    label: "#fff1fa",
    label2: "#c79ad8",
    roadLabel: "#f3cfe6",
    accent: "#5ad8ff",
  },
  miami: {
    ground: "#071420",
    earth: "#0a1a29",
    buildings: "#112638",
    park: "#0d2a33",
    park2: "#103440",
    water: "#0d3d57",
    minor: "#3a6f88",
    major: "#ff7ac6",
    highway: "#2ee6d6",
    railway: "#1e3a4f",
    tunnel: "#163448",
    label: "#f2fbff",
    label2: "#8fc3d4",
    roadLabel: "#d6eef5",
    accent: "#2ee6d6",
  },
  tron: {
    ground: "#01050a",
    earth: "#030a12",
    buildings: "#0a1824",
    park: "#06161c",
    park2: "#081c24",
    water: "#02213a",
    minor: "#0e5068",
    major: "#2ad4ff",
    highway: "#ff9a1f",
    railway: "#123344",
    tunnel: "#0a2a38",
    label: "#e8fbff",
    label2: "#7fb6c8",
    roadLabel: "#bfe9f5",
    accent: "#2ad4ff",
  },
  vapor: {
    ground: "#1d1736",
    earth: "#231c42",
    buildings: "#2f2656",
    park: "#203a4a",
    park2: "#244456",
    water: "#2a4d86",
    minor: "#5f4f96",
    major: "#ff9ad5",
    highway: "#8ef6e4",
    railway: "#463a78",
    tunnel: "#3a3066",
    label: "#fdf6ff",
    label2: "#c2b4e8",
    roadLabel: "#ece2ff",
    accent: "#8ef6e4",
  },
  amber: {
    ground: "#080604",
    earth: "#0d0a07",
    buildings: "#1a140d",
    park: "#10180f",
    park2: "#141f12",
    water: "#06222c",
    minor: "#5a3418",
    major: "#e8762a",
    highway: "#22d3ee",
    railway: "#2e2216",
    tunnel: "#2a1c10",
    label: "#fff4e6",
    label2: "#c2a283",
    roadLabel: "#f0d9bf",
    accent: "#22d3ee",
  },
};

function neon(p: NeonPalette): Flavor {
  const base = namedFlavor("dark");
  return {
    ...base,
    background: p.ground,
    earth: p.earth,
    buildings: p.buildings,
    pedestrian: p.earth,
    park_a: p.park,
    park_b: p.park2,
    wood_a: p.park,
    wood_b: p.park2,
    scrub_a: p.park,
    scrub_b: p.park2,
    zoo: p.park,
    glacier: p.earth,
    school: p.earth,
    hospital: p.earth,
    military: p.earth,
    industrial: p.buildings,
    aerodrome: p.buildings,
    runway: p.highway,
    pier: p.minor,
    sand: p.earth,
    beach: p.earth,
    water: p.water,
    railway: p.railway,
    boundaries: p.major,
    tunnel_other_casing: p.ground,
    tunnel_minor_casing: p.ground,
    tunnel_link_casing: p.ground,
    tunnel_major_casing: p.ground,
    tunnel_highway_casing: p.ground,
    tunnel_other: p.tunnel,
    tunnel_minor: p.tunnel,
    tunnel_link: p.tunnel,
    tunnel_major: p.tunnel,
    tunnel_highway: p.tunnel,
    ...roads(p.ground, p.minor, p.major, p.highway),
    roads_label_minor: p.roadLabel,
    roads_label_minor_halo: p.ground,
    roads_label_major: p.roadLabel,
    roads_label_major_halo: p.ground,
    city_label: p.label,
    city_label_halo: p.ground,
    subplace_label: p.label2,
    subplace_label_halo: p.ground,
    state_label: p.label2,
    state_label_halo: p.ground,
    country_label: p.label2,
    address_label: p.label2,
    address_label_halo: p.ground,
    ocean_label: p.accent,
    landcover: {
      grassland: p.park,
      barren: p.earth,
      urban_area: p.buildings,
      farmland: p.earth,
      glacier: p.earth,
      scrub: p.park,
      forest: p.park2,
    },
  };
}

/** Ground, major-road and motorway colour of a neon style, for a picker swatch. */
export function neonSwatch(theme: NeonTheme): [string, string, string] {
  const p = NEON[theme];
  return [p.ground, p.major, p.highway];
}

export function themeFlavor(theme: MapTheme): Flavor {
  if (theme === "dark") return night();
  if (isNeon(theme)) return neon(NEON[theme]);
  return namedFlavor("light");
}

export function themeSprite(theme: MapTheme): string {
  return theme === "light" ? "light" : "dark";
}
