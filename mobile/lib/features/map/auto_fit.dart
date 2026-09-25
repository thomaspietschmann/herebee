/// When the camera should move on its own.
///
/// The map opens on a wide default view. Left there, a room with people in it
/// looks empty, and a phone screen is too small to hunt for bees by hand. So the
/// camera fits everyone whenever a NEW bee appears: peers arriving after entry,
/// and ourselves once sharing starts. It never moves for mere position updates,
/// never while following someone, and not once the user has taken the camera
/// over by hand. Starting to share is treated as a fresh, explicit intent and
/// re-arms the automatic fit.
///
/// Pure state machine with no map dependency, so it can be unit-tested; the
/// room screen feeds it and performs the actual camera move.
library;

class AutoFit {
  /// Seeds that were on the map at the last automatic fit.
  Set<String> _fitted = const {};

  /// The user moved the camera by gesture since the last automatic fit.
  bool _cameraTaken = false;

  bool _wasSharing = false;

  /// A gesture moved the camera: it belongs to the user now.
  void cameraTaken() => _cameraTaken = true;

  /// Whether the camera should fit everyone now, given the current room state.
  /// [seeds] are the bees on the map, our own included once it has a position.
  bool shouldFit({
    required Set<String> seeds,
    required bool sharing,
    required bool following,
  }) {
    if (sharing && !_wasSharing) _cameraTaken = false; // explicit new intent
    _wasSharing = sharing;
    if (following || _cameraTaken || seeds.isEmpty) return false;
    final newcomers = seeds.difference(_fitted);
    // Record departures too, so someone who leaves and comes back is a
    // newcomer again rather than silently ignored.
    _fitted = Set.unmodifiable(seeds);
    return newcomers.isNotEmpty;
  }
}
