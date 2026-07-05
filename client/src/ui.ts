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

  /** Shown once when entering a room: how watching vs. sharing works. */
  openWelcome(): void {
    this.sheetBody.innerHTML = `
      <h2>Willkommen bei HereBee 🐝</h2>
      <p>Du bist in einem privaten Raum. Alle mit diesem Link finden sich hier live
         auf der Karte.</p>
      <ul class="facts">
        <li><strong>Nur zuschauen ist okay.</strong> Du musst deinen Standort nicht teilen — dann siehst du nur die anderen.</li>
        <li><strong>Standort teilen:</strong> Tippe unten auf <em>„Standort teilen“</em>. Danach sehen <strong>alle im Raum</strong> deinen Live-Standort — Ende-zu-Ende-verschlüsselt, nichts wird gespeichert.</li>
        <li><strong>Jederzeit stoppen:</strong> Der Button wird zu <em>„Teilen stoppen“</em> — ein Tipp, und du bist wieder unsichtbar.</li>
      </ul>
      <div class="linkbox" style="margin-top:18px">
        <button class="btn btn-primary" id="welcome-ok" style="flex:1">Los geht's</button>
      </div>`;
    this.openSheet();
    document.getElementById("welcome-ok")!.addEventListener("click", () => this.closeSheet());
  }

  /** Rename a marker locally. `onSave(null)` means "reset to the generated name". */
  openRename(currentName: string, hasCustom: boolean, onSave: (name: string | null) => void): void {
    this.sheetBody.innerHTML = `
      <h2>Namen vergeben</h2>
      <p>Nur für dich sichtbar, lokal auf diesem Gerät gespeichert.</p>
      <div class="linkbox">
        <input id="rename-input" maxlength="40" placeholder="z. B. Anna" value="${currentName.replace(/"/g, "&quot;")}" />
        <button class="btn btn-primary" id="rename-save">Speichern</button>
      </div>
      ${hasCustom ? `<button class="btn btn-ghost" id="rename-reset" style="margin-top:10px">Auf Zufallsnamen zurücksetzen</button>` : ""}`;
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
      <h2>Dieser Link führt nirgendwo hin</h2>
      <p>Der Raum-Schlüssel im Link fehlt oder ist unvollständig. Raum-Links werden
         automatisch erzeugt — man kann sie nicht von Hand eintippen.</p>
      <div class="linkbox" style="margin-top:16px">
        <button class="btn btn-primary" id="invalid-new" style="flex:1">Neuen Raum öffnen</button>
      </div>`;
    this.openSheet();
    document.getElementById("sheet-close")!.style.display = "none";
    document.getElementById("invalid-new")!.addEventListener("click", () => {
      location.assign("/");
    });
  }

  private openInfo(): void {
    this.sheetBody.innerHTML = `
      <h2>Wie privat ist das?</h2>
      <p>HereBee teilt Standorte <strong>flüchtig und Ende-zu-Ende-verschlüsselt</strong>
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
