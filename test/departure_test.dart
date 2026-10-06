import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jegd/game/airport_game.dart';
import 'package:jegd/game/airport_layout.dart';
import 'package:jegd/game/missions.dart';
import 'package:jegd/game/shift.dart';

void main() {
  test(
    'Departure direction follows terminal placement and keeps the longitudinal axis',
    () {
      for (final mission in Mission.all) {
        final layout = AirportLayout(
          mission.location,
          mission.deadlines.length,
        );
        for (var gate = 0; gate < layout.count; gate++) {
          final delta = layout.departureOffset(gate, 1);
          if (mission.location != 0 || gate == 0) {
            expect(delta.dx, lessThan(0));
            expect(delta.dy, greaterThan(0));
          } else {
            expect(delta.dx, greaterThan(0));
            expect(delta.dy, lessThan(0));
          }
          expect(delta.dy / delta.dx, closeTo(-205 / 440, 1e-10));
          expect(layout.departureOffset(gate, 0), Offset.zero);
        }
      }
    },
  );
  test('Shared forward-tow corridor waits for the lower aircraft to leave', () {
    for (final mission in [Mission.all[1], Mission.all[2], Mission.all.last]) {
      final shift = Shift(mission: mission);
      final flight = shift.flights[1];
      for (final service in Service.values.where((s) => s != Service.tug)) {
        flight.jobs[service] = JobState.done;
      }
      for (final task in shift.tasks) {
        task.completedAt = 0;
      }
      if (mission.location == 0) {
        expect(shift.dispatch(flight, Service.tug), isTrue);
      } else {
        expect(shift.blocked(flight, Service.tug), contains('A1'));
        expect(shift.dispatch(flight, Service.tug), isFalse);
        shift.flights[0].departedAt = 0;
        expect(shift.dispatch(flight, Service.tug), isTrue);
      }
    }
  });
  test(
    'Aircraft and tug move together and leave every viewport before completion',
    () {
      for (final mission in Mission.all) {
        final shift = Shift(mission: mission)..paused = true;
        final game = AirportGame(shift, () {});
        for (final size in [
          Vector2(375, 350),
          Vector2(429, 580),
          Vector2(1100, 450),
        ]) {
          game.onGameResize(size);
          for (final f in shift.flights) {
            game.focusGate(f.gate);
            final tug = shift.vehicles[Service.tug]!;
            tug.flight = f;
            tug.phase = VehiclePhase.servicing;
            final start = shift.layout.nodes['port${f.gate}.4']!;
            for (final progress in [0.0, .25, .5, .75, 1.0]) {
              f.progress[Service.tug] = progress;
              final aircraft = game.aircraftRect(f);
              final vehicle = game.vehicleView(tug)!;
              expect(
                (vehicle.position -
                        Offset(start.x, start.y) -
                        (aircraft.topLeft - game.planeRects[f.gate].topLeft))
                    .distance,
                lessThan(1e-8),
              );
              if (progress == 1) {
                expect(aircraft.overlaps(game.visibleWorld), isFalse);
                expect(
                  game.visibleWorld.inflate(75).contains(vehicle.position),
                  isFalse,
                );
              }
            }
            expect(shift.layout.edgeArea('tow${f.gate}', 'hub'), isNull);
            f.progress[Service.tug] = 0;
          }
        }
      }
    },
  );
}
