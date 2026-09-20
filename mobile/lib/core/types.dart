/// Plaintext shapes that live INSIDE the end-to-end-encrypted payload.
/// The relay never sees these — only the ciphertext. Port of
/// `client/src/types.ts`; the JSON keys are part of the wire format.
library;

sealed class PeerUpdate {
  const PeerUpdate(this.seed);

  /// Drives name, avatar and colour on every client.
  final String seed;

  Map<String, dynamic> toJson();
}

class LocUpdate extends PeerUpdate {
  const LocUpdate({
    required String seed,
    required this.lat,
    required this.lng,
    required this.acc,
    required this.hdg,
    required this.spd,
    required this.at,
  }) : super(seed);

  final double lat;
  final double lng;

  /// Accuracy in metres.
  final double? acc;

  /// Heading in degrees, if moving.
  final double? hdg;

  /// Speed in m/s, if moving — gates whether [hdg] is shown.
  final double? spd;

  /// Client timestamp (ms) of this fix.
  final int at;

  @override
  Map<String, dynamic> toJson() => {
        'k': 'loc',
        'seed': seed,
        'lat': lat,
        'lng': lng,
        'acc': acc,
        'hdg': hdg,
        'spd': spd,
        'at': at,
      };
}

class StopUpdate extends PeerUpdate {
  const StopUpdate(super.seed);

  @override
  Map<String, dynamic> toJson() => {'k': 'stop', 'seed': seed};
}

class Position {
  const Position({
    required this.lat,
    required this.lng,
    this.acc,
    this.hdg,
    this.spd,
  });

  final double lat;
  final double lng;
  final double? acc;
  final double? hdg;
  final double? spd;
}
