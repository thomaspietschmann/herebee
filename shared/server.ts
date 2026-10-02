/**
 * The official HereBee server. Anyone may run the web app elsewhere, and the
 * native apps can be pointed at such a server, but only this one is operated
 * under HereBee's privacy statement. Every other server gets a warning: the
 * payloads stay end-to-end encrypted, yet its operator sees IPs, room timing and
 * (through the map tiles) roughly where people look, and in a browser it also
 * serves the code that holds the key. Keep in sync with mobile/lib/app_config.dart.
 */
export const OFFICIAL_ORIGIN = "https://herebee.app";
export const OFFICIAL_HOST = new URL(OFFICIAL_ORIGIN).host;

export function isOfficialOrigin(origin: string): boolean {
  try {
    const u = new URL(origin);
    return u.protocol === "https:" && u.host === OFFICIAL_HOST;
  } catch {
    return false;
  }
}
