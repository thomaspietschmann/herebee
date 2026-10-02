/// Asks whether to send a report for an uncaught Dart error. Mirrors ACRA's
/// dialog on Android: what is sent, where it goes, an optional comment, and
/// nothing leaves the device unless Send is tapped.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../core/crash_reporter.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/tokens.dart' as tokens;

class CrashPrompt extends StatefulWidget {
  const CrashPrompt({
    required this.reporter,
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final CrashReporter reporter;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<CrashPrompt> createState() => _CrashPromptState();
}

class _CrashPromptState extends State<CrashPrompt> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    widget.reporter.pending.addListener(_onPending);
    // An error may have been recorded before the first frame.
    _onPending();
  }

  @override
  void dispose() {
    widget.reporter.pending.removeListener(_onPending);
    super.dispose();
  }

  void _onPending() {
    if (_showing || widget.reporter.pending.value == null) return;
    // Never open a route from inside a build or an error callback.
    _nextFrame();
  }

  /// Runs [_ask] after the next frame, and makes sure there is one: an idle
  /// app draws no frames, and a post-frame callback alone would wait forever.
  void _nextFrame() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => unawaited(_ask()))
      ..scheduleFrame();
  }

  Future<void> _ask() async {
    if (_showing || !mounted) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null) {
      // The navigator is not up yet; try again after the next frame.
      _nextFrame();
      return;
    }
    final crash = widget.reporter.take();
    if (crash == null) return;
    _showing = true;
    // The dialog sends and shows the outcome itself: a snackbar would sit
    // behind whatever modal sheet happens to be open (the entry gate, say).
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CrashDialog(
        host: AppConfig.hostOf(widget.reporter.serverOrigin()),
        onSend: (comment) => widget.reporter.send(crash, comment: comment),
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks, sends on "Send" and then shows whether it worked. "Don't send"
/// closes it and the report is dropped, never written anywhere.
class _CrashDialog extends StatefulWidget {
  const _CrashDialog({required this.host, required this.onSend});

  final String host;
  final Future<bool> Function(String comment) onSend;

  @override
  State<_CrashDialog> createState() => _CrashDialogState();
}

enum _Phase { asking, sending, sent, failed }

class _CrashDialogState extends State<_CrashDialog> {
  final TextEditingController _comment = TextEditingController();
  _Phase _phase = _Phase.asking;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _phase = _Phase.sending);
    final ok = await widget.onSend(_comment.text);
    if (mounted) setState(() => _phase = ok ? _Phase.sent : _Phase.failed);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final t = tokens.HereBeeTokens.of(context);
    final body = TextStyle(color: t.muted, fontSize: 13.5, height: 1.5);
    final done = _phase == _Phase.sent || _phase == _Phase.failed;
    return AlertDialog(
      key: const ValueKey('crash-dialog'),
      backgroundColor: t.sheetBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.panelRadius),
        side: BorderSide(color: t.panelBorder),
      ),
      title: Text(l.crashTitle,
          style: TextStyle(color: t.mist, fontSize: 19, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: done
            ? Text(_phase == _Phase.sent ? l.crashSent : l.crashSendFailed,
                key: const ValueKey('crash-result'), style: body.copyWith(color: t.mist))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.crashBody(widget.host), style: body),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('crash-comment'),
                    controller: _comment,
                    enabled: _phase == _Phase.asking,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 4,
                    style: TextStyle(color: t.mist),
                    decoration: InputDecoration(
                      hintText: l.crashComment,
                      hintMaxLines: 3,
                      hintStyle: TextStyle(color: t.muted, fontSize: 13),
                      counterText: '',
                    ),
                  ),
                ],
              ),
      ),
      actions: done
          ? [
              FilledButton(
                key: const ValueKey('crash-ok'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ]
          : [
              TextButton(
                key: const ValueKey('crash-dont-send'),
                onPressed: _phase == _Phase.asking ? () => Navigator.of(context).pop() : null,
                child: Text(l.crashDontSend),
              ),
              FilledButton(
                key: const ValueKey('crash-send'),
                onPressed: _phase == _Phase.asking ? _send : null,
                child: _phase == _Phase.sending
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.crashSend),
              ),
            ],
    );
  }
}
