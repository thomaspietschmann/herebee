/// What this app persists in plain preferences: an identity seed, a reconnect
/// token, any names the user typed, and whether their own name is shared.
/// The user's own name and its sharing choice are kept per room, so a new room
/// never knows what they called themselves elsewhere.
///
/// Deliberately nothing else here. There is no "was sharing" flag, because the
/// app never resumes sharing on its own — starting must always come from a tap
/// in the foreground. No location history, no logs. The short list of recent
/// rooms lives in secure storage instead, see core/recent_rooms.dart.
/// See docs/mobile-plan.md §3.
library;

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const String _seedKey = 'herebee.seed';
const String _cidKey = 'herebee.cid';
const String _namePrefix = 'herebee.name.';
const String _ownNamePrefix = 'herebee.ownName.';
const String _shareNamePrefix = 'herebee.shareName.';
// Older builds kept the user's own name and its sharing choice across rooms.
const String _legacyShareNameKey = 'herebee.shareName';

/// Matches the browser's token shape (see `mintToken` in client/src/main.ts).
String mintToken() {
  final rnd = Random.secure();
  return List<int>.generate(9, (_) => rnd.nextInt(256))
      .fold<String>('', (acc, b) => acc + b.toRadixString(36));
}

class Storage {
  Storage(this._prefs);

  static Future<Storage> open() async => Storage(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Stable identity for this install. Never an account, never a device id;
  /// clearing app data mints a new one and that is the intended escape hatch.
  Future<String> seed() async => _getOrMint(_seedKey);

  /// Ephemeral reconnect token. Lets the relay drop THIS client's own stale
  /// socket when it reconnects. Never an identity; see shared/PROTOCOL.md.
  Future<String> cid() async => _getOrMint(_cidKey);

  Future<String> _getOrMint(String key) async {
    final existing = _prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final minted = mintToken();
    await _prefs.setString(key, minted);
    return minted;
  }

  /// A name the user typed for a peer. Local only, never transmitted.
  String? customName(String seed) => _prefs.getString('$_namePrefix$seed');

  Future<void> setCustomName(String seed, String? name) => _setOrRemove('$_namePrefix$seed', name);

  /// The name the user gave themselves in one room. Goes out, encrypted, only
  /// while [sharesName] is on for that room.
  String? ownName(String roomId) => _prefs.getString('$_ownNamePrefix$roomId');

  Future<void> setOwnName(String roomId, String? name) => _setOrRemove('$_ownNamePrefix$roomId', name);

  /// Whether our own name rides along with our position in this room. Off
  /// unless the user said yes when naming themselves there.
  bool sharesName(String roomId) => _prefs.getBool('$_shareNamePrefix$roomId') ?? false;

  Future<void> setSharesName(String roomId, bool on) async {
    if (on) {
      await _prefs.setBool('$_shareNamePrefix$roomId', true);
    } else {
      await _prefs.remove('$_shareNamePrefix$roomId');
    }
  }

  /// Drop the room-independent own name and sharing flag older builds kept.
  Future<void> dropLegacyOwnName(String seed) async {
    await _prefs.remove('$_namePrefix$seed');
    await _prefs.remove(_legacyShareNameKey);
  }

  Future<void> _setOrRemove(String key, String? name) async {
    if (name == null || name.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, name);
    }
  }
}
