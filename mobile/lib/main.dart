/// App entry point.
///
/// A room is identified solely by the 256-bit secret in the link fragment.
///
/// Opened from a link, we join that room. Opened from the home screen, we return
/// to the room entered last, if it is still remembered (see core/recent_rooms.dart),
/// and otherwise mint a fresh one, exactly as the web client does for "/".
/// Opened from a room link whose secret is broken, we say so rather than
/// quietly minting a different room, because the user came expecting a
/// specific one.
///
/// `--dart-define=HEREBEE_SECRET=…` forces a room for testing.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/crypto.dart';
import 'core/deep_links.dart';
import 'core/recent_rooms.dart';
import 'core/storage.dart';
import 'features/room/room_controller.dart';
import 'features/room/room_screen.dart';
import 'l10n/app_localizations.dart';

const String _secretOverride = String.fromEnvironment('HEREBEE_SECRET');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  runApp(HereBeeApp(storage: storage, recent: RecentRooms(SecureSecretStore())));
}

class HereBeeApp extends StatelessWidget {
  HereBeeApp({required this.storage, RecentRooms? recent, super.key})
      : recent = recent ?? RecentRooms(MemorySecretStore());

  final Storage storage;

  /// Defaults to a memory-only list, which is what tests and the widget harness
  /// want. Production passes the secure-storage-backed one.
  final RecentRooms recent;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => L.of(context).title,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF5B301),
          brightness: Brightness.dark,
        ),
      ),
      home: _RoomHost(storage: storage, recent: recent),
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
      _openRoom(_secretOverride);
      return;
    }
    if (initial != null) {
      _onLink(initial);
      return;
    }
    // Home-screen launch: back to where you were, or a fresh room. The entry
    // gate still stands in front of either, so nothing connects on its own.
    await widget.recent.load();
    if (!mounted || _secret != null) return; // a link arrived meanwhile
    _openRoom(widget.recent.latest?.secret ?? generateSecret());
  }

  void _onLink(Uri uri) {
    final secret = secretFromLink(uri);
    if (secret != null) {
      // Tapping the link for the room you are already in should do nothing,
      // not throw you out and back in again.
      if (secret != _secret) _openRoom(secret);
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
    if (_secret == null) _openRoom(generateSecret());
  }

  void _openRoom(String secret) {
    // Switching rooms is a full teardown: the old socket, its peers and its
    // sharing state must not bleed into the new room.
    _controller?.dispose();
    final recent = widget.recent;
    final controller = RoomController(
      secret: secret,
      storage: widget.storage,
      languageCode: Localizations.localeOf(context).languageCode,
      youSuffix: L.of(context).youSuffix,
      onEntered: () => unawaited(recent.touch(secret)),
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
      onOpenRoom: (secret) {
        if (secret != _secret) _openRoom(secret);
      },
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
