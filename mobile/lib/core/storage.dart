/// The only thing this app persists: an identity seed, a reconnect token, and
/// any names the user typed for other people.
///
/// Deliberately nothing else. There is no "was sharing" flag, because the app
/// never resumes sharing on its own — starting must always come from a tap in
/// the foreground. No location history, no logs, no room list.
/// See docs/mobile-plan.md §3.
library;

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const String _seedKey = 'herebee.seed';
const String _cidKey = 'herebee.cid';
const String _namePrefix = 'herebee.name.';

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

  Future<void> setCustomName(String seed, String? name) async {
    if (name == null || name.isEmpty) {
      await _prefs.remove('$_namePrefix$seed');
    } else {
      await _prefs.setString('$_namePrefix$seed', name);
    }
  }
}
