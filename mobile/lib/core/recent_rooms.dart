/// The rooms this device entered recently, so the app can open where you left
/// off and offer the last few rooms for re-entry.
///
/// This is the one place the app keeps room secrets, and a secret is the key.
/// So the list is small (five rooms), short-lived (three days), deletable per
/// entry, and stored in the platform's secure storage (Keychain on iOS, the
/// Keystore-backed store on Android), never in plain preferences. The relay
/// never learns about it; nothing here is transmitted.
///
/// Rooms are ephemeral on the relay, but the secret always derives the same
/// room id, so re-entering later simply recreates the room, and anyone else
/// with the link lands in the same one.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the encoded list lives. One value, read once, rewritten on change.
abstract class SecretStore {
  Future<String?> read();
  Future<void> write(String? value);
}

/// Platform secure storage. The item is bound to this device (no iCloud
/// Keychain sync) and readable only after the first unlock.
class SecureSecretStore implements SecretStore {
  SecureSecretStore()
      : _storage = const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        );

  static const String _key = 'herebee.recentRooms';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      // Corrupt or unreadable keychain item (e.g. after an OS restore). Treat
      // as empty rather than crash the launch; the next write replaces it.
      return null;
    }
  }

  @override
  Future<void> write(String? value) =>
      value == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: value);
}

/// In-memory store for tests and for the widget harness.
class MemorySecretStore implements SecretStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
}

@immutable
class RecentRoom {
  const RecentRoom({required this.secret, required this.lastEntered, this.seeds = const []});

  final String secret;
  final DateTime lastEntered;

  /// Identity seeds of peers seen in this room, newest first, capped. Names are
  /// derived from these locally in the current UI language, exactly as on the
  /// map, so the list can say who you met there without storing names.
  final List<String> seeds;

  Map<String, Object> toJson() => {
        's': secret,
        't': lastEntered.millisecondsSinceEpoch,
        'p': seeds,
      };

  static RecentRoom? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = raw['s'];
    final t = raw['t'];
    final p = raw['p'];
    if (s is! String || s.isEmpty || t is! int) return null;
    return RecentRoom(
      secret: s,
      lastEntered: DateTime.fromMillisecondsSinceEpoch(t),
      seeds: p is List ? p.whereType<String>().toList() : const [],
    );
  }
}

class RecentRooms extends ChangeNotifier {
  RecentRooms(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const int maxRooms = 5;
  static const int maxSeeds = 5;
  static const Duration ttl = Duration(days: 3);
  static const int _version = 1;

  final SecretStore _store;
  final DateTime Function() _clock;
  List<RecentRoom> _rooms = const [];
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Newest first. Expired entries are dropped on read, so a stale list can
  /// never be shown; the file is pruned on the next write.
  List<RecentRoom> get rooms {
    final cutoff = _clock().subtract(ttl);
    return List.unmodifiable(_rooms.where((r) => r.lastEntered.isAfter(cutoff)));
  }

  RecentRoom? get latest => rooms.isEmpty ? null : rooms.first;

  RecentRoom? byId(String secret) {
    for (final r in rooms) {
      if (r.secret == secret) return r;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _rooms = _decode(await _store.read());
    _loaded = true;
    notifyListeners();
  }

  /// Record that the user entered [secret] now. Moves it to the front and
  /// keeps whatever was known about it.
  Future<void> touch(String secret) async {
    final existing = byId(secret);
    final updated = RecentRoom(
      secret: secret,
      lastEntered: _clock(),
      seeds: existing?.seeds ?? const [],
    );
    await _replace([updated, ...rooms.where((r) => r.secret != secret)]);
  }

  /// Remember peers met in [secret]. No-op unless the room is listed and
  /// something is actually new, so calling this on every controller tick is
  /// cheap and never rewrites the store needlessly.
  Future<void> sawPeers(String secret, Iterable<String> seeds) async {
    final existing = byId(secret);
    if (existing == null) return;
    final fresh = seeds.where((s) => !existing.seeds.contains(s)).toList();
    if (fresh.isEmpty) return;
    final merged = [...fresh, ...existing.seeds].take(maxSeeds).toList();
    await _replace([
      for (final r in rooms)
        if (r.secret == secret)
          RecentRoom(secret: r.secret, lastEntered: r.lastEntered, seeds: merged)
        else
          r,
    ]);
  }

  Future<void> forget(String secret) => _replace(rooms.where((r) => r.secret != secret).toList());

  /// Forgets every room except [keep], the one currently open, which the user
  /// is still in and would lose the way back to.
  Future<void> forgetAll({String? keep}) =>
      _replace(rooms.where((r) => r.secret == keep).toList());

  Future<void> _replace(List<RecentRoom> next) async {
    _rooms = next.take(maxRooms).toList();
    await _store.write(_rooms.isEmpty ? null : _encode(_rooms));
    notifyListeners();
  }

  static String _encode(List<RecentRoom> rooms) =>
      jsonEncode({'v': _version, 'rooms': [for (final r in rooms) r.toJson()]});

  static List<RecentRoom> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != _version) return const [];
      final list = decoded['rooms'];
      if (list is! List) return const [];
      return list.map(RecentRoom.fromJson).whereType<RecentRoom>().toList();
    } catch (_) {
      return const [];
    }
  }
}
