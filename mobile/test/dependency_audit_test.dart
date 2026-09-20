/// Enforces the dependency policy from docs/mobile-plan.md §3.
///
/// The privacy claim on the store listing is only as good as what actually ends
/// up in the binary. A transitive plugin that pulls in Play Services or a crash
/// reporter would make the claim false without anyone editing pubspec.yaml, so
/// this checks the RESOLVED dependency set rather than the declared one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Substrings that must not appear in any resolved package's native build files.
const List<String> forbiddenNative = [
  'com.google.android.gms',
  'com.google.firebase',
  'play-services',
  'Firebase/', // CocoaPods spec
  'FirebaseCore',
  'GoogleAnalytics',
  'Crashlytics',
  'Sentry',
];

/// Pub packages that must never appear in the resolved set.
const List<String> forbiddenPackages = [
  'firebase_core',
  'firebase_analytics',
  'firebase_crashlytics',
  'firebase_messaging',
  'sentry_flutter',
  'google_mobile_ads',
  'amplitude_flutter',
  'mixpanel_flutter',
  'posthog_flutter',
  // Pulls in com.google.android.gms:play-services-location on Android.
  'geolocator_android',
];

void main() {
  test('no analytics, crash reporting or Play Services in the resolved packages', () {
    final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
        as Map<String, dynamic>;
    final packages = (config['packages'] as List<dynamic>).cast<Map<String, dynamic>>();

    final names = packages.map((p) => p['name'] as String).toSet();
    for (final banned in forbiddenPackages) {
      expect(names, isNot(contains(banned)),
          reason: '$banned is resolved; it breaks the "no third-party SDK" claim');
    }

    // Walk each package's native build files. This is what actually decides
    // whether a library lands in the APK or the IPA.
    final offenders = <String>[];
    for (final pkg in packages) {
      final name = pkg['name'] as String;
      if (name == 'herebee') continue;
      final rootUri = pkg['rootUri'] as String;
      final root = rootUri.startsWith('file://')
          ? Directory.fromUri(Uri.parse(rootUri))
          : Directory.fromUri(Directory.current.uri.resolve(rootUri));
      if (!root.existsSync()) continue;

      for (final relative in ['android/build.gradle', 'android/build.gradle.kts']) {
        final file = File('${root.path}/$relative');
        if (!file.existsSync()) continue;
        final text = file.readAsStringSync();
        for (final needle in forbiddenNative) {
          if (text.contains(needle)) offenders.add('$name -> $relative contains "$needle"');
        }
      }
      for (final podspec in root.listSync(recursive: false).whereType<Directory>()) {
        if (!podspec.path.endsWith('/ios') && !podspec.path.endsWith('/darwin')) continue;
        for (final f in podspec.listSync().whereType<File>()) {
          if (!f.path.endsWith('.podspec')) continue;
          final text = f.readAsStringSync();
          for (final needle in forbiddenNative) {
            if (text.contains(needle)) offenders.add('$name -> ${f.path} contains "$needle"');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
