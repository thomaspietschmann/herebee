/// App entry point.
///
/// A room is identified solely by the 256-bit secret in the link fragment. With
/// no link (the app opened from the home screen) we mint a fresh room, exactly
/// as the web client does when you open "/". Deep links arrive in Phase 3; until
/// then `--dart-define=HEREBEE_SECRET=…` joins a specific room for testing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/crypto.dart';
import 'core/storage.dart';
import 'features/room/room_controller.dart';
import 'features/room/room_screen.dart';
import 'l10n/app_localizations.dart';

const String _secretOverride = String.fromEnvironment('HEREBEE_SECRET');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  runApp(HereBeeApp(storage: storage));
}

class HereBeeApp extends StatelessWidget {
  const HereBeeApp({required this.storage, super.key});

  final Storage storage;

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
      home: _RoomHost(storage: storage),
    );
  }
}

/// Builds the controller once the locale is known — the locale decides which
/// nickname set peers are shown under, so it is not a detail we can defer.
class _RoomHost extends StatefulWidget {
  const _RoomHost({required this.storage});

  final Storage storage;

  @override
  State<_RoomHost> createState() => _RoomHostState();
}

class _RoomHostState extends State<_RoomHost> {
  RoomController? _controller;

  /// The screen is not built until the room keys exist. Otherwise the entry
  /// gate can be tapped before `init()` resolves, and `enter()` would find no
  /// keys and silently do nothing — a room you can never actually join.
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = RoomController(
      secret: _secretOverride.isNotEmpty ? _secretOverride : generateSecret(),
      storage: widget.storage,
      languageCode: Localizations.localeOf(context).languageCode,
      youSuffix: L.of(context).youSuffix,
    );
    _controller = controller;
    controller.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return RoomScreen(controller: controller);
  }
}
