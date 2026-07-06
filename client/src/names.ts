/**
 * Deterministic bee-persona nickname generator, seeded so every device derives
 * the same name for a given seed — within one language. The generator honours
 * the device locale: German devices get German personas (with correct strong
 * adjective declension), everyone else gets an English set. Locale is stable per
 * device, so a peer's displayed name never flickers between renders.
 */
import { pick, rngFromSeed } from "./rng.js";
import { lang } from "./i18n.js";

// ---- German ---------------------------------------------------------------
// Adjective stems that cleanly take -er/-e/-es endings.
const ADJECTIVES_DE = [
  "flink", "mutig", "wild", "ruhig", "schlau", "sanft", "frech", "flott",
  "klug", "munter", "tapfer", "heiter", "keck", "hurtig", "listig", "drollig",
  "putzig", "wach", "froh", "kühn", "leis", "emsig", "wendig", "verwegen",
  "gewitzt", "pfiffig", "verspielt", "neugierig", "gelassen", "flauschig",
] as const;

type Gender = "m" | "f" | "n";
interface Persona {
  noun: string;
  g: Gender;
}

const PERSONAS_DE: readonly Persona[] = [
  { noun: "Brummer", g: "m" }, { noun: "Wabenwart", g: "m" }, { noun: "Schwarmfreund", g: "m" },
  { noun: "Nektarprofi", g: "m" }, { noun: "Pollenpilot", g: "m" }, { noun: "Summbote", g: "m" },
  { noun: "Wiesenflitzer", g: "m" }, { noun: "Honigfinder", g: "m" }, { noun: "Blütenkundler", g: "m" },
  { noun: "Biene", g: "f" }, { noun: "Honigbiene", g: "f" }, { noun: "Spurbiene", g: "f" },
  { noun: "Tanzbiene", g: "f" }, { noun: "Wabenwache", g: "f" }, { noun: "Sammlerin", g: "f" },
  { noun: "Kundschafterin", g: "f" }, { noun: "Nektarjägerin", g: "f" }, { noun: "Pollenbotin", g: "f" },
  { noun: "Blütenfreundin", g: "f" }, { noun: "Schwarmlotsin", g: "f" },
  { noun: "Summtier", g: "n" }, { noun: "Wabenkind", g: "n" }, { noun: "Honigherz", g: "n" },
  { noun: "Nektarlicht", g: "n" },
] as const;

const ENDING: Record<Gender, string> = { m: "er", f: "e", n: "es" };

function germanName(seed: string): string {
  const rng = rngFromSeed(seed + ":name");
  const adj = pick(rng, ADJECTIVES_DE);
  const persona = pick(rng, PERSONAS_DE);
  return `${adj}${ENDING[persona.g]} ${persona.noun}`;
}

// ---- English --------------------------------------------------------------
const ADJECTIVES_EN = [
  "swift", "brave", "wild", "calm", "clever", "gentle", "cheeky", "nimble",
  "bright", "merry", "bold", "keen", "sly", "cute", "curious", "playful",
  "fuzzy", "plucky", "breezy", "sunny", "dapper", "jolly", "snug", "zesty",
  "perky", "chirpy", "cosy", "spry", "witty", "fluffy",
] as const;

const PERSONAS_EN = [
  "Buzzer", "Forager", "Scout", "Drifter", "Bumbler", "Honeybee", "Dancer",
  "Wanderer", "Nectar Pilot", "Pollen Pilot", "Hive Guard", "Comb Keeper",
  "Waggle Scout", "Bloom Seeker", "Meadow Racer", "Nectar Hunter",
  "Pollen Bearer", "Swarm Guide", "Honey Finder", "Bloom Friend",
] as const;

function englishName(seed: string): string {
  const rng = rngFromSeed(seed + ":name");
  const adj = pick(rng, ADJECTIVES_EN);
  const persona = pick(rng, PERSONAS_EN);
  return `${adj.charAt(0).toUpperCase()}${adj.slice(1)} ${persona}`;
}

export function nameFromSeed(seed: string): string {
  // Persona sets exist for German and English; other locales use the English set.
  return lang === "de" ? germanName(seed) : englishName(seed);
}
