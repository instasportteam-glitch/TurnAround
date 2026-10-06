import 'dart:math';

/// Coordinates shared by the traffic simulation and the rendered markings.
/// The map is an authored apron, not a real-world airport training model.
class RoadPoint {
  const RoadPoint(this.x, this.y);
  final double x, y;
  double distanceTo(RoadPoint other) =>
      sqrt(pow(x - other.x, 2) + pow(y - other.y, 2));
  RoadPoint lerp(RoadPoint other, double t) =>
      RoadPoint(x + (other.x - x) * t, y + (other.y - y) * t);
}

class ApronRoads {
  static final nodes = <String, RoadPoint>{
    'tow0': const RoadPoint(570, 751),
    'tow1': const RoadPoint(845, 315),
    'hub': const RoadPoint(805, 1100),
    'south': const RoadPoint(855, 1020),
    'middle': const RoadPoint(855, 610),
    'north': const RoadPoint(855, 235),
    'a0': const RoadPoint(745, 1020),
    'b0': const RoadPoint(590, 1020),
    'c0': const RoadPoint(355, 1020),
    'aft0': const RoadPoint(770, 610),
    'rear0': const RoadPoint(685, 675),
    'a1': const RoadPoint(780, 610),
    'b1': const RoadPoint(750, 610),
    'c1': const RoadPoint(555, 610),
    'aft1': const RoadPoint(805, 235),
    'rear1': const RoadPoint(805, 315),
    'port0.5': const RoadPoint(215, 960),
    'port1.5': const RoadPoint(410, 545),
    // Dedicated staging pockets / service endpoints. Never drive through a plane.
    'port0.0': const RoadPoint(315, 925),
    'port0.1': const RoadPoint(590, 940),
    'port0.2': const RoadPoint(190, 940),
    'port0.3': const RoadPoint(610, 710),
    'port0.4': const RoadPoint(130, 956),
    'port1.0': const RoadPoint(555, 530),
    'port1.1': const RoadPoint(750, 550),
    'port1.2': const RoadPoint(445, 515),
    'port1.3': const RoadPoint(765, 375),
    'port1.4': const RoadPoint(405, 520),
    'bay0.5': const RoadPoint(215, 1020),
    'bay1.5': const RoadPoint(410, 610),
    'bay0.0': const RoadPoint(315, 1020),
    'bay0.2': const RoadPoint(190, 1020),
    'bay0.4': const RoadPoint(130, 1020),
    'bay1.2': const RoadPoint(445, 610),
    'bay1.4': const RoadPoint(405, 610),
    'park5': const RoadPoint(80, 1070),
    for (var i = 0; i < 5; i++) 'park$i': RoadPoint(170 + i * 125.0, 1150),
    for (var i = 0; i < 5; i++) 'exit$i': RoadPoint(170 + i * 125.0, 1100),
  };

  static List<String> route(int service, int gate) {
    final common = [
      'park$service',
      'exit${service == 5 ? 0 : service}',
      for (var i = service == 5 ? 1 : service + 1; i < 5; i++) 'exit$i',
      'hub',
      'south',
    ];
    final lane =
        gate == 0
            ? ['a0', 'b0', 'c0', 'bay0.0', 'bay0.5', 'bay0.2', 'bay0.4']
            : ['a1', 'b1', 'c1', 'bay1.2', 'bay1.5', 'bay1.4'];
    final turn =
        gate == 0
            ? ['bay0.0', 'b0', 'bay0.2', '', 'bay0.4', 'bay0.5'][service]
            : ['c1', 'b1', 'bay1.2', '', 'bay1.4', 'bay1.5'][service];
    return [
      ...common,
      if (gate == 1 || service == 3) 'middle',
      if (service == 3) ...[
        if (gate == 1) 'north',
        'aft$gate',
        'rear$gate',
      ] else
        ...lane.take(lane.indexOf(turn) + 1),
      'port$gate.$service',
    ];
  }

  static List<String> returnRoute(int service, int gate) {
    if (service != 4) return route(service, gate).reversed.toList();
    return [
      'tow$gate',
      if (gate == 0) ...[
        'rear0',
        'aft0',
        'middle',
      ] else ...[
        'rear1',
        'aft1',
        'north',
        'middle',
      ],
      'south',
      'hub',
      'exit4',
      'park4',
    ];
  }

  static String edgeKey(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
  static Set<String> resources(List<String> route) => {
    // Atomic path reservation prevents opposing traffic and junction deadlocks.
    // Release each traversed edge behind the vehicle, so a follower can enter.
    for (final node in route) 'node:$node',
    for (var i = 1; i < route.length; i++) edgeKey(route[i - 1], route[i]),
  };

  static Map<String, List<RoadPoint>> get edges {
    final result = <String, List<RoadPoint>>{};
    for (var gate = 0; gate < 2; gate++) {
      for (var s = 0; s < 6; s++) {
        final paths = [route(s, gate), returnRoute(s, gate)];
        for (final r in paths) {
          for (var i = 1; i < r.length; i++) {
            result[edgeKey(r[i - 1], r[i])] = [nodes[r[i - 1]]!, nodes[r[i]]!];
          }
        }
      }
    }
    return result;
  }
}

/// Broad quadratic fillets shared by vehicle motion and road rendering.
/// Both halves of a corner share the same point/tangent at the node boundary.
class RoadPose {
  const RoadPose(this.position, this.tangent, this.corner);
  final RoadPoint position, tangent;
  final bool corner;
}

class RoadGeometry {
  static RoadPose sample(List<RoadPoint> points, int segment, double distance) {
    final a = points[segment], b = points[segment + 1];
    final length = a.distanceTo(b);
    final d = distance.clamp(0.0, length);
    if (segment > 0) {
      final prev = points[segment - 1];
      final radius = _radius(prev, a, b);
      if (radius > 0 && d < radius) {
        return _curve(prev, a, b, radius, .5 + d / (2 * radius));
      }
    }
    if (segment + 2 < points.length) {
      final next = points[segment + 2];
      final radius = _radius(a, b, next);
      if (radius > 0 && d > length - radius) {
        return _curve(a, b, next, radius, (d - length + radius) / (2 * radius));
      }
    }
    return RoadPose(
      a.lerp(b, length == 0 ? 0 : d / length),
      RoadPoint(b.x - a.x, b.y - a.y),
      false,
    );
  }

  static double _radius(RoadPoint a, RoadPoint b, RoadPoint c) {
    final first = atan2(b.y - a.y, b.x - a.x),
        second = atan2(c.y - b.y, c.x - b.x);
    if (atan2(sin(second - first), cos(second - first)).abs() < 1e-5) return 0;
    return min(70.0, min(a.distanceTo(b), b.distanceTo(c)) * .45);
  }

  static RoadPose _curve(
    RoadPoint a,
    RoadPoint b,
    RoadPoint c,
    double r,
    double t,
  ) {
    final start = b.lerp(a, r / b.distanceTo(a)),
        end = b.lerp(c, r / b.distanceTo(c));
    final one = start.lerp(b, t), two = b.lerp(end, t);
    return RoadPose(
      one.lerp(two, t),
      RoadPoint(two.x - one.x, two.y - one.y),
      true,
    );
  }
}
