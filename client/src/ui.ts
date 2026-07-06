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
}

type Conn = "connecting" | "on" | "off";

export class UI {
  private connChip = document.getElementById("conn")!;
  private connText = document.getElementById("conn-text")!;
  private geoBtn = document.getElementById("geo-btn")!;
  private geoLabel = this.geoBtn.querySelector<HTMLElement>(".btn-label")!;
  private shareBtn = document.getElementById("share-btn")!;
  private infoBtn = document.getElementById("info-btn")!;
  private roster = document.getElementById("roster") as HTMLButtonElement;
  private rosterStack = this.roster.querySelector<HTMLElement>(".roster-stack")!;
  private rosterCount = this.roster.querySelector<HTMLElement>(".roster-count")!;
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
   * @param sharers  peers currently broadcasting a location (colored pips)
   * @param watchers present-but-not-sharing count (anonymous, hollow pips)
   * @param total    total present incl. self (the "N here" number)
   */
  setRoster(sharers: Sharer[], watchers: number, total: number): void {
    this.lastSharers = sharers;
    this.lastWatchers = watchers;
    // Hide when it's only us alone watching; show once someone shares or others arrive.
    this.roster.hidden = total < 2 && sharers.length < 1;
    this.rosterCount.textContent = t("here", { n: total });
    const colored = sharers
      .slice(0, 5)
      .map((m) => `<span class="pip" style="background:${m.color}" title="${this.esc(m.name)}"></span>`);
    const hollowN = Math.min(watchers, Math.max(0, 5 - colored.length));
    const hollow = Array.from(
      { length: hollowN },
      () => `<span class="pip pip-watcher" title="${t("watcher")}"></span>`
    );
    this.rosterStack.innerHTML = [...colored, ...hollow].join("");
  }

  /** Participant list (opened by tapping the roster pill), with a "fit all" action. */
  private openParticipants(): void {
    const list = this.lastSharers.length
      ? `<ul class="party-list">${this.lastSharers
          .map(
            (m) =>
              `<li><button type="button" class="party" data-seed="${this.esc(m.seed)}"><span class="pip" style="background:${m.color}"></span>${this.esc(m.name)}</button></li>`
          )
          .join("")}</ul>`
      : `<p>${t("noSharers")}</p>`;
    const watching =
      this.lastWatchers > 0 ? `<p class="watching-note">${t("watchingLine", { n: this.lastWatchers })}</p>` : "";
    this.sheetBody.innerHTML = `
      <h2>${t("participantsTitle")}</h2>
      ${list}
      ${watching}
      <div class="linkbox" style="margin-top:18px">
        <button class="btn btn-primary" id="fit-all" style="flex:1">${t("fitAll")}</button>
      </div>`;
    this.openSheet();
    document.getElementById("fit-all")?.addEventListener("click", () => {
      this.closeSheet();
      this.h.onFitAll();
    });
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
      })}</p>`;
    this.openSheet();
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
