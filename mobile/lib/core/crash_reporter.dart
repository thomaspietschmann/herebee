/// Opt-in reports for uncaught Dart errors, on both platforms.
///
/// The Dart counterpart of ACRA on Android (mobile/android/app/src/main/kotlin/
/// app/herebee/crash/). An uncaught Dart error does not kill the process, so
/// ACRA never sees it; this catches it instead, asks the user, and only on
/// "Send" posts it to `<server>/api/crash`, the same endpoint and format, which
/// mails it to that server's operator.
///
/// The privacy rules are the native sender's:
///  - nothing leaves the device without an explicit tap on Send;
///  - an explicit allowlist of fields: app version, OS, the error and its
///    trace, the user's comment. No device model, no identifiers, no logs;
///  - room keys in link fragments, `herebee://` links and anything that looks
///    like a coordinate are redacted before sending;
///  - at most one question per app session, so a repeating error cannot turn
///    into a stream of dialogs (or of reports).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_config.dart';

/// Caps mirror server/src/crash.ts, so a long trace is cut here rather than
/// rejected there.
const int _maxStack = 32000;
const int _maxComment = 2000;
const int _maxShort = 200;

/// Redacts what must never reach a mailbox. Same rules as HereBeeReportSender.
String redactReport(String s) => s
    .replaceAllMapped(
      RegExp(r'((?:https?|herebee)://[^\s#]*)#\S*', caseSensitive: false),
      (m) => '${m[1]}#[redacted]',
    )
    .replaceAll(RegExp(r'herebee://(?!\[redacted\])\S+', caseSensitive: false), 'herebee://[redacted]')
    .replaceAll(RegExp(r'-?\d{1,3}\.\d{5,}'), '[number]');

String _cap(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// One uncaught error, waiting for the user's answer.
@immutable
class PendingCrash {
  const PendingCrash({required this.error, required this.stack, required this.at});

  final String error;
  final String stack;
  final DateTime at;

  /// The wire payload for `/api/crash` (see crashReportSchema on the server).
  Map<String, String> payload({String? comment}) {
    final trace = redactReport('$error\n$stack'.trim());
    final note = comment == null ? '' : redactReport(comment.trim());
    return {
      'platform': Platform.isIOS ? 'ios' : 'android',
      'source': 'dart',
      'appVersionName': AppConfig.clientVersion,
      'osVersion': _cap(redactReport('${Platform.operatingSystem} ${Platform.operatingSystemVersion}'), _maxShort),
      'stackTrace': _cap(trace.isEmpty ? '(no trace)' : trace, _maxStack),
      if (note.isNotEmpty) 'userComment': _cap(note, _maxComment),
      'crashDate': at.toUtc().toIso8601String(),
    };
  }
}

/// Posts a JSON body; returns the HTTP status. Injectable for tests.
typedef CrashPoster = Future<int> Function(Uri url, String body);

Future<int> _httpPost(Uri url, String body) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await http.postUrl(url).timeout(const Duration(seconds: 15));
    req.followRedirects = false;
    req.headers.contentType = ContentType.json;
    req.headers.set('X-HereBee-Client', Platform.operatingSystem);
    req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    await res.drain<void>();
    return res.statusCode;
  } finally {
    http.close(force: true);
  }
}

class CrashReporter {
  CrashReporter({required this.serverOrigin, CrashPoster? post, DateTime Function()? clock})
      : _post = post ?? _httpPost,
        _clock = clock ?? DateTime.now;

  /// The server reports go to: the one configured in the settings, exactly
  /// like the native reporter. Read at send time, not at install time.
  final String Function() serverOrigin;
  final CrashPoster _post;
  final DateTime Function() _clock;

  /// The error waiting for an answer, or null. The UI listens to this.
  final ValueNotifier<PendingCrash?> pending = ValueNotifier(null);

  /// Whether the user was already asked in this session.
  bool _asked = false;

  /// Hooks into Flutter's two places where uncaught errors end up. The
  /// framework's own reporting (console, red screen in debug) stays as it is.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      (previous ?? FlutterError.presentError)(details);
      record(details.exception, details.stack);
    };
    final platform = PlatformDispatcher.instance;
    final previousPlatform = platform.onError;
    platform.onError = (error, stack) {
      record(error, stack);
      if (previousPlatform != null) return previousPlatform(error, stack);
      // Still on the console, as without this handler.
      FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack, library: 'HereBee'));
      return true;
    };
  }

  /// Keeps the first uncaught error of a session for the question. Everything
  /// after it is dropped: one question per session, no queue on disk.
  void record(Object error, StackTrace? stack) {
    if (_asked || pending.value != null) return;
    pending.value = PendingCrash(
      error: '${error.runtimeType}: $error',
      stack: (stack ?? StackTrace.empty).toString(),
      at: _clock(),
    );
  }

  /// Marks the question as shown; from now on nothing more is recorded.
  PendingCrash? take() {
    final crash = pending.value;
    if (crash == null) return null;
    _asked = true;
    pending.value = null;
    return crash;
  }

  /// Sends [crash] after the user said yes. True when the server took it.
  Future<bool> send(PendingCrash crash, {String? comment}) async {
    final origin = serverOrigin();
    try {
      final status = await _post(
        Uri.parse('$origin/api/crash'),
        jsonEncode(crash.payload(comment: comment)),
      );
      return status >= 200 && status < 300;
    } catch (_) {
      return false;
    }
  }
}
