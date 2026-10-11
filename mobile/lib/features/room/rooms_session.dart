import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/recent_rooms.dart';
import 'room_controller.dart';

typedef RoomRef = ({String secret, String origin});

typedef RoomMessage = ({RoomRef room, String seed});

class RoomsSession extends ChangeNotifier with WidgetsBindingObserver {
  RoomsSession(this._create, {this.maxRooms = RecentRooms.maxRooms}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final RoomController Function(RoomRef room) _create;
  final int maxRooms;

  final Map<RoomRef, RoomController> _rooms = {};
  final List<RoomRef> _recency = [];
  final Map<RoomRef, int> _unread = {};
  final Map<RoomRef, StreamSubscription<String>> _messageSubs = {};
  final Map<RoomRef, VoidCallback> _readyWatch = {};
  final StreamController<RoomMessage> _elsewhere = StreamController<RoomMessage>.broadcast();
  RoomRef? _active;
  bool _disposed = false;

  List<RoomRef> get joined => List.unmodifiable(_rooms.keys);

  RoomRef? get active => _active;

  RoomController? get activeController => _active == null ? null : _rooms[_active];

  RoomController? operator [](RoomRef room) => _rooms[room];

  bool contains(RoomRef room) => _rooms.containsKey(room);

  bool get full => _rooms.length >= maxRooms;

  bool get isEmpty => _rooms.isEmpty;

  int unread(RoomRef room) => _unread[room] ?? 0;

  int get unreadElsewhere =>
      _unread.entries.where((e) => e.key != _active).fold(0, (sum, e) => sum + e.value);

  Stream<RoomMessage> get messagesElsewhere => _elsewhere.stream;

  RoomController open(RoomRef room) {
    final existing = _rooms[room];
    if (existing != null) {
      _activate(room);
      return existing;
    }
    if (full) throw StateError('room limit reached');
    final controller = _create(room);
    _rooms[room] = controller;
    _messageSubs[room] = controller.messageEvents.listen((seed) {
      if (room == _active) return;
      _unread[room] = unread(room) + 1;
      _elsewhere.add((room: room, seed: seed));
      notifyListeners();
    });
    void watch() {
      if (!controller.ready) return;
      controller.removeListener(_readyWatch.remove(room)!);
      if (!_disposed) notifyListeners();
    }

    _readyWatch[room] = watch;
    controller.addListener(watch);
    _activate(room);
    unawaited(controller.init());
    return controller;
  }

  void _activate(RoomRef room) {
    _active = room;
    _recency
      ..remove(room)
      ..add(room);
    _unread.remove(room);
    notifyListeners();
  }

  void leave(RoomRef room) {
    final controller = _rooms.remove(room);
    if (controller == null) return;
    unawaited(_messageSubs.remove(room)?.cancel());
    _unread.remove(room);
    _recency.remove(room);
    final watch = _readyWatch.remove(room);
    if (watch != null) controller.removeListener(watch);
    controller.dispose();
    if (_active == room) _active = _recency.isEmpty ? null : _recency.last;
    if (!_disposed) notifyListeners();
  }

  void leaveAll() {
    for (final room in _rooms.keys.toList()) {
      leave(room);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    for (final controller in _rooms.values) {
      if (state == AppLifecycleState.resumed) controller.resume();
      switch (state) {
        case AppLifecycleState.resumed:
          controller.setForeground(true);
        case AppLifecycleState.paused:
        case AppLifecycleState.hidden:
        case AppLifecycleState.detached:
          controller.setForeground(false);
        case AppLifecycleState.inactive:
          break;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    leaveAll();
    unawaited(_elsewhere.close());
    super.dispose();
  }
}
