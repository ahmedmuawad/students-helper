/// درس خصوصي — يا إما متكرر أسبوعيًا أو بموعد واحد محدد.
class PrivateLesson {
  final String id;
  final String subjectId;

  /// معرّف المدرس أو السنتر في دفتر جهات الاتصال — بيانات التواصل والعنوان
  /// محفوظة هناك مرة واحدة وبتترّبط بكل دروسه.
  final String instructorId;

  /// اسم المدرس المكتوب مباشرة — بيتستخدم لو الدرس مش مربوط بجهة محفوظة.
  final String teacherName;

  /// المكان: سنتر، بيت المدرس، أونلاين ...
  final String place;

  /// وصف الحصة (مثال: "حصة 5 - المتتابعات").
  final String sessionTitle;

  /// متكرر أسبوعيًا؟ لو false بيستخدم [specificDate].
  final bool isWeekly;

  /// يوم الأسبوع للدرس المتكرر حسب [DateTime.weekday].
  final int weekday;

  /// تاريخ محدد للدرس غير المتكرر.
  final DateTime? specificDate;

  final int startMinutes;
  final int endMinutes;

  /// تذكير قبل الدرس بيوم لو فيه مهام مرتبطة بيه.
  final bool remindDayBefore;

  /// تذكير إضافي قبل الدرس بعدد دقائق (0 = مفيش).
  final int remindBeforeMinutes;

  /// تكلفة الحصة (اختياري — لمتابعة مصاريف الدروس).
  final double cost;

  final String note;

  const PrivateLesson({
    required this.id,
    required this.subjectId,
    this.instructorId = '',
    this.teacherName = '',
    this.place = '',
    this.sessionTitle = '',
    this.isWeekly = true,
    this.weekday = DateTime.saturday,
    this.specificDate,
    required this.startMinutes,
    required this.endMinutes,
    this.remindDayBefore = true,
    this.remindBeforeMinutes = 60,
    this.cost = 0,
    this.note = '',
  });

  int get durationMinutes => endMinutes - startMinutes;

  /// هل الدرس ده بيقع في اليوم [day]؟
  bool occursOn(DateTime day) {
    if (isWeekly) return day.weekday == weekday;
    final specific = specificDate;
    if (specific == null) return false;
    return specific.year == day.year &&
        specific.month == day.month &&
        specific.day == day.day;
  }

  PrivateLesson copyWith({
    String? subjectId,
    String? instructorId,
    String? teacherName,
    String? place,
    String? sessionTitle,
    bool? isWeekly,
    int? weekday,
    DateTime? specificDate,
    int? startMinutes,
    int? endMinutes,
    bool? remindDayBefore,
    int? remindBeforeMinutes,
    double? cost,
    String? note,
  }) {
    return PrivateLesson(
      id: id,
      subjectId: subjectId ?? this.subjectId,
      instructorId: instructorId ?? this.instructorId,
      teacherName: teacherName ?? this.teacherName,
      place: place ?? this.place,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      isWeekly: isWeekly ?? this.isWeekly,
      weekday: weekday ?? this.weekday,
      specificDate: specificDate ?? this.specificDate,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      remindDayBefore: remindDayBefore ?? this.remindDayBefore,
      remindBeforeMinutes: remindBeforeMinutes ?? this.remindBeforeMinutes,
      cost: cost ?? this.cost,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'teacherName': teacherName,
        'place': place,
        'sessionTitle': sessionTitle,
        'isWeekly': isWeekly,
        'weekday': weekday,
        'specificDate': specificDate?.toIso8601String(),
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'remindDayBefore': remindDayBefore,
        'remindBeforeMinutes': remindBeforeMinutes,
        'cost': cost,
        'note': note,
      };

  factory PrivateLesson.fromJson(Map<String, dynamic> json) => PrivateLesson(
        id: json['id'] as String,
        subjectId: json['subjectId'] as String? ?? '',
        teacherName: json['teacherName'] as String? ?? '',
        place: json['place'] as String? ?? '',
        sessionTitle: json['sessionTitle'] as String? ?? '',
        isWeekly: json['isWeekly'] as bool? ?? true,
        weekday: json['weekday'] as int? ?? DateTime.saturday,
        specificDate: json['specificDate'] == null
            ? null
            : DateTime.tryParse(json['specificDate'] as String),
        startMinutes: json['startMinutes'] as int? ?? 16 * 60,
        endMinutes: json['endMinutes'] as int? ?? 17 * 60 + 30,
        remindDayBefore: json['remindDayBefore'] as bool? ?? true,
        remindBeforeMinutes: json['remindBeforeMinutes'] as int? ?? 60,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        note: json['note'] as String? ?? '',
      );
}
