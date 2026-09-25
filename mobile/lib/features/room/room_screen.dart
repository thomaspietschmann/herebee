/// The one screen: a full-bleed map with the HUD floating over it.
///
/// Layout follows the web client — brand chip top left, roster top right, dock
/// at the bottom — so somebody who used the link in a browser recognises the app
/// immediately.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:herebee_location/herebee_location.dart';
import 'package:maplibre/maplibre.dart';

import '../../app_config.dart';
import '../../core/crypto.dart';
import '../../core/peer_state.dart';
import '../../core/recent_rooms.dart';
import '../../l10n/app_localizations.dart';
import '../hud/hud.dart';
import '../map/auto_fit.dart';
import '../map/bee_marker.dart';
import '../map/marker_menu.dart';
import '../sheets/sheets.dart';
import 'room_controller.dart';

/// Matches the web client's initial view (see client/src/map.ts).
const Geographic _initialCenter = Geographic(lon: 10.5, lat: 50.6);
const double _initialZoom = 5.2;

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    required this.controller,
    required this.recent,
    required this.onOpenRoom,
    super.key,
  });

  final RoomController controller;
  final RecentRooms recent;

  /// Switch to another room (a remembered one, or a freshly minted secret).
  final void Function(String secret) onOpenRoom;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  MapController? _map;
  StreamSubscription<String>? _panSub;

  /// The seed whose bubble menu is open, or null. Only ever one at a time.
  String? _openMenuSeed;
  bool _welcomeShown = false;

  final AutoFit _autoFit = AutoFit();

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
    // Sending slows down off screen (see SendPolicy). "inactive" is transient
    // (control centre, an incoming call) and does not count as leaving.
    switch (state) {
      case AppLifecycleState.resumed:
        c.setForeground(true);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        c.setForeground(false);
      case AppLifecycleState.inactive:
        break;
    }
  }

  LocationStopReason? _shownStopReason;
  bool _batteryHintShown = false;

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoFit();

    // The platform ended sharing without the user asking. Going quiet here would
    // look exactly like "nobody can see me and I don't know why".
    final reason = c.stoppedReason;
    if (reason != null && reason != _shownStopReason) {
      _shownStopReason = reason;
      final l = L.of(context);
      _toast(switch (reason) {
        LocationStopReason.permissionLost => l.sharingStoppedPermission,
        LocationStopReason.servicesDisabled => l.sharingStoppedServices,
        LocationStopReason.killedBySystem => l.sharingStopped,
        LocationStopReason.stoppedFromNotification => l.sharingStopped,
      });
    }
    if (reason == null) _shownStopReason = null;
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

  Future<void> _openRooms() async {
    final choice = await showRoomsSheet(
      context,
      recent: widget.recent,
      currentSecret: c.secret,
      nameFor: c.resolveName,
    );
    if (!mounted || choice == null) return;
    widget.onOpenRoom(choice.secret ?? generateSecret());
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

  /// Fit everyone when a new bee appears (see AutoFit). Runs on every
  /// controller tick and on map creation; AutoFit decides, this just moves.
  void _maybeAutoFit() {
    if (_map == null) return;
    final should = _autoFit.shouldFit(
      seeds: c.peers.entries.map((e) => e.seed).toSet(),
      sharing: c.sharing,
      following: c.followSeed != null,
    );
    if (should) _fitAll();
  }

  /// Two bees at the same spot must not zoom the map to street level: the
  /// native fitBounds has no max zoom, so bounds are widened to at least this
  /// many degrees (~400 m) instead.
  static const double _minSpan = 0.004;

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
    if (maxLat - minLat < _minSpan) {
      final mid = (minLat + maxLat) / 2;
      minLat = mid - _minSpan / 2;
      maxLat = mid + _minSpan / 2;
    }
    if (maxLng - minLng < _minSpan) {
      final mid = (minLng + maxLng) / 2;
      minLng = mid - _minSpan / 2;
      maxLng = mid + _minSpan / 2;
    }
    unawaited(map.fitBounds(
      bounds: LngLatBounds(
        longitudeWest: minLng,
        latitudeSouth: minLat,
        longitudeEast: maxLng,
        latitudeNorth: maxLat,
      ),
      // Asymmetric on purpose: the roster sits under the status bar and the
      // dock covers the bottom, so a symmetric inset puts bees behind them.
      padding: const EdgeInsets.fromLTRB(56, 130, 56, 230),
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
        if (reason == CameraChangeReason.apiGesture) {
          c.dropFollow();
          _autoFit.cameraTaken();
        }
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
              onMapCreated: (controller) {
                _map = controller;
                // Peers may have arrived before the native view existed.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _maybeAutoFit();
                });
              },
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
                if (name == null) return;
                await c.rename(openEntry.seed, name.isEmpty ? null : name);
                // Our own name is never shared without asking.
                if (openEntry.seed == c.selfSeed && name.isNotEmpty && context.mounted) {
                  await c.setSharesName(await askShareName(context, name));
                }
              },
              onToggleFollow: () => c.toggleFollow(openEntry.seed),
              onClose: () => setState(() => _openMenuSeed = null),
            ),
          Hud(
            controller: c,
            onFitAll: _fitAll,
            onGoTo: _goTo,
            onShareLink: () => shareRoomLink(context, c.roomLink),
            onToggleShare: _toggleShare,
            onInfo: () => showInfoSheet(context),
            onRooms: _openRooms,
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

  /// Our own marker, present only while sharing. Until then the info box simply
  /// omits the distance line rather than showing a made-up one.
  PeerEntry? _selfOrNull() {
    final seed = c.selfSeed;
    return seed == null ? null : c.peers[seed];
  }

  // --- sharing ------------------------------------------------------------

  Future<void> _toggleShare() async {
    final l = L.of(context);
    // A start or stop is already in flight. Without this, a double tap would
    // start two platform sessions, and the second would orphan the first.
    if (c.toggling) return;
    if (c.sharing) {
      await c.stopSharing();
      return;
    }

    // Ask only when we have to. Re-prompting someone who already granted it is
    // noise, and on iOS the system would not show a prompt twice anyway.
    LocationPermissionState state;
    try {
      state = await HereBeeLocation.checkPermission();
      if (state == LocationPermissionState.notDetermined) {
        state = await c.requestLocationPermission();
      }
    } on PlatformException {
      // Both platforms answer "pending" when a dialog is already up. A second
      // tap must not surface as an unhandled exception.
      return;
    }
    if (!mounted) return;

    switch (state) {
      case LocationPermissionState.whileInUse:
      case LocationPermissionState.coarseOnly:
        break;
      case LocationPermissionState.servicesDisabled:
        _toast(l.geoUnavailable);
        return;
      case LocationPermissionState.deniedForever:
        // The system will not ask again, so a plain refusal message would be a
        // dead end. Offer the only route that still works.
        _toast(l.geoDenied, actionLabel: l.close, onAction: c.openAppSettings);
        return;
      case LocationPermissionState.denied:
      case LocationPermissionState.notDetermined:
        // On Android "denied" is the ordinary "declined once" state and the app
        // does not re-prompt, so a bare refusal would be a dead end here too.
        _toast(l.geoDenied, actionLabel: l.batteryOpen, onAction: c.openAppSettings);
        return;
    }

    try {
      await c.startSharing(
        notificationTitle: l.notifSharingTitle,
        notificationBody: l.notifSharingBody,
        notificationStopLabel: l.notifStop,
      );
    } on LocationException catch (e) {
      if (!mounted) return;
      _toast(
        switch (e.code) {
          'servicesDisabled' => l.geoUnavailable,
          // Android suppressed the ongoing notification, so there would be no
          // Stop button. Settings is the only way back.
          'notifications' => l.geoDenied,
          _ => l.noGeo,
        },
        actionLabel: e.code == 'notifications' ? l.batteryOpen : null,
        onAction: e.code == 'notifications' ? c.openAppSettings : null,
      );
      return;
    }
    if (!mounted) return;

    // Say what happens next. People put the phone in a pocket expecting this to
    // keep working, and on Android it sometimes will not.
    if (c.batteryRisk && !_batteryHintShown) {
      _batteryHintShown = true;
      _toast(l.batteryWarning,
          duration: const Duration(seconds: 10),
          actionLabel: l.batteryOpen,
          onAction: c.openBatterySettings);
    } else if (!c.batteryRisk) {
      _toast(l.bgNote, duration: const Duration(seconds: 6));
    }
  }

  void _toast(
    String message, {
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context)
      // One message at a time, and never stacked: several queued snackbars sit
      // on top of the dock for a minute and hide the Stop button.
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        // Clears the dock. A floating snackbar defaults to the bottom edge,
        // which is exactly where the primary control lives.
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 150 + MediaQuery.paddingOf(context).bottom,
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ));
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
