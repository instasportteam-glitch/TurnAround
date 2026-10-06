import 'dart:math' as math;
import 'dart:ui';

/// One projected body for every angle: no sprite changes or scale jumps.
class ApronBus {
  static const length = 120.0, width = 35.0, height = 25.0;

  static Offset project(
    Offset center,
    double heading,
    double x,
    double y,
    double z,
  ) {
    final yaw = math.atan2(math.sin(heading) / .6, math.cos(heading));
    return center +
        Offset(
          x * math.cos(yaw) - y * math.sin(yaw),
          .6 * (x * math.sin(yaw) + y * math.cos(yaw)) - z,
        );
  }

  static void draw(
    Canvas c,
    Offset center,
    double heading, {
    bool open = false,
  }) {
    Offset p(double x, double y, double z) => project(center, heading, x, y, z);
    void face(List<Offset> points, Color color) {
      c.drawPath(Path()..addPolygon(points, true), Paint()..color = color);
    }

    final ground = [
      p(-60, -17.5, 0),
      p(60, -17.5, 0),
      p(60, 17.5, 0),
      p(-60, 17.5, 0),
    ];
    c.drawPath(
      Path()
        ..addPolygon(ground.map((p) => p + const Offset(3, 4)).toList(), true),
      Paint()
        ..color = const Color(0x99020818)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final sides = [-1.0, 1.0]
      ..sort((a, b) => p(0, a * 18, 0).dy.compareTo(p(0, b * 18, 0).dy));
    // Rear face and front windscreen, then the visible long side and roof.
    for (final x in [-60.0, 60.0]) {
      face([
        p(x, -17.5, 5),
        p(x, 17.5, 5),
        p(x, 17.5, 25),
        p(x, -17.5, 25),
      ], x > 0 ? const Color(0xffb3bdd7) : const Color(0xff655886));
      face([
        p(x, -14, 13),
        p(x, 14, 13),
        p(x, 14, 22),
        p(x, -14, 22),
      ], const Color(0xff193752));
      for (final y in [-12.0, 12.0]) {
        c.drawCircle(
          p(x, y, 8),
          1.9,
          Paint()
            ..color = x > 0 ? const Color(0xffffe6b8) : const Color(0xffe76077),
        );
      }
    }
    for (final side in sides) {
      final y = side * 17.5;
      face(
        [p(-60, y, 5), p(60, y, 5), p(60, y, 25), p(-60, y, 25)],
        side == sides.last ? const Color(0xffc1c8db) : const Color(0xff7585a5),
      );
      face([
        p(-60, y, 6),
        p(60, y, 6),
        p(60, y, 12),
        p(-60, y, 12),
      ], const Color(0xff7050b6));
      for (var i = 0; i < 8; i++) {
        final x = -55.0 + i * 13;
        face([
          p(x, y, 14),
          p(x + 11, y, 14),
          p(x + 11, y, 23),
          p(x, y, 23),
        ], const Color(0xff183b58));
        c.drawLine(
          p(x + 1, y, 22),
          p(x + 9, y, 22),
          Paint()
            ..color = const Color(0xff69a5c9)
            ..strokeWidth = .7,
        );
      }
      for (final x in [-38.0, 38.0]) {
        c.drawOval(
          Rect.fromCenter(center: p(x, y, 5), width: 11, height: 12),
          Paint()..color = const Color(0xff111727),
        );
        c.drawCircle(p(x, y, 5), 2.4, Paint()..color = const Color(0xff8295af));
      }
      // Passenger doors are on the right side only.
      if (side > 0) {
        for (final x in [-12.0, 41.0]) {
          face([
            p(x, y, 5),
            p(x + 12, y, 5),
            p(x + 12, y, 23),
            p(x, y, 23),
          ], open ? const Color(0xff10182c) : const Color(0xff34506a));
          if (!open) {
            c.drawLine(
              p(x + 6, y, 5),
              p(x + 6, y, 23),
              Paint()..color = const Color(0xffa7b7cc),
            );
          }
        }
      }
    }
    face([
      p(-60, -17.5, 25),
      p(60, -17.5, 25),
      p(60, 17.5, 25),
      p(-60, 17.5, 25),
    ], const Color(0xffdae0ee));
    face([
      p(-31, -11, 26),
      p(15, -11, 26),
      p(15, 11, 26),
      p(-31, 11, 26),
    ], const Color(0xff8f9db8));
    for (var x = -26.0; x < 14; x += 5) {
      c.drawLine(
        p(x, -9, 27),
        p(x, 9, 27),
        Paint()
          ..color = const Color(0xff667694)
          ..strokeWidth = 1,
      );
    }
    face([
      p(24, -12, 25.5),
      p(49, -12, 25.5),
      p(49, 12, 25.5),
      p(24, 12, 25.5),
    ], const Color(0xff9673d4));
  }
}
