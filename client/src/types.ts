/**
 * Plaintext shapes that live INSIDE the end-to-end-encrypted payload.
 * The relay never sees these — only the ciphertext.
 */

/** A peer broadcasts its identity seed + position, or announces it stopped. */
export type PeerUpdate =
  | {
      k: "loc";
      seed: string; // drives name, avatar and colour on every client
      lat: number;
      lng: number;
      acc: number | null; // accuracy in metres
      hdg: number | null; // heading in degrees, if moving
      spd: number | null; // speed in m/s, if moving — gates whether hdg is shown
      at: number; // client timestamp (ms) of this fix
    }
  | { k: "stop"; seed: string };

export interface Position {
  lat: number;
  lng: number;
  acc: number | null;
  hdg: number | null;
  spd: number | null;
}
