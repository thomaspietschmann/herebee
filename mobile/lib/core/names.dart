/// Deterministic bee-persona nickname generator.
///
/// Port of `client/src/names.ts`. Seeded so every device derives the same name
/// for a given seed, within one language. Which language is used follows the
/// DEVICE locale, not the peer's, so the same person may legitimately show a
/// German name on one phone and an English one on another. That is the web's
/// behaviour and it must be kept, or the two clients disagree about names.
library;

import 'rng.dart';

// Adjective stems that cleanly take -er/-e/-es endings.
const List<String> adjectivesDe = [
  'flink', 'mutig', 'wild', 'ruhig', 'schlau', 'sanft', 'frech', 'flott', //
  'klug', 'munter', 'tapfer', 'heiter', 'keck', 'hurtig', 'listig', 'drollig',
  'putzig', 'wach', 'froh', 'kühn', 'leis', 'emsig', 'wendig', 'verwegen',
  'gewitzt', 'pfiffig', 'verspielt', 'neugierig', 'gelassen', 'flauschig',
];

enum Gender { m, f, n }

class Persona {
  const Persona(this.noun, this.gender);
  final String noun;
  final Gender gender;
}

const List<Persona> personasDe = [
  Persona('Brummer', Gender.m), Persona('Wabenwart', Gender.m), Persona('Schwarmfreund', Gender.m),
  Persona('Nektarprofi', Gender.m), Persona('Pollenpilot', Gender.m), Persona('Summbote', Gender.m),
  Persona('Wiesenflitzer', Gender.m), Persona('Honigfinder', Gender.m), Persona('Blütenkundler', Gender.m),
  Persona('Biene', Gender.f), Persona('Honigbiene', Gender.f), Persona('Spurbiene', Gender.f),
  Persona('Tanzbiene', Gender.f), Persona('Wabenwache', Gender.f), Persona('Sammlerin', Gender.f),
  Persona('Kundschafterin', Gender.f), Persona('Nektarjägerin', Gender.f), Persona('Pollenbotin', Gender.f),
  Persona('Blütenfreundin', Gender.f), Persona('Schwarmlotsin', Gender.f),
  Persona('Summtier', Gender.n), Persona('Wabenkind', Gender.n), Persona('Honigherz', Gender.n),
  Persona('Nektarlicht', Gender.n),
];

const Map<Gender, String> _ending = {Gender.m: 'er', Gender.f: 'e', Gender.n: 'es'};

String germanName(String seed) {
  final rng = rngFromSeed('$seed:name');
  final adj = pick(rng, adjectivesDe);
  final persona = pick(rng, personasDe);
  return '$adj${_ending[persona.gender]} ${persona.noun}';
}

const List<String> adjectivesEn = [
  'swift', 'brave', 'wild', 'calm', 'clever', 'gentle', 'cheeky', 'nimble', //
  'bright', 'merry', 'bold', 'keen', 'sly', 'cute', 'curious', 'playful',
  'fuzzy', 'plucky', 'breezy', 'sunny', 'dapper', 'jolly', 'snug', 'zesty',
  'perky', 'chirpy', 'cosy', 'spry', 'witty', 'fluffy',
];

const List<String> personasEn = [
  'Buzzer', 'Forager', 'Scout', 'Drifter', 'Bumbler', 'Honeybee', 'Dancer', //
  'Wanderer', 'Nectar Pilot', 'Pollen Pilot', 'Hive Guard', 'Comb Keeper',
  'Waggle Scout', 'Bloom Seeker', 'Meadow Racer', 'Nectar Hunter',
  'Pollen Bearer', 'Swarm Guide', 'Honey Finder', 'Bloom Friend',
];

String englishName(String seed) {
  final rng = rngFromSeed('$seed:name');
  final adj = pick(rng, adjectivesEn);
  final persona = pick(rng, personasEn);
  return '${adj[0].toUpperCase()}${adj.substring(1)} $persona';
}

/// Persona sets exist for German and English; other locales use the English set.
String nameFromSeed(String seed, String languageCode) =>
    languageCode == 'de' ? germanName(seed) : englishName(seed);

/// Longest shared name, in code points. Matches the rename field's maxLength.
const int sharedNameMax = 40;

// Whitespace of any kind, which becomes a single space.
final RegExp _nameSpace = RegExp(r'[\p{Zs}\p{Zl}\p{Zp}\t\n\x0B\f\r\u0085]+', unicode: true);
// Other control, format and surrogate characters, except ZWNJ/ZWJ
// (U+200C/U+200D), which real scripts and emoji sequences need. This is what
// strips bidi overrides and invisible characters a malicious member could use
// to disguise a name.
final RegExp _nameStrip = RegExp(r'\p{Cc}|\p{Cs}|(?![‌‍])\p{Cf}', unicode: true);

/// Clean a name a peer chose to share, or null if nothing usable is left.
///
/// Every room member holds the key, so this is untrusted input. Port of
/// `sanitizeSharedName` in `client/src/names.ts`; shared/vectors.json pins the
/// output so both sides show the same name.
String? sanitizeSharedName(Object? raw) {
  if (raw is! String) return null;
  final cleaned = raw
      .replaceAll(_nameSpace, ' ')
      .replaceAll(_nameStrip, '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
  final capped = String.fromCharCodes(cleaned.runes.take(sharedNameMax)).trim();
  return capped.isEmpty ? null : capped;
}
