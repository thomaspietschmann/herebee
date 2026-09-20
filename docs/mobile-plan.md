# HereBee mobile: native Android + iOS apps

Plan of record. Approved 2026-09-18. Phases 0, 1 and 2 are implemented; phases 3
and 4 are not started. The protocol contract the apps must satisfy lives in
[`shared/PROTOCOL.md`](../shared/PROTOCOL.md).

**Repository layout: one repo, not two.** The app lives in `mobile/` alongside
the server and the web client. The conformance vectors are the reason: a change
to `client/src/rng.ts` and the Dart test that catches it belong in one commit and
one test run. Split repos would turn that into a publish-and-sync step, and drift
could land in one repo and surface days later in the other. The generated ARB
files and the map style cross the same boundary. The one real objection is that a
push to `main` auto-deploys production, and a redeploy restarts the container and
drops every live room; a mobile-only commit must not do that. Coolify's
`watch_paths` (currently unset on the app) fixes it — see §11.

## 1. Why

The web app cannot keep sharing a location when the phone locks. That is the one
thing a native app buys, and it is the reason for this work. Everything else —
same rooms, same map, same privacy posture — is a constraint, not a goal.

Production today: `https://herebee.app` on the owner's own Coolify instance
(Traefik + Let's Encrypt, `TRUSTED_PROXY_HOPS=1`, auto-deploy on push to `main`).
The basemap is a Europe PMTiles extract (`BBOX=-11,34,40,71`, `MAXZOOM=14`,
~22 GB) on a persistent volume, never in the image. The apps read that same
archive over HTTP range requests, so its size is irrelevant to the client and the
map stays free of any third-party tile service.

## 2. Decision

**Flutter, one codebase, MapLibre Native for rendering, and a hand-written
platform channel for location** instead of an off-the-shelf location plugin.

- **Flutter over SwiftUI + Compose.** About 1.5k lines of the client are portable
  logic (crypto, protocol, identity, marker state). Porting once beats porting
  twice for a single-screen, full-screen-map app. Native binaries, no WebView.
  The toolchain is installed and verified on the dev Mac (Flutter 3.44,
  Android SDK 36 + Pixel_9 AVD, Xcode 26.6, CocoaPods, a paired iPhone).
- **Own location channel over `geolocator`.** `geolocator_android` pulls in
  `com.google.android.gms:play-services-location`. Zero Google libraries keeps
  the app working on de-Googled phones and makes the privacy claim checkable.
  Cost is roughly 250 lines of Kotlin and Swift.
- **Not Capacitor.** A WebView is exactly what the OS suspends in the background.
- **PMTiles** is supported natively by MapLibre Native (Android 11.8+,
  iOS 6.10+), so the existing basemap, glyphs and sprites are reused as-is.

Fallback if the map or background behaviour blocks: two native codebases
(SwiftUI + CryptoKit; Kotlin + Compose + `javax.crypto`). Phase 0 and the
conformance vectors are identical either way, which is why they came first.

## 3. Privacy contract

Binding for every phase. The app must be at least as data-minimal as the web app.

| Concern | Rule |
|---|---|
| Third-party SDKs | None. No Firebase, Sentry, analytics, ads, remote config. Enforced by a Phase 1 test: no `com.google.android.gms` / `com.google.firebase` in `./gradlew :app:dependencies`; `Podfile.lock` limited to Flutter, the map SDK and first-party plugin pods. |
| Network | `herebee.app` only, for everything: relay, style, glyphs, sprites, tiles. Android `network_security_config` forbids cleartext; iOS keeps ATS defaults. |
| Push | None. Android shows a local ongoing notification only because a foreground service requires one. |
| Location source | Android: framework `LocationManager`, not Fused Location Provider. iOS: CoreLocation, which is unavoidable and is disclosed as such. |
| Storage | Identity seed, custom names, per-room "was sharing" flag. Nothing else. No logs, no location history. MapLibre ambient tile cache capped at 50 MB. |
| Identity | Random seed per install. Never an account, never a device identifier. |
| Deep-link verification | Apple's CDN and Google's verifier fetch the `/.well-known/` documents. They learn that this domain has an app; no user data is involved. |
| Apple privacy manifest | `PrivacyInfo.xcprivacy` with `NSPrivacyTracking=false`, no tracking domains, `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`. Nutrition label: Location, not linked to the user, App Functionality. |
| Play Data safety | Location collected, transient, encrypted in transit, not shared. Foreground-service location type declared. |
| Build | No `--obfuscate`; it works against verifiability. Publish SHA-256 of release artifacts. |
| Disclosure | The app's Datenschutz text differs from the web's: bundled code removes the "a compromised server could ship different JS" caveat, and the OS location services are named. Rewrite it, do not copy it. |

## 4. Decisions taken by the owner

1. Application id / bundle id: **`app.herebee`**.
2. Apple Developer Program: **not yet enrolled.** Until then, deep links are
   tested via the `herebee://` scheme. Associated Domains, the `APPLE_APP_IDS`
   env and TestFlight move to the start of Phase 4. Device debugging works with a
   free personal team in Xcode.
3. Android distribution: **Play Store plus a directly downloadable signed APK**
   on `https://herebee.app/download`, with its SHA-256 published.

## 5. Phase 0 — server and shared groundwork (done)

Implemented in this repo; deploys through the normal push to `main`.

| Added | Purpose |
|---|---|
| `scripts/gen-vectors.ts` → `shared/vectors.json` | Conformance vectors generated from the real client code: room derivation, raw AES key, ciphertexts to decrypt, invalid room ids, PRNG streams, names, avatar hashes. `npm run vectors`. |
| `test/vectors.test.ts` | 254 assertions that the web code still reproduces the committed vectors. Exits non-zero on drift. `npm run test:vectors`. |
| `scripts/gen-style.ts` → `client/dist/style/{lang}.json` | The MapLibre style the apps load, one per UI language. Runs from `npm run build`. |
| `/style/{lang}.json` in `server/src/index.ts` | Serves those files, substituting the real origin per request, so one build serves dev and production. |
| `/.well-known/…` in `server/src/index.ts` | Generated `apple-app-site-association` and `assetlinks.json` from env. The whole namespace 404s rather than falling through to the SPA, because a verifier that receives HTML fails opaquely. |
| `originAllowed` change | Accepts `app://herebee`, or `X-HereBee-Client` when the platform forbids setting Origin. Opt-in per deployment via `ALLOWED_ORIGINS`. |
| `scripts/i18n-to-arb.ts` → `mobile/lib/l10n/app_{lang}.arb` | Exports all six languages from `client/src/i18n.ts`, the single source of truth. `npm run i18n:arb`. |
| `shared/PROTOCOL.md` | The cross-client contract. |

Small source changes that enable the above: `germanName` / `englishName` and
`DICTS` are now exported; `tsconfig.json` also typechecks `scripts/` and `test/`.

**Not exported:** the Impressum / Datenschutz sheet in `client/src/ui.ts`. It is
German-only inline HTML with unfilled placeholders, and the app's disclosure
genuinely differs, so Phase 2 rewrites it rather than copying it.

**Production env to set in Coolify before the apps ship:**

```
ALLOWED_ORIGINS=https://herebee.app,app://herebee
PUBLIC_ORIGIN=https://herebee.app
ANDROID_PACKAGE=app.herebee
ANDROID_CERT_SHA256=<upload key>,<Play App Signing key>
APPLE_APP_IDS=<TEAMID>.app.herebee     # after Developer Program enrollment
```

All are runtime values; none requires a rebuild.

## 6. Phase 1 — Flutter skeleton and core port (done)

Project at `mobile/`, application id and bundle id `app.herebee`, Android
`minSdk 26` / `targetSdk 36` / `compileSdk 36` (pinned, not inherited), iOS
deployment target 16.0.

| Ported to `mobile/lib/core/` | From | Notes |
|---|---|---|
| `rng.dart` | `client/src/rng.ts` | cyrb53 + mulberry32, bit-exact. JavaScript's `Math.imul` and `>>>` are emulated explicitly because Dart's `int` is 64-bit. |
| `crypto.dart` | `client/src/crypto.ts` | HKDF-SHA256, AES-256-GCM, packed as `iv ‖ ciphertext ‖ tag` to match WebCrypto. Also ports the relay's room-id checksum. |
| `names.dart`, `avatar.dart` | `names.ts`, `avatar.ts` | Nicknames and the bee SVG. JavaScript's `Math.round` and its integral-number formatting are reproduced; Dart's defaults differ and would silently draw different bees. |
| `types.dart`, `protocol.dart` | `types.ts`, `shared/messages.ts`, `net.ts` | Payload shapes, server frames, and the inbound validation that guards against a malicious room member. |
| `net.dart` | `client/src/net.ts` | Reconnect backoff, ping watchdog, `lastSent` replay, `resync`. Sends the app Origin and `X-HereBee-Client`. |
| `peer_state.dart` | state half of `markers.ts` | Freshness tiers, linger, offline flag. |
| `storage.dart` | `main.ts` storage helpers | Seed, cid, custom names, per-room sharing flag. Nothing else is persisted. |

Localization is wired: `l10n.yaml` generates the `L` class from the ARB files
that `npm run i18n:arb` produces. `flutter pub get` regenerates the Dart sources,
so they are gitignored while the ARB files are tracked.

`lib/main.dart` is a deliberate placeholder. It renders the app name and hint to
prove the localization pipeline, and touches neither network nor location. The
real UI is Phase 2.

**Tests**

| Check | What it proves |
|---|---|
| `mobile/test/vectors_test.dart` | Room derivation, raw AES key bytes, decryption of browser-produced ciphertexts, the PRNG streams, both name sets, and 40 avatar SVG hashes plus two full character-for-character SVGs. |
| `mobile/test/protocol_test.dart` | Malformed and hostile payloads are dropped, range bounds included. |
| `mobile/test/dependency_audit_test.dart` | No Play Services, Firebase, Sentry or analytics in the RESOLVED package set or in any plugin's native build files. |
| `mobile/test/widget_test.dart` | The app builds and all six locales resolve the full key set. |
| `npm run test:interop` | A Node "browser" peer and the app's real `NetClient` join one room through a real relay, with the production origin policy, and decrypt each other. |

Totals: 73 Dart tests, 254 web assertions, one live interop run.

## 7. Phase 2 — map and room UI (done)

**`pmtiles://` works natively on both platforms.** The `maplibre` package 0.3.6
bundles MapLibre Native Android 13.5 and iOS 6.29, both well past the versions
that added PMTiles. The production archive is read over HTTP range requests
exactly as the browser reads it, so the fallback tile endpoint (Phase 0 step 8)
is not needed and should stay unbuilt.

| Built | Notes |
|---|---|
| `features/room/room_controller.dart` | Owns the socket, the peer store, presence, follow state and locally chosen names. No multi-tab leader election: an app process cannot have the same room open twice, so `coord.ts` has no counterpart. |
| `features/room/room_screen.dart` | Full-bleed map with the HUD over it. Camera follow, fit-all, tap-to-dismiss, and dropping follow on a real pan gesture only. |
| `features/map/bee_marker.dart` | The bee: pulse ring while fresh, heading arrow above 1.5 m/s, fading through the stale and ghost tiers, name plus status suffix. |
| `features/map/marker_menu.dart` | Rename and follow, with last-seen, distance and link state. |
| `features/hud/hud.dart` | Connection chip, roster with colour pips and the participants sheet, dock. |
| `features/sheets/sheets.dart` | Entry gate, info, Impressum and Datenschutz, rename, invalid link. |
| `util/markup.dart` | Renders the `<strong>/<em>/<code>` the shared strings carry. |

### Scope: this phase joins as a WATCHER

The app renders peers and counts as present, but does not transmit a position.
Sharing needs the location service, which is Phase 3. "Just watching" is a
first-class state in HereBee, not a stand-in, so this is a shippable slice
rather than a stub. **Phase 3 must update the Standortfreigabe paragraph in
`showLegalSheet` in the same change that enables sharing** — the current wording
says the app does not access location, and shipping it alongside a build that
does would make the disclosure false.

### Deviations from the plan, and why

- **Widget markers, not a symbol layer.** The plan preferred a symbol layer for
  pan performance. The web client uses DOM markers at the same scale (rooms are
  a handful of people), and widget markers buy the pulse animation, the bubble
  menu and direct SVG rendering. Revisit if a busy room ever stutters.
- **Copy link, not a share sheet.** Matches the web button. `share_plus` moves to
  Phase 3 with the rest of the platform integration.
- **`org.jlleitschuh.gradle.ktlint` declared in `android/settings.gradle.kts`.**
  Upstream bug: `maplibre_android` 0.3.6 applies that plugin without a version,
  and its own settings file is ignored when Flutter includes it as a subproject.
  Build-time only. Remove when upstream stops leaking its lint config.
- **`NSAllowsLocalNetworking` in the iOS Info.plist**, plus a debug-only
  `network_security_config` on Android. Both permit cleartext to the DEV machine
  only; release builds still refuse plain HTTP, and the production origin is
  https either way.

### Tests

`integration_test/room_flow_test.dart` drives the app on a real device or
simulator, because the map is a native platform view and cannot build in the
headless harness. It walks the entry gate, waits for a peer's encrypted position,
and asserts a bee appears under the nickname derived locally from that peer's
seed. `scripts/fake-peer.ts` supplies the peer.

```bash
npx tsx scripts/fake-peer.ts --ws ws://127.0.0.1:3100/ws --seed dev-anna
cd mobile && flutter test integration_test/room_flow_test.dart \
  --dart-define=HEREBEE_ORIGIN=http://127.0.0.1:3100 \
  --dart-define=HEREBEE_SECRET=<the secret the peer printed>
```

`--dart-define=HEREBEE_HOLD_SECONDS=40` keeps the app on screen afterwards so a
screenshot can be taken from outside.

### Gotcha worth knowing

A small local basemap extract looks exactly like a rendering bug. At the initial
DACH-wide zoom, only the one zoom-5 tile that overlaps the extract has data and
everything else shows the style's `#cccccc` background, which reads as a clipped
map view. Check the archive's real bounds before suspecting the renderer:

```bash
.bin/pmtiles show server/assets/tiles/basemap.pmtiles
```

## 8. Phase 3 — background location, lifecycle, deep links

Own plugin `mobile/packages/herebee_location/`. Android: a
`foregroundServiceType="location"` service with an ongoing notification carrying
a Stop action; permissions `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `POST_NOTIFICATIONS`,
`INTERNET`, and deliberately **not** `ACCESS_BACKGROUND_LOCATION`. iOS:
`UIBackgroundModes: location`, `allowsBackgroundLocationUpdates`,
`pausesLocationUpdatesAutomatically = false`, When-In-Use only unless testing
shows suspension while stationary. Lifecycle resume and connectivity regain call
`resync()`. Deep links via `app_links`, reading `uri.fragment`.

Acceptance: ten minutes locked while sharing, with a web peer still receiving.

## 9. Phase 4 — release

Icons and splash from `client/public/brand/`. Localization and accessibility
pass. Web additions: the `/download` page and a Smart App Banner. Store metadata
and the privacy forms from §3. Signing, then feed the Team ID and SHA-256
fingerprints into the Phase 0 env vars. Play's closed-test requirement for new
accounts adds two calendar weeks, so start it during Phase 3.

## 10. Risks

- Plugin background behaviour differs from its documentation on real hardware.
  Test on the physical iPhone and a physical Android phone, not only emulators.
- iOS may suspend a stationary app even with the location background mode.
  Automatic pausing is already disabled; escalate to Always only if measured.
- A bit-exact PRNG port is easy to get subtly wrong. The vectors exist for this.

## 11. Follow-ups before the apps ship

1. **Coolify `watch_paths`.** Currently unset, so every push to `main` redeploys
   and drops every live room. Set it to the paths that actually affect the
   server, so mobile-only commits do not redeploy:
   `client/**`, `server/**`, `shared/**`, `scripts/**`, `Dockerfile`,
   `package.json`, `package-lock.json`, `tsconfig.json`. Verify afterwards that a
   web change still deploys; a too-narrow list fails silently in the other
   direction.
2. The production env vars from §5.
3. Apple Developer Program enrollment, which gates Universal Links and TestFlight.
