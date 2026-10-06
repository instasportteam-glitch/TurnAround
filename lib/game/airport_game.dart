import '../l10n/strings.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flame/game.dart';
import 'package:flutter/material.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight;
import 'roads.dart';
import 'apron_bus.dart';
import 'airport_layout.dart';
import 'shift.dart';
import 'vehicle_heading.dart';

/// Layered, pre-rendered 3D scene. Every movable object remains independent.
class AirportGame extends FlameGame {
  AirportGame(this.shift, this.onFrame);
  final Shift shift;
  final void Function() onFrame;
  int selected = 0;
  // Discrete, authored views. Simulation keeps its continuous road graph,
  // but the player switches areas instead of dragging a stitched bitmap.
  int sceneIndex = 0;
  int simulationSpeed = 1;
  int get sceneCount => math.max(1, shift.flights.length - 1);
  double get worldWidth => shift.layout.width;
  double get worldHeight => shift.layout.height;
  List<Rect> get planeRects => [
    for (var i = 0; i < shift.flights.length; i++) shift.layout.planeRect(i),
  ];
  List<int> get visibleGates =>
      sceneIndex < 0
          ? []
          : sceneIndex == 0
          ? [for (var i = 0; i < math.min(2, shift.flights.length); i++) i]
          : [sceneIndex + 1];
  Rect get sceneBounds =>
      sceneIndex < 0
          ? const Rect.fromLTWH(0, 970, 970, 300)
          : const Rect.fromLTWH(0, 0, 1120, 1085).shift(
            sceneIndex == 0
                ? Offset.zero
                : shift.layout.standOffset(sceneIndex + 1),
          );
  // Fit the complete playable region inside a safe inset, independently of
  // background cover. This keeps parked buses, wingtips and doors on screen.
  double get viewScale => math.min(
    math.max(1, size.x - 24) / sceneBounds.width,
    math.max(1, size.y - 134) / sceneBounds.height,
  );
  Offset get viewCenter => sceneBounds.center;
  Offset get screenCenter => Offset(size.x / 2, size.y / 2 - 25);
  String sceneTitle(int index) =>
      index < 0
          ? 'Services'
          : index == 0
          ? 'Terminal'
          : shift.mission.location == 1
          ? 'Coastal apron'
          : index == 1
          ? 'De-icing apron'
          : 'Cargo apron';
  String get sceneAsset =>
      sceneIndex < 0
          ? 'scene-services.png'
          : shift.mission.location == 0
          ? 'apron.png'
          : shift.mission.location == 1
          ? (sceneIndex == 0 ? 'scene-coast.png' : 'scene-coast-remote.png')
          : (sceneIndex == 0
              ? 'scene-north.png'
              : sceneIndex == 1
              ? 'scene-north-remote.png'
              : 'scene-north-cargo.png');
  bool get mirrorScene => shift.mission.location == 1 && sceneIndex >= 0;
  void focusGate(int gate) {
    sceneIndex = gate < 2 ? 0 : gate - 1;
  }

  void focusBase() {
    sceneIndex = -1;
  }

  double animation = 0, _notification = 0;
  Image? apron, airliner, fleet;
  List<Image> directionSheets = [];
  final Map<String, Image> sceneImages = {};
  final List<List<Rect>> frameBounds = [];
  @override
  Future<void> onLoad() async {
    final loaded = await images.loadAll([
      shift.mission.asset,
      'airliner.png',
      'vehicles.png',
      'bags-directions-16.png',
      'fuel-directions-16.png',
      'clean-directions-16.png',
      'cater-directions-16.png',
      'tug-directions-16.png',
    ]);
    apron = loaded[0];
    final names = {
      'apron.png',
      'scene-services.png',
      if (shift.mission.location == 1) ...[
        'scene-coast.png',
        'scene-coast-remote.png',
      ],
      if (shift.mission.location == 2) ...[
        'scene-north.png',
        'scene-north-remote.png',
        'scene-north-cargo.png',
      ],
    };
    for (final name in names) {
      sceneImages[name] = await images.load(name);
    }
    airliner = loaded[1];
    fleet = loaded[2];
    directionSheets = loaded.sublist(3);
    // Measure opaque body bounds once; transparent atlas padding varies by view.
    for (final sheet in directionSheets) {
      final bytes = (await sheet.toByteData(format: ImageByteFormat.rawRgba))!;
      final bounds = <Rect>[];
      for (var frame = 0; frame < 16; frame++) {
        final left = (frame % 4 * sheet.width / 4).ceil();
        final top = (frame ~/ 4 * sheet.height / 4).ceil();
        final right = ((frame % 4 + 1) * sheet.width / 4).floor();
        final bottom = ((frame ~/ 4 + 1) * sheet.height / 4).floor();
        var x0 = right, y0 = bottom, x1 = left, y1 = top;
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            if (bytes.getUint8((y * sheet.width + x) * 4 + 3) < 200) continue;
            x0 = math.min(x0, x);
            y0 = math.min(y0, y);
            x1 = math.max(x1, x);
            y1 = math.max(y1, y);
          }
        }
        bounds.add(
          Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0),
        );
      }
      frameBounds.add(bounds);
    }
  }

  @override
  Color backgroundColor() => const Color(0xff080e22);
  @override
  void update(double dt) {
    super.update(dt);
    if (apron == null || frameBounds.length != 5) return;
    shift.tick(dt.clamp(0, .1).toDouble() * simulationSpeed);
    if (!shift.paused && !shift.finished) animation += dt * simulationSpeed;
    _notification += dt;
    if (_notification > .1) {
      _notification = 0;
      onFrame();
    }
  }

  int gateAt(double x, double y) {
    if (visibleGates.isEmpty) return selected;
    if (mirrorScene) x = size.x - x;
    final world = viewCenter + (Offset(x, y) - screenCenter) / viewScale;
    var nearest = visibleGates.first;
    for (final i in visibleGates.skip(1)) {
      if ((planeRects[i].center - world).distance <
          (planeRects[nearest].center - world).distance) {
        nearest = i;
      }
    }
    return nearest;
  }

  String language = 'en';

  void label(
    Canvas c,
    String text,
    Offset p,
    double size,
    Color color, {
    bool bold = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: GameStrings(language).tr(text),
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          fontFamily: 'Arial',
          letterSpacing: .5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (mirrorScene) {
      c.save();
      c.translate(p.dx * 2 + painter.width, 0);
      c.scale(-1, 1);
      painter.paint(c, p);
      c.restore();
    } else {
      painter.paint(c, p);
    }
  }

  Offset point(RoadPoint p) => Offset(p.x, p.y);
  void sprite(Canvas c, Image image, Rect dest, {Paint? paint, Rect? source}) =>
      c.drawImageRect(
        image,
        source ??
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
        dest,
        paint ?? (Paint()..filterQuality = FilterQuality.medium),
      );

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (apron == null || frameBounds.length != 5) return;
    final background = sceneImages[sceneAsset]!;
    // One image per screen, never tiled or pasted into neighbouring stands.
    // Cover only the scenery; foreground always uses a contain transform.
    final cover = math.max(
      size.x / background.width,
      size.y / background.height,
    );
    sprite(
      canvas,
      background,
      Rect.fromLTWH(
        (size.x - background.width * cover) / 2,
        0,
        background.width * cover,
        background.height * cover,
      ),
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y));
    if (mirrorScene) {
      canvas.translate(size.x, 0);
      canvas.scale(-1, 1);
    }
    final scale = viewScale;
    final center = viewCenter;
    canvas.translate(
      screenCenter.dx - center.dx * scale,
      screenCenter.dy - center.dy * scale,
    );
    canvas.scale(scale);
    // Only the actual screen clips traffic; portal endpoints lie beyond it.
    drawRoads(canvas);
    if (sceneIndex < 0) drawDepots(canvas);
    // Ground layers: lead-in lines, safety markings, shadows and ground equipment.
    for (final f in shift.flights.where((f) => visibleGates.contains(f.gate))) {
      final r = planeRects[f.gate];
      final nose = Offset(r.left + r.width * .065, r.top + r.height * .90);
      final tail = Offset(r.left + r.width * .79, r.top + r.height * .25);
      canvas.drawLine(
        nose + const Offset(-30, 25),
        tail,
        Paint()
          ..color = const Color(0x99e0b651)
          ..strokeWidth = 3,
      );
      if (!f.departed) {
        final moving = aircraftRect(f);
        final shadow = Rect.fromLTWH(
          moving.left + 28,
          moving.top + r.height * .57,
          r.width * .8,
          r.height * .27,
        );
        canvas.drawOval(
          shadow,
          Paint()
            ..color = const Color(0xaa020718)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
      }
      final sign = r.topLeft + const Offset(6, 55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(sign.dx, sign.dy, 66, 43),
          const Radius.circular(5),
        ),
        Paint()..color = const Color(0xe60a1122),
      );
      label(
        canvas,
        'A${f.gate + 1}',
        sign + const Offset(10, 6),
        25,
        const Color(0xfff2eedf),
      );
    }
    // Aircraft are drawn far to near. Vehicles behind a wing draw before it.
    final objects = <({double depth, void Function() draw})>[];
    for (final f in shift.flights.where((f) => visibleGates.contains(f.gate))) {
      if (f.departed) continue;
      objects.add((
        depth: aircraftRect(f).top + planeRects[f.gate].height * .68,
        draw: () => drawPlane(canvas, f),
      ));
    }
    for (final v in shift.vehicles.values) {
      final view = vehicleView(v);
      if (view == null) continue;
      objects.add((
        depth: view.position.dy,
        draw: () => drawVehicle(canvas, v),
      ));
    }
    objects.sort((a, b) => a.depth.compareTo(b.depth));
    for (final item in objects) {
      item.draw();
    }
    for (final f in shift.flights.where((f) => visibleGates.contains(f.gate))) {
      drawFlightTag(canvas, f);
    }
    if (sceneIndex >= 0) drawDetails(canvas);
    for (final task in shift.tasks.where(
      (t) => t.active && visibleGates.contains(t.spec.gate),
    )) {
      final r = planeRects[task.spec.gate];
      final p = Offset(r.left + r.width * .45, r.top + r.height * .64);
      if (task.spec.validFor > 0) {
        for (var i = 0; i < 12; i++) {
          final phase = (animation * .5 + i / 12) % 1;
          canvas.drawCircle(
            p + Offset(phase * 100 - 50, -phase * 35),
            6 + phase * 13,
            Paint()
              ..color = Color.fromRGBO(159, 205, 239, (1 - phase) * .28)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
        }
      }
      label(
        canvas,
        '${task.spec.title} ${(task.progress * 100).round()}%',
        p + const Offset(-65, 45),
        13,
        const Color(0xff94e7e4),
      );
    }
    if (shift.mission.location == 2) {
      for (var i = 0; i < 45; i++) {
        final x =
            (i * 139.0 + animation * (shift.gustActive ? 38 : 12)) %
                sceneBounds.width +
            sceneBounds.left;
        final y =
            (i * 211.0 + animation * 24) % sceneBounds.height + sceneBounds.top;
        canvas.drawCircle(
          Offset(x, y),
          1.3,
          Paint()..color = const Color(0x77dfedff),
        );
      }
    }
    canvas.restore();
  }

  double departureProgress(Flight f) {
    final t = shift.paused || shift.finished ? 1.0 : shift.interpolation;
    return f.previousTowProgress +
        (f.progress[Service.tug]! - f.previousTowProgress) * t;
  }

  Offset departureTravel(Flight f) => shift.layout.departureOffset(
    f.gate,
    departureProgress(f),
    exitBounds: visibleWorld,
  );
  Rect aircraftRect(Flight f) => planeRects[f.gate].shift(departureTravel(f));

  Rect get visibleWorld => Rect.fromLTWH(
    viewCenter.dx - screenCenter.dx / viewScale,
    viewCenter.dy - screenCenter.dy / viewScale,
    size.x / viewScale,
    size.y / viewScale,
  );

  RoadPoint get portal {
    if (sceneIndex < 0) return RoadPoint(visibleWorld.right + 180, 1100);
    final node =
        sceneIndex == 0 ? 'south' : shift.layout.local('south', sceneIndex + 1);
    return RoadPoint(visibleWorld.right + 180, shift.layout.nodes[node]!.y);
  }

  ({Offset position, double heading})? vehicleView(Vehicle v) {
    if (shift.vehicleArea(v) != sceneIndex) return null;
    final t = shift.paused || shift.finished ? 1.0 : shift.interpolation;
    if (v.service == Service.tug && v.phase == VehiclePhase.servicing) {
      return (
        position:
            point(shift.layout.nodes['port${v.flight!.gate}.4']!) +
            departureTravel(v.flight!),
        heading:
            v.previousHeading +
            VehicleHeading.delta(v.previousHeading, v.heading) * t,
      );
    }
    if (!v.moving) {
      return (
        position: point(v.previousPosition.lerp(v.position, t)),
        heading:
            v.previousHeading +
            VehicleHeading.delta(v.previousHeading, v.heading) * t,
      );
    }
    final section = shift.layout.section(v.route, sceneIndex, portal);
    if (section == null || !section.contains(v.segment)) return null;
    RoadPose pose(int segment, double distance) {
      final physicalLength = shift.layout.nodes[v.route[segment]]!.distanceTo(
        shift.layout.nodes[v.route[segment + 1]]!,
      );
      final i = segment - section.start;
      final displayedLength = section.points[i].distanceTo(
        section.points[i + 1],
      );
      return RoadGeometry.sample(
        section.points,
        i,
        distance / physicalLength * displayedLength,
      );
    }

    final current = pose(v.segment, v.segmentDistance);
    final previous =
        section.contains(v.previousSegment)
            ? pose(v.previousSegment, v.previousSegmentDistance)
            : current;
    final position = point(previous.position.lerp(current.position, t));
    final tangent = previous.tangent.lerp(current.tangent, t);
    final heading =
        v.segment == 0 && v.segmentDistance == 0
            ? v.previousHeading +
                VehicleHeading.delta(v.previousHeading, v.heading) * t
            : math.atan2(tangent.y, tangent.x);
    return (position: position, heading: heading);
  }

  /// Sample the same fillets as the traffic simulation, including portal legs.
  List<List<RoadPoint>> get visibleRoads {
    final unique = <String, List<RoadPoint>>{};
    for (var gate = 0; gate < shift.flights.length; gate++) {
      for (var service = 0; service < 6; service++) {
        for (final route in [
          shift.layout.route(service, gate),
          shift.layout.returnRoute(service, gate),
        ]) {
          final section = shift.layout.section(route, sceneIndex, portal);
          if (section == null) continue;
          final points = section.points;
          final key = points.map((p) => '${p.x},${p.y}').join('|');
          final reverse = points.reversed.map((p) => '${p.x},${p.y}').join('|');
          if (!unique.containsKey(reverse)) unique[key] = points;
        }
      }
    }
    return unique.values.toList();
  }

  Path roadPath(List<RoadPoint> points) {
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (var i = 0; i < points.length - 1; i++) {
      final length = points[i].distanceTo(points[i + 1]);
      for (double distance = 0; distance < length; distance += 4) {
        final p = RoadGeometry.sample(points, i, distance).position;
        path.lineTo(p.x, p.y);
      }
      final p = RoadGeometry.sample(points, i, length).position;
      path.lineTo(p.x, p.y);
    }
    return path;
  }

  String _roadCacheKey = '';
  List<Path> _roadPaths = [];
  Path _roadDashes = Path();
  Path _serviceGuides = Path();
  void drawRoads(Canvas c) {
    final key = '$sceneIndex:${size.x}:${size.y}';
    if (_roadCacheKey != key) {
      _roadCacheKey = key;
      _serviceGuides = Path();
      if (sceneIndex >= 0) {
        for (final gate in visibleGates) {
          for (var service = 0; service < 6; service++) {
            final section =
                shift.layout.section(
                  shift.layout.route(service, gate),
                  sceneIndex,
                  portal,
                )!;
            for (final metric in roadPath(section.points).computeMetrics()) {
              for (
                double d = math.max(0, metric.length - 230);
                d < metric.length;
                d += 26
              ) {
                _serviceGuides.addPath(
                  metric.extractPath(d, math.min(d + 12, metric.length)),
                  Offset.zero,
                );
              }
            }
          }
        }
      }
      _roadDashes = Path();
      final lines = <List<RoadPoint>>[];
      if (sceneIndex < 0) {
        lines.add([
          for (var i = 0; i < 5; i++) shift.layout.nodes['exit$i']!,
          portal,
        ]);
      } else {
        RoadPoint n(String name) =>
            shift.layout.nodes[sceneIndex == 0
                ? name
                : shift.layout.local(name, sceneIndex + 1)]!;
        lines.add([
          portal,
          n('south'),
          n('middle'),
          if (sceneIndex == 0 && shift.flights.length > 1) n('north'),
        ]);
        lines.add([
          portal,
          n('south'),
          for (final name in [
            'a0',
            'b0',
            'c0',
            'bay0.0',
            'bay0.5',
            'bay0.2',
            'bay0.4',
          ])
            n(name),
        ]);
        if (sceneIndex == 0 && shift.flights.length > 1) {
          lines.add([
            portal,
            n('south'),
            n('middle'),
            for (final name in ['a1', 'b1', 'c1', 'bay1.2', 'bay1.5', 'bay1.4'])
              n(name),
          ]);
        }
      }
      _roadPaths = lines.map(roadPath).toList();
      for (final line in lines) {
        for (final metric in roadPath(line).computeMetrics()) {
          for (double d = 12; d < metric.length; d += 40) {
            _roadDashes.addPath(
              metric.extractPath(d, math.min(d + 17, metric.length)),
              Offset.zero,
            );
          }
        }
      }
    }
    final paths = _roadPaths;
    // Main service lanes retain the wet apron texture. Stand approaches are
    // painted guides on concrete, not separate asphalt fingers under aircraft.
    c.saveLayer(null, Paint()..color = const Color(0x70ffffff));
    // Draw all borders first, then pavement, so merging lanes form one junction.
    for (final path in paths) {
      c.drawPath(
        path,
        Paint()
          ..color = const Color(0xff8b9dad)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 57
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final path in paths) {
      c.drawPath(
        path,
        Paint()
          ..color = const Color(0xff293749)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 53
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    c.restore();
    c.drawPath(
      _serviceGuides,
      Paint()
        ..color = const Color(0x99cfb885)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    c.drawPath(
      _roadDashes,
      Paint()
        ..color = const Color(0xffb5c1c9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    label(
      c,
      sceneIndex < 0
          ? 'TO APRONS →'
          : mirrorScene
          ? '← SERVICE BASE'
          : 'SERVICE BASE →',
      Offset(visibleWorld.right - 270, portal.y - 48),
      14,
      const Color(0xff9fbacf),
    );
    if (sceneIndex >= 0) {
      for (final name in ['south', 'middle']) {
        final node =
            sceneIndex == 0 ? name : shift.layout.local(name, sceneIndex + 1);
        final p = point(shift.layout.nodes[node]!) + const Offset(-20, -15);
        c.drawLine(
          p,
          p + const Offset(38, 0),
          Paint()
            ..color = const Color(0xffe3d6be)
            ..strokeWidth = 5,
        );
        label(c, 'STOP', p + const Offset(-5, 8), 13, const Color(0xffe3d6be));
      }
    }
    for (var i = 0; sceneIndex < 0 && i < 6; i++) {
      final p = point(shift.layout.nodes['park$i']!);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: p, width: 102, height: 61),
          const Radius.circular(3),
        ),
        Paint()
          ..color = const Color(0x667b9aab)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      label(
        c,
        ['BAGGAGE', 'FUEL', 'CLEANING', 'CATERING', 'TUG', 'BUS'][i],
        p + const Offset(-40, 20),
        12,
        const Color(0xff7e98b5),
      );
    }
    if (sceneIndex <= 0) {
      label(
        c,
        'SERVICE ROAD',
        const Offset(647, 1058),
        12,
        const Color(0xffa2b8d1),
      );
    }
    if (sceneIndex < 0) {
      label(
        c,
        'GSE  /  GROUND SERVICES',
        const Offset(205, 1187),
        11,
        const Color(0xff96a8c8),
      );
    }
    if (shift.pushbackActive && sceneIndex >= 0) {
      final node =
          sceneIndex == 0
              ? 'south'
              : shift.layout.local('south', sceneIndex + 1);
      final p = point(shift.layout.nodes[node]!);
      c.drawLine(
        p + const Offset(-26, 60),
        p + const Offset(26, 60),
        Paint()
          ..color = const Color(0xffee9875)
          ..strokeWidth = 5,
      );
    }
  }

  void drawPlane(Canvas c, Flight f) {
    final push = f.progress[Service.tug]!;
    final base = planeRects[f.gate];
    final r = aircraftRect(f);
    if (push > 0) {
      final tug =
          point(shift.layout.nodes['port${f.gate}.4']!) + departureTravel(f);
      final wheel = AirportLayout.noseGear(r);
      c.drawLine(
        wheel,
        tug + const Offset(28, -13),
        Paint()
          ..color = const Color(0xffc2bd91)
          ..strokeWidth = 4,
      );
    }
    sprite(c, airliner!, r);
    // Wheel chocks and cones surround the parked nose, outside vehicle approaches.
    if (push == 0) {
      final origin = Offset(
        base.left + base.width * .23,
        base.top + base.height * .92,
      );
      for (final d in [const Offset(0, 0), const Offset(42, 18)]) {
        final p = origin + d;
        c.drawOval(
          Rect.fromCenter(center: p + const Offset(0, 3), width: 15, height: 6),
          Paint()..color = const Color(0x99000000),
        );
        c.drawPath(
          Path()
            ..moveTo(p.dx - 5, p.dy)
            ..lineTo(p.dx, p.dy - 14)
            ..lineTo(p.dx + 5, p.dy)
            ..close(),
          Paint()..color = const Color(0xffee994f),
        );
        c.drawLine(
          p + const Offset(-3, -5),
          p + const Offset(3, -5),
          Paint()
            ..color = const Color(0xfff9eee2)
            ..strokeWidth = 3,
        );
      }
    }
  }

  void drawVehicle(Canvas c, Vehicle v) {
    final view = vehicleView(v);
    if (view == null) return;
    final p = view.position;
    final depth = ((v.position.y - 400) / 500).clamp(0.0, 1.0);
    final width = 94 + 4 * depth * depth * (3 - 2 * depth);
    final height = width;
    final heading = view.heading;
    if (v.service == Service.bus) {
      if (v.phase == VehiclePhase.servicing) drawBoarding(c, v, p, heading);
      ApronBus.draw(c, p, heading, open: v.phase == VehiclePhase.servicing);
      return;
    }
    final views = VehicleHeading.blend(heading, v.service.index);
    final sheet = directionSheets[v.service.index];
    c.drawOval(
      Rect.fromCenter(
        center: p + const Offset(5, 3),
        width: width * .74,
        height: height * .25,
      ),
      Paint()
        ..color = const Color(0xaa03091c)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    // Add premultiplied views in an isolated layer so the blend stays opaque.
    c.saveLayer(Rect.fromCircle(center: p, radius: width * 2), Paint());
    void drawView(int frame, double opacity) {
      if (opacity <= 0) return;
      final body = frameBounds[v.service.index][frame];
      final angle =
          VehicleHeading.angles[v.service.index][frame] * math.pi / 180;
      final cos = math.cos(angle).abs(), sin = math.sin(angle).abs();
      // A common physical envelope preserves the narrower end-on silhouette.
      final projectedWidth = cos + .43 * sin;
      final projectedHeight = .52 * sin + .43 * .52 * cos + .34;
      final expectedDiagonal = math.sqrt(
        projectedWidth * projectedWidth + projectedHeight * projectedHeight,
      );
      final scale =
          width *
          .78 *
          expectedDiagonal /
          math.sqrt(body.width * body.width + body.height * body.height);
      final cell = Rect.fromLTWH(
        (frame % 4) * sheet.width / 4,
        (frame ~/ 4) * sheet.height / 4,
        sheet.width / 4,
        sheet.height / 4,
      );
      c.save();
      c.translate(p.dx, p.dy - height * .28);
      c.rotate(VehicleHeading.delta(angle, heading));
      sprite(
        c,
        sheet,
        Rect.fromLTWH(
          (cell.left - body.center.dx) * scale,
          (cell.top - body.center.dy) * scale,
          cell.width * scale,
          cell.height * scale,
        ),
        source: cell,
        paint:
            Paint()
              ..filterQuality = FilterQuality.medium
              ..color = Color.fromRGBO(255, 255, 255, opacity)
              ..blendMode = BlendMode.plus,
      );
      c.restore();
    }

    drawView(views.from, 1 - views.mix);
    drawView(views.to, views.mix);
    c.restore();
    if (v.preparing) {
      final progress = (v.holdTime / v.preparationDuration).clamp(0.0, 1.0);
      final origin = p + const Offset(-47, -35);
      if (v.service == Service.bags) {
        drawConveyor(c, origin, p + const Offset(0, -19), v.holdTime, 1);
      } else {
        drawFuelFlow(c, origin, p + const Offset(0, -16), v.holdTime);
      }
      c.drawRect(
        Rect.fromLTWH(p.dx - 32, p.dy + 10, 64 * progress, 3),
        Paint()..color = const Color(0xff7adef3),
      );
    }
    if (v.phase != VehiclePhase.parked) {
      final light = Offset(p.dx, p.dy - height * .67);
      c.drawCircle(
        light,
        2.5,
        Paint()
          ..color = Color.fromRGBO(
            255,
            196,
            97,
            .65 + .3 * math.sin(animation * 6).abs(),
          ),
      );
      if (v.trafficWaiting && !v.preparing) {
        c.drawCircle(
          p + Offset(0, -height - 1),
          10,
          Paint()..color = const Color(0xe6282339),
        );
        label(c, 'Ⅱ', p + Offset(-5, -height - 9), 14, const Color(0xffffc97f));
      }
    }
    if (v.phase == VehiclePhase.servicing && v.service != Service.tug) {
      final f = v.flight!;
      final plane = planeRects[f.gate];
      if (v.service == Service.bags) {
        final hatch = Offset(
          plane.left + plane.width * .29,
          plane.top + plane.height * .77,
        );
        // Raised belt connects the trailer to the open cargo door.
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: hatch, width: 24, height: 19),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xff121c31),
        );
        c.drawLine(
          hatch + const Offset(-12, -12),
          hatch + const Offset(12, -17),
          Paint()
            ..color = const Color(0xffa5afcc)
            ..strokeWidth = 4,
        );
        drawConveyor(
          c,
          p + const Offset(8, -18),
          hatch,
          v.workElapsed,
          1 - f.progress[Service.bags]!,
        );
      }
      if (v.service == Service.fuel) {
        final attach = Offset(
          plane.left + plane.width * .63,
          plane.top + plane.height * .77,
        );
        drawFuelFlow(c, p + const Offset(-15, -5), attach, v.workElapsed);
      }
      // Ramp agent with reflective vest next to active equipment.
      final worker = p + const Offset(26, 9);
      c.drawLine(
        worker,
        worker + const Offset(-1, -13),
        Paint()
          ..color = const Color(0xffd4de55)
          ..strokeWidth = 5,
      );
      c.drawCircle(
        worker + const Offset(-1, -17),
        3,
        Paint()..color = const Color(0xffe2b99e),
      );
      c.drawLine(
        worker,
        worker + const Offset(-3, 7),
        Paint()
          ..color = const Color(0xff263044)
          ..strokeWidth = 3,
      );
      c.drawLine(
        worker,
        worker + const Offset(4, 7),
        Paint()
          ..color = const Color(0xff263044)
          ..strokeWidth = 3,
      );
      final bar = Rect.fromLTWH(p.dx - 28, p.dy + 13, 56, 4);
      c.drawRect(bar, Paint()..color = const Color(0xff122139));
      c.drawRect(
        Rect.fromLTWH(bar.left, bar.top, bar.width * f.progress[v.service]!, 4),
        Paint()..color = const Color(0xff9d7aff),
      );
    }
  }

  void drawBoarding(Canvas c, Vehicle bus, Offset p, double heading) {
    final f = bus.flight!;
    final r = planeRects[f.gate];
    final door = AirportLayout.doorSill(r);
    final factor = r.width / 650;
    final foot = door + Offset(7 * factor, 62 * factor);
    final exit = ApronBus.project(p, heading, 47, 22, 0);
    c.drawLine(
      foot,
      door,
      Paint()
        ..color = const Color(0xffb4c0d5)
        ..strokeWidth = 17,
    );
    for (var i = 0; i < 9; i++) {
      final step = Offset.lerp(foot, door, i / 9)!;
      c.drawLine(
        step + const Offset(-7, 0),
        step + const Offset(7, 0),
        Paint()
          ..color = const Color(0xff52617d)
          ..strokeWidth = 2,
      );
    }
    for (final dx in [-10.0, 10.0]) {
      c.drawLine(
        foot + Offset(dx, -9),
        door + Offset(dx, -9),
        Paint()
          ..color = const Color(0xffdde1ef)
          ..strokeWidth = 1.5,
      );
    }
    // Match the existing forward passenger door in the aircraft artwork.
    Offset onBody(double x, double y) =>
        Offset(r.left + r.width * x, r.top + r.height * y);
    final doorway =
        Path()..addPolygon([
          onBody(.219, .707),
          onBody(.240, .699),
          onBody(.257, .797),
          onBody(.230, .817),
        ], true);
    c.drawPath(doorway, Paint()..color = const Color(0xff27384e));
    c.drawPath(
      doorway,
      Paint()
        ..color = const Color(0xffdee2ea)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * factor,
    );
    // Visible hinged door leaf, folded out from the left jamb.
    c.drawPath(
      Path()..addPolygon([
        onBody(.219, .707),
        onBody(.199, .703),
        onBody(.209, .804),
        onBody(.230, .817),
      ], true),
      Paint()..color = const Color(0xffbcc9df),
    );
    c.drawLine(
      foot + Offset(-10 * factor, 0),
      door + Offset(-10 * factor, 0),
      Paint()
        ..color = const Color(0xffe8e9ef)
        ..strokeWidth = 2 * factor,
    );
    // Four-second paths, staggered departures; everyone reaches the door before completion.
    for (var i = 0; i < 12; i++) {
      final progress = (bus.workElapsed - i * .95) / 4;
      if (progress < 0 || progress > .985) continue;
      final person =
          progress < .7
              ? Offset.lerp(exit, foot, progress / .7)!
              : Offset.lerp(foot, door, (progress - .7) / .3)!;
      final stride = math.sin(progress * math.pi * 16) * 2;
      final color =
          [
            const Color(0xffbb88cf),
            const Color(0xff80b7ce),
            const Color(0xffcead7c),
          ][i % 3];
      c.save();
      if (progress > .93) c.clipPath(doorway);
      c.translate(person.dx, person.dy);
      c.scale(1.3 * factor);
      c.translate(-person.dx, -person.dy);
      c.drawOval(
        Rect.fromCenter(center: person, width: 9, height: 3),
        Paint()..color = const Color(0x77030a19),
      );
      for (final side in [-1.0, 1.0]) {
        c.drawLine(
          person + const Offset(0, -6),
          person + Offset(side * 2, side * stride),
          Paint()
            ..color = const Color(0xff283a59)
            ..strokeWidth = 2,
        );
      }
      c.drawLine(
        person + const Offset(0, -5),
        person + const Offset(0, -12),
        Paint()
          ..color = color
          ..strokeWidth = 4,
      );
      c.drawCircle(
        person + const Offset(0, -15),
        2.3,
        Paint()..color = const Color(0xffe0ba98),
      );
      c.restore();
    }
    label(
      c,
      'BOARDING ${(f.progress[Service.bus]! * 100).round()}%',
      p + const Offset(-42, 29),
      12,
      const Color(0xff8edced),
    );
  }

  void drawCase(Canvas c, Offset p, Color color, {double scale = 1}) {
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(scale);
    c.drawOval(
      const Rect.fromLTWH(-8, 2, 20, 7),
      Paint()..color = const Color(0x8803091c),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8, -7, 15, 11),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
    c.drawPath(
      Path()
        ..moveTo(-8, -7)
        ..lineTo(-3, -11)
        ..lineTo(12, -11)
        ..lineTo(7, -7)
        ..close(),
      Paint()..color = Color.lerp(color, const Color(0xffffffff), .35)!,
    );
    c.drawPath(
      Path()
        ..moveTo(7, -7)
        ..lineTo(12, -11)
        ..lineTo(12, 0)
        ..lineTo(7, 4)
        ..close(),
      Paint()..color = Color.lerp(color, const Color(0xff10182f), .4)!,
    );
    c.drawLine(
      const Offset(-1, -7),
      const Offset(-1, 4),
      Paint()
        ..color = const Color(0xffb5b4ce)
        ..strokeWidth = 1.5,
    );
    c.restore();
  }

  void drawConveyor(
    Canvas c,
    Offset start,
    Offset end,
    double time,
    double load,
  ) {
    final d = end - start;
    final n = Offset(-d.dy, d.dx) / math.max(1, d.distance);
    for (final t in [.1, .8]) {
      final foot = Offset.lerp(start, end, t)!;
      c.drawLine(
        foot,
        foot + const Offset(0, 15),
        Paint()
          ..color = const Color(0xff8191a7)
          ..strokeWidth = 3,
      );
    }
    c.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xff919cb7)
        ..strokeWidth = 21,
    );
    c.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xff25304a)
        ..strokeWidth = 15,
    );
    for (var i = 0; i < 13; i++) {
      final t = (i / 13 + time * .24) % 1;
      final p = Offset.lerp(start, end, t)!;
      c.drawLine(
        p - n * 6,
        p + n * 6,
        Paint()
          ..color = const Color(0xff5b6a88)
          ..strokeWidth = 1.5,
      );
    }
    for (var i = 0; i < 3; i++) {
      final t = (time * .24 + i / 3) % 1;
      drawCase(
        c,
        Offset.lerp(start, end, t)! + const Offset(0, -5),
        [
          const Color(0xff9265c4),
          const Color(0xff4ea6b8),
          const Color(0xffce955a),
        ][i],
        scale: .8,
      );
    }
    for (var i = 0; i < (load * 4).ceil(); i++) {
      drawCase(
        c,
        start + Offset(-19 - (i % 2) * 12, 10 - (i ~/ 2) * 10),
        const Color(0xff7658a6),
        scale: .7,
      );
    }
  }

  void drawFuelFlow(Canvas c, Offset start, Offset end, double time) {
    final control = (start + end) / 2 + const Offset(15, 22);
    final hose =
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    c.drawPath(
      hose,
      Paint()
        ..color = const Color(0xff080e1c)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    c.drawPath(
      hose,
      Paint()
        ..color = const Color(0xff607890)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final t = (time * .6) % 1;
    final flow =
        start * ((1 - t) * (1 - t)) +
        control * (2 * (1 - t) * t) +
        end * (t * t);
    c.drawCircle(flow, 2.5, Paint()..color = const Color(0xff84dfeb));
  }

  void drawDepots(Canvas c) {
    // Dedicated supply points sit beside the staging pockets, off the road.
    for (var i = 0; sceneIndex < 0 && i < 6; i++) {
      final p = point(shift.layout.nodes['park$i']!) + const Offset(-48, -26);
      c.drawPath(
        Path()
          ..moveTo(p.dx - 18, p.dy + 7)
          ..lineTo(p.dx + 10, p.dy + 7)
          ..lineTo(p.dx + 18, p.dy)
          ..lineTo(p.dx - 10, p.dy)
          ..close(),
        Paint()..color = const Color(0xff293955),
      );
      if (i == 0 || i == 3) {
        for (var j = 0; j < 3; j++) {
          drawCase(c, p + Offset(0, -j * 10.0), const Color(0xff7764a2));
        }
      } else if (i == 1) {
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(p.dx - 11, p.dy - 37, 23, 38),
            const Radius.circular(5),
          ),
          Paint()..color = const Color(0xff8a9cb3),
        );
        c.drawOval(
          Rect.fromLTWH(p.dx - 11, p.dy - 40, 23, 10),
          Paint()..color = const Color(0xffc4cfe0),
        );
        c.drawRect(
          Rect.fromLTWH(p.dx - 10, p.dy - 24, 21, 7),
          Paint()..color = const Color(0xffdfb772),
        );
        label(c, 'F', p + const Offset(-4, -21), 12, const Color(0xff19263e));
      }
    }
  }

  void drawFlightTag(Canvas c, Flight f) {
    final p =
        planeRects[f.gate].topLeft +
        Offset(planeRects[f.gate].width * .08, planeRects[f.gate].height * .45);
    final active = f.gate == selected;
    final overdue = shift.elapsed > f.deadline && !f.departed;
    final rect = Rect.fromLTWH(p.dx, p.dy, 183, 63);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()..color = const Color(0xee0e1933),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..color = active ? const Color(0xffa88aff) : const Color(0xff5a7999)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.8 : 1.4,
    );
    label(
      c,
      'A${f.gate + 1}  ·  ${f.code}',
      p + const Offset(12, 9),
      16,
      const Color(0xffeaf0ff),
    );
    label(
      c,
      f.departed
          ? 'FLIGHT DEPARTED'
          : f.jobs[Service.tug] == JobState.working
          ? (shift.layout.departsForward(f.gate) ? 'FORWARD TOW' : 'PUSHBACK')
          : '${overdue ? '+' : ''}${clockText((f.deadline - shift.elapsed).abs())}  TO DEPARTURE',
      p + const Offset(12, 35),
      12,
      overdue ? const Color(0xffffbd83) : const Color(0xff99d6ff),
    );
  }

  void drawDetails(Canvas c) {
    // Blue edge lights and subtle halos remain independent of the texture.
    for (var y = 260.0; y < 1060; y += 95) {
      final p = Offset(895, y) + sceneBounds.topLeft;
      c.drawCircle(
        p,
        12,
        Paint()
          ..color = const Color(0x2245aaff)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      c.drawCircle(p, 2.3, Paint()..color = const Color(0xff86ceff));
    }
  }
}
