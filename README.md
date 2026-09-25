# HereBee 🐝

Ephemeral, end-to-end-encrypted live location sharing. Open the app, share the
link, and everyone who opens it sees each other move on a map as a small bee
face. Nothing is stored. A web client runs in the browser; native iOS and
Android apps keep sharing while the phone is locked.

> ⚠️ **Status: in development and testing. Do not use this for anything real yet.**
> The project, and especially the mobile apps, are unfinished. Rooms, links, the
> encryption format and the apps may change without notice. There is no support
> and no stability guarantee.

## Honest privacy statement

This is **data-minimised, non-persisted, end-to-end-encrypted** location sharing
for the peer payloads. It is deliberately private, but it is **not "anonymous"**.
That word would be a lie.

- **The server never sees your location, your name, or the key.** A 256-bit
  secret lives in the URL fragment (`#...`), which browsers never send to the
  server. From it the client derives (via HKDF) a routing room id and an
  AES-256-GCM key. Every update is encrypted on the client. The relay only
  forwards opaque ciphertext.
- **Web E2EE caveat.** This assumes the delivered client code is trustworthy. A
  malicious or compromised server could ship different JavaScript on a future
  page load. That is the normal hard limit of browser-based end-to-end
  encryption. The native apps bundle their code and do not have this caveat.
- **No database. Room state is RAM-only.** Rooms exist while someone is
  connected and vanish when the last person leaves. Nothing stores coordinates,
  names, or room history.
- **The link is the key.** Anyone with the full link can see the room for its
  lifetime. Share it deliberately. A leaked link cannot be revoked short of
  ending the room.
- **IP addresses are the honest limit.** The relay and the map server see your
  IP for the duration of the connection. The app does not log IPs, but your
  proxy, host, load balancer, or platform may keep infrastructure logs. No
  client can hide your IP from its own infrastructure without Tor or a VPN.
- **Self-hosted maps.** Tiles, fonts and sprites are served by this app. No tile
  CDN can profile which areas you pan across.

## How it works

The room secret is generated in the client and placed in the URL fragment. HKDF
derives two values from it: a room id, which is the only thing the relay learns,
and an AES-256-GCM key, which never leaves the client. Position updates are
encrypted with that key and sent as opaque blobs over a WebSocket. The relay
keeps rooms in memory only and forwards blobs to the other members of the same
room id.

The map is a self-hosted Protomaps basemap: one PMTiles archive read over HTTP
range requests, plus glyphs and sprites, all served by the same process. The web
client builds its MapLibre style in the browser. The native apps fetch the same
style, generated at build time, from `/style/{lang}.json`. The server
substitutes the real origin into it per request, so one build serves every
domain.

## Repository layout

| Path | Contents |
|---|---|
| `client/` | Web client. Vite, vanilla TypeScript, MapLibre GL JS. |
| `server/` | Node relay (`ws`) plus static hosting for the client and map assets. One process, one port. |
| `shared/` | Message schema (`messages.ts`), the cross-client contract (`PROTOCOL.md`) and the conformance vectors (`vectors.json`) used by both clients. |
| `mobile/` | Flutter app for iOS and Android. MapLibre Native, own location plugin in `mobile/packages/herebee_location/`. |
| `scripts/` | Asset fetching, style and vector generation, the interop test, a fake peer for development, the Docker entrypoint. |
| `test/` | Web-side tests: conformance vectors, a relay end-to-end test, the web peer for the interop test. |
| `docs/` | The mobile plan of record. |

It is one repository on purpose. Both clients are tested against the same
`shared/vectors.json`. A change to the web crypto or PRNG and the Dart test that
catches it land in one commit and one CI run. The interop test goes one step
further: it drives a web peer and the app's real network client through one
relay and checks that they land in the same room and decrypt each other.

## Running locally

### Web

```bash
npm install
npm run fetch-assets    # one-time: map extract, fonts, sprites
npm run dev             # client on :5173, relay on :3000
```

Open the printed URL. You are redirected to `/r/#<secret>`. Open the same full
URL, including the fragment, in a second window to see two peers.

### Map assets

`scripts/fetch-assets.sh` downloads the `pmtiles` CLI, extracts a region from
the latest Protomaps planet build into `server/assets/tiles/basemap.pmtiles`,
and clones the Protomaps fonts and sprites into `server/assets/basemaps/`.

| Variable | Default | Meaning |
|---|---|---|
| `BBOX` | `5.5,45.5,17.2,55.1` (DACH) | `minLon,minLat,maxLon,maxLat` of the extract |
| `MAXZOOM` | `14` | Maximum zoom level in the extract |
| `OUT` | `server/assets/tiles/basemap.pmtiles` | Output path |
| `PLANET` | latest build | Explicit planet URL |

A small extract is fast and enough for development:

```bash
BBOX="13.0,52.3,13.8,52.7" MAXZOOM=14 npm run fetch-assets   # Berlin only
```

Note that a small extract looks like a clipped map at the initial wide zoom.
That is the extract's bounds, not a rendering bug.

### Flutter app against a local relay

The apps need the generated style, so build first and run the relay on its
own port. The Vite dev server does not proxy `/style/`.

```bash
npm run build
PORT=3100 ALLOWED_ORIGINS="http://localhost:3100,app://herebee" npm run start
```

If `ALLOWED_ORIGINS` is set, it must include the app origin `app://herebee`, or
the relay refuses the app's WebSocket. Left unset, the relay accepts it.

```bash
cd mobile
flutter pub get
flutter run --dart-define=HEREBEE_ORIGIN=http://localhost:3100     # iOS simulator
flutter run --dart-define=HEREBEE_ORIGIN=http://10.0.2.2:3100      # Android emulator
```

Add `--dart-define=HEREBEE_SECRET=<secret>` to open a known room instead of
minting a new one. `scripts/fake-peer.ts` prints a secret and walks a position
around the room:

```bash
npx tsx scripts/fake-peer.ts --ws ws://127.0.0.1:3100/ws --seed dev-anna
```

Plain HTTP to the development machine is allowed by a debug-only network
security config on Android and by `NSAllowsLocalNetworking` on iOS. Release
builds on Android refuse cleartext.

## Tests

| Command | What it checks |
|---|---|
| `npm test` | `tsc --noEmit` plus `test/vectors.test.ts`: the web code reproduces `shared/vectors.json`. |
| `cd mobile && flutter test` | Dart unit tests: the same vectors, protocol validation, deep-link parsing, the sharing state machine, the dependency audit (no Play Services, Firebase or analytics), widgets and locales. |
| `cd mobile && flutter test integration_test/room_flow_test.dart --dart-define=HEREBEE_ORIGIN=... --dart-define=HEREBEE_SECRET=...` | On a booted simulator or device, with a relay and `fake-peer.ts` running: enters the room and asserts the peer's bee appears under the locally derived nickname. Also shares its own position where location is pre-granted. |
| `npm run test:interop` | Starts a relay with the production origin policy, then a Node web peer and the app's real `NetClient` join one room and decrypt each other. Needs a Flutter toolchain (`FLUTTER` and `DART` env override the path). |
| `npx tsx test/e2e-relay.ts` | Relay end-to-end test against a running server. |

`npm run vectors` regenerates `shared/vectors.json` from the web code. Run it
after a deliberate change and commit the result. CI (`.github/workflows/ci.yml`)
runs the web job and the Flutter job on every push and pull request, and fails
if the committed vectors are stale.

`npm run i18n:arb` exports the six UI languages from `client/src/i18n.ts` to
`mobile/lib/l10n/app_{lang}.arb`.

## Deployment

### Docker image

```bash
docker build -t herebee .
```

The image contains the built client bundle including the generated styles,
the server, `shared/` without `vectors.json`, the Node dependencies, the
Protomaps fonts and sprites, and the `pmtiles` CLI. `mobile/` is excluded by
`.dockerignore`. The container runs unprivileged as `node` on port 3000 and
answers `/healthz`.

### Tiles volume

The PMTiles archive is not in the image. Mount a persistent volume at
`/app/server/assets/tiles`. On start, the entrypoint extracts
`basemap.pmtiles` from the latest Protomaps planet build in the background when
the file is missing or when `BBOX` or `MAXZOOM` differ from the last extract.
The server starts within seconds either way. The map fills in once the extract
finishes. To refresh the basemap, delete `basemap.pmtiles` on the volume or
change `BBOX`/`MAXZOOM` and restart.

Run it as one container behind an HTTPS reverse proxy that forwards the
WebSocket upgrade.

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `3000` | Listening port |
| `ALLOWED_ORIGINS` | unset | Comma list of browser origins allowed to open the WebSocket. When set, a browser `Origin` is required. Add `app://herebee` to admit the native apps. |
| `PUBLIC_ORIGIN` | derived per request | Absolute origin written into `/style/{lang}.json`. Set it in production. |
| `TRUSTED_PROXY_HOPS` | `0` | Number of reverse proxies in front of the process. `1` behind a single proxy, so the per-IP cap uses the real client IP. |
| `BBOX` | `5.5,45.5,17.2,55.1` | Region of the tile extract |
| `MAXZOOM` | `14` | Maximum zoom of the tile extract |
| `PLANET_URL` | latest build | Explicit Protomaps planet URL for the extract |
| `APPLE_APP_IDS` | unset | Comma list of `TEAMID.bundleId` for `apple-app-site-association` |
| `ANDROID_PACKAGE` | unset | Android application id for `assetlinks.json` |
| `ANDROID_CERT_SHA256` | unset | Comma list of signing certificate SHA-256 fingerprints for `assetlinks.json` |
| `MAX_CONNS` | `10000` | Global WebSocket ceiling |
| `MAX_ROOMS` | `5000` | Maximum concurrent rooms |
| `MAX_CONNS_PER_ROOM` | `100` | Maximum members per room |

### Deep-link association files

`/.well-known/apple-app-site-association` is served only when `APPLE_APP_IDS`
is set. `/.well-known/assetlinks.json` is served only when both
`ANDROID_PACKAGE` and `ANDROID_CERT_SHA256` are set. Everything else under
`/.well-known/` returns 404 rather than the web app's HTML, so a verifier
never receives a page instead of JSON.

## Releases

### Android

Pushing a tag `android-vX.Y.Z` runs `.github/workflows/release-android.yml`. It
builds a signed release APK with Flutter 3.44.0 and JDK 21, verifies that the
APK is not debug-signed, and attaches it to a GitHub Release of the same name,
marked as a pre-release.

```bash
git tag android-v0.0.1 && git push origin android-v0.0.1
```

Signing comes from the repository secrets `SIGNING_KEYSTORE_B64`,
`SIGNING_STORE_PASSWORD`, `SIGNING_KEY_ALIAS` and `SIGNING_KEY_PASSWORD`. A
local release build reads `mobile/android/key.properties` instead, which is
gitignored. With neither present, `flutter build apk --release` falls back to
the debug key. Never ship such a build.

### iOS

Not distributed yet. The project is not enrolled in the Apple Developer
Program, so there is no TestFlight. The app registers the `herebee://` scheme
and runs on the simulator and on a paired device with a free personal team.

Universal Links are prepared but inactive: `mobile/ios/Runner/Runner.entitlements`
declares `applinks:herebee.app`, but it is not wired into code signing because a
personal team cannot sign the Associated Domains capability and every device
build would fail. Once enrolled, set `CODE_SIGN_ENTITLEMENTS` for the Runner
target (or add the capability in Xcode) and set `APPLE_APP_IDS` on the server.

See [`shared/PROTOCOL.md`](shared/PROTOCOL.md) for the cross-client contract
and [`docs/mobile-plan.md`](docs/mobile-plan.md) for the mobile plan and its
review history.
