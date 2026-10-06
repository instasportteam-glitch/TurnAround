import 'dart:math' as math;
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jegd/game/airport_game.dart';
import 'package:jegd/game/missions.dart';
import 'package:jegd/game/roads.dart';
import 'package:jegd/game/shift.dart';

void main() {
  test(
    'Every disappearance and reappearance happens fully outside the screen',
    () {
      for (final mission in [
        Mission.all.first,
        Mission.all[2],
        Mission.all.last,
      ]) {
        for (var gate = 0; gate < mission.deadlines.length; gate++) {
          for (final size in [
            Vector2(375, 350),
            Vector2(429, 580),
            Vector2(1100, 450),
          ]) {
            final shift = Shift(mission: mission);
            final game = AirportGame(shift, () {})..onGameResize(size);
            final v = shift.vehicles[Service.bags]!;
            shift.dispatch(shift.flights[gate], Service.bags);
            final areas = [-1, gate < 2 ? 0 : gate - 1];
            final last = <int, Offset?>{};
            var exits = 0, entries = 0;
            for (var tick = 0; tick < 6000; tick++) {
              shift.tick(.05);
              for (final area in areas) {
                game.sceneIndex = area;
                final view = game.vehicleView(v);
                Offset? screen =
                    view == null
                        ? null
                        : (view.position - game.viewCenter) * game.viewScale +
                            game.screenCenter;
                if (screen != null && game.mirrorScene) {
                  screen = Offset(size.x - screen.dx, screen.dy);
                }
                final envelope = Rect.fromLTWH(
                  0,
                  0,
                  size.x,
                  size.y,
                ).inflate(75 * game.viewScale);
                if (last.containsKey(area)) {
                  if (last[area] != null && screen == null) {
                    expect(
                      envelope.contains(last[area]!),
                      isFalse,
                      reason: '${mission.title} A${gate + 1}, exit area $area',
                    );
                    exits++;
                  }
                  if (last[area] == null && screen != null) {
                    expect(
                      envelope.contains(screen),
                      isFalse,
                      reason: '${mission.title} A${gate + 1}, entry area $area',
                    );
                    entries++;
                  }
                }
                last[area] = screen;
              }
              if (tick > 1 && v.phase == VehiclePhase.parked) break;
            }
            expect(exits, 2);
            expect(entries, 2);
          }
        }
      }
    },
  );
  test('Authored visible routes have no acute-angle switchbacks', () {
    for (final mission in Mission.all) {
      final game = AirportGame(Shift(mission: mission), () {})
        ..onGameResize(Vector2(429, 580));
      for (final area in [-1, for (var i = 0; i < game.sceneCount; i++) i]) {
        game.sceneIndex = area;
        for (final points in game.visibleRoads) {
          for (var i = 1; i < points.length - 1; i++) {
            final a = points[i - 1], b = points[i], c = points[i + 1];
            final first = math.atan2(b.y - a.y, b.x - a.x),
                second = math.atan2(c.y - b.y, c.x - b.x);
            final turn =
                math
                    .atan2(math.sin(second - first), math.cos(second - first))
                    .abs();
            expect(
              turn,
              lessThanOrEqualTo(math.pi / 2 + .001),
              reason: '${mission.title} area:$area at ${b.x},${b.y}',
            );
            final before = RoadGeometry.sample(points, i - 1, a.distanceTo(b));
            final after = RoadGeometry.sample(points, i, 0);
            expect(before.position.distanceTo(after.position), lessThan(1e-8));
            expect(
              (math.atan2(before.tangent.y, before.tangent.x) -
                      math.atan2(after.tangent.y, after.tangent.x))
                  .abs(),
              lessThan(1e-8),
            );
          }
        }
      }
    }
  });
}
