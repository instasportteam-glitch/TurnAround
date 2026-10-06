import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:jegd/game/shift.dart';

void until(
  Shift s,
  bool Function() condition, {
  double maxSeconds = Shift.limit - 1,
}) {
  var steps = 0;
  while (!condition() && !s.finished && steps++ < maxSeconds * 20) {
    s.tick(.05);
  }
  expect(
    condition(),
    isTrue,
    reason: 'Condition not reached at ${s.elapsed} seconds',
  );
}

void dispatchAll(Shift s) {
  for (final f in s.flights) {
    for (final service in Service.values) {
      s.dispatch(f, service);
    }
  }
}

void main() {
  test(
    'Baggage and fuel prepare at their supply base before joining the road',
    () {
      for (final service in [Service.bags, Service.fuel]) {
        final shift = Shift();
        final vehicle = shift.vehicles[service]!;
        final base = vehicle.position;
        shift.dispatch(shift.flights.first, service);
        for (var i = 0; i < 60; i++) {
          shift.tick(.05);
        }
        expect(vehicle.preparing, isTrue);
        expect(vehicle.position.distanceTo(base), 0);
        for (var i = 0; i < 180; i++) {
          shift.tick(.05);
        }
        expect(vehicle.preparing, isFalse);
        expect(vehicle.position.distanceTo(base), greaterThan(10));
      }
    },
  );

  test(
    'Shared vehicle completes first job before taking second; duplicate rejected',
    () {
      final s = Shift();
      final a = s.flights[0], b = s.flights[1];
      expect(s.dispatch(a, Service.bags), isTrue);
      expect(s.dispatch(a, Service.bags), isFalse);
      s.dispatch(b, Service.bags);
      until(s, () => a.jobs[Service.bags] == JobState.working);
      expect(b.jobs[Service.bags], JobState.queued);
      until(s, () => b.jobs[Service.bags] == JobState.done);
      expect(a.jobs[Service.bags], JobState.done);
    },
  );
  test(
    'Boarding is required, follows cabin and fuel service, and blocks pushback',
    () {
      final s = Shift(), f = Flight('TEST', 0, 290);
      expect(s.dispatch(f, Service.bus), isFalse);
      for (final service in [
        Service.bags,
        Service.clean,
        Service.cater,
        Service.fuel,
      ]) {
        f.jobs[service] = JobState.done;
      }
      expect(f.ready, isFalse);
      expect(s.dispatch(f, Service.bus), isTrue);
      until(s, () => f.jobs[Service.bus] == JobState.working);
      expect(s.dispatch(f, Service.tug), isFalse);
      until(s, () => f.jobs[Service.bus] == JobState.done);
      expect(f.ready, isTrue);
      expect(s.dispatch(f, Service.tug), isFalse);
      until(s, () => s.standClear(f));
      expect(s.dispatch(f, Service.tug), isTrue);
    },
  );
  test('Dependencies, cancellation and pause preserve rules', () {
    final s = Shift();
    final f = s.flights.first;
    expect(s.dispatch(f, Service.cater), isFalse);
    expect(s.dispatch(f, Service.tug), isFalse);
    s.dispatch(f, Service.clean);
    expect(s.cancel(f, Service.clean), isTrue);
    s.dispatch(f, Service.clean);
    s.paused = true;
    s.tick(50);
    expect(s.elapsed, 0);
    s.paused = false;
    until(s, () => f.jobs[Service.clean] == JobState.done);
    expect(s.dispatch(f, Service.cater), isTrue);
    s.tick(1);
    expect(s.cancel(f, Service.cater), isFalse);
  });
  test('Both flights complete on time through the road network', () {
    final s = Shift();
    for (var i = 0; i < Shift.limit * 20 + 1 && !s.finished; i++) {
      dispatchAll(s);
      s.tick(.05);
    }
    expect(s.finished, isTrue);
    expect(s.onTime, 2);
    expect(s.stars, 3);
    final earned = s.credits, time = s.elapsed;
    s.tick(100);
    expect(s.credits, earned);
    expect(s.elapsed, time);
  });
  test('Inaction ends with failure at limit', () {
    final s = Shift()..tick(Shift.limit + 1);
    expect(s.finished, isTrue);
    expect(s.stars, 0);
  });
  test('Fixed steps do not depend on rendering frame sizes', () {
    final a = Shift(), b = Shift();
    for (final s in [a, b]) {
      s.dispatch(s.flights.first, Service.fuel);
    }
    a.tick(10);
    for (var i = 0; i < 100; i++) {
      b.tick(.1);
    }
    expect(a.elapsed, closeTo(b.elapsed, 1e-6));
    expect(
      a.vehicles[Service.fuel]!.position.x,
      closeTo(b.vehicles[Service.fuel]!.position.x, 1e-6),
    );
  });
  test(
    'Vehicles follow marked roads, wait for traffic and keep separation',
    () {
      final s = Shift();
      var waits = 0, turns = 0;
      for (var i = 0; i < Shift.limit * 20 && !s.finished; i++) {
        dispatchAll(s);
        s.tick(.05);
        for (final v in s.vehicles.values) {
          if (v.trafficWaiting) waits++;
          if (!v.moving || !v.hasReservation || s.vehicleArea(v) == null) {
            continue;
          }
          var roadDistance = double.infinity;
          for (var edge = 1; edge < v.route.length; edge++) {
            final a = s.layout.nodes[v.route[edge - 1]]!,
                b = s.layout.nodes[v.route[edge]]!;
            final dx = b.x - a.x, dy = b.y - a.y;
            final t =
                ((v.position.x - a.x) * dx + (v.position.y - a.y) * dy) /
                (dx * dx + dy * dy);
            roadDistance = min(
              roadDistance,
              v.position.distanceTo(a.lerp(b, t.clamp(0, 1))),
            );
          }
          expect(
            roadDistance,
            lessThanOrEqualTo(26.5),
            reason: 'Rounded turn must remain within the service lane',
          );
          if (v.segment > 2) turns++;
          for (final o in s.vehicles.values) {
            if (o == v ||
                o.phase == VehiclePhase.parked ||
                s.vehicleArea(o) != s.vehicleArea(v)) {
              continue;
            }
            expect(
              v.position.distanceTo(o.position),
              greaterThanOrEqualTo(39.9),
            );
          }
        }
        for (final entry in s.reservations.entries) {
          expect(entry.value.reserved, contains(entry.key));
        }
      }
      expect(waits, greaterThan(0));
      expect(turns, greaterThan(0));
      expect(s.completed, 2);
    },
  );
  test('Pushback waits until service vehicles clear the stand', () {
    final s = Shift();
    final f = s.flights.first;
    for (var i = 0; i < Shift.limit * 20 && !f.ready; i++) {
      for (final t in Service.values.where((s) => s != Service.tug)) {
        s.dispatch(f, t);
      }
      s.tick(.05);
    }
    expect(f.ready, isTrue);
    expect(s.standClear(f), isFalse);
    expect(s.dispatch(f, Service.tug), isFalse);
    until(s, () => s.standClear(f));
    expect(s.dispatch(f, Service.tug), isTrue);
    until(s, () => s.vehicles[Service.tug]!.phase == VehiclePhase.servicing);
    final other = s.flights[1];
    s.dispatch(other, Service.bags);
    final vehicle = s.vehicles[Service.bags]!, position = vehicle.position;
    s.tick(1);
    expect(vehicle.waitReason, 'Yielding to aircraft');
    expect(vehicle.position.distanceTo(position), 0);
    until(s, () => f.departed);
    expect(
      s.vehicles[Service.tug]!.position.x,
      closeTo(s.layout.nodes['tow0']!.x, .1),
    );
  });
  test('Different orderings do not deadlock the apron', () {
    for (var seed = 0; seed < 12; seed++) {
      final s = Shift(), random = Random(seed);
      for (var i = 0; i < Shift.limit * 20 && !s.finished; i++) {
        final flights = s.flights.toList()..shuffle(random);
        final services = Service.values.toList()..shuffle(random);
        for (final f in flights) {
          for (final type in services) {
            s.dispatch(f, type);
          }
        }
        s.tick(.05);
      }
      expect(s.completed, 2, reason: 'Dispatch permutation $seed failed');
      expect(
        s.reservations.values.toSet().length,
        lessThanOrEqualTo(Service.values.length),
      );
    }
  });
}
