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

- **The server never sees your location, your name, your messages, or the key.** A 256-bit
  secret lives in the URL fragment (`#...`), which browsers never send to the
  server. From it the client derives (via HKDF) a routing room id and an
  AES-256-GCM key. Every update is encrypted on the client. The relay only
  forwards opaque ciphertext.
- **Web E2EE caveat.** This assumes the delivered client code is trustworthy. A
  malicious or compromised server could ship different JavaScript on a future
  page load. That is the normal hard limit of browser-based end-to-end
  encryption. The native apps bundle their code and do not have this caveat.
- **No database. Room state is RAM-only.** Rooms exist while someone is
  connected and vanish when the last person leaves. The server stores no
  coordinates, names, messages, or room history. A message your bee says lives
  for ten minutes in the other participants' memory and nowhere else. The native apps keep the last five
  rooms, including their keys, for three days in the device's secure storage
  (Keychain or Keystore) so you can re-enter them. On launch the app asks which
  room to open; it never re-enters one on its own. Each entry can be deleted at
  any time.
- **The link is the key.** Anyone with the full link can see the room for its
  lifetime. Share it deliberately. A leaked link cannot be revoked short of
  ending the room.
- **IP addresses are the honest limit.** The relay and the map server see your
  IP for the duration of the connection. The app does not log IPs, but your
  proxy, host, load balancer, or platform may keep infrastructure logs. No
  client can hide your IP from its own infrastructure without Tor or a VPN.
- **Other servers are warned about.** The apps can use any server that runs
  HereBee, but only `herebee.app` is covered by this statement. Choosing
  another one, or opening a link that names one, shows a warning first.
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

Settings → Kartenstil offers four styles: automatic (follows the system),
light, dark and Synthwave. Dark and Synthwave are served from
`/style/dark/{lang}.json` and `/style/synthwave/{lang}.json`; the palettes live in
`shared/map-theme.ts`. Synthwave also restyles the whole chrome in neon green
and hot pink with monospace labels and a faint floor grid, on the web
(`:root[data-map-theme="synthwave"]` in `client/src/style.css`) and in the apps
(`HereBeeTokens.synthwave` in `mobile/lib/ui/tokens.dart`).

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
| `BBOX` | `-180,-85,180,85` (whole world) | `minLon,minLat,maxLon,maxLat` of the extract |
| `MAXZOOM` | `12` | Maximum zoom level in the extract |
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

### Other servers

Anyone can run HereBee. The official server is `https://herebee.app`
(`OFFICIAL_ORIGIN` in `shared/server.ts`, `AppConfig.officialOrigin` in the
app). The apps can use any other server that runs this web app:

- **Settings → Server.** The address is checked against `/healthz` first. A
  server other than the official one needs a confirmed warning, and it applies
  to new rooms. Rooms already remembered keep their server.
- **Room links name their server.** `https://other.example/r/#<secret>` (pasted)
  or `herebee://r?server=https%3A%2F%2Fother.example#<secret>` open the room on
  that server, again only after the warning. On iOS the web page on another server
  builds that `herebee://` link for its "open in the app" button.
- Every room on such a server repeats the warning in its entry gate. The web
  app shows the same warning in its entry gate and settings whenever it is not
  served from the official host, which includes `localhost` during development.

For the apps to work against your server, it must be HTTPS (release builds
refuse cleartext) and, if `ALLOWED_ORIGINS` is set, it must include
`app://herebee`. See [Running your own server](#running-your-own-server) for
setting one up with your own map.

The payloads stay end-to-end encrypted on any server. The warning exists
because the operator sees IPs, room timing and, through the tiles, roughly which
area people look at. In a browser it also serves the code that handles the key.

### House numbers

The Protomaps basemap carries house numbers only from zoom 15, and the extract
stops at 12 or 14. House numbers therefore come from a separate, much smaller
archive, `server/assets/tiles/addresses.pmtiles` (Europe, North, Central and
South America: about 1.8 GB), shown from zoom 15 on top of the basemap. Without
it the map works as before, only without house numbers.

It is built from OpenStreetMap with Planetiler, osmium and Geofabrik country
extracts by `scripts/addresses/build.sh`, which filters each country to objects
with `addr:housenumber`, merges them (dropping the duplicates where extracts
overlap at borders) and builds one PMTiles layer `addresses` at zoom 14:

```bash
SNAPSHOT=260929 WORK=/some/scratch/dir scripts/addresses/build.sh
```

`REGIONS` selects the Geofabrik regions (default
`europe north-america north-america/us central-america south-america`).

`.github/workflows/addresses.yml` runs this every two months (and on demand),
publishes the result as a GitHub release asset (`addresses-YYYYMMDD`) under the
ODbL, like the OSM data it comes from, and opens a PR that pins the new URL and
checksum. In production the container
entrypoint downloads it into the tiles volume and checks its SHA-256; the pinned
URL and checksum live in `scripts/entrypoint.sh` and can be overridden with
`ADDRESSES_URL` / `ADDRESSES_SHA256` (an empty `ADDRESSES_URL` disables it). For
local development, `ADDRESSES=1 npm run fetch-assets` fetches the same file.

## Tests

| Command | What it checks |
|---|---|
| `npm test` | `tsc --noEmit`, `test/vectors.test.ts` (the web code reproduces `shared/vectors.json`) and `test/crash.test.ts` (validation, limits and mail of `/api/crash`). |
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
The server starts within seconds either way. When `BBOX`/`MAXZOOM` changed, the
old file is deleted first (a different region/zoom can be a very different
size, and the volume may not fit both at once) — so the basemap is briefly
missing until the new extract lands. To refresh the basemap, delete
`basemap.pmtiles` on the volume or change `BBOX`/`MAXZOOM` and restart.

Run it as one container behind an HTTPS reverse proxy that forwards the
WebSocket upgrade.

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `3000` | Listening port |
| `ALLOWED_ORIGINS` | unset | Comma list of browser origins allowed to open the WebSocket. When set, a browser `Origin` is required. Add `app://herebee` to admit the native apps. |
| `PUBLIC_ORIGIN` | derived per request | Absolute origin written into `/style/{lang}.json`. Set it in production. |
| `TRUSTED_PROXY_HOPS` | `0` | Number of reverse proxies in front of the process. `1` behind a single proxy, so the per-IP cap uses the real client IP. |
| `BBOX` | `-180,-85,180,85` | Region of the tile extract |
| `MAXZOOM` | `12` | Maximum zoom of the tile extract |
| `PLANET_URL` | latest build | Explicit Protomaps planet URL for the extract |
| `ADDRESSES_URL` | pinned release | House-number archive to download. Empty disables house numbers. |
| `ADDRESSES_SHA256` | pinned checksum | SHA-256 the download must match |
| `ASSETS_DIR` | `/app/server/assets` | Root of `tiles/`, `basemaps/fonts/` and `basemaps/sprites/` |
| `APPLE_APP_IDS` | unset | Comma list of `TEAMID.bundleId` for `apple-app-site-association` |
| `ANDROID_PACKAGE` | unset | Android application id for `assetlinks.json` |
| `ANDROID_CERT_SHA256` | unset | Comma list of signing certificate SHA-256 fingerprints for `assetlinks.json` |
| `MAX_CONNS` | `10000` | Global WebSocket ceiling |
| `MAX_ROOMS` | `5000` | Maximum concurrent rooms |
| `MAX_CONNS_PER_ROOM` | `100` | Maximum members per room |
| `SMTP_URL` | unset | SMTP connection URL for crash-report mail, e.g. `smtps://user:pass@mail.example.org:465` (percent-encode `@` in the user). Unset: `POST /api/crash` answers 503. |
| `CRASH_MAIL_TO` | `thomas@pietschie.de` | Recipient of crash reports. Self-hosters set their own. |
| `CRASH_MAIL_FROM` | SMTP user | Sender address, e.g. `HereBee <crash@example.org>`. Defaults to the SMTP user if that is an address, else `CRASH_MAIL_TO`. |
| `CRASH_MAX_PER_HOUR` | `30` | Global cap on crash mails per hour; on top of 5 reports per IP per hour. |

### Crash reports

The Android app uses [ACRA](https://github.com/ACRA/acra) with its consent
dialog only. After a crash the next screen asks whether to send a report; it
names the server, lists what is included and offers an optional comment.
Nothing leaves the phone unless the user taps Send, and a declined report is
deleted on the next start. An accepted report goes as JSON to `POST /api/crash`
on the HereBee server the app is using (default `https://herebee.app`), never
to a third party. It contains the app version, package name, Android version,
device brand and model, the stack trace and its hash, the crash time and the
comment. No logcat, device or installation ids, settings, preferences,
locations, names or room data; room-link fragments and coordinate-like numbers
are redacted before sending.

The server validates the report, emails it as plain text to `CRASH_MAIL_TO`
and forgets it. Neither the report nor the sender's IP is logged or stored.
Set `SMTP_URL` to enable it; without it the endpoint answers 503 and the app
keeps the accepted report to retry later.

**Dart errors (iOS and Android).** An uncaught Dart error does not kill the app,
so ACRA never sees it. `mobile/lib/core/crash_reporter.dart` catches it
(`FlutterError.onError`, `PlatformDispatcher.onError`) and asks in the same
words, at most once per app session. On Send it posts to the same endpoint
with `source: "dart"`: app version, OS version, the error and its trace, the
crash time and the comment, redacted by the same rules. Nothing is stored on
the device; a declined or unanswered report is gone. Release builds ask; debug
builds only with `--dart-define=HEREBEE_CRASH_REPORTS=true`.
`--dart-define=HEREBEE_CRASH_SELFTEST=true` throws one test error four seconds
after launch to try the flow end to end; `adb shell am crash app.herebee` does
the same for ACRA.

Both send to the server in effect: the one chosen in the settings, else the
built-in default. The app mirrors it under `herebee.reportOrigin` so the
native sender reads the same one. Native C/C++ crashes (Flutter engine,
MapLibre) and native iOS crashes are not covered.

### Deep-link association files

`/.well-known/apple-app-site-association` is served only when `APPLE_APP_IDS`
is set. `/.well-known/assetlinks.json` is served only when both
`ANDROID_PACKAGE` and `ANDROID_CERT_SHA256` are set. Everything else under
`/.well-known/` returns 404 rather than the web app's HTML, so a verifier
never receives a page instead of JSON.

## Running your own server

A complete HereBee server is the Docker image plus one volume for the map
archives. No database, no other service. A minimal run:

```bash
docker build -t herebee .
docker volume create herebee-tiles
docker run -d --name herebee -p 3000:3000 \
  -v herebee-tiles:/app/server/assets/tiles \
  -e PUBLIC_ORIGIN=https://map.example.org \
  -e ALLOWED_ORIGINS=https://map.example.org,app://herebee \
  -e TRUSTED_PROXY_HOPS=1 \
  -e BBOX=5.5,45.5,17.2,55.1 -e MAXZOOM=14 \
  herebee
```

Put an HTTPS reverse proxy in front of it (Caddy, nginx, Traefik). It must
forward the WebSocket upgrade on `/ws` and pass `Range` and `If-Range` through
unchanged; MapLibre reads the archives in byte ranges and breaks on a proxy
that strips them or recompresses `.pmtiles`. `TRUSTED_PROXY_HOPS` is the number
of proxies in front of the container, so the per-IP limits see the real client.
`/healthz` answers as soon as the process is up, before any map is there.

The apps can then use it via Settings → Server (see [Other servers](#other-servers)).
It must be reachable over HTTPS with a valid certificate.

### Choosing the map

The style expects an archive in the Protomaps basemap schema (the layers that
`@protomaps/basemaps` v5 styles). There are three ways to get one onto the
volume:

1. **Automatic extract (default).** On start the entrypoint cuts
   `basemap.pmtiles` out of the latest Protomaps planet build with
   `pmtiles extract`, in the background. Only the tiles inside `BBOX` up to
   `MAXZOOM` are downloaded, never the whole planet. Plan the volume for the
   extract plus its temporary copy (`basemap.pmtiles.tmp`).

   | Extract | Size |
   |---|---|
   | World, zoom 6 | 45 MB |
   | World, zoom 8 | 557 MB |
   | World, zoom 10 | 3.8 GB |
   | World, zoom 11 | 8 GB |
   | World, zoom 12 (default) | 18 GB |
   | World, zoom 13 | 36 GB |
   | World, zoom 14 | 68 GB |
   | World, zoom 15 (full planet) | 138 GB |
   | Europe (`-25,34,45,72`), zoom 14 | 25 GB |
   | Germany (`5.87,47.27,15.04,55.06`), zoom 14 | 3.4 GB |

   Measured on the build of 2026-10-02 with `pmtiles extract … --dry-run`, in
   decimal GB. From zoom 12 on, each level roughly doubles the size. To size
   your own region, run the same dry run; it reads only the archive's
   directories, not the tiles:

   ```bash
   pmtiles extract https://build.protomaps.com/20261002.pmtiles /tmp/x.pmtiles \
     --bbox=5.87,47.27,15.04,55.06 --maxzoom=14 --dry-run
   ```
2. **A pinned or mirrored planet.** `PLANET_URL` points the extract at a
   specific Protomaps build or at your own copy of one. Any HTTPS URL that
   supports range requests works, including object storage. Use this when the
   map must not change between restarts.
3. **Your own archive.** Copy a finished `basemap.pmtiles` onto the volume, for
   example a full build from [maps.protomaps.com/builds](https://maps.protomaps.com/builds/)
   or one you built yourself with the Planetiler profile in
   [protomaps/basemaps](https://github.com/protomaps/basemaps) (`tiles/`). Then write
   `.params` next to it with the same `BBOX@MAXZOOM` the container runs with,
   otherwise the entrypoint treats the file as stale and replaces it:

   ```bash
   printf '%s' '5.5,45.5,17.2,55.1@14' > /path/to/volume/.params
   ```

The entrypoint re-extracts only when `basemap.pmtiles` is missing or
`BBOX`/`MAXZOOM` changed. It deletes the old file first, so the map is gone
until the new extract finishes. The style URL carries a version token derived
from the file's size and mtime, so clients drop cached tiles of a replaced
archive on their own.

### House numbers on your server

By default the entrypoint downloads the pinned Europe-and-Americas archive from
this repository's releases. Alternatives:

- `ADDRESSES_URL=` (empty) disables house numbers.
- Build your own region with `REGIONS="asia" SNAPSHOT=... WORK=... scripts/addresses/build.sh`,
  host the result anywhere over HTTPS and set `ADDRESSES_URL` and
  `ADDRESSES_SHA256` to it. A mismatched checksum keeps the previous file.
- Or put an `addresses.pmtiles` on the volume yourself and set
  `ADDRESSES_URL=` so the entrypoint leaves it alone.

### Fonts and sprites

Glyphs and sprites are baked into the image from a pinned commit of
[protomaps/basemaps-assets](https://github.com/protomaps/basemaps-assets)
(`BASEMAPS_ASSETS_COMMIT` build argument) and served from `/basemaps/`. Nothing
on the volume is needed for them.

### What else to set

- `PUBLIC_ORIGIN` to your HTTPS origin, so the app styles point at the right host.
- `ALLOWED_ORIGINS` with your web origin and `app://herebee`, or leave it unset.
- `SMTP_URL` and **`CRASH_MAIL_TO`** if you want crash reports. The default
  recipient is the HereBee maintainer; without `SMTP_URL` nothing is sent.
- `APPLE_APP_IDS` / `ANDROID_PACKAGE` / `ANDROID_CERT_SHA256` only if you ship
  your own app build that claims your domain. The official apps claim links
  for `herebee.app` only, so a link to your server opens in the browser. On
  iOS its entry gate offers "open in the app" (a `herebee://r?server=…` link);
  on Android the link can be pasted into the app.

### Licences and attribution

The map data is © OpenStreetMap contributors under the ODbL, the basemap build
is from Protomaps. The attribution is part of the style and must stay visible.
If you build and publish your own archives, they are ODbL derivatives too.

## Releases

### Android

Pushing a tag `android-vX.Y.Z` runs `.github/workflows/release-android.yml`. It
builds a signed release APK with Flutter 3.47.5 and JDK 21, verifies that the
APK is not debug-signed, and attaches it to a GitHub Release of the same name.
It is deliberately not marked as a pre-release, because updaters such as
Obtainium skip pre-releases by default.

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
