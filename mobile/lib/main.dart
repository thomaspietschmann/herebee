/// App entry point.
///
/// A room is identified solely by the 256-bit secret in the link fragment.
///
/// Opened from a link, we join that room. Opened from the home screen, we ask
/// which remembered room to return to, or whether to start a new one (see
/// core/recent_rooms.dart); with nothing remembered we mint a fresh one
/// directly, exactly as the web client does for "/".
/// Opened from a room link whose secret is broken, we say so rather than
/// quietly minting a different room, because the user came expecting a
/// specific one.
///
/// `--dart-define=HEREBEE_SECRET=…` forces a room for testing.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_config.dart';
import 'core/crash_reporter.dart';
import 'core/crypto.dart';
import 'core/deep_links.dart';
import 'ui/tokens.dart' as tokens;
import 'core/names.dart';
import 'core/recent_rooms.dart';
import 'core/storage.dart';
import 'features/crash/crash_prompt.dart';
import 'features/room/room_controller.dart';
import 'features/room/room_screen.dart';
import 'features/sheets/sheets.dart';
import 'features/start/start_screen.dart';
import 'l10n/app_localizations.dart';

const String _secretOverride = String.fromEnvironment('HEREBEE_SECRET');

/// `--dart-define=HEREBEE_CRASH_SELFTEST=true` throws one uncaught error a few
/// seconds after launch, to try the error-report dialog end to end. Compiled
/// out otherwise.
const bool _crashSelfTest = bool.fromEnvironment('HEREBEE_CRASH_SELFTEST');

/// Error reports are asked for in release builds. A debug build fails loudly
/// on its own; `--dart-define=HEREBEE_CRASH_REPORTS=true` turns them on there.
const bool _crashReports = !kDebugMode || _crashSelfTest || bool.fromEnvironment('HEREBEE_CRASH_REPORTS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  CrashReporter? crashes;
  if (_crashReports) {
    crashes = CrashReporter(serverOrigin: () => storage.serverOrigin)..install();
  }
  runApp(HereBeeApp(storage: storage, recent: RecentRooms(SecureSecretStore()), crashes: crashes));
  if (_crashSelfTest) {
    // Carries a room link and a coordinate on purpose: both must arrive redacted.
    Timer(const Duration(seconds: 4), () {
      throw StateError('crash self-test at 52.520008,13.404954 https://herebee.app/r/#$_selfTestSecret');
    });
  }
}

const String _selfTestSecret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

class HereBeeApp extends StatelessWidget {
  HereBeeApp({required this.storage, RecentRooms? recent, this.crashes, super.key})
      : recent = recent ?? RecentRooms(MemorySecretStore());

  final Storage storage;

  /// Asks before reporting an uncaught Dart error; null disables it.
  final CrashReporter? crashes;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Defaults to a memory-only list, which is what tests and the widget harness
  /// want. Production passes the secure-storage-backed one.
  final RecentRooms recent;

  @override
  Widget build(BuildContext context) {
    final crashes = this.crashes;
    // The synthwave map style restyles the whole chrome, so the app theme
    // follows the stored preference live.
    return ValueListenableBuilder<MapThemePref>(
      valueListenable: storage.mapThemeListenable,
      builder: (context, pref, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        builder: crashes == null
            ? null
            : (context, child) => CrashPrompt(
                  reporter: crashes,
                  navigatorKey: _navigatorKey,
                  child: child ?? const SizedBox.shrink(),
                ),
        onGenerateTitle: (context) => L.of(context).title,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          L.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L.supportedLocales,
        theme: themeFor(pref),
        home: _RoomHost(storage: storage, recent: recent),
      ),
    );
  }
}

/// Builds the controller once the locale is known — the locale decides which
/// nickname set peers are shown under, so it is not a detail we can defer.
class _RoomHost extends StatefulWidget {
  const _RoomHost({required this.storage, required this.recent});

  final Storage storage;
  final RecentRooms recent;

  @override
  State<_RoomHost> createState() => _RoomHostState();
}

class _RoomHostState extends State<_RoomHost> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  RoomController? _controller;
  String? _secret;

  /// A link arrived without a usable secret. Shown instead of a room.
  bool _brokenLink = false;

  /// Plain launch with remembered rooms: ask before opening anything.
  bool _choosing = false;

  /// The screen is not built until the room keys exist. Otherwise the entry
  /// gate can be tapped before `init()` resolves, and `enter()` would find no
  /// keys and silently do nothing — a room you can never actually join.
  bool _ready = false;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    // A link that launched the app is delivered once, separately from the
    // stream; missing it would land a tapped link in a freshly minted room.
    Uri? initial;
    try {
      initial = await _appLinks.getInitialLink();
    } catch (_) {
      // No link, or the platform has none to give.
    }
    _linkSub = _appLinks.uriLinkStream.listen(_onLink);

    if (_secretOverride.isNotEmpty) {
      _openRoom(_secretOverride, widget.storage.serverOrigin);
      return;
    }
    if (initial != null) {
      _onLink(initial);
      return;
    }
    // Home-screen launch. With remembered rooms the user picks; the app never
    // re-enters one on its own. Nothing connects before a room is open AND
    // its entry gate has been passed.
    await widget.recent.load();
    if (!mounted || _secret != null) return; // a link arrived meanwhile
    if (widget.recent.rooms.isEmpty) {
      _openRoom(generateSecret(), widget.storage.serverOrigin);
    } else {
      setState(() => _choosing = true);
    }
  }

  /// Names for the start screen, before any room controller exists: the same
  /// derivation the map uses, including names the user typed.
  String _nameFor(RecentRoom room, String seed) =>
      (room.roomId.isEmpty ? null : widget.storage.customName(room.roomId, seed)) ??
      nameFromSeed(seed, Localizations.localeOf(context).languageCode);

  void _onLink(Uri uri) {
    final secret = secretFromLink(uri);
    if (secret != null) {
      unawaited(_openLinked(secret, linkOrigin(uri)));
      return;
    }
    if (looksLikeRoomLink(uri)) {
      // Tear the old room down first. Showing only a notice while its controller
      // lives on would keep the socket open and, if the user was sharing, keep
      // broadcasting a location behind a screen with no Stop button.
      _controller?.dispose();
      setState(() {
        _controller = null;
        _secret = null;
        _ready = false;
        _brokenLink = true;
      });
      return;
    }
    // Not a room link at all (the bare site). Only mint a room if we have none.
    if (_secret == null) _openRoom(generateSecret(), widget.storage.serverOrigin);
  }

  /// Opens a room someone handed over, on the server the link names (null: the
  /// configured one). A server other than the official one is followed only
  /// after a warning, unless the user already chose that server themselves.
  /// Declining keeps the current room, or opens a fresh one on the user's own
  /// server when there is none yet.
  Future<void> _openLinked(String secret, String? linkedOrigin) async {
    final origin = linkedOrigin ?? widget.storage.serverOrigin;
    // Tapping the link for the room you are already in should do nothing,
    // not throw you out and back in again.
    if (secret == _secret && origin == _controller?.origin) return;
    if (!await _acceptServer(origin, fromLink: true)) {
      if (_secret == null && mounted) _openRoom(generateSecret(), widget.storage.serverOrigin);
      return;
    }
    if (mounted) _openRoom(secret, origin);
  }

  /// Whether the room may open on [origin]. The official server and the one the
  /// user configured need no question; anything else is warned about first.
  Future<bool> _acceptServer(String origin, {required bool fromLink}) async {
    if (AppConfig.isOfficial(origin) || origin == widget.storage.serverOrigin) return true;
    // The first frame may not be up yet when a launch link arrives.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;
    return showServerWarning(context, origin: origin, fromLink: fromLink);
  }

  /// A choice from the start screen or the rooms sheet.
  Future<void> _choose(RoomsChoice choice) async {
    final secret = choice.secret;
    if (secret == null) {
      _openRoom(generateSecret(), widget.storage.serverOrigin);
      return;
    }
    final origin = choice.origin ?? widget.storage.serverOrigin;
    // A remembered room was accepted when it was first entered.
    if (!choice.remembered && !await _acceptServer(origin, fromLink: true)) return;
    if (!mounted || (secret == _secret && origin == _controller?.origin)) return;
    _openRoom(secret, origin);
  }

  void _openRoom(String secret, String origin) {
    // Switching rooms is a full teardown: the old socket, its peers and its
    // sharing state must not bleed into the new room.
    _controller?.dispose();
    final recent = widget.recent;
    final controller = RoomController(
      secret: secret,
      storage: widget.storage,
      languageCode: Localizations.localeOf(context).languageCode,
      youSuffix: L.of(context).youSuffix,
      origin: origin,
      onEntered: (roomId) => unawaited(recent.touch(secret, roomId: roomId, origin: origin)),
    );
    // Remember who was met here, so the rooms list can say more than a date.
    // sawPeers() is a no-op unless something is new, so a listener that fires
    // on every tick is fine.
    controller.addListener(() {
      final seeds = controller.peers.entries.where((e) => !e.isSelf).map((e) => e.seed);
      unawaited(recent.sawPeers(secret, seeds));
    });
    setState(() {
      _secret = secret;
      _controller = controller;
      _brokenLink = false;
      _choosing = false;
      _ready = false;
    });
    controller.init().then((_) {
      if (mounted && _controller == controller) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_brokenLink) return const _BrokenLinkScreen();
    if (_choosing) {
      return StartScreen(
        recent: widget.recent,
        nameFor: _nameFor,
        onChoose: (choice) => unawaited(_choose(choice)),
      );
    }
    final controller = _controller;
    if (controller == null || !_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Keyed by secret so switching rooms rebuilds the screen from scratch
    // rather than reusing state that belongs to the previous room.
    return RoomScreen(
      key: ValueKey(_secret),
      controller: controller,
      recent: widget.recent,
      onOpenRoom: (choice) => unawaited(_choose(choice)),
    );
  }
}

/// A room link whose secret is missing or mangled. Room links are generated and
/// cannot be typed, so there is nothing for the user to correct here.
class _BrokenLinkScreen extends StatelessWidget {
  const _BrokenLinkScreen();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.invalidTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(l.invalidBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, height: 1.45)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app theme for a map-style preference: synthwave restyles the chrome,
/// every other choice keeps the standard look.
ThemeData themeFor(MapThemePref pref) =>
    _theme(pref == MapThemePref.synthwave ? tokens.HereBeeTokens.synthwave : tokens.HereBeeTokens.standard);

ThemeData _theme(tokens.HereBeeTokens t) {
  final pill = t.pill();
  final label = TextStyle(
    fontSize: t.uppercase ? 13 : 15,
    fontWeight: FontWeight.w600,
    letterSpacing: t.uppercase ? 1 : -0.15,
  );
  const size = Size(48, 48);
  const padding = EdgeInsets.symmetric(horizontal: 22);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: t.fontFamily,
    fontFamilyFallback: t.fontFamilyFallback,
    scaffoldBackgroundColor: t.ink,
    extensions: [t],
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.signal,
      brightness: Brightness.dark,
    ).copyWith(
      primary: t.signal,
      onPrimary: t.onSignal,
      surface: t.ink2,
      onSurface: t.mist,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.signal,
        foregroundColor: t.onSignal,
        minimumSize: size,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: pill,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: t.inkGlass,
        foregroundColor: t.mist,
        side: BorderSide(color: t.outline),
        minimumSize: size,
        padding: padding,
        shape: pill,
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.mist, textStyle: label),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.toastBg,
      contentTextStyle: TextStyle(color: t.toastFg, fontSize: 13, fontWeight: FontWeight.w600),
      actionTextColor: t.toastFg,
      shape: pill,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.ink,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.hair),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.hair),
      ),
    ),
  );
}
