import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'missions.dart';
import 'shift.dart';

class ShiftRecord {
  const ShiftRecord({
    required this.mission,
    required this.finishedAt,
    required this.stars,
    required this.departed,
    required this.total,
    required this.onTime,
    required this.credits,
    required this.seconds,
  });
  final int mission, stars, departed, total, onTime, credits, seconds;
  final DateTime finishedAt;
  Map<String, Object> toJson() => {
    'mission': mission,
    'at': finishedAt.toUtc().toIso8601String(),
    'stars': stars,
    'departed': departed,
    'total': total,
    'onTime': onTime,
    'credits': credits,
    'seconds': seconds,
  };
  static ShiftRecord? parse(dynamic value) {
    try {
      final m = value as Map<String, dynamic>;
      final r = ShiftRecord(
        mission: m['mission'] as int,
        finishedAt: DateTime.parse(m['at'] as String),
        stars: m['stars'] as int,
        departed: m['departed'] as int,
        total: m['total'] as int,
        onTime: m['onTime'] as int,
        credits: m['credits'] as int,
        seconds: m['seconds'] as int,
      );
      if (r.mission < 0 ||
          r.mission >= Mission.all.length ||
          r.stars < 0 ||
          r.stars > 3 ||
          r.total < 1 ||
          r.total > 4 ||
          r.departed < 0 ||
          r.departed > r.total ||
          r.onTime < 0 ||
          r.onTime > r.departed ||
          r.seconds < 0 ||
          r.credits < 0) {
        return null;
      }
      return r;
    } catch (_) {
      return null;
    }
  }
}

class PlayerProfile extends ChangeNotifier {
  static const storageKey = 'player.profile.v1';
  static const historyKey = 'player.history.v1';
  static const historyLimit = 50;
  String name = 'Captain';
  String language = 'en';
  Uint8List? avatar;
  final List<ShiftRecord> _history = [];
  List<ShiftRecord> get history => List.unmodifiable(_history);
  bool loaded = false, historySaveFailed = false;
  SharedPreferences? _preferences;
  Future<void>? _loading;
  bool _disposed = false;
  Future<void> load() => _loading ??= _load();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      final raw = _preferences!.getString(storageKey);
      if (raw != null) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final savedName = data['name'];
          if (savedName is String && validName(savedName)) {
            name = savedName.trim();
          }
          if (data['language'] == 'de') language = 'de';
          final photo = data['avatar'];
          if (photo is String && photo.length < 500000) {
            avatar = base64Decode(photo);
          }
        } catch (_) {
          /* Keep usable defaults if one stored profile is damaged. */
        }
      }
      final history = _preferences!.getString(historyKey);
      if (history != null) {
        try {
          final entries = jsonDecode(history) as List;
          _history.addAll(
            entries
                .map(ShiftRecord.parse)
                .whereType<ShiftRecord>()
                .take(historyLimit),
          );
        } catch (_) {
          /* A corrupt history must not block the game. */
        }
      }
    } catch (_) {
      historySaveFailed = true;
    }
    loaded = true;
    _changed();
  }

  static bool validName(String value) =>
      value.trim().isNotEmpty &&
      value.trim().characters.length <= 24 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

  Future<bool> save({
    required String name,
    required String language,
    Uint8List? avatar,
  }) async {
    await load();
    if (!validName(name) ||
        !['en', 'de'].contains(language) ||
        (avatar?.length ?? 0) > 350000) {
      return false;
    }
    try {
      final ok = await _preferences?.setString(
        storageKey,
        jsonEncode({
          'name': name.trim(),
          'language': language,
          'avatar': avatar == null ? null : base64Encode(avatar),
        }),
      );
      if (ok != true) return false;
      this.name = name.trim();
      this.language = language;
      this.avatar = avatar;
      _changed();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> record(Shift shift) async {
    // Snapshot immediately; another mission can start while storage is loading.
    if (!shift.finished) return;
    final entry = ShiftRecord(
      mission: shift.mission.id,
      finishedAt: DateTime.now(),
      stars: shift.stars,
      departed: shift.completed,
      total: shift.flights.length,
      onTime: shift.onTime,
      credits: shift.credits,
      seconds: shift.elapsed.round(),
    );
    await load();
    _history.insert(0, entry);
    if (_history.length > historyLimit) {
      _history.removeRange(historyLimit, _history.length);
    }
    try {
      historySaveFailed =
          await _preferences?.setString(
            historyKey,
            jsonEncode(_history.map((r) => r.toJson()).toList()),
          ) !=
          true;
    } catch (_) {
      historySaveFailed = true;
    }
    _changed();
  }
}
