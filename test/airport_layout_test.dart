import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jegd/game/airport_game.dart';
import 'package:jegd/game/airport_layout.dart';
import 'package:jegd/game/missions.dart';
import 'package:jegd/game/shift.dart';

void main() {
  for (final mission in Mission.all) {
    test(
      '${mission.title}: visible roads stay inside the apron; off-screen links may leave it',
      () {
        final map = AirportLayout(mission.location, mission.deadlines.length);
        for (final entry in map.edges.entries) {
          final edge = entry.value;
          final names = entry.key.split('|');
          if (map.edgeArea(names[0], names[1]) == null) continue;
          expect(edge[0].distanceTo(edge[1]), greaterThan(0));
          for (final p in edge) {
            expect(p.x, inInclusiveRange(0, map.width));
            expect(p.y, inInclusiveRange(0, map.height));
          }
        }
      },
    );
  }
  test(
    'Fixed screens fit aircraft and base; coastal picking respects mirrored view',
    () {
      for (final mission in Mission.all) {
        final game = AirportGame(Shift(mission: mission), () {});
        for (final viewport in [
          Vector2(390, 560),
          Vector2(375, 350),
          Vector2(1100, 450),
        ]) {
          game.onGameResize(viewport);
          Offset screen(Offset world) {
            var p =
                (world - game.viewCenter) * game.viewScale + game.screenCenter;
            if (game.mirrorScene) p = Offset(viewport.x - p.dx, p.dy);
            return p;
          }

          final frame = Rect.fromLTWH(0, 0, viewport.x, viewport.y);
          for (var i = 0; i < game.shift.flights.length; i++) {
            game.focusGate(i);
            expect(game.visibleGates, contains(i));
            final r = game.planeRects[i];
            for (final corner in [
              r.topLeft,
              r.topRight,
              r.bottomLeft,
              r.bottomRight,
            ]) {
              expect(frame.contains(screen(corner)), isTrue);
            }
            final p = screen(r.center);
            expect(game.gateAt(p.dx, p.dy), i);
          }
          game.focusBase();
          expect(game.visibleGates, isEmpty);
          for (var i = 0; i < 6; i++) {
            final p = game.shift.layout.nodes['park$i']!;
            expect(
              frame.deflate(8).contains(screen(Offset(p.x - 60, p.y))),
              isTrue,
            );
            expect(
              frame.deflate(8).contains(screen(Offset(p.x + 60, p.y))),
              isTrue,
            );
          }
        }
      }
    },
  );
  test('New airports and remote areas use separate authored backgrounds', () {
    final assets = <String>{};
    for (final mission in [Mission.all[2], Mission.all.last]) {
      final game = AirportGame(Shift(mission: mission), () {});
      for (var i = 0; i < game.sceneCount; i++) {
        game.sceneIndex = i;
        expect(assets.add(game.sceneAsset), isTrue);
      }
    }
    expect(assets.length, 5);
  });
  test(
    'Boarding target is the forward passenger door in the source artwork',
    () {
      final sill = AirportLayout.doorSill(
        const Rect.fromLTWH(0, 0, 1536, 1024),
      );
      expect(sill.dx, inInclusiveRange(352, 394));
      expect(sill.dy, inInclusiveRange(815, 835));
    },
  );
}
