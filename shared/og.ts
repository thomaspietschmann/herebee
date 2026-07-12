/**
 * Localized Open Graph / Twitter Card metadata for `client/index.html`.
 *
 * Social crawlers (Twitter, Facebook, WhatsApp, …) don't execute JavaScript, so
 * the client's runtime i18n (see client/src/i18n.ts) never reaches them — only
 * whatever the server sends on the initial HTML response counts. `OG.de` is
 * the literal source of truth: its strings must match `client/index.html`
 * verbatim, since the server (see server/src/index.ts) localizes by replacing
 * those exact substrings with the negotiated language's version.
 */

export type OgLang = "de" | "en" | "es" | "it" | "fr" | "pt";
const SUPPORTED: readonly OgLang[] = ["de", "en", "es", "it", "fr", "pt"];

export interface OgStrings {
  /** <title> and og:title / twitter:title (all three share one string). */
  title: string;
  /** <meta name="description"> — distinct wording from ogDescription. */
  description: string;
  /** og:description / twitter:description (share one string). */
  ogDescription: string;
  /** og:image:alt / twitter:image:alt (share one string). og:image itself is language-neutral. */
  imageAlt: string;
  /** og:locale, e.g. "de_DE". */
  ogLocale: string;
  /** <html lang="…">. */
  htmlLang: OgLang;
}

export const OG: Record<OgLang, OgStrings> = {
  de: {
    title: "HereBee — flüchtig zusammenfinden",
    description:
      "HereBee teilt Live-Standorte flüchtig per Link – privat, ohne Account und Ende-zu-Ende-verschlüsselt.",
    ogDescription: "Privaten Raum teilen, Live-Standorte sehen, nichts speichern. Ende-zu-Ende-verschlüsselt.",
    imageAlt: "HereBee Logo auf einer dunklen Kartenansicht mit leuchtenden Standortpunkten",
    ogLocale: "de_DE",
    htmlLang: "de",
  },
  en: {
    title: "HereBee — meet up, fleetingly",
    description: "HereBee shares live locations fleetingly via a link — private, no account, end-to-end encrypted.",
    ogDescription: "Share a private room, see live locations, nothing stored. End-to-end encrypted.",
    imageAlt: "HereBee logo over a dark map view with glowing location dots",
    ogLocale: "en_US",
    htmlLang: "en",
  },
  es: {
    title: "HereBee — encontrarse al instante",
    description:
      "HereBee comparte ubicaciones en vivo de forma efímera mediante un enlace: privado, sin cuenta y cifrado de extremo a extremo.",
    ogDescription: "Comparte una sala privada, ve ubicaciones en vivo, nada se guarda. Cifrado de extremo a extremo.",
    imageAlt: "Logotipo de HereBee sobre una vista de mapa oscura con puntos de ubicación brillantes",
    ogLocale: "es_ES",
    htmlLang: "es",
  },
  it: {
    title: "HereBee — ritrovarsi al volo",
    description:
      "HereBee condivide posizioni in tempo reale in modo effimero tramite un link: privato, senza account, cifrato end-to-end.",
    ogDescription: "Condividi una stanza privata, vedi le posizioni in tempo reale, nulla viene salvato. Cifrato end-to-end.",
    imageAlt: "Logo di HereBee su una mappa scura con punti di posizione luminosi",
    ogLocale: "it_IT",
    htmlLang: "it",
  },
  fr: {
    title: "HereBee — se retrouver en un instant",
    description:
      "HereBee partage des positions en direct de façon éphémère via un lien — privé, sans compte, chiffré de bout en bout.",
    ogDescription: "Partage un salon privé, vois les positions en direct, rien n'est conservé. Chiffré de bout en bout.",
    imageAlt: "Logo HereBee sur une carte sombre avec des points de localisation lumineux",
    ogLocale: "fr_FR",
    htmlLang: "fr",
  },
  pt: {
    title: "HereBee — encontrar-se num instante",
    description:
      "O HereBee partilha localizações em tempo real de forma efémera através de um link — privado, sem conta, cifrado de ponta a ponta.",
    ogDescription: "Partilha uma sala privada, vê localizações em tempo real, nada é guardado. Cifrado de ponta a ponta.",
    imageAlt: "Logótipo do HereBee sobre um mapa escuro com pontos de localização brilhantes",
    ogLocale: "pt_PT",
    htmlLang: "pt",
  },
};

/**
 * Pick the best-supported language from a raw `Accept-Language` header, e.g.
 * "en-US,en;q=0.9,de;q=0.8". Falls back to English — a sensible default for
 * devices outside DACH, and consistent with the client's own detectLang().
 */
export function negotiate(acceptLanguage: string | null | undefined): OgLang {
  if (!acceptLanguage) return "en";
  const ranked = acceptLanguage
    .split(",")
    .map((part): { code: string; q: number } => {
      const [tag, ...params] = part.trim().split(";");
      const qParam = params.find((p) => p.trim().startsWith("q="));
      const q = qParam ? parseFloat(qParam.slice(qParam.indexOf("=") + 1)) : 1;
      return { code: (tag ?? "").trim().slice(0, 2).toLowerCase(), q: Number.isFinite(q) ? q : 1 };
    })
    .sort((a, b) => b.q - a.q);
  for (const { code } of ranked) {
    if ((SUPPORTED as readonly string[]).includes(code)) return code as OgLang;
  }
  return "en";
}
