import 'dart:ui';
import 'roads.dart';

/// Geometry shared by navigation, aircraft placement and camera bounds.
class AirportLayout {
  AirportLayout(this.location, this.count) {
    nodes.addAll(ApronRoads.nodes);
    if (location != 0) {
      final x = location == 1 ? 940.0 : 1050.0;
      for (final name in ['south', 'middle', 'north']) {
        nodes[name] = RoadPoint(x, nodes[name]!.y);
      }
      nodes['hub'] = const RoadPoint(805, 1100);
    }
    nodes['east'] = const RoadPoint(1900, 1100);
    for (var gate = 2; gate < count; gate++) {
      final offset = standOffset(gate);
      for (final entry in ApronRoads.nodes.entries) {
        if (entry.key.startsWith('park') || entry.key.startsWith('exit')) {
          continue;
        }
        nodes[local(entry.key, gate)] = RoadPoint(
          entry.value.x + offset.dx,
          entry.value.y + offset.dy,
        );
      }
      nodes['link$gate'] = RoadPoint(1900, 1100 + offset.dy);
    }
    for (var gate = 0; gate < count; gate++) {
      final wheel = noseGear(planeRect(gate));
      final start = RoadPoint(wheel.dx - 74, wheel.dy + 74 * 205 / 440);
      nodes['port$gate.4'] = start;
      final bay = gate < 2 ? 'bay$gate.4' : local('bay0.4', gate);
      nodes[bay] = RoadPoint(start.x, nodes[bay]!.y);
      final delta = departureOffset(gate, 1);
      nodes['tow$gate'] = RoadPoint(start.x + delta.dx, start.y + delta.dy);
    }
  }
  final int location, count;
  final nodes = <String, RoadPoint>{};
  double get width =>
      count > 2
          ? 2100
          : location == 0
          ? 1550
          : 1650;
  double get height => count > 3 ? 2300 : 1500;
  Offset standOffset(int gate) =>
      gate < 2
          ? Offset.zero
          : gate == 2
          ? Offset(950, location == 1 ? -200 : 0)
          : const Offset(200, 1000);
  Rect planeRect(int gate) {
    final base =
        gate == 1
            ? const Rect.fromLTWH(380, 220, 410, 273.333)
            : const Rect.fromLTWH(90, 510, 650, 433.333);
    return base.shift(standOffset(gate));
  }

  /// Coastal/northern terminals face the apron from above. Pull aircraft
  /// nose-first down the open apron. Only the upper night stand has an open
  /// tail-first corridor to the right of its terminal.
  bool departsForward(int gate) => location != 0 || gate != 1;
  // The upper forward-tow route passes the lower stand's wing envelope.
  // It may use that corridor only after A1 has departed.
  int? departurePredecessor(int gate) => location != 0 && gate == 1 ? 0 : null;
  Offset departureOffset(int gate, double progress, {Rect? exitBounds}) {
    final r = planeRect(gate);
    final forward = departsForward(gate);
    final distance =
        exitBounds == null
            ? 1700.0
            : forward
            ? (r.right - exitBounds.left + 180).clamp(0.0, double.infinity)
            : (exitBounds.right - r.left + 180).clamp(0.0, double.infinity);
    final p = progress.clamp(0.0, 1.0);
    // Smooth acceleration/deceleration; no sideways translation or rotation
    // of the prerendered aircraft. Its longitudinal axis is preserved.
    final eased = p * p * (3 - 2 * p);
    final dx = distance * eased * (forward ? -1 : 1);
    return Offset(dx, -dx * 205 / 440);
  }

  static Offset noseGear(Rect plane) =>
      Offset(plane.left + plane.width * .176, plane.top + plane.height * .94);

  static Offset doorSill(Rect plane) =>
      Offset(plane.left + plane.width * .241, plane.top + plane.height * .805);
  String local(String name, int gate) {
    if (name.startsWith('port0.')) {
      return name.replaceFirst('port0.', 'port$gate.');
    }
    if (name == 'tow0') return 'tow$gate';
    return 'z$gate:$name';
  }

  List<String> links(int gate) => [
    'east',
    if (standOffset(gate).dy != 0) 'link$gate',
  ];
  List<String> route(int service, int gate) {
    if (gate < 2) return ApronRoads.route(service, gate);
    final base = ApronRoads.route(service, 0);
    final hub = base.indexOf('hub');
    return [
      ...base.take(hub + 1),
      ...links(gate),
      local('hub', gate),
      ...base.skip(hub + 1).map((name) => local(name, gate)),
    ];
  }

  List<String> returnRoute(int service, int gate) {
    if (service == 4) {
      // Tow convoy has already left the screen. Tug uses the off-screen
      // perimeter link, then re-enters the base through its ordinary portal.
      return ['tow$gate', 'hub', 'exit4', 'park4'];
    }
    return route(service, gate).reversed.toList();
  }

  /// A hub is a shared boundary: the base side ends outside the frame;
  /// its apron side starts outside the next frame. Links are off-screen travel.
  int? edgeArea(String a, String b) {
    if (a.startsWith('tow') || b.startsWith('tow')) return null;
    if ([a, b].any((n) => n == 'east' || n.startsWith('link'))) return null;
    if ([a, b].any((n) => n.startsWith('park') || n.startsWith('exit'))) {
      return -1;
    }
    for (var gate = 2; gate < count; gate++) {
      if ([a, b].any(
        (n) =>
            n.startsWith('z$gate:') ||
            n.startsWith('port$gate.') ||
            n == 'tow$gate',
      )) {
        return gate - 1;
      }
    }
    return 0;
  }

  RoadSection? section(List<String> route, int area, RoadPoint portal) {
    final start =
        List.generate(
          route.length - 1,
          (i) => i,
        ).where((i) => edgeArea(route[i], route[i + 1]) == area).firstOrNull;
    if (start == null) return null;
    var end = start + 1;
    while (end < route.length - 1 &&
        edgeArea(route[end], route[end + 1]) == area) {
      end++;
    }
    return RoadSection(start, [
      for (var i = start; i <= end; i++)
        route[i] == 'hub' || route[i].endsWith(':hub')
            ? portal
            : nodes[route[i]]!,
    ]);
  }

  Map<String, List<RoadPoint>> get edges {
    final result = <String, List<RoadPoint>>{};
    for (var gate = 0; gate < count; gate++) {
      for (var service = 0; service < 6; service++) {
        for (final route in [
          this.route(service, gate),
          returnRoute(service, gate),
        ]) {
          for (var i = 1; i < route.length; i++) {
            result[ApronRoads.edgeKey(route[i - 1], route[i])] = [
              nodes[route[i - 1]]!,
              nodes[route[i]]!,
            ];
          }
        }
      }
    }
    return result;
  }
}

/// A continuous route fragment belonging to one screen, with a portal endpoint.
class RoadSection {
  const RoadSection(this.start, this.points);
  final int start;
  final List<RoadPoint> points;
  bool contains(int segment) =>
      segment >= start && segment < start + points.length - 1;
}
