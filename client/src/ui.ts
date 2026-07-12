/**
 * View layer: HUD chrome, dock controls, share/info sheets, toasts.
 * Holds no app state beyond the DOM — main.ts drives it.
 */
import { t } from "./i18n.js";

export interface UIHandlers {
  onToggleShare: () => void;
  onFitAll: () => void; // zoom the map so every shared marker fits on screen
  onGoTo: (seed: string) => void; // fly the map to one participant's marker
}

interface Sharer {
  seed: string;
  color: string;
  name: string;
  offline: boolean; // was sharing but its link dropped — still a ghost on the map
}

type Conn = "connecting" | "on" | "off";

export class UI {
  private connChip = document.getElementById("conn")!;
  private connText = document.getElementById("conn-text")!;
  private geoBtn = document.getElementById("geo-btn")!;
  private geoLabel = this.geoBtn.querySelector<HTMLElement>(".btn-label")!;
  private shareBtn = document.getElementById("share-btn")!;
  private infoBtn = document.getElementById("info-btn")!;
  private rosterGroup = document.getElementById("roster-group")!;
  private roster = document.getElementById("roster") as HTMLButtonElement;
  private rosterStack = this.roster.querySelector<HTMLElement>(".roster-stack")!;
  private rosterCount = this.roster.querySelector<HTMLElement>(".roster-count")!;
  private fitAllBtn = document.getElementById("fit-all-btn")!;
  private hint = document.getElementById("hint")!;
  private sheet = document.getElementById("sheet")!;
  private sheetBody = document.getElementById("sheet-body")!;
  private toastEl = document.getElementById("toast")!;
  private sharing = false;
  private toastTimer = 0;
  private gated = false; // a mandatory sheet (entry gate / invalid link) is open
  private lastSharers: Sharer[] = [];
  private lastWatchers = 0;

  constructor(private readonly h: UIHandlers) {
    this.geoBtn.addEventListener("click", () => h.onToggleShare());
    this.shareBtn.addEventListener("click", () => this.copyLink());
    this.infoBtn.addEventListener("click", () => this.openInfo());
    this.roster.addEventListener("click", () => this.openParticipants());
    this.fitAllBtn.addEventListener("click", () => this.h.onFitAll());
    document.getElementById("sheet-close")!.addEventListener("click", () => this.closeSheet());
    this.sheet.addEventListener("click", (e) => {
      if (e.target === this.sheet && !this.gated) this.closeSheet();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !this.gated) this.closeSheet();
    });
  }

  private esc(s: string): string {
    return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
  }

  setConnection(state: Conn): void {
    this.connChip.classList.toggle("is-on", state === "on");
    this.connChip.classList.toggle("is-off", state === "off");
    const label = t(state === "on" ? "connOn" : state === "off" ? "connOff" : "connConnecting");
    this.connText.textContent = label;
    this.connChip.title = label;
  }

  setSharing(on: boolean): void {
    this.sharing = on;
    this.geoBtn.classList.toggle("is-sharing", on);
    this.geoLabel.textContent = t(on ? "stopSharing" : "shareLocation");
    if (on) this.hideHint();
  }

  isSharing(): boolean {
    return this.sharing;
  }

  /**
   * @param sharers  everyone with a marker on the map (online + offline ghosts),
   *                 online first; colored pips, offline ones dimmed.
   * @param watchers present-but-not-sharing count (anonymous, hollow pips)
   * @param present  connected participants right now (online sharers + watchers)
   * @param offline  sharers whose link dropped but whose ghost still lingers
   */
  setRoster(sharers: Sharer[], watchers: number, present: number, offline: number): void {
    this.lastSharers = sharers;
    this.lastWatchers = watchers;
    // Show whenever anyone else is around or has a marker (incl. offline ghosts).
    this.rosterGroup.hidden = present < 2 && sharers.length < 1;
    // Only collapse to a single "N here" when nobody is offline; otherwise spell
    // out the split so "1 here" next to two markers can't read as a bug.
    this.rosterCount.textContent = offline > 0 ? t("hereActiveOffline", { active: present, offline }) : t("here", { n: present });
    const sharerPips = sharers
      .slice(0, 5)
      .map(
        (m) =>
          `<span class="pip${m.offline ? " pip-offline" : ""}" style="background:${m.color}" title="${this.esc(m.name)}"></span>`
      );
    const hollowN = Math.min(watchers, Math.max(0, 5 - sharerPips.length));
    const hollow = Array.from(
      { length: hollowN },
      () => `<span class="pip pip-watcher" title="${t("watcher")}"></span>`
    );
    this.rosterStack.innerHTML = [...sharerPips, ...hollow].join("");
  }

  /** Participant list, opened by tapping the roster pill. "Fit everyone on
   *  screen" lives as its own icon button next to the pill (see fitAllBtn),
   *  not in here, so it doesn't require opening this sheet first. */
  private openParticipants(): void {
    const list = this.lastSharers.length
      ? `<ul class="party-list">${this.lastSharers
          .map(
            (m) =>
              `<li><button type="button" class="party${m.offline ? " is-offline" : ""}" data-seed="${this.esc(m.seed)}"><span class="pip${m.offline ? " pip-offline" : ""}" style="background:${m.color}"></span><span class="party-name">${this.esc(m.name)}</span>${m.offline ? `<span class="party-status">${t("offlineStatus")}</span>` : ""}</button></li>`
          )
          .join("")}</ul>`
      : `<p>${t("noSharers")}</p>`;
    const watching =
      this.lastWatchers > 0 ? `<p class="watching-note">${t("watchingLine", { n: this.lastWatchers })}</p>` : "";
    this.sheetBody.innerHTML = `
      <h2>${t("participantsTitle")}</h2>
      ${list}
      ${watching}`;
    this.openSheet();
    // Tap a participant to fly the map to their marker.
    this.sheetBody.querySelectorAll<HTMLElement>(".party[data-seed]").forEach((el) => {
      el.addEventListener("click", () => {
        this.closeSheet();
        this.h.onGoTo(el.dataset.seed!);
      });
    });
  }

  hideHint(): void {
    this.hint.classList.add("is-hidden");
  }

  toast(msg: string): void {
    this.toastEl.textContent = msg;
    this.toastEl.hidden = false;
    requestAnimationFrame(() => this.toastEl.classList.add("is-show"));
    clearTimeout(this.toastTimer);
    this.toastTimer = window.setTimeout(() => {
      this.toastEl.classList.remove("is-show");
      setTimeout(() => (this.toastEl.hidden = true), 300);
    }, 2200);
  }

  private async copyLink(): Promise<void> {
    const url = location.href;
    try {
      await navigator.clipboard.writeText(url);
      this.toast(t("linkCopied"));
    } catch {
      this.openShare(url);
    }
  }

  private openShare(url: string): void {
    this.sheetBody.innerHTML = `
      <h2>${t("shareTitle")}</h2>
      <p>${t("shareBody")}</p>
      <div class="linkbox">
        <input id="link-input" readonly value="${url.replace(/"/g, "&quot;")}" />
        <button class="btn btn-ghost" id="link-copy">${t("copy")}</button>
      </div>`;
    this.openSheet();
    const input = document.getElementById("link-input") as HTMLInputElement;
    document.getElementById("link-copy")!.addEventListener("click", () => {
      input.select();
      document.execCommand?.("copy");
      this.toast(t("linkCopied"));
    });
  }

  /**
   * Entry gate: explains watching vs. sharing and presence, then connects only
   * when the user confirms. Mandatory — no × and no backdrop dismiss — so no data
   * flows until they actively enter. `onEnter` opens the WebSocket.
   */
  openWelcome(onEnter: () => void): void {
    this.sheetBody.innerHTML = `
      <img class="splash-logo" src="/brand/herebee-logo.png" alt="" aria-hidden="true" />
      <h2>${t("welcomeTitle")}</h2>
      <p>${t("welcomeIntro")}</p>
      <ul class="facts">
        <li>${t("welcomeFact1")}</li>
        <li>${t("welcomeFact2")}</li>
        <li>${t("welcomeFact3")}</li>
      </ul>
      <div class="linkbox" style="margin-top:18px">
        <button class="btn btn-primary" id="welcome-ok" style="flex:1">${t("welcomeCta")}</button>
      </div>`;
    this.gated = true;
    this.openSheet("splash");
    document.getElementById("sheet-close")!.style.display = "none";
    document.getElementById("welcome-ok")!.addEventListener("click", () => {
      this.closeSheet();
      onEnter();
    });
  }

  /**
   * Programmatically close the entry gate — used when another tab of the same
   * browser has already entered the room (consent was given for the browser, so
   * we don't force a second confirmation). No-op unless the splash gate is open.
   */
  dismissWelcome(): void {
    if (!this.sheet.classList.contains("is-splash")) return;
    this.sheet.hidden = true;
    this.sheet.classList.remove("is-splash");
    this.gated = false;
    document.getElementById("sheet-close")!.style.display = "";
  }

  /** Rename a marker locally. `onSave(null)` means "reset to the generated name". */
  openRename(currentName: string, hasCustom: boolean, onSave: (name: string | null) => void): void {
    this.sheetBody.innerHTML = `
      <h2>${t("renameTitle")}</h2>
      <p>${t("renameBody")}</p>
      <div class="linkbox">
        <input id="rename-input" maxlength="40" placeholder="${t("renamePlaceholder")}" value="${currentName.replace(/"/g, "&quot;")}" />
        <button class="btn btn-primary" id="rename-save">${t("save")}</button>
      </div>
      ${hasCustom ? `<button class="btn btn-ghost" id="rename-reset" style="margin-top:10px">${t("renameReset")}</button>` : ""}`;
    this.openSheet();
    const input = document.getElementById("rename-input") as HTMLInputElement;
    input.focus();
    input.select();
    const save = () => {
      const v = input.value.trim();
      onSave(v.length ? v : null);
      this.closeSheet();
    };
    document.getElementById("rename-save")!.addEventListener("click", save);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") save();
    });
    document.getElementById("rename-reset")?.addEventListener("click", () => {
      onSave(null);
      this.closeSheet();
    });
  }

  /** Shown when the room link's secret is missing or malformed. */
  openInvalidLink(): void {
    this.sheetBody.innerHTML = `
      <h2>${t("invalidTitle")}</h2>
      <p>${t("invalidBody")}</p>
      <div class="linkbox" style="margin-top:16px">
        <button class="btn btn-primary" id="invalid-new" style="flex:1">${t("invalidCta")}</button>
      </div>`;
    this.gated = true;
    this.openSheet();
    document.getElementById("sheet-close")!.style.display = "none";
    document.getElementById("invalid-new")!.addEventListener("click", () => {
      location.assign("/");
    });
  }

  private openInfo(): void {
    this.sheetBody.innerHTML = `
      <h2>${t("infoTitle")}</h2>
      <p>${t("infoIntro")}</p>
      <ul class="facts">
        <li>${t("infoFact1")}</li>
        <li>${t("infoFact2")}</li>
        <li>${t("infoFact3")}</li>
        <li class="warn">${t("infoFact4")}</li>
        <li class="warn">${t("infoFact5")}</li>
      </ul>
      <p class="attrib-note">${t("mapCredits", {
        pm: '<a href="https://protomaps.com" target="_blank" rel="noreferrer">Protomaps</a>',
        osm: '<a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a>',
      })}</p>
      <p class="sheet-foot"><button type="button" class="linklike" id="open-legal">${t("legalLink")}</button></p>`;
    this.openSheet();
    document.getElementById("open-legal")!.addEventListener("click", () => this.openLegal());
  }

  /**
   * Impressum (§5 DDG) + Datenschutzerklärung (Art. 13 DSGVO), German-only as is
   * conventional for a German-operated service. Deliberately kept in sync with the
   * app's real data handling. While the app is not publicly operated, the Impressum
   * carries a development notice instead of an address; the `.ph` placeholders mark
   * exactly what must be filled in before any public launch (name, ladungsfähige
   * Anschrift, contact e-mail, hosting provider). "In Entwicklung" is NOT a legal
   * exemption once the service is publicly reachable — the address must go in then.
   */
  private openLegal(): void {
    const ph = (s: string) => `<span class="ph">${this.esc(s)}</span>`;
    this.sheetBody.innerHTML = `
      <button type="button" class="linklike legal-back" id="legal-back">‹ ${t("infoTitle")}</button>

      <h2>Impressum</h2>
      <p>Angaben gemäß § 5 DDG (Digitale-Dienste-Gesetz).</p>
      <p class="legal-dev"><strong>Hinweis:</strong> HereBee befindet sich in aktiver Entwicklung und
      wird derzeit nicht öffentlich betrieben. Solange der Dienst nicht öffentlich erreichbar ist,
      besteht keine Impressumspflicht. Vor der öffentlichen Bereitstellung wird hier die vollständige
      Anbieterkennzeichnung mit ladungsfähiger Anschrift ergänzt.</p>
      <p><strong>Diensteanbieter:</strong><br />
      ${ph("[Name – wird vor Veröffentlichung ergänzt]")}<br />
      ${ph("[Ladungsfähige Anschrift – wird vor Veröffentlichung ergänzt]")}</p>
      <p><strong>Kontakt:</strong><br />
      ${ph("[E-Mail – wird vor Veröffentlichung ergänzt]")}</p>

      <h2 style="margin-top:22px">Datenschutzerklärung</h2>
      <p><strong>Verantwortlicher</strong> im Sinne der DSGVO ist der im Impressum genannte
      Diensteanbieter.</p>
      <p><strong>Grundprinzip.</strong> HereBee ist bewusst datensparsam gebaut. Ein 256-Bit-Schlüssel
      steckt ausschließlich im Link hinter <code>#</code> und wird nie an den Server übertragen. Der
      Browser leitet daraus die Raum-Kennung und einen AES-256-GCM-Schlüssel ab; alle Koordinaten und
      Anzeigenamen werden im Browser verschlüsselt. Der Server (Relay) leitet nur undurchsichtige,
      verschlüsselte Datenpakete weiter und kann sie nicht entschlüsseln.</p>
      <p><strong>Welche Daten verarbeitet werden:</strong></p>
      <ul class="facts">
        <li><strong>IP-Adresse</strong> – vorübergehend, um die WebSocket-Verbindung aufzubauen und die
        Zahl gleichzeitiger Verbindungen pro IP zu begrenzen (Missbrauchsschutz). Rechtsgrundlage:
        Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse am Betrieb und Schutz des Dienstes). Die
        Anwendung selbst speichert die IP nicht.</li>
        <li><strong>Verschlüsselte Standort- und Namensdaten</strong> – werden nur weitergeleitet,
        nicht gespeichert und sind für den Betreiber nicht lesbar.</li>
        <li><strong>Raumzustand</strong> – ausschließlich im Arbeitsspeicher; wird gelöscht, sobald der
        letzte Teilnehmer die Verbindung trennt. Keine Datenbank, keine Historie, keine Speicherung von
        Koordinaten oder Namen.</li>
      </ul>
      <p style="margin-top:12px"><strong>Standortfreigabe.</strong> Die App nutzt die
      Geolocation-Funktion des Browsers. Der Zugriff erfolgt nur nach ausdrücklicher Erlaubnis über die
      Abfrage des Browsers (Einwilligung, Art. 6 Abs. 1 lit. a DSGVO) und ist jederzeit in den
      Browser-Einstellungen widerrufbar. Die Koordinaten sind Ende-zu-Ende-verschlüsselt und für den
      Server nie sichtbar.</p>
      <p><strong>Anzeigename.</strong> Frei wählbar (Pseudonym oder echter Name – deine Entscheidung),
      im Browser verschlüsselt, für den Betreiber nie sichtbar.</p>
      <p><strong>Hosting.</strong> Die App wird auf einem Server in Deutschland betrieben. Der
      Hosting-Anbieter ${ph("[Anbieter, Anschrift – wird vor Veröffentlichung ergänzt]")} kann im
      Rahmen des Serverbetriebs Infrastruktur-/Server-Logs (einschließlich IP-Adresse) im Auftrag des
      Verantwortlichen verarbeiten; hierzu besteht ein Auftragsverarbeitungsvertrag nach Art. 28 DSGVO.
      Rechtsgrundlage: Art. 6 Abs. 1 lit. f DSGVO.</p>
      <p><strong>Keine Cookies, kein Tracking.</strong> HereBee setzt keine Cookies, nutzt keine
      Analyse- oder Tracking-Dienste und bindet keine fremden CDNs ein. Karten, Schriften und Symbole
      werden selbst gehostet.</p>
      <p><strong>Speicherdauer.</strong> Über die aktive Sitzung hinaus speichert die Anwendung nichts.
      Für etwaige Infrastruktur-Logs gilt die Aufbewahrungsfrist des Hosting-Anbieters.</p>
      <p><strong>Deine Rechte.</strong> Du hast das Recht auf Auskunft, Berichtigung, Löschung,
      Einschränkung, Datenübertragbarkeit und Widerspruch (Art. 15–22 DSGVO). Da über die Sitzung
      hinaus keine personenbezogenen Daten gespeichert werden, ergibt eine Auskunft in der Regel, dass
      keine gespeicherten Daten vorliegen. Außerdem besteht ein Beschwerderecht bei einer
      Aufsichtsbehörde (Art. 77 DSGVO).</p>
      <p><strong>Empfänger.</strong> Eine Weitergabe an Dritte erfolgt nicht, außer an den
      Hosting-Anbieter als Auftragsverarbeiter. Es findet keine Datenübermittlung in Drittländer statt.</p>
      <p class="legal-updated">Stand: ${ph("[Datum – bei Veröffentlichung ergänzen]")}</p>`;
    this.openSheet();
    this.sheetBody.scrollTop = 0;
    document.getElementById("legal-back")!.addEventListener("click", () => this.openInfo());
  }

  private openSheet(kind?: "splash"): void {
    this.sheet.classList.toggle("is-splash", kind === "splash");
    this.sheet.hidden = false;
  }
  private closeSheet(): void {
    this.sheet.hidden = true;
    this.sheet.classList.remove("is-splash");
    this.gated = false;
    document.getElementById("sheet-close")!.style.display = "";
  }
}
