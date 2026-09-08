/// حصة في الجدول المدرسي الأسبوعي.
class SchoolPeriod {
  final String id;

  /// يوم الأسبوع حسب [DateTime.weekday] (1 = الاثنين ... 7 = الأحد).
  final int weekday;

  /// رقم الحصة في اليوم (1، 2، 3 ...).
  final int periodNumber;

  final String subjectId;
  final String teacherName;

  /// المكان: رقم الفصل أو المعمل.
  final String room;

  /// بداية الحصة بالدقائق من منتصف الليل.
  final int startMinutes;

  /// نهاية الحصة بالدقائق من منتصف الليل.
  final int endMinutes;

  final String note;

  const SchoolPeriod({
    required this.id,
    required this.weekday,
    required this.periodNumber,
    required this.subjectId,
    this.teacherName = '',
    this.room = '',
    required this.startMinutes,
    required this.endMinutes,
    this.note = '',
  });

  int get durationMinutes => endMinutes - startMinutes;

  SchoolPeriod copyWith({
    int? weekday,
    int? periodNumber,
    String? subjectId,
    String? teacherName,
    String? room,
    int? startMinutes,
    int? endMinutes,
    String? note,
  }) {
    return SchoolPeriod(
      id: id,
      weekday: weekday ?? this.weekday,
      periodNumber: periodNumber ?? this.periodNumber,
      subjectId: subjectId ?? this.subjectId,
      teacherName: teacherName ?? this.teacherName,
      room: room ?? this.room,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'weekday': weekday,
        'periodNumber': periodNumber,
        'subjectId': subjectId,
        'teacherName': teacherName,
        'room': room,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'note': note,
      };

  factory SchoolPeriod.fromJson(Map<String, dynamic> json) => SchoolPeriod(
        id: json['id'] as String,
        weekday: json['weekday'] as int? ?? DateTime.saturday,
        periodNumber: json['periodNumber'] as int? ?? 1,
        subjectId: json['subjectId'] as String? ?? '',
        teacherName: json['teacherName'] as String? ?? '',
        room: json['room'] as String? ?? '',
        startMinutes: json['startMinutes'] as int? ?? 8 * 60,
        endMinutes: json['endMinutes'] as int? ?? 8 * 60 + 45,
        note: json['note'] as String? ?? '',
      );
}
