/// End-to-end crypto. The whole security model lives here.
///
/// A direct port of `client/src/crypto.ts`; see `shared/PROTOCOL.md` for the
/// contract. A 256-bit secret lives in the link fragment and never reaches the
/// server. From it, HKDF-SHA256 derives two independent values:
///   - roomId: 16 bytes of key material + an 8-byte SHA-256 checksum, base64url
///     (32 chars). Only this leaves the device, purely as a routing handle.
///   - key:    an AES-256-GCM key that NEVER leaves the device.
///
/// One layout detail decides whether this app can talk to the browser at all:
/// WebCrypto returns ciphertext with the 16-byte GCM tag APPENDED, while this
/// package keeps the MAC separate. The packing below reproduces the browser's
/// byte order exactly.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const List<int> _fixedSalt = [
  // UTF-8 of "localizer/v1"
  0x6c, 0x6f, 0x63, 0x61, 0x6c, 0x69, 0x7a, 0x65, 0x72, 0x2f, 0x76, 0x31,
];

const int ivBytes = 12;
const int tagBytes = 16;
const int roomIdLength = 32;

final AesGcm _aesGcm = AesGcm.with256bits();

String bytesToB64url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List b64urlToBytes(String s) {
  final pad = s.length % 4 == 0 ? '' : '=' * (4 - s.length % 4);
  return base64Url.decode(s + pad);
}

/// New 256-bit room secret, base64url. This IS the capability — share carefully.
String generateSecret() {
  final rnd = Random.secure();
  return bytesToB64url(List<int>.generate(32, (_) => rnd.nextInt(256)));
}

class RoomKeys {
  const RoomKeys({required this.roomId, required this.key});

  /// Opaque routing handle. The only derived value that leaves the device.
  final String roomId;

  /// AES-256-GCM key. Never transmitted, never persisted.
  final SecretKey key;
}

Future<List<int>> _hkdf(Uint8List secret, String info, int outputBytes) async {
  final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: outputBytes)
      .deriveKey(
        secretKey: SecretKey(secret),
        nonce: _fixedSalt,
        info: utf8.encode(info),
      );
  return derived.extractBytes();
}

Future<RoomKeys> deriveRoomKeys(String secretB64) async {
  final secret = b64urlToBytes(secretB64);

  final idMaterial = await _hkdf(secret, 'room-id', 16);
  final digest = await Sha256().hash(idMaterial);
  final raw = Uint8List(24)
    ..setRange(0, 16, idMaterial)
    ..setRange(16, 24, digest.bytes.sublist(0, 8));

  final keyBytes = await _hkdf(secret, 'aes-key', 32);
  return RoomKeys(roomId: bytesToB64url(raw), key: SecretKey(keyBytes));
}

/// Encrypt with a fresh 96-bit IV and pack as base64url(iv ‖ ciphertext ‖ tag).
Future<String> encryptJson(SecretKey key, Object? value) async {
  final box = await _aesGcm.encrypt(
    utf8.encode(jsonEncode(value)),
    secretKey: key,
    nonce: _aesGcm.newNonce(),
  );
  final packed = Uint8List(box.nonce.length + box.cipherText.length + box.mac.bytes.length)
    ..setRange(0, box.nonce.length, box.nonce)
    ..setRange(box.nonce.length, box.nonce.length + box.cipherText.length, box.cipherText)
    ..setRange(box.nonce.length + box.cipherText.length,
        box.nonce.length + box.cipherText.length + box.mac.bytes.length, box.mac.bytes);
  return bytesToB64url(packed);
}

/// Decrypt a packed blob. Returns null for a wrong key, tampering or garbage —
/// those are normal on a shared relay and must never surface as an error.
Future<Object?> decryptJson(SecretKey key, String dataB64) async {
  try {
    final packed = b64urlToBytes(dataB64);
    if (packed.length < ivBytes + tagBytes) return null;
    final clear = await _aesGcm.decrypt(
      SecretBox(
        packed.sublist(ivBytes, packed.length - tagBytes),
        nonce: packed.sublist(0, ivBytes),
        mac: Mac(packed.sublist(packed.length - tagBytes)),
      ),
      secretKey: key,
    );
    return jsonDecode(utf8.decode(clear));
  } catch (_) {
    return null;
  }
}

/// Verify a room id's self-certifying checksum, exactly as the relay does
/// (`server/src/roomId.ts`). Used to reject a mistyped or truncated link before
/// opening a socket.
Future<bool> isValidRoomId(String roomId) async {
  if (roomId.length != roomIdLength) return false;
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(roomId)) return false;
  final Uint8List raw;
  try {
    raw = b64urlToBytes(roomId);
  } catch (_) {
    return false;
  }
  if (raw.length != 24) return false;
  final expected = (await Sha256().hash(raw.sublist(0, 16))).bytes.sublist(0, 8);
  final actual = raw.sublist(16, 24);
  for (int i = 0; i < 8; i++) {
    if (expected[i] != actual[i]) return false;
  }
  return true;
}
