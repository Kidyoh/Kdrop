/// How close a peer appears to be, based on its smoothed BLE signal.
enum Closeness { touching, near, inRange, far }

/// Turns a noisy stream of BLE RSSI samples into "the phones are touching"
/// events.
///
/// RSSI jumps around by ±10 dBm from sample to sample, so a single strong
/// reading is not enough. Each device's signal is smoothed with an exponential
/// moving average, and a touch fires only after [requiredSamples] consecutive
/// smoothed readings at or above [touchThreshold]. Once fired, the device must
/// drift back below [releaseThreshold] (hysteresis) and [cooldown] must pass
/// before it can fire again, so holding the phones together does not spam
/// transfers.
class ProximityDetector {
  ProximityDetector({
    this.touchThreshold = -40,
    this.releaseThreshold = -55,
    this.requiredSamples = 3,
    this.smoothing = 0.5,
    this.cooldown = const Duration(seconds: 4),
    this.gapReset = const Duration(seconds: 2),
  }) : assert(releaseThreshold < touchThreshold),
       assert(smoothing > 0 && smoothing <= 1);

  /// Smoothed RSSI (dBm) at or above which the phones count as touching.
  double touchThreshold;

  /// Smoothed RSSI the signal has to fall below before re-arming.
  double releaseThreshold;
  final int requiredSamples;

  /// EMA weight of the newest sample, in (0, 1].
  final double smoothing;
  final Duration cooldown;

  /// A gap this long between samples discards the old average.
  final Duration gapReset;

  final Map<String, _Track> _tracks = {};

  /// Feeds one RSSI sample for [id]. Returns true if this sample starts a new
  /// touch.
  bool addSample(String id, int rssi, DateTime at) {
    final track = _tracks.putIfAbsent(id, _Track.new);
    final last = track.lastSampleAt;
    if (track.smoothed == null || last == null || at.difference(last) > gapReset) {
      track.smoothed = rssi.toDouble();
      track.streak = 0;
    } else {
      track.smoothed = smoothing * rssi + (1 - smoothing) * track.smoothed!;
    }
    track.lastSampleAt = at;
    final value = track.smoothed!;

    if (track.engaged) {
      if (value < releaseThreshold) {
        track.engaged = false;
        track.streak = 0;
      }
      return false;
    }

    track.streak = value >= touchThreshold ? track.streak + 1 : 0;
    if (track.streak < requiredSamples) return false;

    final lastTouch = track.lastTouchAt;
    if (lastTouch != null && at.difference(lastTouch) < cooldown) return false;

    track.engaged = true;
    track.lastTouchAt = at;
    track.streak = 0;
    return true;
  }

  /// Latest smoothed RSSI for [id], if we have heard from it.
  double? smoothedRssi(String id) => _tracks[id]?.smoothed;

  Closeness? closeness(String id) {
    final value = smoothedRssi(id);
    if (value == null) return null;
    if (value >= touchThreshold) return Closeness.touching;
    if (value >= -60) return Closeness.near;
    if (value >= -75) return Closeness.inRange;
    return Closeness.far;
  }

  /// All devices with a smoothed signal, keyed by device id.
  Map<String, double> get snapshot => {
        for (final e in _tracks.entries)
          if (e.value.smoothed != null) e.key: e.value.smoothed!,
      };

  /// Forgets devices that have not been heard from within [staleAfter].
  /// Returns true if anything was removed.
  bool prune(DateTime now, {Duration staleAfter = const Duration(seconds: 6)}) {
    final before = _tracks.length;
    _tracks.removeWhere((_, t) {
      final last = t.lastSampleAt;
      return last == null || now.difference(last) > staleAfter;
    });
    return _tracks.length != before;
  }

  void reset() => _tracks.clear();
}

class _Track {
  double? smoothed;
  DateTime? lastSampleAt;
  DateTime? lastTouchAt;
  int streak = 0;
  bool engaged = false;
}
