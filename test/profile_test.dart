import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jegd/game/player_profile.dart';
import 'package:jegd/game/missions.dart';
import 'package:jegd/game/shift.dart';
import 'package:jegd/l10n/catalog.dart';
import 'package:jegd/l10n/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Name, language, avatar persist independently of campaign progress',
    () async {
      SharedPreferences.setMockInitialValues({'mission.0.stars': 3});
      final p = PlayerProfile();
      await p.load();
      expect(p.language, 'en');
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(
        await p.save(name: '  Anna ✈️  ', language: 'de', avatar: bytes),
        isTrue,
      );
      final restored = PlayerProfile();
      await restored.load();
      expect(restored.name, 'Anna ✈️');
      expect(restored.language, 'de');
      expect(restored.avatar, bytes);
      expect(
        (await SharedPreferences.getInstance()).getInt('mission.0.stars'),
        3,
      );
      expect(await restored.save(name: 'Anna', language: 'en'), isTrue);
      final cleared = PlayerProfile();
      await cleared.load();
      expect(cleared.avatar, isNull);
      expect(cleared.language, 'en');
    },
  );
  test(
    'Empty, control-character and long names cannot overwrite the profile',
    () async {
      final p = PlayerProfile();
      await p.load();
      for (final name in ['', '   ', 'A\nB', 'a' * 25]) {
        expect(await p.save(name: name, language: 'de'), isFalse);
      }
      expect(p.name, 'Captain');
      expect(PlayerProfile.validName('✈️' * 24), isTrue);
    },
  );
  test(
    'History snapshots finished shifts only and keeps latest 50 on reload',
    () async {
      final p = PlayerProfile();
      await p.load();
      final shift = Shift(mission: Mission.all[0]);
      await p.record(shift);
      expect(p.history, isEmpty);
      shift.tick(shift.timeLimit);
      expect(shift.finished, isTrue);
      await p.record(shift);
      expect(p.history.single.departed, 0);
      expect(p.history.single.stars, 0);
      expect(p.history.single.seconds, 360);
      for (var i = 0; i < 51; i++) {
        final completed = Shift(mission: Mission.all[1]);
        for (final f in completed.flights) {
          f.departedAt = 250;
        }
        completed.elapsed = 250;
        completed.finished = true;
        await p.record(completed);
      }
      final restored = PlayerProfile();
      await restored.load();
      expect(restored.history.length, 50);
      expect(restored.history.every((r) => r.mission == 1), isTrue);
      expect(restored.history.first.onTime, 2);
      expect(restored.history.first.credits, 400);
    },
  );
  test(
    'Malformed persisted data recovers; invalid history entries are ignored',
    () async {
      SharedPreferences.setMockInitialValues({
        PlayerProfile.storageKey: '{invalid',
        PlayerProfile.historyKey: jsonEncode([
          {'mission': 99},
          null,
        ]),
      });
      final p = PlayerProfile();
      await p.load();
      expect(p.loaded, isTrue);
      expect(p.name, 'Captain');
      expect(p.history, isEmpty);
      expect(await p.save(name: 'Alex', language: 'de'), isTrue);
    },
  );
  test(
    'German catalog covers mission copy and composed messages without partial-word replacement',
    () {
      const de = GameStrings('de');
      for (final e in germanCatalog.entries) {
        expect(de.tr(e.key), e.value, reason: e.key);
        expect(const GameStrings('en').tr(e.key), e.key);
      }
      for (final m in Mission.all) {
        expect(germanCatalog.containsKey(m.title), isTrue);
        expect(germanCatalog.containsKey(m.brief), isTrue);
        expect(germanCatalog.containsKey(m.airport), isTrue);
        for (final task in m.tasks) {
          expect(germanCatalog.containsKey(task.title), isTrue);
        }
      }
      expect(de.tr('2. Night Express'), '2. Nachtexpress');
      expect(de.tr('Assign: Fuel'), 'Zuweisen: Treibstoff');
      expect(
        de.tr('First dispatch A1 — shared corridor'),
        'Zuerst A1 abfertigen — gemeinsame Fahrgasse',
      );
      expect(
        de.tr('Departed: 2/3 · On time: 1/3'),
        'Abgeflogen: 2/3 · Pünktlich: 1/3',
      );
      expect(de.tr('Restarted'), 'Restarted');
    },
  );
}
