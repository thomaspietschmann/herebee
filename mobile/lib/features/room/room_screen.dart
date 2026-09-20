/// The one screen: a full-bleed map with the HUD floating over it.
///
/// Layout follows the web client — brand chip top left, roster top right, dock
/// at the bottom — so somebody who used the link in a browser recognises the app
/// immediately.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../../app_config.dart';
import '../../core/peer_state.dart';
import '../../l10n/app_localizations.dart';
import '../hud/hud.dart';
import '../map/bee_marker.dart';
import '../map/marker_menu.dart';
import '../sheets/sheets.dart';
import 'room_controller.dart';

/// Matches the web client's initial view (see client/src/map.ts).
const Geographic _initialCenter = Geographic(lon: 10.5, lat: 50.6);
const double _initialZoom = 5.2;

class RoomScreen extends StatefulWidget {
  const RoomScreen({required this.controller, super.key});

  final RoomController controller;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  MapController? _map;
  StreamSubscription<String>? _panSub;

  /// The seed whose bubble menu is open, or null. Only ever one at a time.
  String? _openMenuSeed;
  bool _welcomeShown = false;

  RoomController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _panSub = c.panRequests.listen(_panTo);
    c.addListener(_onControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_panSub?.cancel());
    c.removeListener(_onControllerChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Standby can leave the socket frozen; rebuilding it is cheap and the only
    // reliable way to notice.
    if (state == AppLifecycleState.resumed) c.resume();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _maybeOpenGate() async {
    if (_welcomeShown || !mounted) return;
    _welcomeShown = true;
    if (c.invalidLink) {
      await showInvalidLinkSheet(context);
      return;
    }
    // Nothing has touched the network yet; entering is the user's decision.
    await showWelcomeSheet(context);
    if (!mounted) return;
    await c.enter();
  }

  void _panTo(String seed) {
    final entry = c.peers[seed];
    final map = _map;
    if (entry == null || map == null) return;
    unawaited(map.animateCamera(
      center: Geographic(lon: entry.position.lng, lat: entry.position.lat),
      nativeDuration: const Duration(milliseconds: 500),
    ));
  }

  void _goTo(String seed) {
    final entry = c.peers[seed];
    final map = _map;
    if (entry == null || map == null) return;
    final zoom = (map.camera?.zoom ?? _initialZoom).clamp(15.0, 22.0);
    unawaited(map.animateCamera(
      center: Geographic(lon: entry.position.lng, lat: entry.position.lat),
      zoom: zoom,
      nativeDuration: const Duration(milliseconds: 700),
    ));
  }

  void _fitAll() {
    final map = _map;
    final all = c.peers.entries.toList();
    if (map == null || all.isEmpty) return;
    if (all.length == 1) {
      _goTo(all.first.seed);
      return;
    }
    var minLat = all.first.position.lat, maxLat = minLat;
    var minLng = all.first.position.lng, maxLng = minLng;
    for (final e in all) {
      minLat = e.position.lat < minLat ? e.position.lat : minLat;
      maxLat = e.position.lat > maxLat ? e.position.lat : maxLat;
      minLng = e.position.lng < minLng ? e.position.lng : minLng;
      maxLng = e.position.lng > maxLng ? e.position.lng : maxLng;
    }
    unawaited(map.fitBounds(
      bounds: LngLatBounds(
        longitudeWest: minLng,
        latitudeSouth: minLat,
        longitudeEast: maxLng,
        latitudeNorth: maxLat,
      ),
      padding: const EdgeInsets.all(72),
      nativeDuration: const Duration(milliseconds: 700),
    ));
  }

  void _onMapEvent(MapEvent event) {
    switch (event) {
      case MapEventClick():
        // Tapping empty map dismisses an open bubble menu.
        if (_openMenuSeed != null) setState(() => _openMenuSeed = null);
      case MapEventStartMoveCamera(:final reason):
        // Only a real gesture means "the user took the camera over".
        if (reason == CameraChangeReason.apiGesture) c.dropFollow();
      default:
        break;
    }
  }

  List<Marker> _markers(BuildContext context) {
    final now = DateTime.now();
    return c.peers.entries.map((entry) {
      final identity = c.identityFor(entry.seed);
      return Marker(
        point: Geographic(lon: entry.position.lng, lat: entry.position.lat),
        size: beeMarkerSize,
        child: BeeMarker(
          identity: identity,
          entry: entry,
          now: now,
          isSelf: entry.isSelf,
          onTap: () => setState(
            () => _openMenuSeed = _openMenuSeed == entry.seed ? null : entry.seed,
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final openSeed = _openMenuSeed;
    final openEntry = openSeed == null ? null : c.peers[openSeed];

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: Stack(
        children: [
          // Positioned.fill, not a bare child: a Stack hands non-positioned
          // children LOOSE constraints, and the native map view then sizes
          // itself to something arbitrary instead of the screen.
          Positioned.fill(
            child: MapLibreMap(
              options: MapOptions(
                initStyle: AppConfig.styleUrl(locale),
                initCenter: _initialCenter,
                initZoom: _initialZoom,
                // Location comes from peers, not from the camera; keep the
                // canvas gesture-friendly and upright, like the web client.
                gestures: const MapGestures(pan: true, zoom: true, rotate: false, pitch: false),
              ),
              onMapCreated: (controller) => _map = controller,
              onEvent: _onMapEvent,
              children: [
                WidgetLayer(markers: _markers(context), allowInteraction: true),
              ],
            ),
          ),
          if (openEntry != null)
            MarkerMenu(
              identity: c.identityFor(openEntry.seed),
              entry: openEntry,
              following: c.followSeed == openEntry.seed,
              referenceEntry: _selfOrNull(),
              onRename: () async {
                setState(() => _openMenuSeed = null);
                final name = await showRenameSheet(
                  context,
                  current: c.resolveName(openEntry.seed),
                  hasCustom: c.storage.customName(openEntry.seed) != null,
                );
                if (name != null) await c.rename(openEntry.seed, name.isEmpty ? null : name);
              },
              onToggleFollow: () => c.toggleFollow(openEntry.seed),
              onClose: () => setState(() => _openMenuSeed = null),
            ),
          Hud(
            controller: c,
            onFitAll: _fitAll,
            onGoTo: _goTo,
            onShareLink: () => shareRoomLink(context, c.roomLink),
            onInfo: () => showInfoSheet(context),
          ),
          if (c.fatal != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 140,
              child: _FatalBanner(
                message: c.fatal == 'invalid-room' ? l.fatalInvalidRoom : l.fatalRejected,
              ),
            ),
        ],
      ),
    );
  }

  /// Our own marker, once this client shares a position (Phase 3). Until then
  /// there is none, and distances in the info box are simply omitted.
  PeerEntry? _selfOrNull() {
    final seed = c.selfSeed;
    return seed == null ? null : c.peers[seed];
  }
}

class _FatalBanner extends StatelessWidget {
  const _FatalBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xEE7F1D1D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      );
}
