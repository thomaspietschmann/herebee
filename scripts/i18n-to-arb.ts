/**
 * Export client/src/i18n.ts to Flutter ARB files (mobile/lib/l10n/app_{lang}.arb).
 *
 * The web app and the native apps must say the same things in the same words —
 * two hand-maintained string sets would drift within a release. So the web
 * tables stay the single source of truth and this script regenerates the ARB
 * files; `npm run i18n:arb` after any wording change.
 *
 * Two things carry over unchanged on purpose:
 *  - Placeholders. The web's `t(key, {n})` uses `{name}` syntax, which is also
 *    what ARB/intl uses, so the strings need no rewriting. Every placeholder is
 *    declared as String (not int/num) so Dart must stringify exactly as the web
 *    does — locale-aware number formatting would make "vor 1.000 s" appear on a
 *    phone and "vor 1000 s" in the browser for the same event.
 *  - Inline markup (<strong>, <em>, <code>). Kept verbatim; the Flutter side
 *    renders it with a small tag-to-TextSpan helper. Keys carrying markup are
 *    flagged in their @-metadata so that is not discovered at render time.
 *
 * NOT exported: the Impressum / Datenschutz sheet (client/src/ui.ts). It is
 * German-only inline HTML with unfilled placeholders, and the app's disclosure
 * genuinely differs from the web's (bundled code, OS location services), so it
 * must be rewritten rather than copied. See docs/mobile-plan.md, Phase 2.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { DICTS, type Key, type Lang } from "../client/src/i18n.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "..", "mobile", "lib", "l10n");

const LANGS: readonly Lang[] = ["de", "en", "es", "it", "fr", "pt"];
/** The language whose file carries the @-metadata (intl's "template" ARB). */
const TEMPLATE: Lang = "de";

const placeholdersOf = (s: string): string[] => [
  ...new Set([...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1])),
];
const hasMarkup = (s: string): boolean => /<\/?(strong|em|code)>/.test(s);

function arbFor(lang: Lang): string {
  const dict = DICTS[lang];
  const out: Record<string, unknown> = { "@@locale": lang };
  for (const key of Object.keys(dict) as Key[]) {
    const value = dict[key];
    out[key] = value;
    // intl only reads @-metadata from the template file; emitting it in every
    // language would be redundant and would drift.
    if (lang !== TEMPLATE) continue;

    const names = placeholdersOf(value);
    const meta: Record<string, unknown> = {};
    const notes: string[] = [];
    if (hasMarkup(value)) notes.push("Contains inline markup (<strong>/<em>/<code>); render as rich text.");
    if (notes.length) meta.description = notes.join(" ");
    if (names.length) {
      meta.placeholders = Object.fromEntries(
        names.map((n) => [n, { type: "String", example: n === "n" ? "3" : undefined }])
      );
    }
    if (Object.keys(meta).length) out[`@${key}`] = meta;
  }
  return JSON.stringify(out, null, 2) + "\n";
}

mkdirSync(OUT_DIR, { recursive: true });
for (const lang of LANGS) {
  writeFileSync(join(OUT_DIR, `app_${lang}.arb`), arbFor(lang), "utf8");
}

const keyCount = Object.keys(DICTS[TEMPLATE]).length;
console.log(`wrote ${LANGS.length} ARB files (${keyCount} keys each) to ${OUT_DIR}`);

// Guard: a missing key in a non-template language would silently ship an English
// string inside an otherwise German UI. The TS types already require full
// coverage, but this also catches an empty string slipping through.
for (const lang of LANGS) {
  for (const key of Object.keys(DICTS[TEMPLATE]) as Key[]) {
    if (!DICTS[lang][key]) throw new Error(`i18n: ${lang} is missing a value for "${key}"`);
  }
}
