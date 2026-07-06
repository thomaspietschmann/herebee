/**
 * WebSocket client with auto-reconnect. Encrypts every outbound update and
 * decrypts inbound peer blobs. The socket carries only opaque ciphertext plus
 * the routing roomId; the AES key stays in this process.
 */
import { decryptJson, encryptJson, type RoomKeys } from "./crypto.js";
import type { ServerMessage } from "../../shared/messages.js";
import type { PeerUpdate } from "./types.js";

export interface NetHandlers {
  onPeer: (id: string, update: PeerUpdate) => void;
  onLeft: (id: string) => void;
  onRequest: () => void; // a peer joined; re-broadcast our latest state
  onStatus: (connected: boolean) => void;
  onPresence: (n: number) => void; // room occupancy (count only, no identity)
  onFatal: (reason: string) => void;
}

export class NetClient {
  private ws: WebSocket | null = null;
  private backoff = 500;
  private closed = false;
  private lastResync = 0;
  private lastSent: string | null = null; // for latest-state re-broadcast on request

  constructor(private readonly keys: RoomKeys, private readonly h: NetHandlers) {}

  connect(): void {
    // Always start from a clean slate. A previous socket may be dead-but-OPEN
    // (mobile standby zombie) or wedged in CONNECTING (network handover on wake);
    // tearing it down first means a reconnect attempt never stacks a second socket
    // on top of a live one, nor gets blocked waiting on a hung one.
    this.teardown();
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const ws = new WebSocket(`${proto}://${location.host}/ws`);
    this.ws = ws;

    ws.onopen = () => {
      this.backoff = 500;
      ws.send(JSON.stringify({ t: "join", roomId: this.keys.roomId }));
      this.h.onStatus(true);
      if (this.lastSent) ws.send(this.lastSent); // resume visibility after reconnect
    };

    ws.onmessage = async (ev) => {
      let msg: ServerMessage;
      try {
        msg = JSON.parse(ev.data as string);
      } catch {
        return;
      }
      if (msg.t === "peer") {
        const update = await decryptJson<PeerUpdate>(this.keys.key, msg.data);
        if (update) this.h.onPeer(msg.id, update);
      } else if (msg.t === "left") {
        this.h.onLeft(msg.id);
      } else if (msg.t === "request") {
        this.h.onRequest();
      } else if (msg.t === "presence") {
        this.h.onPresence(msg.n);
      } else if (msg.t === "error") {
        this.closed = true;
        this.h.onFatal(msg.reason);
      }
    };

    ws.onclose = () => {
      this.h.onStatus(false);
      if (!this.closed) this.scheduleReconnect();
    };
    ws.onerror = () => ws.close();
  }

  /** Detach and close the current socket without triggering its handlers. */
  private teardown(): void {
    const ws = this.ws;
    if (!ws) return;
    ws.onopen = null;
    ws.onmessage = null;
    ws.onerror = null;
    ws.onclose = null;
    try {
      ws.close();
    } catch {
      /* ignore */
    }
    this.ws = null;
  }

  private scheduleReconnect(): void {
    const delay = Math.min(this.backoff, 15_000);
    this.backoff = Math.min(this.backoff * 2, 15_000);
    setTimeout(() => {
      if (!this.closed) this.connect();
    }, delay);
  }

  /**
   * Force a fresh connection. Call this when the page returns to the foreground:
   * standby/tab-switch often leaves a "zombie" socket that still reports OPEN but
   * carries nothing, so we can't rely on onclose. Reconnecting makes the server
   * re-request peer broadcasts (so we see them) and re-sends our last position
   * (so they see us).
   */
  resync(): void {
    if (this.closed) return;
    const now = Date.now();
    if (now - this.lastResync < 2000) return; // debounce rapid focus/blur
    this.lastResync = now;
    this.backoff = 500;
    this.connect(); // connect() tears down any existing socket first
  }

  async broadcast(update: PeerUpdate): Promise<void> {
    const data = await encryptJson(this.keys.key, update);
    const frame = JSON.stringify({ t: "relay", data });
    // lastSent is replayed on every reconnect (see onopen). Keep it only while we are
    // actively sharing a position; a "stop" must clear it, or a later reconnect would
    // resurrect our old position and make us reappear to peers after we stopped.
    if (update.k === "loc") this.lastSent = frame;
    else if (update.k === "stop") this.lastSent = null;
    if (this.ws && this.ws.readyState === WebSocket.OPEN) this.ws.send(frame);
  }

  close(): void {
    this.closed = true;
    this.ws?.close();
  }
}
