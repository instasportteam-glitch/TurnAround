import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jegd/game/campaign.dart';
import 'package:jegd/game/missions.dart';
import 'package:jegd/game/shift.dart';

void main() {
  for (final mission in Mission.all) {
    test('${mission.title}: all objectives and flights can be completed', () {
      final s = Shift(mission: mission);
      for (var i = 0; i < mission.seconds * 20 + 1 && !s.finished; i++) {
        for (final task in s.tasks) {
          s.startTask(task);
        }
        for (final f in s.flights) {
          for (final service in Service.values) {
            s.dispatch(f, service);
          }
        }
        s.tick(.05);
      }
      expect(
        s.completed,
        mission.deadlines.length,
        reason:
            '${mission.title} at ${s.elapsed}: ${s.flights.map((f) => f.jobs)}',
      );
      expect(
        s.onTime,
        mission.deadlines.length,
        reason: '${mission.title}: ${s.flights.map((f) => f.departedAt)}',
      );
      expect(s.tasks.every((t) => t.done), isTrue);
    });
  }
  test(
    'One crew respects prerequisites and pause; icing expires and requires a repeat',
    () {
      final s = Shift(mission: Mission.all[4]);
      expect(s.startTask(s.tasks.first), isFalse);
      for (final f in s.flights) {
        f.jobs[Service.bus] = JobState.done;
      }
      expect(s.startTask(s.tasks.first), isTrue);
      expect(s.startTask(s.tasks.last), isFalse);
      s.paused = true;
      s.tick(30);
      expect(s.tasks.first.progress, 0);
      s.paused = false;
      s.tick(23);
      expect(s.tasks.first.done, isTrue);
      s.tick(91);
      expect(s.tasks.first.done, isFalse);
      expect(s.repeatedTasks, 1);
      expect(s.startTask(s.tasks.first), isTrue);
    },
  );
  test(
    'Progress persists best stars and unlocks only after completing both flights',
    () async {
      SharedPreferences.setMockInitialValues({});
      final campaign = Campaign();
      await campaign.load();
      expect(campaign.unlocked(1), isFalse);
      await campaign.record(0, 1);
      expect(campaign.unlocked(1), isFalse);
      await campaign.record(0, 3);
      await campaign.record(0, 2);
      final restored = Campaign();
      await restored.load();
      expect(restored.best[0], 3);
      expect(restored.unlocked(1), isTrue);
      expect(restored.unlocked(2), isFalse);
    },
  );
}
