import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'missions.dart';

class Campaign {
  final best = List<int>.filled(Mission.all.length, 0);
  SharedPreferences? _preferences;
  bool saveFailed = false;
  int get stars => best.fold(0, (sum, value) => sum + value);
  bool unlocked(int id) => id == 0 || best[id - 1] >= 2;
  Future<void> load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      for (var i = 0; i < best.length; i++) {
        best[i] = (_preferences!.getInt('mission.$i.stars') ?? 0).clamp(0, 3);
      }
    } catch (_) {
      saveFailed = true;
    }
  }

  Future<void> record(int id, int stars) async {
    best[id] = max(best[id], stars);
    try {
      final saved = await _preferences?.setInt('mission.$id.stars', best[id]);
      saveFailed = saved != true;
    } catch (_) {
      saveFailed = true;
    }
  }
}
