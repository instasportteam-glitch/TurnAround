import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jegd/main.dart';
import 'package:flame/game.dart';
import 'package:jegd/game/airport_game.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Briefing starts playable shift, pause stops it, restart restores briefing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TurnaroundApp());
      await tester.ensureVisible(find.text('START SHIFT'));
      expect(find.text('START SHIFT'), findsOneWidget);
      await tester.tap(find.text('START SHIFT'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('START SHIFT'), findsNothing);
      expect(find.text('Baggage'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(find.text('Shift paused'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      expect(find.text('START SHIFT'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Saved campaign unlocks coastal mission and exposes its tasks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mission.0.stars': 3,
      'mission.1.stars': 2,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const TurnaroundApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('CHOOSE MISSION'));
    await tester.tap(find.text('CHOOSE MISSION'));
    await tester.pump();
    expect(find.text('MISSION MAP'), findsOneWidget);
    await tester.ensureVisible(find.text('3. Sea Breeze'));
    await tester.tap(find.text('3. Sea Breeze'));
    await tester.pump();
    expect(find.text('Sea Breeze'), findsOneWidget);
    await tester.ensureVisible(find.text('START SHIFT'));
    await tester.tap(find.text('START SHIFT'));
    await tester.pump();
    expect(find.textContaining('Secure equipment'), findsOneWidget);
    final game =
        tester.widget<GameWidget>(find.byType(GameWidget<AirportGame>)).game
            as AirportGame;
    await tester.tap(find.text('Coastal apron'));
    await tester.pump();
    expect(game.sceneIndex, 1);
    expect(game.visibleGates, [2]);
    final before = game.viewCenter;
    await tester.drag(
      find.byType(GameWidget<AirportGame>),
      const Offset(-140, 50),
    );
    await tester.pump();
    expect(game.viewCenter, before);
    await tester.tap(find.text('Services'));
    await tester.pump();
    expect(game.sceneIndex, -1);
    await tester.tap(find.text('Terminal'));
    await tester.pump();
    expect(game.visibleGates, [0, 1]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final size in [const Size(375, 667), const Size(430, 932)]) {
    testWidgets('Phone layout ${size.width} x ${size.height}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TurnaroundApp());
      await tester.ensureVisible(find.text('START SHIFT'));
      await tester.tap(find.text('START SHIFT'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('START SHIFT'), findsNothing);
      await tester.tap(find.text('Baggage'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
