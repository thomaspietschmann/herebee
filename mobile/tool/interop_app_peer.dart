/// The "app side" of the interop check (see scripts/interop-test.sh).
///
/// Uses the app's real NetClient, so this also exercises the join frame, the
/// app Origin header and the reconnect wiring, not just the crypto.
///
/// Usage: `dart run tool/interop_app_peer.dart <secret> <wsUrl> <resultFile>`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:herebee/core/crypto.dart';
import 'package:herebee/core/net.dart';
import 'package:herebee/core/types.dart';

const String self = 'app-peer';
const String expectPeer = 'web-peer';
const Duration timeout = Duration(seconds: 20);

final LocUpdate myUpdate = const LocUpdate(
  seed: self,
  lat: 48.137154,
  lng: 11.576124,
  acc: 12.25,
  hdg: 91.5,
  spd: 2.5,
  at: 1700000000456,
);

Future<void> main(List<String> args) async {
  final secret = args[0];
  final wsUrl = args[1];
  final resultFile = File(args[2]);

  final keys = await deriveRoomKeys(secret);
  final completer = Completer<Map<String, Object?>>();

  void finish(Map<String, Object?> result) {
    if (!completer.isCompleted) completer.complete(result);
  }

  late final NetClient net;
  net = NetClient(
    endpoint: wsUrl,
    keys: keys,
    cid: 'app-peer-cid',
    clientLabel: 'interop/1.0',
    handlers: NetHandlers(
      onPeer: (id, update) {
        if (update.seed != expectPeer) return;
        if (update is! LocUpdate) return;
        finish({
          'ok': true,
          'roomId': keys.roomId,
          'decrypted': update.toJson(),
        });
      },
      onLeft: (_) {},
      onRequest: () => unawaited(net.broadcast(myUpdate)),
      onStatus: (connected) {
        if (connected) unawaited(net.broadcast(myUpdate));
      },
      onPresence: (_) {},
      onFatal: (reason) => finish({'ok': false, 'error': 'relay rejected: $reason'}),
    ),
  );

  await net.connect();
  final timer = Timer(timeout, () {
    finish({'ok': false, 'error': 'timed out waiting for the web peer', 'roomId': keys.roomId});
  });

  final result = await completer.future;
  timer.cancel();
  await net.close();

  resultFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln('[app-peer] ${jsonEncode(result)}');
  exit(result['ok'] == true ? 0 : 1);
}
