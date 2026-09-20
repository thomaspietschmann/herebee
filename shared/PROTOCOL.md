# HereBee wire protocol

The contract every client must implement identically: the web app
(`client/src/*`) and the native Android / iOS apps (`mobile/`).

Two properties make the details unusually unforgiving:

1. **The roomId is derived, not assigned.** Get the derivation wrong by one byte
   and the client joins a *different, valid, empty* room. Nothing errors; the
   user simply never sees anyone. There is no server-side check that can catch it.
2. **Identity is derived, not transmitted.** Names, colours and bee avatars come
   from a seeded PRNG run independently on every device. Get the PRNG wrong and
   the same person appears as a different bee on every phone.

`shared/vectors.json` pins both. Regenerate with `npm run vectors`, verify with
`npm run test:vectors`; the Dart port tests against the same file.

---

## 1. The secret and the room

The room secret is **32 random bytes**, encoded **base64url without padding**
(43 chars). It lives in the URL fragment (`https://herebee.app/r/#<secret>`),
which browsers never send to a server. **The secret is the capability**: anyone
holding it can read the room, and it is the only thing that grants access.

From the secret, HKDF-SHA256 derives two independent values:

| | |
|---|---|
| Salt | UTF-8 bytes of `localizer/v1` (both derivations) |
| Info `room-id` | 128 bits → the room id material |
| Info `aes-key` | 256 bits → the AES-256-GCM key |

The **roomId** is `base64url(idMaterial ‖ SHA-256(idMaterial)[0..8])` — 24 bytes,
32 chars. The trailing 8 bytes are a checksum, which is what makes ids
self-certifying: the server verifies them statelessly (`server/src/roomId.ts`),
so nobody can hand-pick or guess a valid id (forgery chance 2⁻⁶⁴) and vanity
codes are impossible. **The roomId is the only derived value that leaves the
device.** The AES key never does.

Reference: `client/src/crypto.ts` (`deriveRoomKeys`).

## 2. Payload encryption

Every update is encrypted with **AES-256-GCM** under a **fresh random 96-bit IV**.
The transmitted blob is:

```
base64url( iv[12] ‖ ciphertext ‖ tag[16] )
```

Note the layout: WebCrypto appends the 16-byte authentication tag to the
ciphertext, so implementations that keep the tag separate (Dart's
`package:cryptography` exposes `nonce` / `cipherText` / `mac`) must concatenate
in exactly this order. Decryption failure — wrong key, tampering, garbage — is
**not** an error condition; the frame is silently dropped.

## 3. Plaintext inside the envelope

The server never sees these shapes. Reference: `client/src/types.ts`.

```jsonc
{ "k": "loc", "seed": "<string>", "lat": 52.52, "lng": 13.405,
  "acc": 12.5,   // accuracy in metres, or null
  "hdg": 180,    // heading in degrees, or null
  "spd": 1.4,    // speed in m/s, or null — gates whether hdg is shown
  "at": 1700000000000 }   // client clock, ms

{ "k": "stop", "seed": "<string>" }
```

### Inbound validation is mandatory

Every room member holds the same key, so a *malicious member* can put arbitrary
plaintext inside a perfectly valid ciphertext. Validate before anything reaches
the map (`validPeerUpdate` in `client/src/net.ts`):

- `seed`: string, length 1…128.
- `k`: exactly `"loc"` or `"stop"`; anything else → drop.
- `lat` ∈ [−90, 90], `lng` ∈ [−180, 180], both finite.
- `acc`, `hdg`, `spd`: finite number or `null`.
- `at`: finite number.

Anything malformed is dropped silently.

## 4. WebSocket frames

Endpoint `/ws`, JSON text frames, max 16 KiB per frame.

**Client → server** (`shared/messages.ts`):

| Frame | Notes |
|---|---|
| `{t:"join", roomId, cid?}` | First frame. A second join on the same socket is ignored. |
| `{t:"relay", data}` | `data` = the base64url blob from §2, max 8192 chars. |
| `{t:"ping"}` | Liveness probe. |

**Server → client**:

| Frame | Meaning |
|---|---|
| `{t:"hello", selfId}` | Joined. `selfId` is ephemeral, per-socket. |
| `{t:"peer", id, data}` | Opaque blob from another member. `id` is their socket id. |
| `{t:"request"}` | Somebody joined — re-broadcast your latest position. |
| `{t:"left", id}` | That socket dropped. Mark the peer offline; do **not** remove it. |
| `{t:"presence", n}` | Room occupancy. A bare count, never an identity. |
| `{t:"pong"}` | Reply to `ping`. |
| `{t:"error", reason}` | Fatal: `invalid-room`, `capacity`, `room-full`. Socket closes. |

The server rate-limits to 10 frames/s (burst 10) and silently drops the excess.

### `cid` — the reconnect token

An ephemeral per-client token (web: per browser tab, in `sessionStorage`; native:
per install). On join, the relay **closes any other socket in the room carrying
the same `cid`**. That is what stops a standby/reload zombie socket from
double-counting occupancy and replaying a stale cached position. It must be
stable across reconnects of one client and different between genuinely separate
clients. It is **never an identity** and must not be derived from the seed or
from anything device-specific.

### Last-blob replay

The relay keeps each socket's most recent ciphertext in RAM and replays it to a
newcomer immediately, so a peer whose phone is asleep still appears. Consequence
for clients: **ignore inbound updates whose `seed` equals your own** — you will
otherwise be fed your own stale position by a lingering previous socket.

## 5. Timings

Ported from `client/src/net.ts` and `client/src/main.ts`. Same numbers everywhere,
or peers time each other out inconsistently.

| | |
|---|---|
| Outbound position throttle | 1000 ms (own marker still renders every fix) |
| Stationary re-send heartbeat | 10 s while sharing |
| Client ping | 15 s |
| Link considered dead | 35 s with no inbound frame of any kind |
| Watchdog tick | 5 s |
| Reconnect backoff | 500 ms, doubling, capped at 15 s |
| Resync debounce | 2 s |
| Marker fresh → stale | 15 s |
| Marker stale → ghost | 120 s |
| Ghost removed | 20 min after its last fix |
| Heading arrow shown | only when `spd` ≥ 1.5 m/s |

A peer is removed **only** on an explicit `stop`. A lost signal leaves a ghost at
the last known position.

## 6. Identity derivation

All of this is local and deterministic; nothing about it is transmitted except
the `seed` string itself.

- `seed`: a random token, stable per install (web: per browser, `localStorage`).
  Never an account, never a device identifier.
- **cyrb53** (`client/src/rng.ts`) hashes the seed; **mulberry32** turns that into
  a float stream. Both are 32-bit-arithmetic algorithms: a port must emulate
  JavaScript's `Math.imul` and `>>>` exactly (mask to 32 bits after every
  multiply), or every derived value diverges.
- **Name**: `germanName` / `englishName` from `rngFromSeed(seed + ":name")`.
  Which set is used follows the *device* locale, not the peer's — so the same
  person may legitimately show a German name on one phone and an English one on
  another. That is intended; keep the behaviour.
- **Avatar**: `creatureSvg(seed, hue)` assembles an SVG from
  `mulberry32(cyrb53(seed, 0x1234))`. The order of `pick()` calls *is* the format.
- **Colour**: assigned by **first-seen order** from the hardcoded `HUE_PALETTE`
  (`hueFromIndex`), not from the seed — so people present at the same time stay
  visually distinct. Each device assigns independently, so two devices may colour
  the same person differently. Also intended.

## 7. What the server learns

Exhaustive, by design:

- the roomId (an opaque routing handle),
- opaque ciphertext and its size,
- connection timing and the client IP for the duration of the connection
  (used only for a per-IP connection cap; never logged or stored),
- room occupancy counts.

Not: coordinates, names, the key, any history. There is no database; rooms exist
only while somebody is connected.

## 8. Native client specifics

- **Origin.** Native clients send `Origin: app://herebee` on the upgrade, or, if
  the platform forbids setting it, `X-HereBee-Client: <platform>/<version>` with
  no Origin. The operator opts in by listing `app://herebee` in `ALLOWED_ORIGINS`.
  This check is browser CSRF hygiene, not authentication (see `originAllowed` in
  `server/src/index.ts`).
- **Map style.** `GET /style/{lang}.json` for `de|en|es|it|fr|pt`, generated by
  `scripts/gen-style.ts`. The server substitutes the real origin per request, so
  the URLs in the response are absolute and ready to use.
- **Deep links.** `https://herebee.app/r/#<secret>` (Universal Links / App Links,
  association documents under `/.well-known/`) and the fallback scheme
  `herebee://r#<secret>`. The secret is in the **fragment**, so read `uri.fragment`.
