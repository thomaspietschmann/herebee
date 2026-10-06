/// The one screen: a full-bleed map with the HUD floating over it.
///
/// Layout follows the web client — brand chip top left, roster top right, dock
/// at the bottom — so somebody who used the link in a browser recognises the app
/// immediately.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:herebee_location/herebee_location.dart';
import 'package:maplibre/maplibre.dart';

import '../../app_config.dart';
import '../../core/names.dart';
import '../../core/peer_state.dart';
import '../../core/recent_rooms.dart';
import '../../core/storage.dart';
import '../../core/style_guard.dart';
import '../../l10n/app_localizations.dart';
import '../hud/hud.dart';
import '../map/auto_fit.dart';
import '../map/bee_marker.dart';
import '../map/follow_drag.dart';
import '../map/marker_menu.dart';
import '../sheets/sheets.dart';
import '../../ui/floor_grid.dart';
import '../../ui/tokens.dart';
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

  /// Switch to another room: a remembered one, a pasted link, or a new one.
  final void Function(RoomsChoice choice) onOpenRoom;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WidgetsBindingObserver {
  MapController? _map;
  StreamSubscription<String>? _panSub;
  StreamSubscription<String>? _messageSub;

  /// The seed whose bubble menu is open, or null. Only ever one at a time.
  String? _openMenuSeed;
  bool _welcomeShown = false;

  String? _style;
  int _styleGeneration = 0;
  Geographic _mapCenter = _initialCenter;
  double _mapZoom = _initialZoom;
  String? _styleTheme;
  String? _styleLoadingTheme;
  String? _styleLocale;
  bool _styleLoading = false;
  bool _styleFailed = false;
  Timer? _styleRetry;

  final AutoFit _autoFit = AutoFit();

  final ValueNotifier<double> _followStretch = ValueNotifier(0);
  bool _holding = false;
  bool _freeDrag = false;
  String? _burstSeed;
  Timer? _burstTimer;

  final GlobalKey _brandKey = GlobalKey();
  final GlobalKey _hintKey = GlobalKey();
  final GlobalKey _controlsKey = GlobalKey();

  RoomController get c => widget.controller;

  void _moveCamera(Future<void> move) => unawaited(move.catchError((Object _) {}));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _panSub = c.panRequests.listen(_panTo);
    _messageSub = c.messageEvents.listen(_onMessage);
    c.addListener(_onControllerChange);
    _followStretch.addListener(_closeMenuOnStretch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenGate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _styleLocale = Localizations.localeOf(context).languageCode;
    _syncStyle();
  }

  /// The map theme to show, as named in the style URL.
  String _wantTheme() => switch (c.mapTheme) {
        MapThemePref.auto => MediaQuery.platformBrightnessOf(context) == Brightness.dark ? 'dark' : 'light',
        final pref => pref.name,
      };

  void _syncStyle() {
    if (!mounted || _styleLocale == null) return;
    if (_styleRetry?.isActive ?? false) return;
    final theme = _wantTheme();
    if (_styleLoading) {
      if (_styleLoadingTheme == theme) return;
    } else if (_style != null && _styleTheme == theme) {
      return;
    }
    unawaited(_loadStyle(theme));
  }

  Future<void> _loadStyle(String theme) async {
    final locale = _styleLocale;
    if (locale == null) return;
    _styleLoading = true;
    _styleLoadingTheme = theme;
    _styleRetry?.cancel();
    String? style;
    try {
      style = await StyleGuard(c.origin).fetch(AppConfig.styleUrl(c.origin, locale, theme: theme));
    } on StyleRejected {
      style = null;
    }
    if (_styleLoadingTheme != theme) return;
    _styleLoading = false;
    if (!mounted) return;
    if (style == null) {
      setState(() => _styleFailed = true);
      _styleRetry = Timer(const Duration(seconds: 10), _syncStyle);
      return;
    }
    final camera = _map?.camera;
    setState(() {
      if (camera != null) {
        _mapCenter = camera.center;
        _mapZoom = camera.zoom;
      }
      if (_style != null) {
        _map = null;
        _styleGeneration++;
      }
      _style = style;
      _styleTheme = theme;
      _styleFailed = false;
    });
    _syncStyle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_panSub?.cancel());
    unawaited(_messageSub?.cancel());
    c.removeListener(_onControllerChange);
    _styleRetry?.cancel();
    _burstTimer?.cancel();
    _followStretch.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Standby can leave the socket frozen; rebuilding it is cheap and the only
    // reliable way to notice.
    if (state == AppLifecycleState.resumed) {
      c.resume();
      c.recenterFollow();
    }
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
    _syncStyle();
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
    await showWelcomeSheet(context, origin: c.origin);
    if (!mounted) return;
    await c.enter();
  }

  Future<void> _openRooms() async {
    final choice = await showRoomsSheet(
      context,
      recent: widget.recent,
      currentSecret: c.secret,
      nameFor: (room, seed) => room.secret == c.secret
          ? c.resolveName(seed)
          : (room.roomId.isEmpty ? null : c.storage.customName(room.roomId, seed)) ??
              nameFromSeed(seed, c.languageCode),
    );
    if (!mounted || choice == null) return;
    widget.onOpenRoom(choice);
  }

  void _onMessage(String seed) {
    if (!mounted) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final entry = c.peers[seed];
    final message = entry?.message;
    if (entry == null || message == null) return;
    final l = L.of(context);
    final name = c.identityFor(seed).name;
    unawaited(HapticFeedback.lightImpact());
    unawaited(SemanticsService.sendAnnouncement(
      View.of(context),
      l.sayAnnounce(name, message),
      Directionality.of(context),
    ));
    if (c.bubblesVisible && _onScreen(entry)) return;
    _toast('$name: $message', actionLabel: l.menuZoomAria, onAction: () => _goTo(seed));
  }

  bool _onScreen(PeerEntry entry) {
    final map = _map;
    if (map == null) return false;
    final p = map.toScreenLocations([Geographic(lon: entry.position.lng, lat: entry.position.lat)]).first;
    return (Offset.zero & MediaQuery.sizeOf(context)).contains(p);
  }

  void _panTo(String seed) {
    if (_holding) return;
    final entry = c.peers[seed];
    final map = _map;
    if (entry == null || map == null) return;
    _moveCamera(map.animateCamera(
      center: Geographic(lon: entry.position.lng, lat: entry.position.lat),
      nativeDuration: const Duration(milliseconds: 500),
    ));
  }

  void _closeMenuOnStretch() {
    if (_followStretch.value > 0 && _openMenuSeed != null && mounted) {
      setState(() => _openMenuSeed = null);
    }
  }

  void _snapBackToFollowed() {
    final seed = c.followSeed;
    final entry = seed == null ? null : c.peers[seed];
    final map = _map;
    if (entry == null || map == null) return;
    _moveCamera(map.animateCamera(
      center: Geographic(lon: entry.position.lng, lat: entry.position.lat),
      nativeDuration: const Duration(milliseconds: 260),
    ));
  }

  void _burstFollow() {
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _freeDrag = true);
    _autoFit.cameraTaken();
    _popFollow();
  }

  void _popFollow() {
    final seed = c.followSeed;
    if (seed == null) return;
    _burstTimer?.cancel();
    setState(() => _burstSeed = seed);
    _burstTimer = Timer(const Duration(milliseconds: 560), () {
      if (mounted) setState(() => _burstSeed = null);
    });
    c.dropFollow();
  }

  void _goTo(String seed) {
    final entry = c.peers[seed];
    final map = _map;
    if (entry == null || map == null) return;
    final zoom = (map.camera?.zoom ?? _initialZoom).clamp(16.0, 22.0);
    _moveCamera(map.animateCamera(
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
    _moveCamera(map.fitBounds(
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
        if (reason == CameraChangeReason.apiGesture && c.followSeed == null && !_freeDrag) {
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
      final pinned = entry.seed == c.followSeed || entry.seed == _burstSeed;
      return Marker(
        point: Geographic(lon: entry.position.lng, lat: entry.position.lat),
        size: beeMarkerSize,
        alignment: beeMarkerAlignment,
        child: BeeMarker(
          identity: identity,
          entry: entry,
          now: now,
          isSelf: entry.isSelf,
          menuOpen: entry.seed == _openMenuSeed,
          bubblesVisible: c.bubblesVisible,
          followStretch: pinned ? _followStretch : null,
          pinBursting: entry.seed == _burstSeed,
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
    final openSeed = _openMenuSeed;
    final openEntry = openSeed == null ? null : c.peers[openSeed];
    final tk = HereBeeTokens.of(context);
    final gridLine = tk.gridLine;

    return Scaffold(
      backgroundColor: tk.ink,
      body: Stack(
        children: [
          // Positioned.fill, not a bare child: a Stack hands non-positioned
          // children LOOSE constraints, and the native map view then sizes
          // itself to something arbitrary instead of the screen.
          Positioned.fill(
            child: _style == null ? const SizedBox.shrink() : MapLibreMap(
              key: ValueKey(_styleGeneration),
              options: MapOptions(
                initStyle: _style!,
                initCenter: _mapCenter,
                initZoom: _mapZoom,
                // Location comes from peers, not from the camera; keep the
                // canvas gesture-friendly and upright, like the web client.
                gestures: const MapGestures(pan: true, zoom: true, rotate: false, pitch: false),
              ),
              onMapCreated: (controller) {
                _map = controller;
                // Peers may have arrived before the native view existed.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _maybeAutoFit();
                  c.recenterFollow();
                });
              },
              onEvent: _onMapEvent,
              children: [
                if (c.followSeed != null || _freeDrag)
                  FollowDragLayer(
                    stretch: _followStretch,
                    onActive: (active) => _holding = active,
                    onBurst: _burstFollow,
                    onSnapBack: _snapBackToFollowed,
                    onTap: () {
                      if (_openMenuSeed != null) setState(() => _openMenuSeed = null);
                    },
                    onDone: () {
                      if (mounted) setState(() => _freeDrag = false);
                    },
                  ),
                WidgetLayer(markers: _markers(context), allowInteraction: true),
                MarkerMenu(
                  data: openEntry == null ? null : _menuData(openEntry),
                  bounds: _menuBounds(context),
                  onClose: () {
                    if (mounted && _openMenuSeed != null) setState(() => _openMenuSeed = null);
                  },
                ),
              ],
            ),
          ),
          // Synthwave's floor grid: over the map, under the HUD, never in the
          // way of a touch.
          if (gridLine != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.sizeOf(context).height * tk.gridHeight,
              child: IgnorePointer(child: FloorGrid(line: gridLine, wash: tk.gridWash)),
            ),
          if (_styleFailed && _style == null)
            Positioned(
              left: 16,
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(child: _FatalBanner(message: l.mapUnavailable)),
            ),
          Hud(
            controller: c,
            onFitAll: () {
              _popFollow();
              _fitAll();
            },
            onGoTo: (seed) {
              if (c.followSeed != null && c.followSeed != seed) _popFollow();
              _goTo(seed);
            },
            onShareLink: () => shareRoomLink(context, c.roomLink),
            onToggleShare: _toggleShare,
            onInfo: () => showInfoSheet(context, controller: c),
            onRooms: _openRooms,
            brandKey: _brandKey,
            hintKey: _hintKey,
            controlsKey: _controlsKey,
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

  MarkerMenuData _menuData(PeerEntry entry) => MarkerMenuData(
        identity: c.identityFor(entry.seed),
        entry: entry,
        following: c.followSeed == entry.seed,
        connected: c.connection == LinkState.on,
        referenceEntry: _selfOrNull(),
        onRename: () async {
          setState(() => _openMenuSeed = null);
          final name = await showRenameSheet(
            context,
            current: c.plainName(entry.seed),
            hasCustom: c.customName(entry.seed) != null,
          );
          if (name == null) return;
          await c.rename(entry.seed, name.isEmpty ? null : name);
          // Our own name is never shared without asking.
          if (entry.seed == c.selfSeed && name.isNotEmpty && mounted) {
            await c.setSharesName(await askShareName(context, name));
          }
        },
        onZoom: () => _goTo(entry.seed),
        onToggleFollow: () => c.toggleFollow(entry.seed),
        onSay: entry.isSelf && c.sharing
            ? () async {
                setState(() => _openMenuSeed = null);
                final text = await showSaySheet(context, current: c.ownMessage?.text);
                if (text == null || !mounted) return;
                c.setOwnMessage(text.isEmpty ? null : text);
              }
            : null,
      );

  Rect _menuBounds(BuildContext context) {
    const inset = 8.0;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    Rect? rectOf(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    final top = rectOf(_brandKey)?.bottom ?? padding.top + 56;
    final dock = rectOf(c.sharing ? _controlsKey : _hintKey)?.top ?? size.height - 160;
    return Rect.fromLTRB(inset, top + inset, size.width - inset, dock - inset);
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
