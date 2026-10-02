/**
 * View layer: HUD chrome, dock controls, share/info sheets, toasts.
 * Holds no app state beyond the DOM — main.ts drives it.
 */
import { t } from "./i18n.js";
import { OFFICIAL_ORIGIN, isOfficialOrigin } from "../../shared/server.js";

/** Apple devices. iPads report a Mac user agent, and the Mac shares with the same glyph. */
const APPLE = /iPhone|iPad|iPod|Macintosh/.test(navigator.userAgent);

/**
 * The share glyph people know from their own platform: Apple's box with an
 * arrow, elsewhere Android's three connected dots.
 */
const SHARE_ICON = APPLE
  ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="M8 7l4-4 4 4"/><path d="M8.5 10H7a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7a2 2 0 0 0-2-2h-1.5"/></svg>'
  : '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z"/></svg>';

export interface UIHandlers {
  onToggleShare: () => void;
  onFitAll: () => void; // zoom the map so every shared marker fits on screen
  onGoTo: (seed: string) => void; // fly the map to one participant's marker
  onToggleBubbles: () => void;
  mapTheme: () => MapThemePref;
  onMapTheme: (pref: MapThemePref) => void;
}

export type MapThemePref = "auto" | "light" | "dark" | "synthwave";

interface Sharer {
  seed: string;
  color: string;
  name: string;
  offline: boolean; // was sharing but its link dropped — still a ghost on the map
  say?: string;
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
  private bubblesBtn = document.getElementById("bubbles-btn")!;
  private sayLive = document.getElementById("say-live")!;
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
    this.shareBtn.innerHTML = SHARE_ICON;
    this.shareBtn.title = t("shareLink");
    this.infoBtn.title = t("infoAria");
    this.shareBtn.addEventListener("click", () => void this.shareLink());
    this.infoBtn.addEventListener("click", () => this.openInfo());
    this.roster.addEventListener("click", () => this.openParticipants());
    this.fitAllBtn.addEventListener("click", () => this.h.onFitAll());
    this.bubblesBtn.addEventListener("click", () => this.h.onToggleBubbles());
    document.getElementById("sheet-close")!.addEventListener("click", () => this.closeSheet());
    this.sheet.addEventListener("click", (e) => {
      if (e.target === this.sheet && !this.gated) this.closeSheet();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !this.gated) this.closeSheet();
    });
  }

  private paintPips(root: HTMLElement): void {
    root.querySelectorAll<HTMLElement>(".pip[data-color]").forEach((el) => {
      el.style.background = el.dataset.color!;
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
          `<span class="pip${m.offline ? " pip-offline" : ""}" data-color="${this.esc(m.color)}" title="${this.esc(m.name)}"></span>`
      );
    const hollowN = Math.min(watchers, Math.max(0, 5 - sharerPips.length));
    const hollow = Array.from(
      { length: hollowN },
      () => `<span class="pip pip-watcher" title="${t("watcher")}"></span>`
    );
    this.rosterStack.innerHTML = [...sharerPips, ...hollow].join("");
    this.paintPips(this.rosterStack);
  }

  /** Participant list, opened by tapping the roster pill. "Fit everyone on
   *  screen" lives as its own icon button next to the pill (see fitAllBtn),
   *  not in here, so it doesn't require opening this sheet first. */
  private openParticipants(): void {
    const list = this.lastSharers.length
      ? `<ul class="party-list">${this.lastSharers
          .map(
            (m) =>
              `<li><button type="button" class="party${m.offline ? " is-offline" : ""}" data-seed="${this.esc(m.seed)}"><span class="pip${m.offline ? " pip-offline" : ""}" data-color="${this.esc(m.color)}"></span><span class="party-text"><span class="party-name">${this.esc(m.name)}</span>${m.say ? `<span class="party-say">💬 ${this.esc(m.say)}</span>` : ""}</span>${m.offline ? `<span class="party-status">${t("offlineStatus")}</span>` : ""}</button></li>`
          )
          .join("")}</ul>`
      : `<p>${t("noSharers")}</p>`;
    const watching =
      this.lastWatchers > 0 ? `<p class="watching-note">${t("watchingLine", { n: this.lastWatchers })}</p>` : "";
    this.sheetBody.innerHTML = `
      <h2>${t("participantsTitle")}</h2>
      ${list}
      ${watching}`;
    this.paintPips(this.sheetBody);
    this.openSheet();
    // Tap a participant to fly the map to their marker.
    this.sheetBody.querySelectorAll<HTMLElement>(".party[data-seed]").forEach((el) => {
      el.addEventListener("click", () => {
        this.closeSheet();
        this.h.onGoTo(el.dataset.seed!);
      });
    });
  }

  menuBounds(): { left: number; top: number; right: number; bottom: number } {
    const inset = 8;
    const hud = document.querySelector<HTMLElement>(".hud")!.getBoundingClientRect();
    const roster = this.rosterGroup.hidden ? hud : this.rosterGroup.getBoundingClientRect();
    const dockTop = this.hint.classList.contains("is-hidden")
      ? document.querySelector<HTMLElement>(".controls")!.getBoundingClientRect().top
      : this.hint.getBoundingClientRect().top;
    return {
      left: inset,
      top: Math.max(hud.bottom, roster.bottom) + inset,
      right: window.innerWidth - inset,
      bottom: dockTop - inset,
    };
  }

  setBubblesVisible(visible: boolean): void {
    const label = t(visible ? "bubblesHide" : "bubblesShow");
    this.bubblesBtn.setAttribute("aria-pressed", String(visible));
    this.bubblesBtn.setAttribute("aria-label", label);
    this.bubblesBtn.title = label;
  }

  announce(text: string): void {
    this.sayLive.textContent = "";
    requestAnimationFrame(() => (this.sayLive.textContent = text));
  }

  toastAction(msg: string, onClick: () => void): void {
    this.toast(msg);
    const handler = () => {
      this.toastEl.removeEventListener("click", handler);
      this.toastEl.classList.remove("is-action");
      onClick();
    };
    this.toastEl.classList.add("is-action");
    this.toastEl.addEventListener("click", handler);
    window.setTimeout(() => {
      this.toastEl.removeEventListener("click", handler);
      this.toastEl.classList.remove("is-action");
    }, 2500);
  }

  openSay(current: string | null, onSave: (text: string | null) => void): void {
    this.sheetBody.innerHTML = `
      <h2>${t("sayTitle")}</h2>
      <p>${t("sayBody")}</p>
      <div class="linkbox">
        <div class="say-field">
          <input id="say-input" class="say-input" maxlength="100" enterkeyhint="send" placeholder="${t("sayPlaceholder")}" value="${this.esc(current ?? "")}" />
          <button type="button" class="say-x" id="say-x" aria-label="${t("sayClearInput")}" title="${t("sayClearInput")}">×</button>
        </div>
        <button class="btn btn-primary" id="say-send">${t("saySend")}</button>
      </div>
      <p class="say-meta" id="say-count"></p>
      ${current ? `<button class="btn btn-ghost btn-gap-10" id="say-clear">${t("sayClear")}</button>` : ""}`;
    this.openSheet();
    const input = document.getElementById("say-input") as HTMLInputElement;
    const count = document.getElementById("say-count")!;
    const clearBtn = document.getElementById("say-x")!;
    const updateCount = () => {
      count.textContent = `${Array.from(input.value).length}/100`;
      clearBtn.hidden = input.value.length === 0;
    };
    clearBtn.addEventListener("click", () => {
      input.value = "";
      updateCount();
      input.focus();
    });
    updateCount();
    input.addEventListener("input", updateCount);
    input.focus();
    input.select();
    const send = (text: string) => {
      const v = text.trim();
      this.closeSheet();
      onSave(v.length ? v : null);
    };
    document.getElementById("say-send")!.addEventListener("click", () => send(input.value));
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") send(input.value);
    });
    document.getElementById("say-clear")?.addEventListener("click", () => {
      this.closeSheet();
      onSave(null);
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

  /** The platform share sheet where there is one, else the clipboard. */
  private async shareLink(): Promise<void> {
    const url = location.href;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ url });
        return;
      } catch (e) {
        // Dismissing the sheet is a normal answer, not a reason to copy.
        if (e instanceof DOMException && e.name === "AbortError") return;
      }
    }
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
        <input id="link-input" readonly value="${this.esc(url)}" />
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
    this.sheetBody.innerHTML = `${this.appLinkRow()}
      <img class="splash-logo" src="/brand/herebee-logo.png" alt="" aria-hidden="true" />
      <h2>${t("welcomeTitle")}</h2>
      <p>${t("welcomeIntro")}</p>
      ${this.serverWarning()}
      <ul class="facts">
        <li>${t("welcomeFact1")}</li>
        <li>${t("welcomeFact2")}</li>
        <li>${t("welcomeFact3")}</li>
      </ul>
      <div class="linkbox linkbox-gap-18">
        <button class="btn btn-primary btn-fill" id="welcome-ok">${t("welcomeCta")}</button>
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
   * On iOS, a way from this page into the installed app. Until Universal Links
   * are active, tapping a room link in a chat always lands here in Safari; the
   * custom scheme hands the same fragment secret to the app. The secret stays
   * in the fragment, so it still never reaches a server. Without the app
   * installed the link just does nothing, hence the plain secondary button.
   * It sits above the logo because the gate scrolls on a phone, and below the
   * fold nobody who came here for the app would find it.
   */
  private appLinkRow(): string {
    const ios =
      /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (navigator.userAgent.includes("Macintosh") && navigator.maxTouchPoints > 1);
    if (!ios || !location.hash) return "";
    // The app talks to the official server unless told otherwise, so a room on
    // another server must name it, or the app would open an empty namesake.
    const server = isOfficialOrigin(location.origin) ? "" : `?server=${encodeURIComponent(location.origin)}`;
    const href = this.esc(`herebee://r${server}${location.hash}`);
    return `
      <div class="linkbox linkbox-app">
        <a class="btn btn-fill btn-anchor" href="${href}">${t("welcomeOpenApp")}</a>
      </div>`;
  }

  /**
   * The warning for a page served by anyone but the official server. Empty on
   * the official one. In a browser the server also delivers the code that
   * handles the key, which is why the web version says more than the app's.
   */
  private serverWarning(): string {
    if (isOfficialOrigin(location.origin)) return "";
    const host = this.esc(location.host);
    return `
      <div class="server-warn" role="note">
        <h3>${t("serverWarnTitle")}</h3>
        <p>${t("serverWarnBody", { host, official: new URL(OFFICIAL_ORIGIN).host })}</p>
        <p>${t("serverWarnWeb")}</p>
      </div>`;
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
        <input id="rename-input" maxlength="40" placeholder="${t("renamePlaceholder")}" value="${this.esc(currentName)}" />
        <button class="btn btn-primary" id="rename-save">${t("save")}</button>
      </div>
      ${hasCustom ? `<button class="btn btn-ghost btn-gap-10" id="rename-reset">${t("renameReset")}</button>` : ""}`;
    this.openSheet();
    const input = document.getElementById("rename-input") as HTMLInputElement;
    input.focus();
    input.select();
    // Close first: onSave may open the next sheet (the share question).
    const save = () => {
      const v = input.value.trim();
      this.closeSheet();
      onSave(v.length ? v : null);
    };
    document.getElementById("rename-save")!.addEventListener("click", save);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") save();
    });
    document.getElementById("rename-reset")?.addEventListener("click", () => {
      this.closeSheet();
      onSave(null);
    });
  }

  /** After naming yourself: may the others see it? Needs an answer, so it can't be dismissed. */
  askShareName(name: string, onAnswer: (share: boolean) => void): void {
    this.sheetBody.innerHTML = `
      <h2>${t("shareNameTitle")}</h2>
      <p>${t("shareNameBody", { name: this.esc(name) })}</p>
      <div class="linkbox linkbox-gap-16">
        <button class="btn btn-ghost btn-fill" id="share-name-no">${t("shareNameNo")}</button>
        <button class="btn btn-primary btn-fill" id="share-name-yes">${t("shareNameYes")}</button>
      </div>`;
    this.gated = true;
    this.openSheet();
    document.getElementById("sheet-close")!.style.display = "none";
    const answer = (share: boolean) => {
      this.closeSheet();
      onAnswer(share);
    };
    document.getElementById("share-name-yes")!.addEventListener("click", () => answer(true));
    document.getElementById("share-name-no")!.addEventListener("click", () => answer(false));
  }

  /** Shown when the room link's secret is missing or malformed. */
  openInvalidLink(): void {
    this.sheetBody.innerHTML = `
      <h2>${t("invalidTitle")}</h2>
      <p>${t("invalidBody")}</p>
      <div class="linkbox linkbox-gap-16">
        <button class="btn btn-primary btn-fill" id="invalid-new">${t("invalidCta")}</button>
      </div>`;
    this.gated = true;
    this.openSheet();
    document.getElementById("sheet-close")!.style.display = "none";
    document.getElementById("invalid-new")!.addEventListener("click", () => {
      location.assign("/");
    });
  }

  private openInfo(): void {
    const current = this.h.mapTheme();
    const choice = (
      pref: MapThemePref,
      key: "mapThemeAuto" | "mapThemeLight" | "mapThemeDark" | "mapThemeSynthwave"
    ) =>
      `<button type="button" class="seg${pref === current ? " is-active" : ""}" data-theme="${pref}" aria-pressed="${pref === current}">${t(key)}</button>`;
    this.sheetBody.innerHTML = `
      <h2>${t("mapTheme")}</h2>
      <div class="segmented segmented-4" role="group" aria-label="${t("mapTheme")}">
        ${choice("auto", "mapThemeAuto")}${choice("light", "mapThemeLight")}${choice("dark", "mapThemeDark")}${choice(
          "synthwave",
          "mapThemeSynthwave"
        )}
      </div>
      <h2 class="sheet-section">${t("serverTitle")}</h2>
      <p class="server-line"><code>${this.esc(location.host)}</code> · ${t(
        isOfficialOrigin(location.origin) ? "serverOfficial" : "serverUnofficial"
      )}</p>
      ${this.serverWarning()}
      <h2 class="sheet-section">${t("infoTitle")}</h2>
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
    this.sheetBody.querySelectorAll<HTMLElement>(".seg[data-theme]").forEach((el) => {
      el.addEventListener("click", () => {
        const pref = el.dataset.theme as MapThemePref;
        this.h.onMapTheme(pref);
        this.sheetBody.querySelectorAll<HTMLElement>(".seg[data-theme]").forEach((b) => {
          b.classList.toggle("is-active", b === el);
          b.setAttribute("aria-pressed", String(b === el));
        });
      });
    });
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

      <h2 class="sheet-section">Datenschutzerklärung</h2>
      <p><strong>Verantwortlicher</strong> im Sinne der DSGVO ist der im Impressum genannte
      Diensteanbieter.</p>
      <p><strong>Grundprinzip.</strong> HereBee ist bewusst datensparsam gebaut. Ein 256-Bit-Schlüssel
      steckt ausschließlich im Link hinter <code>#</code> und wird nie an den Server übertragen. Der
      Browser leitet daraus die Raum-Kennung und einen AES-256-GCM-Schlüssel ab; alle Koordinaten,
      Anzeigenamen und Nachrichten werden im Browser verschlüsselt. Der Server (Relay) leitet nur undurchsichtige,
      verschlüsselte Datenpakete weiter und kann sie nicht entschlüsseln.</p>
      <p><strong>Welche Daten verarbeitet werden:</strong></p>
      <ul class="facts">
        <li><strong>IP-Adresse</strong> – vorübergehend, um die WebSocket-Verbindung aufzubauen und die
        Zahl gleichzeitiger Verbindungen pro IP zu begrenzen (Missbrauchsschutz). Rechtsgrundlage:
        Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse am Betrieb und Schutz des Dienstes). Die
        Anwendung selbst speichert die IP nicht. Da die Kartenkacheln vom selben Server geladen werden,
        kann dieser anhand der angefragten Kacheln grob erkennen, welche Region du ansiehst; die
        Koordinaten selbst bleiben Ende-zu-Ende-verschlüsselt.</li>
        <li><strong>Verschlüsselte Standort-, Namens- und Nachrichtendaten</strong> – werden nur weitergeleitet,
        nicht gespeichert und sind für den Betreiber nicht lesbar.</li>
        <li><strong>Raumzustand</strong> – ausschließlich im Arbeitsspeicher; wird gelöscht, sobald der
        letzte Teilnehmer die Verbindung trennt. Keine Datenbank, keine Historie, keine Speicherung von
        Koordinaten oder Namen.</li>
      </ul>
      <p class="sheet-gap-12"><strong>Standortfreigabe.</strong> Die App nutzt die
      Geolocation-Funktion des Browsers. Der Zugriff erfolgt nur nach ausdrücklicher Erlaubnis über die
      Abfrage des Browsers (Einwilligung, Art. 6 Abs. 1 lit. a DSGVO) und ist jederzeit in den
      Browser-Einstellungen widerrufbar. Die Koordinaten sind Ende-zu-Ende-verschlüsselt und für den
      Server nie sichtbar.</p>
      <p><strong>Anzeigename.</strong> Frei wählbar (Pseudonym oder echter Name – deine Entscheidung),
      im Browser verschlüsselt, für den Betreiber nie sichtbar.</p>
      <p><strong>Nachrichten.</strong> Eine kurze Nachricht deiner Biene sehen alle im Raum zehn Minuten
      lang, solange du deinen Standort teilst. Sie wird im Browser verschlüsselt, mit jeder
      Standortmeldung erneut übertragen und bei den anderen nur im Arbeitsspeicher gehalten; niemand
      speichert sie dauerhaft.</p>
      <p><strong>Hosting.</strong> Die App wird auf einem Server in Deutschland betrieben. Der
      Hosting-Anbieter ${ph("[Anbieter, Anschrift – wird vor Veröffentlichung ergänzt]")} kann im
      Rahmen des Serverbetriebs Infrastruktur-/Server-Logs (einschließlich IP-Adresse) im Auftrag des
      Verantwortlichen verarbeiten; hierzu besteht ein Auftragsverarbeitungsvertrag nach Art. 28 DSGVO.
      Rechtsgrundlage: Art. 6 Abs. 1 lit. f DSGVO.</p>
      <p><strong>Keine Cookies, kein Tracking.</strong> HereBee setzt keine Cookies, nutzt keine
      Analyse- oder Tracking-Dienste und bindet keine fremden CDNs ein. Karten, Schriften und Symbole
      werden selbst gehostet.</p>
      <p><strong>Räume sind streng getrennt.</strong> Deine Biene ist in jedem Raum eine andere: Die
      Kennung wird im Browser aus einem geheimen Geräteschlüssel und dem Raum abgeleitet und lässt sich
      ohne diesen Schlüssel keinem anderen Raum zuordnen. Auch Namen gelten immer nur in dem Raum, in
      dem sie vergeben wurden. Wer dich in mehreren Räumen sieht, kann dich daher nicht an einer
      Kennung oder einem Namen wiedererkennen – wohl aber an deinem Standort, wenn du in mehreren
      Räumen teilst, oder an einem Namen, den du selbst in mehreren Räumen teilst.</p>
      <p><strong>Im Browser gespeichert.</strong> Im lokalen Speicher deines Browsers (localStorage)
      liegen der geheime Geräteschlüssel sowie pro Raum die Namen, die du anderen Teilnehmern gegeben
      hast, dein eigener Name und ob du ihn teilst, außerdem ob Sprechblasen angezeigt werden und welcher Kartenstil gewählt ist. Nur für
      den geöffneten Tab (sessionStorage) kommen ein zufälliges Token für die Wiederverbindung, die
      Angabe, ob du gerade teilst, und deine aktuelle Nachricht bis zu ihrem Ablauf hinzu. Das ist für die Funktion technisch erforderlich (§ 25 Abs. 2 TDDDG), verlässt den
      Browser nur verschlüsselt an die Teilnehmer bzw. als Token an den Server und lässt sich über die
      Website-Daten des Browsers jederzeit löschen.</p>
      <p><strong>Speicherdauer.</strong> Auf dem Server speichert die Anwendung über die aktive Sitzung
      hinaus nichts. Die Daten im Browser bleiben, bis du sie löschst. Für etwaige Infrastruktur-Logs
      gilt die Aufbewahrungsfrist des Hosting-Anbieters.</p>
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
    this.sheet.querySelector<HTMLElement>(".sheet-panel")!.scrollTop = 0;
  }
  private closeSheet(): void {
    this.sheet.hidden = true;
    this.sheet.classList.remove("is-splash");
    this.gated = false;
    document.getElementById("sheet-close")!.style.display = "";
  }
}
