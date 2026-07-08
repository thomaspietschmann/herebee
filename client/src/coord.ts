/**
 * Single-instance-per-browser coordination.
 *
 * A room may be open in several tabs of one browser, but the user must appear as
 * exactly ONE participant: one WebSocket, one geolocation watch, one presence
 * slot. We elect a single "leader" tab that owns the network + GPS; every other
 * tab is a "follower" that renders the same state (mirrored from the leader over
 * a BroadcastChannel) and posts its button intents back to the leader.
 *
 * Leadership rides on the Web Locks API: whoever holds the exclusive lock is the
 * leader, and the browser hands the lock to a waiting tab the instant the leader
 * tab dies (close / crash / reload) — no heartbeat, no hand-rolled election, no
 * split brain. A tab is a follower until (maybe) promoted once; it is never
 * demoted, so downstream code never has to tear an engine back down.
 *
 * Where Web Locks or BroadcastChannel are unavailable (old browser, some private
 * modes), every tab simply becomes its own leader — i.e. the pre-existing
 * behaviour where each tab connects independently. Correctness degrades to
 * "second tab counts twice", never to "nothing works".
 */

export interface Coordinator {
  /** Broadcast a message to the other tabs of this browser (no-op if unsupported). */
  post(msg: unknown): void;
  /** Register a handler for messages from other tabs. */
  onMessage(cb: (msg: any) => void): void;
  /** True once this tab holds leadership (owns the socket + GPS). */
  isLeader(): boolean;
}

export function createCoordinator(roomId: string, onBecomeLeader: () => void): Coordinator {
  const channelName = "herebee.room." + roomId;
  const lockName = "herebee.leader." + roomId;
  const listeners: Array<(m: any) => void> = [];
  let leader = false;

  const bc = "BroadcastChannel" in self ? new BroadcastChannel(channelName) : null;
  if (bc) {
    bc.onmessage = (ev) => {
      for (const l of listeners) l(ev.data);
    };
  }

  const promote = () => {
    if (leader) return;
    leader = true;
    onBecomeLeader();
  };

  const locks = navigator.locks;
  if (bc && locks && typeof locks.request === "function") {
    // Hold the exclusive lock for this tab's entire lifetime. The callback runs
    // only while we hold it; the returned promise never resolves, so we keep
    // leadership until the tab is gone — at which point the browser releases the
    // lock and the next waiting follower's callback fires (it becomes leader).
    locks
      .request(lockName, { mode: "exclusive" }, () => {
        promote();
        return new Promise<void>(() => {
          /* held until this tab is destroyed */
        });
      })
      .catch(() => promote()); // lock manager refused -> degrade to self-leader
  } else {
    // No coordination available: behave like a lone tab that owns everything.
    // Defer to a microtask so promotion never fires before `createCoordinator`
    // has returned and callers have finished wiring up (same timing as the
    // Web Locks path, which always resolves asynchronously).
    queueMicrotask(promote);
  }

  return {
    post: (msg) => bc?.postMessage(msg),
    onMessage: (cb) => listeners.push(cb),
    isLeader: () => leader,
  };
}