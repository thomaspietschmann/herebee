/// What this app persists in plain preferences: any names the user typed, and
/// whether their own name is shared.
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

import 'crypto.dart';
import 'recent_rooms.dart';

import 'package:shared_preferences/shared_preferences.dart';

const String _legacySeedKey = 'herebee.seed';
const String _legacyCidKey = 'herebee.cid';
const String _namePrefix = 'herebee.name.';
const String _ownNamePrefix = 'herebee.ownName.';
const String _shareNamePrefix = 'herebee.shareName.';
const String _legacyShareNameKey = 'herebee.shareName';

/// Matches the browser's token shape (see `mintToken` in client/src/main.ts).
String mintToken() {
  final rnd = Random.secure();
  return List<int>.generate(9, (_) => rnd.nextInt(256))
      .fold<String>('', (acc, b) => acc + b.toRadixString(36));
}

class Storage {
  Storage(this._prefs, this._device);

  static Future<Storage> open({SecretStore? device}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyCidKey);
    await prefs.remove(_legacySeedKey);
    await prefs.remove(_legacyShareNameKey);
    for (final key in prefs.getKeys().toList()) {
      if (RegExp(r'^herebee\.name\.[^.]+$').hasMatch(key)) await prefs.remove(key);
    }
    return Storage(prefs, device ?? SecureSecretStore('herebee.device'));
  }

  final SharedPreferences _prefs;
  final SecretStore _device;
  Future<String>? _deviceSecret;

  Future<String> roomSeed(String roomId) async => deriveRoomSeed(await (_deviceSecret ??= _loadDeviceSecret()), roomId);

  Future<String> _loadDeviceSecret() async {
    final existing = await _device.read();
    if (existing != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(existing)) return existing;
    final minted = generateSecret();
    try {
      await _device.write(minted);
    } catch (_) {
      return minted;
    }
    return minted;
  }

  /// Ephemeral reconnect token. Lets the relay drop THIS client's own stale
  /// socket when it reconnects. Never an identity; see shared/PROTOCOL.md.
  Future<String> cid() async => _processCid;

  static final String _processCid = mintToken();

  /// A name the user typed for a peer. Local only, never transmitted.
  String? customName(String roomId, String seed) => _prefs.getString('$_namePrefix$roomId.$seed');

  Future<void> setCustomName(String roomId, String seed, String? name) =>
      _setOrRemove('$_namePrefix$roomId.$seed', name);

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

  Future<void> _setOrRemove(String key, String? name) async {
    if (name == null || name.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, name);
    }
  }
}
