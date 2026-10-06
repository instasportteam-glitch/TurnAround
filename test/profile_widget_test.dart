import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jegd/main.dart';
import 'package:jegd/profile_screen.dart';
import 'package:jegd/game/player_profile.dart';
import 'package:jegd/game/airport_game.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Profile switches the whole app to German, saves name, and restores on restart',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const TurnaroundApp());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('profile-name')), 'Lena');
      await tester.tap(find.text('Deutsch'));
      await tester.pumpAndSettle();
      expect(find.text('Profil'), findsOneWidget);
      await tester.ensureVisible(find.text('Profil speichern'));
      await tester.tap(find.text('Profil speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Erster Abflug'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const TurnaroundApp());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Erster Abflug'), findsOneWidget);
      await tester.tap(find.byTooltip('Profil'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('profile-name')))
            .controller!
            .text,
        'Lena',
      );
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Erster Abflug'), findsOneWidget); // Discarded draft.
      await tester.ensureVisible(find.text('SCHICHT STARTEN'));
      await tester.tap(find.text('SCHICHT STARTEN'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Gepäck'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Avatar import normalizes dimensions, saves bytes and supports removal',
    (tester) async {
      final profile = PlayerProfile();
      await profile.load();
      Uint8List? image;
      await tester.runAsync(() async {
        image =
            (await rootBundle.load(
              'assets/images/apron.png',
            )).buffer.asUint8List();
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('en'), Locale('de')],
          home: Scaffold(
            body: ProfileScreen(profile: profile, pickImage: () async => image),
          ),
        ),
      );
      await tester.runAsync(() async {
        final action =
            tester
                .widget<TextButton>(
                  find
                      .ancestor(
                        of: find.text('Choose avatar'),
                        matching: find.byWidgetPredicate(
                          (w) => w is TextButton,
                        ),
                      )
                      .first,
                )
                .onPressed!;
        await (action as Future<void> Function())();
      });
      await tester.pumpAndSettle();
      expect(find.text('Remove photo'), findsOneWidget);
      await tester.runAsync(() async {
        final action =
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save profile'),
                )
                .onPressed!;
        await (action as Future<void> Function())();
      });
      await tester.pump();
      expect(profile.avatar, isNotNull);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(profile.avatar!);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 256);
        expect(frame.image.height, 256);
        frame.image.dispose();
        codec.dispose();
      });
      expect(profile.avatar!.length, lessThan(350000));
      final restored = PlayerProfile();
      await restored.load();
      expect(restored.avatar, profile.avatar);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('A failed shift enters history exactly once', (tester) async {
    await tester.pumpWidget(const TurnaroundApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('START SHIFT'));
    await tester.tap(find.text('START SHIFT'));
    await tester.pump();
    final game =
        tester
            .widget<GameWidget<AirportGame>>(
              find.byType(GameWidget<AirportGame>),
            )
            .game!;
    game.shift.tick(game.shift.timeLimit);
    game.onFrame();
    await tester.pump(const Duration(milliseconds: 100));
    game.onFrame();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Shift history'));
    expect(find.text('Departed: 0/1 · On time: 0/1'), findsOneWidget);
    final restored = PlayerProfile();
    await restored.load();
    expect(restored.history.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Opening profile pauses vehicles and closing restores the previous pause state',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const TurnaroundApp());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('START SHIFT'));
      await tester.tap(find.text('START SHIFT'));
      await tester.pump();
      final game =
          tester
              .widget<GameWidget<AirportGame>>(
                find.byType(GameWidget<AirportGame>),
              )
              .game!;
      expect(game.shift.paused, isFalse);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      final before = game.shift.elapsed;
      game.shift.tick(5);
      expect(game.shift.elapsed, before);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(game.shift.paused, isFalse);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(game.shift.paused, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
