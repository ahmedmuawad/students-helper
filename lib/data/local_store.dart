import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// تخزين محلي بصيغة JSON فوق [SharedPreferences].
///
/// التطبيق **أوفلاين أولًا**: كل قراءة وكتابة بتحصل محليًا وفورًا، والمزامنة
/// مع السيرفر بتحصل في الخلفية. كده الطالب يشتغل من غير نت خالص.
class LocalStore {
  final SharedPreferences _prefs;

  const LocalStore(this._prefs);

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }

  // ----- قيم مفردة -----

  String? readString(String key) => _prefs.getString(key);

  Future<void> writeString(String key, String value) =>
      _prefs.setString(key, value);

  bool readBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> writeBool(String key, bool value) => _prefs.setBool(key, value);

  int readInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;

  Future<void> writeInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> remove(String key) => _prefs.remove(key);

  // ----- كائن واحد -----

  Map<String, dynamic>? readObject(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // بيانات تالفة — بنتجاهلها بدل ما التطبيق يقع عند الفتح.
      return null;
    }
    return null;
  }

  Future<void> writeObject(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  // ----- قوائم -----

  /// قراءة قائمة كائنات وتحويلها لموديلات.
  ///
  /// أي عنصر تالف بيتتخطى بدل ما يضيّع القائمة كلها.
  List<T> readList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <T>[];

    late final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return <T>[];
    }
    if (decoded is! List) return <T>[];

    final result = <T>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        result.add(fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        continue;
      }
    }
    return result;
  }

  Future<void> writeList<T>(
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) {
    final encoded = jsonEncode(items.map(toJson).toList());
    return _prefs.setString(key, encoded);
  }

  Future<void> clearAll() => _prefs.clear();
}

/// مفاتيح التخزين — مجمّعة في مكان واحد عشان ما يحصلش تعارض.
class StoreKeys {
  static const profile = 'profile';
  static const subjects = 'subjects';
  static const periods = 'school_periods';
  static const lessons = 'private_lessons';
  static const instructors = 'instructors';
  static const tasks = 'study_tasks';
  static const exams = 'exams';
  static const guardianLinks = 'guardian_links';
  static const calcHistory = 'calc_history';
  static const calcAngleMode = 'calc_angle_mode';
  static const calcBase = 'calc_base';
  static const calcVariables = 'calc_variables';
  static const languageCode = 'language_code';
  static const themeMode = 'theme_mode';
  static const onboardingDone = 'onboarding_done';
  static const accountRole = 'account_role';
  static const personalizedAds = 'personalized_ads';
  static const lastSyncAt = 'last_sync_at';
  static const syncCursor = 'sync_cursor';
  static const syncPending = 'sync_pending';
}
