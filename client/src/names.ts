/**
 * Deterministic German nickname generator: adjective + animal, seeded.
 * The attributive adjective takes the strong-declension nominative ending that
 * agrees with the animal's grammatical gender (der -> -er, die -> -e, das -> -es):
 *   der Fuchs -> "Flinker Fuchs" · die Katze -> "Flinke Katze" · das Reh -> "Flinkes Reh"
 */
import { pick, rngFromSeed } from "./rng.js";

// Adjective stems that cleanly take -er/-e/-es endings.
const ADJECTIVES = [
  "flink", "mutig", "wild", "ruhig", "schlau", "sanft", "frech", "flott",
  "klug", "munter", "tapfer", "heiter", "keck", "hurtig", "listig", "drollig",
  "putzig", "wach", "froh", "kühn", "leis", "emsig", "wendig", "verwegen",
  "gewitzt", "pfiffig", "verspielt", "neugierig", "gelassen", "flauschig",
] as const;

type Gender = "m" | "f" | "n";
interface Animal {
  noun: string;
  g: Gender;
}

const ANIMALS: readonly Animal[] = [
  { noun: "Fuchs", g: "m" }, { noun: "Dachs", g: "m" }, { noun: "Falke", g: "m" },
  { noun: "Igel", g: "m" }, { noun: "Hirsch", g: "m" }, { noun: "Biber", g: "m" },
  { noun: "Marder", g: "m" }, { noun: "Luchs", g: "m" }, { noun: "Waschbär", g: "m" },
  { noun: "Kranich", g: "m" }, { noun: "Specht", g: "m" }, { noun: "Uhu", g: "m" },
  { noun: "Adler", g: "m" }, { noun: "Wolf", g: "m" }, { noun: "Hase", g: "m" },
  { noun: "Rabe", g: "m" }, { noun: "Storch", g: "m" }, { noun: "Pinguin", g: "m" },
  { noun: "Katze", g: "f" }, { noun: "Eule", g: "f" }, { noun: "Robbe", g: "f" },
  { noun: "Möwe", g: "f" }, { noun: "Ente", g: "f" }, { noun: "Biene", g: "f" },
  { noun: "Libelle", g: "f" }, { noun: "Schnecke", g: "f" }, { noun: "Elster", g: "f" },
  { noun: "Amsel", g: "f" }, { noun: "Krähe", g: "f" }, { noun: "Fledermaus", g: "f" },
  { noun: "Schildkröte", g: "f" }, { noun: "Meise", g: "f" }, { noun: "Lerche", g: "f" },
  { noun: "Reh", g: "n" }, { noun: "Wiesel", g: "n" }, { noun: "Eichhörnchen", g: "n" },
  { noun: "Murmeltier", g: "n" }, { noun: "Faultier", g: "n" }, { noun: "Nashorn", g: "n" },
  { noun: "Erdmännchen", g: "n" }, { noun: "Rentier", g: "n" }, { noun: "Kaninchen", g: "n" },
  { noun: "Frettchen", g: "n" },
] as const;

const ENDING: Record<Gender, string> = { m: "er", f: "e", n: "es" };

export function nameFromSeed(seed: string): string {
  const rng = rngFromSeed(seed + ":name");
  const adj = pick(rng, ADJECTIVES);
  const animal = pick(rng, ANIMALS);
  return `${adj}${ENDING[animal.g]} ${animal.noun}`;
}
