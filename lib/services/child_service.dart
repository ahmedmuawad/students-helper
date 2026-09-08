import '../models/private_lesson.dart';
import '../models/school_period.dart';
import '../models/study_task.dart';
import 'api_client.dart';

/// ابن مربوط بولي الأمر، زي ما السيرفر بيرجّعه.
class LinkedChild {
  final int studentId;
  final String name;
  final int? gradeLevel;
  final Map<String, dynamic> permissions;

  const LinkedChild({
    required this.studentId,
    required this.name,
    this.gradeLevel,
    this.permissions = const {},
  });

  bool can(String permission) => permissions[permission] == true;

  bool get canSeeTimetable => can('viewTimetable');
  bool get canSeeLessons => can('viewLessons');
  bool get canSeeTasks => can('viewTasks');
  bool get canSeeCosts => can('viewLessonCosts');

  factory LinkedChild.fromJson(Map<String, dynamic> json) => LinkedChild(
        studentId: json['student_id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        gradeLevel: json['grade_level'] as int?,
        permissions: json['permissions'] is Map
            ? Map<String, dynamic>.from(json['permissions'] as Map)
            : const {},
      );
}

/// بيانات الابن المسموح لولي أمره يشوفها.
class ChildData {
  final List<SchoolPeriod> periods;
  final List<PrivateLesson> lessons;
  final List<StudyTask> tasks;

  const ChildData({
    this.periods = const [],
    this.lessons = const [],
    this.tasks = const [],
  });

  bool get isEmpty => periods.isEmpty && lessons.isEmpty && tasks.isEmpty;

  /// المهام اللي فات موعدها ولسه ما خلصتش — ده اللي ولي الأمر بيدوّر عليه.
  List<StudyTask> get overdueTasks =>
      tasks.where((t) => t.isOverdue).toList(growable: false);

  List<StudyTask> get pendingTasks =>
      tasks.where((t) => !t.isDone).toList(growable: false);
}

/// قراءة ولي الأمر لبيانات ابنه.
///
/// السيرفر هو اللي بيفلتر حسب الصلاحيات اللي الطالب سمح بيها — التطبيق
/// مش بيخبّي حاجة، هو أصلاً مش بيستلمها.
class ChildService {
  final ApiClient _api;

  const ChildService(this._api);

  Future<List<LinkedChild>> children() async {
    final data = await _api.get('/api/v1/children');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => LinkedChild.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<ChildData> dataFor(int studentId) async {
    final data = await _api.get('/api/v1/children/$studentId/records');
    if (data is! Map) return const ChildData();

    final periods = <SchoolPeriod>[];
    final lessons = <PrivateLesson>[];
    final tasks = <StudyTask>[];

    for (final item in (data['records'] as List? ?? const [])) {
      if (item is! Map) continue;
      final record = Map<String, dynamic>.from(item);
      if (record['deleted'] == true) continue;

      final payload = record['payload'];
      if (payload is! Map) continue;
      final json = Map<String, dynamic>.from(payload);

      // سجل واحد مش مفهوم مايضيّعش الصفحة كلها
      try {
        switch (record['kind']) {
          case 'period':
            periods.add(SchoolPeriod.fromJson(json));
          case 'lesson':
            lessons.add(PrivateLesson.fromJson(json));
          case 'task':
            tasks.add(StudyTask.fromJson(json));
        }
      } catch (_) {
        continue;
      }
    }

    return ChildData(periods: periods, lessons: lessons, tasks: tasks);
  }
}
