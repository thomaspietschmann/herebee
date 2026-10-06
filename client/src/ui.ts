/**
 * View layer: HUD chrome, dock controls, share/info sheets, toasts.
 * Holds no app state beyond the DOM — main.ts drives it.
 */
import { lang, t } from "./i18n.js";
import { OFFICIAL_ORIGIN, isOfficialOrigin } from "../../shared/server.js";
import { NEON_NAMES, NEON_THEMES, isNeon, neonSwatch, type MapTheme, type NeonTheme } from "../../shared/map-theme.js";

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

export type MapThemePref = "auto" | MapTheme;

export interface RoomsView {
  enabled: boolean;
  current: string;
  rooms: Array<{ secret: string; title: string; current: boolean }>;
}

export interface RoomsHandlers {
  view: () => RoomsView;
  onNew: () => void;
  onOpen: (secret: string) => void;
  onLink: (url: string) => boolean;
  onToggle: (on: boolean) => void;
  onForget: (secret: string) => void;
  onForgetAll: () => void;
}

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

  bindRooms(h: RoomsHandlers): void {
    this.connChip.setAttribute("role", "button");
    this.connChip.setAttribute("tabindex", "0");
    this.connChip.setAttribute("aria-haspopup", "dialog");
    this.connChip.title = t("roomsTitle");
    this.connChip.classList.add("is-button");
    this.connChip.addEventListener("click", () => this.openRooms(h));
    this.connChip.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        this.openRooms(h);
      }
    });
  }

  private openRooms(h: RoomsHandlers): void {
    if (this.gated) return;
    const v = h.view();
    const list = v.rooms.length
      ? `<p class="rooms-label">${t("roomsRecent")}</p>
        <ul class="party-list">${v.rooms
          .map(
            (r) =>
              `<li class="room-row"><button type="button" class="party room-open" data-secret="${r.secret}"${r.current ? " disabled" : ""}><span class="party-text"><span class="party-name">${this.esc(r.title)}</span>${r.current ? `<span class="party-say">${t("roomsCurrent")}</span>` : ""}</span></button>${r.current ? "" : `<button type="button" class="room-forget" data-secret="${r.secret}" aria-label="${t("roomsForget")}" title="${t("roomsForget")}">✕</button>`}</li>`
          )
          .join("")}</ul>
        ${v.rooms.some((r) => !r.current) ? `<p class="rooms-forget-all"><button type="button" class="linklike" id="rooms-forget-all">${t("roomsForgetAll")}</button></p>` : ""}`
      : "";
    this.sheetBody.innerHTML = `
      <h2>${t("roomsTitle")}</h2>
      <button type="button" class="btn btn-primary btn-fill" id="rooms-new">＋ ${t("roomsNew")}</button>
      <div class="linkbox linkbox-gap-16">
        <input id="rooms-link" inputmode="url" autocomplete="off" placeholder="${t("roomsLinkHint")}" />
      </div>
      <p class="rooms-invalid" id="rooms-invalid" hidden>${t("roomsLinkInvalid")}</p>
      <label class="rooms-switch">
        <input type="checkbox" id="rooms-remember"${v.enabled ? " checked" : ""} />
        <span class="rooms-switch-track" aria-hidden="true"></span>
        <span>${t("roomsRemember")}</span>
      </label>
      <p class="rooms-note">${t(v.enabled ? "roomsRememberOn" : "roomsRememberOff")}</p>
      ${list}`;
    this.openSheet();
    document.getElementById("rooms-new")!.addEventListener("click", () => h.onNew());
    const link = document.getElementById("rooms-link") as HTMLInputElement;
    const invalid = document.getElementById("rooms-invalid")!;
    const tryLink = () => {
      const text = link.value.trim();
      if (!text) {
        invalid.hidden = true;
        return;
      }
      invalid.hidden = h.onLink(text);
    };
    link.addEventListener("input", tryLink);
    link.addEventListener("keydown", (e) => {
      if (e.key === "Enter") tryLink();
    });
    document.getElementById("rooms-remember")!.addEventListener("change", (e) => {
      h.onToggle((e.target as HTMLInputElement).checked);
      this.openRooms(h);
    });
    this.sheetBody.querySelectorAll<HTMLElement>(".room-open:not([disabled])").forEach((el) =>
      el.addEventListener("click", () => h.onOpen(el.dataset.secret!))
    );
    this.sheetBody.querySelectorAll<HTMLElement>(".room-forget").forEach((el) =>
      el.addEventListener("click", () => {
        h.onForget(el.dataset.secret!);
        this.openRooms(h);
      })
    );
    document.getElementById("rooms-forget-all")?.addEventListener("click", () => {
      h.onForgetAll();
      this.openRooms(h);
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
    const choice = (pref: MapThemePref, key: "mapThemeAuto" | "mapThemeLight" | "mapThemeDark") =>
      `<button type="button" class="seg${pref === current ? " is-active" : ""}" data-theme="${pref}" aria-pressed="${pref === current}">${t(key)}</button>`;
    const neonLabel = (pref: MapThemePref) => (isNeon(pref) ? NEON_NAMES[pref] : t("mapThemeSynthwave"));
    const neonOption = (theme: NeonTheme) => {
      const [ground, major, highway] = neonSwatch(theme);
      return `<li><button type="button" class="neon-opt${theme === current ? " is-active" : ""}" role="menuitemradio" aria-checked="${theme === current}" data-theme="${theme}"><span class="neon-swatch" data-sw="${ground}|${major}|${highway}"></span>${NEON_NAMES[theme]}</button></li>`;
    };
    this.sheetBody.innerHTML = `
      <h2>${t("mapTheme")}</h2>
      <div class="segmented segmented-4" role="group" aria-label="${t("mapTheme")}">
        ${choice("auto", "mapThemeAuto")}${choice("light", "mapThemeLight")}${choice("dark", "mapThemeDark")}<button type="button" class="seg seg-neon${isNeon(current) ? " is-active" : ""}" id="neon-toggle" aria-haspopup="menu" aria-expanded="false" aria-controls="neon-menu"><span class="seg-neon-label">${neonLabel(current)}</span><span class="seg-caret" aria-hidden="true">▾</span></button>
      </div>
      <ul class="neon-menu" id="neon-menu" role="menu" aria-label="${t("mapThemeSynthwave")}" hidden>
        ${NEON_THEMES.map(neonOption).join("")}
      </ul>
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
    this.sheetBody.querySelectorAll<HTMLElement>(".neon-swatch[data-sw]").forEach((el) => {
      const [a, b, c] = el.dataset.sw!.split("|");
      el.style.setProperty("--sw-a", a);
      el.style.setProperty("--sw-b", b);
      el.style.setProperty("--sw-c", c);
    });
    const neonToggle = document.getElementById("neon-toggle")!;
    const neonMenu = document.getElementById("neon-menu")!;
    const showMenu = (open: boolean) => {
      neonMenu.hidden = !open;
      neonToggle.setAttribute("aria-expanded", String(open));
    };
    const pick = (pref: MapThemePref) => {
      this.h.onMapTheme(pref);
      this.sheetBody.querySelectorAll<HTMLElement>(".seg[data-theme]").forEach((b) => {
        b.classList.toggle("is-active", b.dataset.theme === pref);
        b.setAttribute("aria-pressed", String(b.dataset.theme === pref));
      });
      neonToggle.classList.toggle("is-active", isNeon(pref));
      neonToggle.querySelector(".seg-neon-label")!.textContent = neonLabel(pref);
      neonMenu.querySelectorAll<HTMLElement>(".neon-opt").forEach((b) => {
        b.classList.toggle("is-active", b.dataset.theme === pref);
        b.setAttribute("aria-checked", String(b.dataset.theme === pref));
      });
      showMenu(false);
    };
    this.sheetBody.querySelectorAll<HTMLElement>(".seg[data-theme], .neon-opt").forEach((el) => {
      el.addEventListener("click", () => pick(el.dataset.theme as MapThemePref));
    });
    neonToggle.addEventListener("click", () => showMenu(neonMenu.hidden));
    document.getElementById("open-legal")!.addEventListener("click", () => this.openLegal());
  }

  private openLegal(): void {
    const de = lang === "de";
    const body = de
      ? `
      <h2>Datenschutz</h2>
      <p class="legal-dev"><strong>Kurz gesagt:</strong> Keine Konten, keine Datenbank, keine Cookies,
      kein Tracking. Standort, Name und Nachrichten werden in deinem Browser verschlüsselt. Der Server
      leitet sie nur weiter und kann sie nicht lesen.</p>

      <p><strong>Was wir verarbeiten</strong></p>
      <ul class="facts">
        <li>Deine <strong>IP-Adresse</strong>, solange du verbunden bist. Ohne sie erreicht dich der
        Server nicht; außerdem begrenzt er damit die Verbindungen pro Adresse, um Missbrauch zu
        verhindern.</li>
        <li><strong>Verschlüsselte Datenpakete</strong> deines Raums (Standort, Name, Nachricht). Der
        Server reicht sie an die anderen im Raum weiter, ohne sie lesen zu können.</li>
        <li>Die <strong>Kartenkacheln</strong>, die dein Browser lädt. Daran ließe sich grob ablesen,
        welche Gegend du gerade ansiehst.</li>
      </ul>

      <p class="sheet-gap-12"><strong>Was wir nicht erheben</strong></p>
      <ul class="facts">
        <li>Keine Konten, keine E-Mail-Adresse, keine Telefonnummer, keine Kontakte.</li>
        <li>Keine lesbaren Koordinaten, Namen oder Nachrichten und niemals den Raum-Schlüssel.</li>
        <li>Keine Standorthistorie, keine Datenbank, keine Zugriffs-Logs der Anwendung.</li>
        <li>Keine Cookies, keine Analyse, keine Werbung, keine fremden Tracking-Dienste oder CDNs.</li>
      </ul>

      <p class="sheet-gap-12"><strong>So funktioniert das Standortteilen</strong></p>
      <p>Jeder Raum hat einen 256-Bit-Schlüssel, der nur im Link hinter <code>#</code> steht und nie an
      den Server geht. Dein Browser leitet daraus die Raum-Kennung und einen AES-256-GCM-Schlüssel ab und
      verschlüsselt damit Standort, Anzeigenamen und Nachrichten, bevor etwas das Gerät verlässt. Der
      Server sieht weder Koordinaten noch Namen noch den Schlüssel.</p>
      <p>Alles ist flüchtig: Ein Raum existiert nur im Arbeitsspeicher des Servers und verschwindet,
      sobald der letzte Teilnehmer geht. Dein Standort wird nur übertragen, solange du teilst; eine
      Nachricht ist zehn Minuten lang sichtbar. Nichts davon wird gespeichert.</p>
      <p>Der Browser fragt vor dem ersten Zugriff auf deinen Standort um Erlaubnis. Du kannst das Teilen
      jederzeit stoppen und die Erlaubnis in den Browser-Einstellungen entziehen. Wer den vollständigen
      Link hat, sieht den Raum – teile ihn nur mit Leuten, denen du vertraust.</p>
      <p>Deine Biene ist in jedem Raum eine andere: Ihre Kennung wird aus einem geheimen Geräteschlüssel
      und dem Raum abgeleitet, und Namen gelten nur in dem Raum, in dem sie vergeben wurden.
      Wiedererkennbar bist du über Räume hinweg nur an deinem Standort oder an einem Namen, den du selbst
      in mehreren Räumen verwendest.</p>

      <p><strong>Server und IP-Adressen</strong></p>
      <p>Der Server steht in Deutschland. Die HereBee-Software protokolliert und speichert weder
      IP-Adressen noch Inhalte; deine IP liegt nur während der Verbindung im Arbeitsspeicher. Die
      Infrastruktur davor (Hosting-Anbieter, Proxy) kann eigene technische Logs mit IP-Adressen führen,
      die nach deren Fristen gelöscht werden.</p>

      <p><strong>Fehlerberichte</strong></p>
      <p>Die Web-Version sendet keine Fehlerberichte.</p>

      <p><strong>Karten</strong></p>
      <p>Karten, Schriften und Symbole kommen vom HereBee-Server selbst (Kartendaten © OpenStreetMap-Mitwirkende,
      Format von Protomaps). Kartendienste Dritter wie Google Maps werden nicht
      aufgerufen.</p>

      <p><strong>In deinem Browser gespeichert</strong></p>
      <p>Im localStorage: der geheime Geräteschlüssel, pro Raum die Namen, die du anderen gegeben hast,
      dein eigener Name und ob du ihn teilst, sowie deine Einstellungen für Sprechblasen und Kartenstil.
      Nur für den offenen Tab (sessionStorage): ein zufälliges Token für die Wiederverbindung, ob du
      gerade teilst, und deine aktuelle Nachricht bis zu ihrem Ablauf. Das ist für die Funktion nötig und
      lässt sich über die Website-Daten des Browsers jederzeit löschen.</p>

      <p><strong>Dritte</strong></p>
      <p>Wir geben keine Daten weiter und verkaufen nichts. Einziger Dienstleister ist der
      Hosting-Anbieter, der den Server für uns betreibt.</p>

      <p><strong>Kinder</strong></p>
      <p>HereBee ist nicht speziell für Kinder gemacht. Da es keine Konten gibt, fragen wir kein Alter ab
      und erheben wissentlich keine Daten von Kindern. Lässt du ein Kind seinen Standort teilen, gib den
      Link nur an Menschen, denen du vertraust.</p>

      <p><strong>Deine Rechte</strong></p>
      <p>Du hast das Recht auf Auskunft, Berichtigung, Löschung und Widerspruch sowie das Recht, dich bei
      einer Datenschutzbehörde zu beschweren. Da HereBee über die laufende Verbindung hinaus nichts über
      dich speichert, gibt es in der Regel nichts herauszugeben oder zu löschen.</p>

      <p><strong>Änderungen</strong></p>
      <p>Ändert sich HereBee, passen wir diese Seite an. Es gilt die hier veröffentlichte Fassung; das
      Datum unten zeigt den Stand.</p>

      <p><strong>Kontakt</strong></p>
      <p>Fragen zum Datenschutz oder zu HereBee erreichen uns über die Kontaktangaben im App Store bzw.
      bei Google Play.</p>

      <h2 class="sheet-section">Über HereBee</h2>
      <p><strong>Betreiber:</strong> HereBee</p>
      <p>Für alle Anliegen zu HereBee – auch rechtliche – nutze die Kontaktangaben im App Store bzw. bei
      Google Play.</p>
      <p class="legal-updated">Stand: 3. Oktober 2026</p>`
      : `
      <h2>Privacy</h2>
      <p class="legal-dev"><strong>In short:</strong> No accounts, no database, no cookies, no tracking.
      Your location, name and messages are encrypted in your browser. The server only passes them on and
      cannot read them.</p>

      <p><strong>What we process</strong></p>
      <ul class="facts">
        <li>Your <strong>IP address</strong>, while you are connected. The server cannot reach you
        without it, and it uses it to limit connections per address against abuse.</li>
        <li><strong>Encrypted data packets</strong> of your room (location, name, message). The server
        hands them to the others in the room without being able to read them.</li>
        <li>The <strong>map tiles</strong> your browser loads. They could reveal roughly which area you
        are looking at.</li>
      </ul>

      <p class="sheet-gap-12"><strong>What we don't collect</strong></p>
      <ul class="facts">
        <li>No accounts, no e-mail address, no phone number, no contacts.</li>
        <li>No readable coordinates, names or messages, and never the room key.</li>
        <li>No location history, no database, no access logs kept by the application.</li>
        <li>No cookies, no analytics, no ads, no third-party tracking services or CDNs.</li>
      </ul>

      <p class="sheet-gap-12"><strong>How location sharing works</strong></p>
      <p>Every room has a 256-bit key that lives only in the link after <code>#</code> and is never sent
      to the server. Your browser derives the room ID and an AES-256-GCM key from it and encrypts your
      location, display name and messages before anything leaves your device. The server never sees
      coordinates, names or the key.</p>
      <p>Everything is ephemeral: a room exists only in the server's memory and disappears when the last
      participant leaves. Your location is sent only while you share; a message stays visible for ten
      minutes. None of it is stored.</p>
      <p>Your browser asks for permission before the first access to your location. You can stop sharing
      at any time and revoke the permission in your browser settings. Anyone with the full link can see
      the room, so only share it with people you trust.</p>
      <p>Your bee is a different one in every room: its ID is derived from a secret device key and the
      room, and names only apply in the room where they were given. Across rooms you can only be
      recognised by your location or by a name you use in several rooms yourself.</p>

      <p><strong>Server and IP addresses</strong></p>
      <p>The server is located in Germany. The HereBee software neither logs nor stores IP addresses or
      content; your IP is held in memory only while you are connected. The infrastructure in front of it
      (hosting provider, proxy) may keep its own technical logs including IP addresses, deleted according
      to its own retention periods.</p>

      <p><strong>Crash reports</strong></p>
      <p>The web version does not send crash reports.</p>

      <p><strong>Map tiles</strong></p>
      <p>Maps, fonts and icons are served by the HereBee server itself (map data © OpenStreetMap
      contributors, format by Protomaps). No third-party map services such as Google Maps are
      contacted.</p>

      <p><strong>Stored in your browser</strong></p>
      <p>In localStorage: the secret device key, per room the names you gave others, your own name and
      whether you share it, and your speech bubble and map style settings. For the open tab only
      (sessionStorage): a random reconnect token, whether you are sharing, and your current message until
      it expires. This is needed for the app to work and can be deleted at any time via your browser's
      site data.</p>

      <p><strong>Third parties</strong></p>
      <p>We don't share or sell any data. The only service provider is the hosting provider that
      runs the server for us.</p>

      <p><strong>Children</strong></p>
      <p>HereBee is not made for children specifically. As there are no accounts, we don't ask for age
      and don't knowingly collect data from children. If you let a child share their location, only give
      the link to people you trust.</p>

      <p><strong>Your rights</strong></p>
      <p>You have the right to access, correct and delete your data, to object, and to complain to a data
      protection authority. Since HereBee stores nothing about you beyond the active connection, there is
      usually nothing to hand over or delete.</p>

      <p><strong>Changes</strong></p>
      <p>When HereBee changes, we update this page. The version published here applies; the date below
      shows when it was last updated.</p>

      <p><strong>Contact</strong></p>
      <p>For questions about privacy or HereBee, use the contact details in the App Store or on Google
      Play.</p>

      <h2 class="sheet-section">About HereBee</h2>
      <p><strong>Operator:</strong> HereBee</p>
      <p>For any matter concerning HereBee, including legal ones, use the contact details in the App Store
      or on Google Play.</p>
      <p class="legal-updated">Last updated: October 3, 2026</p>`;
    this.sheetBody.innerHTML = `
      <button type="button" class="linklike legal-back" id="legal-back">‹ ${t("infoTitle")}</button>
      ${body}`;
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
