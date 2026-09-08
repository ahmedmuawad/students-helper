import 'enums.dart';

/// مهمة دراسية — واجب أو مذاكرة أو مراجعة، ممكن تترط بحصة مدرسية أو درس خصوصي.
class StudyTask {
  final String id;
  final String title;
  final String details;
  final TaskType type;
  final TaskPriority priority;
  final String subjectId;

  /// موعد التسليم / الاستحقاق.
  final DateTime? dueDate;

  /// ربط بحصة مدرسية (معرّف [SchoolPeriod]) — يعني المهمة دي لازم تخلص قبلها.
  final String? linkedPeriodId;

  /// ربط بدرس خصوصي (معرّف [PrivateLesson]).
  final String? linkedLessonId;

  final bool isDone;
  final DateTime? completedAt;

  /// الوقت المقدّر لإنجاز المهمة بالدقائق (مدخل لخوارزمية الجدولة).
  final int estimatedMinutes;

  /// وقت المذاكرة الفعلي المسجّل من مؤقّت التركيز.
  final int spentMinutes;

  final DateTime createdAt;

  const StudyTask({
    required this.id,
    required this.title,
    this.details = '',
    this.type = TaskType.homework,
    this.priority = TaskPriority.normal,
    this.subjectId = '',
    this.dueDate,
    this.linkedPeriodId,
    this.linkedLessonId,
    this.isDone = false,
    this.completedAt,
    this.estimatedMinutes = 30,
    this.spentMinutes = 0,
    required this.createdAt,
  });

  bool get isLinked => linkedPeriodId != null || linkedLessonId != null;

  /// متأخرة؟ (فات موعدها وهي لسه مش خلصانة)
  bool get isOverdue {
    final due = dueDate;
    if (due == null || isDone) return false;
    return due.isBefore(DateTime.now());
  }

  StudyTask copyWith({
    String? title,
    String? details,
    TaskType? type,
    TaskPriority? priority,
    String? subjectId,
    DateTime? dueDate,
    String? linkedPeriodId,
    String? linkedLessonId,
    bool? isDone,
    DateTime? completedAt,
    int? estimatedMinutes,
    int? spentMinutes,
    bool clearDueDate = false,
    bool clearLinks = false,
  }) {
    return StudyTask(
      id: id,
      title: title ?? this.title,
      details: details ?? this.details,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      subjectId: subjectId ?? this.subjectId,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      linkedPeriodId:
          clearLinks ? null : (linkedPeriodId ?? this.linkedPeriodId),
      linkedLessonId:
          clearLinks ? null : (linkedLessonId ?? this.linkedLessonId),
      isDone: isDone ?? this.isDone,
      completedAt: completedAt ?? this.completedAt,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      spentMinutes: spentMinutes ?? this.spentMinutes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'details': details,
        'type': type.name,
        'priority': priority.name,
        'subjectId': subjectId,
        'dueDate': dueDate?.toIso8601String(),
        'linkedPeriodId': linkedPeriodId,
        'linkedLessonId': linkedLessonId,
        'isDone': isDone,
        'completedAt': completedAt?.toIso8601String(),
        'estimatedMinutes': estimatedMinutes,
        'spentMinutes': spentMinutes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory StudyTask.fromJson(Map<String, dynamic> json) => StudyTask(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        details: json['details'] as String? ?? '',
        type: TaskType.fromId(json['type'] as String?),
        priority: TaskPriority.fromId(json['priority'] as String?),
        subjectId: json['subjectId'] as String? ?? '',
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.tryParse(json['dueDate'] as String),
        linkedPeriodId: json['linkedPeriodId'] as String?,
        linkedLessonId: json['linkedLessonId'] as String?,
        isDone: json['isDone'] as bool? ?? false,
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.tryParse(json['completedAt'] as String),
        estimatedMinutes: json['estimatedMinutes'] as int? ?? 30,
        spentMinutes: json['spentMinutes'] as int? ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
