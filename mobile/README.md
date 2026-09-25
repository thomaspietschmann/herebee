# HereBee mobile

Flutter app for iOS and Android. See the [root README](../README.md) for what
HereBee is, the privacy statement, deployment and releases, and
[`docs/mobile-plan.md`](../docs/mobile-plan.md) for the design decisions.

The app talks to one origin only, `https://herebee.app` by default. Override it
with `--dart-define=HEREBEE_ORIGIN` for a local relay. All commands run from
this directory.

| Command | Purpose |
|---|---|
| `flutter pub get` | Fetch dependencies and generate the localization classes from `lib/l10n/*.arb` |
| `flutter run --dart-define=HEREBEE_ORIGIN=http://localhost:3100` | Run on the iOS simulator against a local relay |
| `flutter run --dart-define=HEREBEE_ORIGIN=http://10.0.2.2:3100` | Run on the Android emulator against a local relay |
| `... --dart-define=HEREBEE_SECRET=<secret>` | Open a known room instead of minting one |
| `flutter analyze` | Static analysis, as in CI |
| `flutter test` | Unit tests, including the conformance vectors from `../shared/vectors.json` |
| `flutter test integration_test/room_flow_test.dart --dart-define=HEREBEE_ORIGIN=... --dart-define=HEREBEE_SECRET=...` | Room flow on a booted simulator or device, with `../scripts/fake-peer.ts` supplying the peer |
| `flutter build apk --release` | Signed release APK when `android/key.properties` exists (gitignored); otherwise debug-signed |

The ARB files are generated from the web client with `npm run i18n:arb` in the
repository root. The interop test, `npm run test:interop` in the root, runs
`tool/interop_app_peer.dart` against a live relay.
