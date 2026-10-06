import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:jegd/game/vehicle_heading.dart';
import 'package:jegd/game/roads.dart';
import 'package:jegd/game/shift.dart';

void main() {
  test('Calibrated 16-frame body axis aligns with travel at every angle', () {
    for (var service = 0; service < 5; service++) {
      expect(VehicleHeading.angles[service].length, 16);
      for (var degree = 0; degree < 360; degree++) {
        final heading = degree * math.pi / 180;
        final result = VehicleHeading.pose(heading, service);
        final body =
            VehicleHeading.angles[service][result.frame] * math.pi / 180 +
            result.correction;
        expect(VehicleHeading.delta(body, heading).abs(), lessThan(1e-9));
        expect(result.correction.abs(), lessThan(.5));
      }
    }
  });
  test(
    'View opacity stays continuous across every calibrated boundary and wrap',
    () {
      List<double> weights(double heading, int service) {
        final pose = VehicleHeading.blend(heading, service);
        final result = List<double>.filled(16, 0);
        result[pose.from] += 1 - pose.mix;
        result[pose.to] += pose.mix;
        return result;
      }

      for (var service = 0; service < 5; service++) {
        for (final degrees in VehicleHeading.angles[service]) {
          final angle = degrees * math.pi / 180;
          final before = weights(angle - 1e-6, service);
          final after = weights(angle + 1e-6, service);
          expect(before.reduce((a, b) => a + b), closeTo(1, 1e-9));
          for (var i = 0; i < 16; i++) {
            expect((after[i] - before[i]).abs(), lessThan(1e-7));
          }
        }
      }
    },
  );
  test('Heading wraps without a full rotation', () {
    final from = 179 * math.pi / 180, to = -179 * math.pi / 180;
    expect(VehicleHeading.delta(from, to), closeTo(2 * math.pi / 180, 1e-9));
    expect(VehicleHeading.pose(-.001, 0).frame, 0);
  });
  test('Corner position and tangent are continuous across graph nodes', () {
    const points = [RoadPoint(0, 0), RoadPoint(100, 0), RoadPoint(100, 100)];
    final before = RoadGeometry.sample(points, 0, 100);
    final after = RoadGeometry.sample(points, 1, 0);
    expect(before.position.distanceTo(after.position), lessThan(1e-9));
    expect(before.tangent.distanceTo(after.tangent), lessThan(1e-9));
    expect(before.position.x, lessThan(100));
    expect(before.position.y, greaterThan(0));
  });
  test(
    'Vehicle turns at bounded speed and stops without an orientation snap',
    () {
      final s = Shift();
      final f = s.flights.first, v = s.vehicles[Service.bags]!;
      s.dispatch(f, Service.bags);
      for (var i = 0; i < 2000 && v.phase != VehiclePhase.servicing; i++) {
        final old = v.heading;
        s.tick(.05);
        expect(
          VehicleHeading.delta(old, v.heading).abs(),
          lessThanOrEqualTo(.175001),
        );
      }
      expect(v.phase, VehiclePhase.servicing);
      final parkedHeading = v.heading;
      s.tick(1);
      expect(v.heading, parkedHeading);
    },
  );
}
