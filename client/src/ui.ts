/**
 * View layer: HUD chrome, dock controls, share/info sheets, toasts.
 * Holds no app state beyond the DOM — main.ts drives it.
 */

export interface UIHandlers {
  onToggleShare: () => void;
}

type Conn = "connecting" | "on" | "off";

export class UI {
  private connChip = document.getElementById("conn")!;
  private connDot = this.connChip.querySelector<HTMLElement>(".chip-text")!;
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

  constructor(h: UIHandlers) {
    this.geoBtn.addEventListener("click", () => h.onToggleShare());
    this.shareBtn.addEventListener("click", () => this.copyLink());
    this.infoBtn.addEventListener("click", () => this.openInfo());
    this.roster.addEventListener("click", () => this.openInfo());
    document.getElementById("sheet-close")!.addEventListener("click", () => this.closeSheet());
    this.sheet.addEventListener("click", (e) => {
      if (e.target === this.sheet) this.closeSheet();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.closeSheet();
    });
  }

  setConnection(state: Conn): void {
    this.connChip.classList.toggle("is-on", state === "on");
    this.connChip.classList.toggle("is-off", state === "off");
    this.connDot.textContent =
      state === "on" ? "Verbunden" : state === "off" ? "Getrennt" : "Verbindung…";
  }

  setSharing(on: boolean): void {
    this.sharing = on;
    this.geoBtn.classList.toggle("is-sharing", on);
    this.geoLabel.textContent = on ? "Teilen stoppen" : "Standort teilen";
    if (on) this.hideHint();
  }

  isSharing(): boolean {
    return this.sharing;
  }

  setRoster(members: { color: string; name: string }[]): void {
    const n = members.length;
    this.roster.hidden = n === 0;
    this.rosterCount.textContent = n === 1 ? "1 hier" : `${n} hier`;
    this.rosterStack.innerHTML = members
      .slice(0, 5)
      .map((m) => `<span class="pip" style="background:${m.color}" title="${m.name}"></span>`)
      .join("");
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
      this.toast("Link kopiert");
    } catch {
      this.openShare(url);
    }
  }

  private openShare(url: string): void {
    this.sheetBody.innerHTML = `
      <h2>Raum teilen</h2>
      <p>Wer diesen Link öffnet, tritt dem Raum bei und sieht die Live-Standorte.
         Der Link <strong>ist</strong> der Schlüssel — teile ihn bewusst.</p>
      <div class="linkbox">
        <input id="link-input" readonly value="${url.replace(/"/g, "&quot;")}" />
        <button class="btn btn-ghost" id="link-copy">Kopieren</button>
      </div>`;
    this.openSheet();
    const input = document.getElementById("link-input") as HTMLInputElement;
    document.getElementById("link-copy")!.addEventListener("click", () => {
      input.select();
      document.execCommand?.("copy");
      this.toast("Link kopiert");
    });
  }

  private openInfo(): void {
    this.sheetBody.innerHTML = `
      <h2>Wie privat ist das?</h2>
      <p>localizer teilt Standorte <strong>flüchtig und Ende-zu-Ende-verschlüsselt</strong>
         zwischen aktiven Teilnehmern. Es ist bewusst datensparsam — aber nenne es nicht
         „vollständig anonym“.</p>
      <ul class="facts">
        <li>Der Server sieht <strong>weder Koordinaten noch Namen noch den Schlüssel</strong> — nur verschlüsselte Datenpakete.</li>
        <li>Der Schlüssel steckt im Link hinter <code>#</code> und wird nie an den Server gesendet.</li>
        <li>Es gibt <strong>keine Datenbank und keine Logs</strong>; Räume leben nur, solange jemand da ist.</li>
        <li class="warn">Relay und Karten-Server sehen deine <strong>IP</strong> für die Dauer der Verbindung (nicht gespeichert). Das lässt sich im Browser nicht wegzaubern.</li>
        <li class="warn">Wer den vollständigen Link hat, sieht den Raum. Teile ihn nur mit Vertrauten.</li>
      </ul>`;
    this.openSheet();
  }

  private openSheet(): void {
    this.sheet.hidden = false;
  }
  private closeSheet(): void {
    this.sheet.hidden = true;
  }
}
