import 'dart:math' as math;

/// Calibrated front-to-rear axes in screen space, not ideal atlas slot numbers.
/// Image generation can reorder views, so each sheet has its own angle map.
class VehicleHeading {
  static double delta(double from, double to) =>
      math.atan2(math.sin(to - from), math.cos(to - from));
  static double approach(double from, double to, double maxStep) =>
      from + delta(from, to).clamp(-maxStep, maxStep);
  static const angles = <List<double>>[
    [0, 24, 38, 63, 90, 116, 139, 158, 180, 201, 218, 244, 270, 296, 321, 343],
    [0, 29, 38, 132, 90, 118, 132, 152, 180, 205, 218, 235, 270, 300, 320, 335],
    [0, 30, 42, 65, 90, 123, 135, 157, 180, 211, 224, 242, 270, 312, 326, 337],
    [0, 25, 40, 66, 90, 115, 137, 157, 180, 204, 220, 245, 270, 294, 320, 340],
    [0, 37, 42, 133, 90, 118, 131, 150, 180, 215, 225, 313, 270, 302, 315, 215],
  ];

  /// Adjacent calibrated views, including the wrap from 360 to zero.
  static ({int from, int to, double mix}) blend(double heading, int service) {
    final degrees = (heading * 180 / math.pi) % 360;
    final ordered = <int>[];
    for (var i = 0; i < angles[service].length; i++) {
      if (!ordered.any((j) => angles[service][j] == angles[service][i])) {
        ordered.add(i);
      }
    }
    ordered.sort((a, b) => angles[service][a].compareTo(angles[service][b]));
    for (var i = 0; i < ordered.length; i++) {
      final from = ordered[i], to = ordered[(i + 1) % ordered.length];
      final start = angles[service][from];
      final end = angles[service][to] + (i == ordered.length - 1 ? 360 : 0);
      if (degrees >= start && degrees < end) {
        final t = (degrees - start) / (end - start);
        return (from: from, to: to, mix: t * t * (3 - 2 * t));
      }
    }
    return (from: ordered.first, to: ordered.first, mix: 0);
  }

  static ({int frame, double correction}) pose(double heading, int service) {
    var best = 0, error = double.infinity;
    for (var i = 0; i < 16; i++) {
      final difference =
          delta(angles[service][i] * math.pi / 180, heading).abs();
      if (difference < error) {
        error = difference;
        best = i;
      }
    }
    return (
      frame: best,
      correction: delta(angles[service][best] * math.pi / 180, heading),
    );
  }
}
