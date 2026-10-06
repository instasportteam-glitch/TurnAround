import 'dart:math' as math;
import 'roads.dart';
import 'missions.dart';
import 'airport_layout.dart';
import 'vehicle_heading.dart';

enum Service { bags, fuel, clean, cater, tug, bus }

enum JobState { waiting, queued, driving, working, done }

enum VehiclePhase { parked, outbound, servicing, returning }

extension ServiceInfo on Service {
  String get label =>
      ['Baggage', 'Fuel', 'Cleaning', 'Catering', 'Tug', 'Passengers'][index];
  double get duration => [12, 18, 10, 12, 12, 16][index].toDouble();
}

class Flight {
  Flight(this.code, this.gate, this.deadline);
  final String code;
  final int gate;
  final double deadline;
  final jobs = {for (final s in Service.values) s: JobState.waiting};
  final progress = {for (final s in Service.values) s: 0.0};
  double? departedAt;
  double previousTowProgress = 0;
  bool get departed => departedAt != null;
  bool get ready => Service.values
      .where((s) => s != Service.tug)
      .every((s) => jobs[s] == JobState.done);
  bool get onTime => departed && departedAt! <= deadline;
}

class Vehicle {
  Vehicle(this.service) : position = ApronRoads.nodes['park${service.index}']!;
  final Service service;
  final List<Flight> queue = [];
  Flight? flight;
  VehiclePhase phase = VehiclePhase.parked;
  RoadPoint position;
  RoadPoint direction = const RoadPoint(0, -1);
  double heading = -math.pi / 2;
  double previousHeading = -math.pi / 2;
  late RoadPoint previousPosition = position;
  List<String> route = [];
  Set<String> reserved = {};
  int segment = 0;
  int previousSegment = 0;
  double previousSegmentDistance = 0;
  double segmentDistance = 0;
  double workElapsed = 0;
  double holdTime = 0;
  bool yieldedAtEntry = false;
  bool trafficWaiting = false;
  String waitReason = '';
  double get preparationDuration =>
      service == Service.bags
          ? 5
          : service == Service.fuel
          ? 6
          : .65;
  bool get preparing =>
      phase == VehiclePhase.outbound &&
      !yieldedAtEntry &&
      (service == Service.bags || service == Service.fuel);
  bool get driving => phase == VehiclePhase.outbound;
  double get returning => phase == VehiclePhase.returning ? 1 : 0;
  bool get moving =>
      phase == VehiclePhase.outbound || phase == VehiclePhase.returning;
  bool get hasReservation => reserved.isNotEmpty;
}

class Shift {
  Shift({this.mission = const Mission(0, 'First Departure', 0, '')}) {
    layout = AirportLayout(mission.location, mission.deadlines.length);
    flights = [
      for (var i = 0; i < mission.deadlines.length; i++)
        Flight(
          '${['VT', 'AZ', 'NR'][mission.location]} ${218 + mission.id * 30 + i * 188}',
          i,
          mission.deadlines[i],
        ),
    ];
    tasks = mission.tasks.map(MissionTask.new).toList();
  }
  final Mission mission;
  late final AirportLayout layout;
  late final List<Flight> flights;
  late final List<MissionTask> tasks;
  int repeatedTasks = 0;
  double get timeLimit => mission.seconds;
  bool get gustActive =>
      mission.gusts && elapsed % 90 >= 65 && elapsed % 90 < 85;
  double get roadSpeed => mission.speed * (gustActive ? .6 : 1);
  static const limit = 360.0;
  final vehicles = {for (final s in Service.values) s: Vehicle(s)};
  final Map<String, Vehicle> reservations = {};
  double elapsed = 0;
  bool paused = false, finished = false;
  double _accumulator = 0;
  double get interpolation => (_accumulator / .05).clamp(0, 1);
  int get onTime => flights.where((f) => f.onTime).length;
  int get completed => flights.where((f) => f.departed).length;
  int get stars =>
      onTime == flights.length && repeatedTasks == 0
          ? 3
          : completed == flights.length
          ? 2
          : completed > 0
          ? 1
          : 0;
  int get credits => completed * 120 + onTime * 80;
  bool get pushbackActive =>
      vehicles[Service.tug]!.phase == VehiclePhase.servicing;
  bool standClear(Flight f) =>
      vehicles.values.every((v) => v.service == Service.tug || v.flight != f);

  String? blocked(Flight f, Service s) {
    if (finished || paused) return 'Shift is paused';
    if (f.departed) return 'Flight departed';
    if (f.jobs[s] != JobState.waiting) return 'Job already assigned';
    if (s == Service.cater && f.jobs[Service.clean] != JobState.done) {
      return 'Finish cleaning first';
    }
    if (s == Service.bus &&
        [
          Service.clean,
          Service.cater,
          Service.fuel,
        ].any((s) => f.jobs[s] != JobState.done)) {
      return 'Board after cleaning, catering and refuelling';
    }
    if ((s == Service.tug || s == Service.bus) &&
        tasks.any(
          (t) =>
              t.spec.gate == f.gate &&
              !t.done &&
              (s == Service.tug || t.spec.validFor == 0),
        )) {
      return 'Finish the aircraft tasks first';
    }
    if (s == Service.bus &&
        vehicles.values.any((v) => v.flight == f && v.service != Service.bus)) {
      return 'Board when vehicles have cleared the stand';
    }
    if (s == Service.tug && !f.ready) return 'Finish all services first';
    if (s == Service.tug) {
      final blockingGate = layout.departurePredecessor(f.gate);
      if (blockingGate != null && !flights[blockingGate].departed) {
        return 'First dispatch A${blockingGate + 1} — shared corridor';
      }
    }
    if (s == Service.tug && !standClear(f)) {
      return 'Waiting for vehicles to clear the stand';
    }
    return null;
  }

  String? taskBlocked(MissionTask task) {
    if (paused || finished) return 'Shift is paused';
    if (task.done) return 'Completed';
    if (task.active) return 'In progress';
    if (flights[task.spec.gate].departed) return 'Flight departed';
    if (elapsed < task.spec.availableAt) {
      return 'Available in ${clockText(task.spec.availableAt - elapsed)}';
    }
    if (tasks.any((t) => t.active)) return 'Crew busy';
    for (final name in task.spec.after) {
      final service = Service.values.firstWhere((s) => s.name == name);
      if (flights[task.spec.gate].jobs[service] != JobState.done) {
        return 'First: ${service.label}';
      }
    }
    return null;
  }

  bool startTask(MissionTask task) {
    if (!tasks.contains(task) || taskBlocked(task) != null) return false;
    task.active = true;
    return true;
  }

  bool dispatch(Flight f, Service s) {
    if (blocked(f, s) != null) return false;
    f.jobs[s] = JobState.queued;
    vehicles[s]!.queue.add(f);
    return true;
  }

  bool cancel(Flight f, Service s) {
    if (paused || finished || f.jobs[s] != JobState.queued) return false;
    vehicles[s]!.queue.remove(f);
    f.jobs[s] = JobState.waiting;
    return true;
  }

  void tick(double dt) {
    if (paused || finished || dt <= 0 || !dt.isFinite) return;
    _accumulator += dt;
    while (_accumulator + 1e-9 >= .05 && !finished) {
      _accumulator -= .05;
      _step(.05);
    }
  }

  void _release(Vehicle v) {
    for (final r in v.reserved) {
      if (reservations[r] == v) reservations.remove(r);
    }
    v.reserved.clear();
  }

  void _startRoute(Vehicle v, List<String> route, VehiclePhase phase) {
    v.route = route;
    v.segment = 0;
    v.segmentDistance = 0;
    v.phase = phase;
    v.yieldedAtEntry = false;
    v.holdTime = 0;
    v.position = layout.nodes[route.first]!;
  }

  bool _reserve(Vehicle v) {
    final required = ApronRoads.resources(v.route);
    if (required.any(
      (r) => reservations.containsKey(r) && reservations[r] != v,
    )) {
      return false;
    }
    // Also protect physical junction envelopes where separately authored branches converge.
    if (vehicles.values.any(
      (other) =>
          other != v &&
          vehicleArea(other) == vehicleArea(v) &&
          other.moving &&
          other.hasReservation &&
          other.position.distanceTo(v.position) < 48,
    )) {
      return false;
    }
    for (final r in required) {
      reservations[r] = v;
    }
    v.reserved = required;
    return true;
  }

  void _step(double dt) {
    elapsed = math.min(timeLimit, elapsed + dt);
    for (final task in tasks) {
      final f = flights[task.spec.gate];
      if (task.done &&
          task.spec.validFor > 0 &&
          !f.departed &&
          f.jobs[Service.tug] != JobState.driving &&
          f.jobs[Service.tug] != JobState.working &&
          elapsed - task.completedAt! > task.spec.validFor) {
        task.completedAt = null;
        task.progress = 0;
        repeatedTasks++;
        if (f.jobs[Service.tug] == JobState.queued) {
          vehicles[Service.tug]!.queue.remove(f);
          f.jobs[Service.tug] = JobState.waiting;
        }
      }
      if (!task.active) continue;
      task.progress = math.min(1, task.progress + dt / task.spec.duration);
      if (task.progress >= 1) {
        task.active = false;
        task.completedAt = elapsed;
      }
    }
    for (final f in flights) {
      f.previousTowProgress = f.progress[Service.tug]!;
    }
    for (final v in vehicles.values) {
      v.previousPosition = v.position;
      v.previousSegment = v.segment;
      v.previousSegmentDistance = v.segmentDistance;
      v.previousHeading = v.heading;
    }
    // Returning traffic gets first opportunity to clear the apron.
    final ordered =
        vehicles.values.toList()..sort(
          (a, b) => (a.phase == VehiclePhase.returning ? 0 : 1).compareTo(
            b.phase == VehiclePhase.returning ? 0 : 1,
          ),
        );
    for (final v in ordered) {
      v.trafficWaiting = false;
      v.waitReason = '';
      if (v.phase == VehiclePhase.parked && v.queue.isNotEmpty) {
        v.flight = v.queue.removeAt(0);
        v.flight!.jobs[v.service] = JobState.driving;
        _startRoute(
          v,
          layout.route(v.service.index, v.flight!.gate),
          VehiclePhase.outbound,
        );
      }
      if (v.moving) {
        _move(v, dt);
        continue;
      }
      if (v.phase != VehiclePhase.servicing) continue;
      final f = v.flight!;
      if (v.service == Service.tug &&
          vehicles.values.any((o) => o != v && o.moving && o.hasReservation)) {
        v.trafficWaiting = true;
        v.waitReason = 'Waiting for road clearance';
        continue;
      }
      if (v.service == Service.tug && v.workElapsed == 0) {
        final delta = layout.departureOffset(f.gate, 1);
        final target = math.atan2(delta.dy, delta.dx);
        v.heading = VehicleHeading.approach(v.heading, target, dt * 3.5);
        if (VehicleHeading.delta(v.heading, target).abs() > .001) continue;
      }
      v.workElapsed += dt;
      f.progress[v.service] =
          (v.workElapsed / (v.service.duration * mission.work)).clamp(0, 1);
      if (v.service == Service.tug) {
        final start = layout.nodes['port${f.gate}.4']!;
        final delta = layout.departureOffset(f.gate, f.progress[v.service]!);
        v.position = RoadPoint(start.x + delta.dx, start.y + delta.dy);
        final direction = layout.departureOffset(f.gate, 1);
        v.direction = RoadPoint(direction.dx, direction.dy);
      }

      if (v.workElapsed + 1e-9 >= v.service.duration * mission.work) {
        f.jobs[v.service] = JobState.done;
        if (v.service == Service.tug) f.departedAt = elapsed;
        _startRoute(
          v,
          layout.returnRoute(v.service.index, f.gate),
          VehiclePhase.returning,
        );
      }
    }
    finished = completed == flights.length || elapsed >= timeLimit;
  }

  int? vehicleArea(Vehicle v) {
    if (v.phase == VehiclePhase.parked) return -1;
    if (v.phase == VehiclePhase.servicing) {
      return v.flight!.gate < 2 ? 0 : v.flight!.gate - 1;
    }
    if (v.segment >= v.route.length - 1) return null;
    return layout.edgeArea(v.route[v.segment], v.route[v.segment + 1]);
  }

  static double clearance(Vehicle v, Vehicle other, RoadPoint candidate) {
    final bus =
        v.service == Service.bus
            ? v
            : other.service == Service.bus
            ? other
            : null;
    if (bus == null) return 40;
    final dx = candidate.x - other.position.x;
    final dy = candidate.y - other.position.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < .001) return 74;
    final along =
        ((dx * math.cos(bus.heading) + dy * math.sin(bus.heading)) / distance)
            .abs();
    // Longitudinal clearance, with narrow lateral clearance for adjacent lanes.
    return 40 + 34 * along * along * along * along;
  }

  void _move(Vehicle v, double dt) {
    // Aircraft has priority. Already moving vehicles clear the road before pushback starts.
    if (!v.hasReservation && pushbackActive && v.service != Service.tug) {
      v.trafficWaiting = true;
      v.waitReason = 'Yielding to aircraft';
      return;
    }
    if (!v.yieldedAtEntry) {
      v.holdTime += dt;
      v.trafficWaiting = true;
      v.waitReason =
          v.preparing
              ? (v.service == Service.bags
                  ? 'Loading baggage at the warehouse'
                  : 'Filling the tanker at the base')
              : 'Stop · checking clearance';
      if (v.holdTime >=
          (v.phase == VehiclePhase.outbound ? v.preparationDuration : .65)) {
        v.yieldedAtEntry = true;
      }
      return;
    }
    if (!v.hasReservation && !_reserve(v)) {
      v.trafficWaiting = true;
      v.waitReason = 'Yielding to vehicles';
      return;
    }
    final a = layout.nodes[v.route[v.segment]]!;
    final b = layout.nodes[v.route[v.segment + 1]]!;
    final distance = a.distanceTo(b);
    final approach =
        v.route[v.segment].startsWith('port') ||
        v.route[v.segment + 1].startsWith('port');
    final points = v.route.map((id) => layout.nodes[id]!).toList();
    final now = RoadGeometry.sample(points, v.segment, v.segmentDistance);
    var speed =
        approach
            ? 48.0
            : now.corner
            ? 75.0
            : 140.0;
    final crossing = [
      v.route[v.segment],
      v.route[v.segment + 1],
    ].any((n) => n == 'hub' || n.endsWith(':hub'));
    if (crossing && vehicleArea(v) != null) {
      // Give a full on-screen exit/entry time instead of rushing across a short
      // logical boundary edge. Transit time remains independent of viewport size.
      speed = math.min(speed, distance / 2);
    }
    var progress = math.min(
      distance,
      v.segmentDistance + speed * roadSpeed * dt,
    );
    var pose = RoadGeometry.sample(points, v.segment, progress);
    var targetHeading = math.atan2(
      pose.position.y - v.position.y,
      pose.position.x - v.position.x,
    );
    // On a curve, shorten the advance to match the steering rate instead of
    // alternating a full-speed step with a stationary turn every other tick.
    final tangentHeading = math.atan2(now.tangent.y, now.tangent.x);
    if (VehicleHeading.delta(v.heading, tangentHeading).abs() < .3) {
      for (
        var attempt = 0;
        attempt < 8 &&
            VehicleHeading.delta(v.heading, targetHeading).abs() > dt * 3.5;
        attempt++
      ) {
        progress = v.segmentDistance + (progress - v.segmentDistance) * .5;
        pose = RoadGeometry.sample(points, v.segment, progress);
        targetHeading = math.atan2(
          pose.position.y - v.position.y,
          pose.position.x - v.position.x,
        );
      }
    }
    v.heading = VehicleHeading.approach(v.heading, targetHeading, dt * 3.5);
    // Orient before leaving a bay or after a reversal, rather than sliding sideways.
    if (VehicleHeading.delta(v.heading, targetHeading).abs() > .045) {
      v.trafficWaiting = true;
      v.waitReason = 'Turning';
      return;
    }
    final candidate = pose.position;
    // A following vehicle keeps its distance, even after a section is released.
    if (vehicles.values.any(
      (o) =>
          o != v &&
          vehicleArea(o) == vehicleArea(v) &&
          o.phase != VehiclePhase.parked &&
          o.position.distanceTo(candidate) < clearance(v, o, candidate) &&
          o.position.distanceTo(v.position) >= o.position.distanceTo(candidate),
    )) {
      v.trafficWaiting = true;
      v.waitReason = 'Keeping a safe distance';
      return;
    }
    v.direction = pose.tangent;
    v.position = candidate;
    v.segmentDistance = progress;
    if (progress + 1e-9 < distance) return;
    final released = [
      ApronRoads.edgeKey(v.route[v.segment], v.route[v.segment + 1]),
      'node:${v.route[v.segment]}',
    ];
    for (final r in released) {
      if (reservations[r] == v) reservations.remove(r);
      v.reserved.remove(r);
    }
    v.segment++;
    v.segmentDistance = 0;
    if (v.segment < v.route.length - 1) return;
    _release(v);
    if (v.phase == VehiclePhase.returning) {
      v.phase = VehiclePhase.parked;
      v.flight = null;
      v.route = [];
    } else {
      v.phase = VehiclePhase.servicing;
      v.workElapsed = 0;
      v.flight!.jobs[v.service] = JobState.working;
    }
  }
}

String clockText(double seconds) {
  final value = seconds.ceil().clamp(0, 9999);
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}
