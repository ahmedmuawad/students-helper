/// مادة دراسية. الأسماء ثنائية اللغة عشان التطبيق يشتغل عربي/إنجليزي.
class Subject {
  final String id;
  final String nameAr;
  final String nameEn;

  /// هل المادة بتضاف للمجموع؟ (مهم في نظام البكالوريا المصرية)
  final bool countsTowardTotal;

  /// لون مميز للمادة في الجداول (قيمة ARGB).
  final int colorValue;

  const Subject({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.countsTowardTotal = true,
    this.colorValue = 0xFF2E7D91,
  });

  String localizedName(String languageCode) =>
      languageCode == 'en' ? nameEn : nameAr;

  Subject copyWith({
    String? nameAr,
    String? nameEn,
    bool? countsTowardTotal,
    int? colorValue,
  }) {
    return Subject(
      id: id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      countsTowardTotal: countsTowardTotal ?? this.countsTowardTotal,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'countsTowardTotal': countsTowardTotal,
        'colorValue': colorValue,
      };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: json['id'] as String,
        nameAr: json['nameAr'] as String? ?? '',
        nameEn: json['nameEn'] as String? ?? '',
        countsTowardTotal: json['countsTowardTotal'] as bool? ?? true,
        colorValue: json['colorValue'] as int? ?? 0xFF2E7D91,
      );

  @override
  bool operator ==(Object other) => other is Subject && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// مسار دراسي (مسارات البكالوريا المصرية الأربعة، أو مسارات الأنظمة الدولية).
///
/// المسارات مخزّنة كبيانات مش كـ enum عشان تتحدّث من السيرفر من غير تحديث
/// للتطبيق — الوزارة بتعدّل التسميات والمسارات بين السنين.
class AcademicTrack {
  final String id;
  final String nameAr;
  final String nameEn;
  final String systemId;

  const AcademicTrack({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.systemId,
  });

  String localizedName(String languageCode) =>
      languageCode == 'en' ? nameEn : nameAr;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'systemId': systemId,
      };

  factory AcademicTrack.fromJson(Map<String, dynamic> json) => AcademicTrack(
        id: json['id'] as String,
        nameAr: json['nameAr'] as String? ?? '',
        nameEn: json['nameEn'] as String? ?? '',
        systemId: json['systemId'] as String? ?? '',
      );
}
