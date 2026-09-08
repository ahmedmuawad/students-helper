import 'enums.dart';

/// إعدادات وقت الطالب — دي مدخلات أساسية لخوارزمية توزيع خطة المذاكرة.
class StudyAvailability {
  /// موعد النوم (دقائق من منتصف الليل).
  final int sleepStartMinutes;

  /// موعد الاستيقاظ (دقائق من منتصف الليل).
  final int wakeUpMinutes;

  /// وقت الأكل والراحة والصلاة يوميًا (بالدقائق).
  final int dailyBreakMinutes;

  /// أقصى عدد دقائق مذاكرة الطالب مستعد لها في اليوم (سقف واقعي).
  final int maxDailyStudyMinutes;

  /// تعديل يدوي لكل يوم أسبوع: مفتاح = DateTime.weekday، قيمة = دقائق متاحة.
  /// لو اليوم مش موجود هنا، التطبيق بيحسبه تلقائيًا من الجدول.
  final Map<int, int> weekdayOverrides;

  const StudyAvailability({
    this.sleepStartMinutes = 23 * 60,
    this.wakeUpMinutes = 6 * 60 + 30,
    this.dailyBreakMinutes = 150,
    this.maxDailyStudyMinutes = 300,
    this.weekdayOverrides = const {},
  });

  StudyAvailability copyWith({
    int? sleepStartMinutes,
    int? wakeUpMinutes,
    int? dailyBreakMinutes,
    int? maxDailyStudyMinutes,
    Map<int, int>? weekdayOverrides,
  }) {
    return StudyAvailability(
      sleepStartMinutes: sleepStartMinutes ?? this.sleepStartMinutes,
      wakeUpMinutes: wakeUpMinutes ?? this.wakeUpMinutes,
      dailyBreakMinutes: dailyBreakMinutes ?? this.dailyBreakMinutes,
      maxDailyStudyMinutes: maxDailyStudyMinutes ?? this.maxDailyStudyMinutes,
      weekdayOverrides: weekdayOverrides ?? this.weekdayOverrides,
    );
  }

  /// إجمالي دقائق اليقظة في اليوم بعد خصم النوم.
  int get awakeMinutes {
    // النوم عادة بيعدّي منتصف الليل، فبنحسب الفرق بشكل دائري.
    final sleepDuration =
        (wakeUpMinutes - sleepStartMinutes + 24 * 60) % (24 * 60);
    return 24 * 60 - sleepDuration;
  }

  Map<String, dynamic> toJson() => {
    'sleepStartMinutes': sleepStartMinutes,
    'wakeUpMinutes': wakeUpMinutes,
    'dailyBreakMinutes': dailyBreakMinutes,
    'maxDailyStudyMinutes': maxDailyStudyMinutes,
    'weekdayOverrides': weekdayOverrides.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
  };

  factory StudyAvailability.fromJson(Map<String, dynamic> json) {
    final raw = (json['weekdayOverrides'] as Map?) ?? const {};
    final overrides = <int, int>{};
    raw.forEach((key, value) {
      final day = int.tryParse(key.toString());
      final minutes = value is int ? value : int.tryParse(value.toString());
      if (day != null && minutes != null) overrides[day] = minutes;
    });
    return StudyAvailability(
      sleepStartMinutes: json['sleepStartMinutes'] as int? ?? 23 * 60,
      wakeUpMinutes: json['wakeUpMinutes'] as int? ?? 6 * 60 + 30,
      dailyBreakMinutes: json['dailyBreakMinutes'] as int? ?? 150,
      maxDailyStudyMinutes: json['maxDailyStudyMinutes'] as int? ?? 300,
      weekdayOverrides: overrides,
    );
  }
}

/// الملف الشخصي للطالب.
class StudentProfile {
  final String id;
  final String name;
  final DateTime? birthDate;

  /// كود الدولة (ISO-3166 alpha-2) مثل EG، SA.
  final String countryCode;
  final String schoolName;

  /// رقم الصف الدراسي: 1..6 ابتدائي، 7..9 إعدادي، 10..12 ثانوي.
  final int gradeLevel;

  final EducationSystem educationSystem;
  final SchoolLanguage schoolLanguage;
  final Term currentTerm;

  /// معرّف المسار الدراسي (للبكالوريا والأنظمة الدولية). فاضي = مفيش مسار.
  final String trackId;

  /// مسار الصورة الشخصية على الجهاز.
  final String? avatarPath;

  /// معرّفات المواد اللي الطالب بيدرسها.
  final List<String> subjectIds;

  final StudyAvailability availability;

  /// معرّف حساب Firebase بعد تسجيل الدخول (فاضي = شغّال بدون حساب).
  final String? authUid;

  const StudentProfile({
    required this.id,
    required this.name,
    this.birthDate,
    this.countryCode = 'EG',
    this.schoolName = '',
    this.gradeLevel = 7,
    this.educationSystem = EducationSystem.egyptGeneral,
    this.schoolLanguage = SchoolLanguage.arabic,
    this.currentTerm = Term.first,
    this.trackId = '',
    this.avatarPath,
    this.subjectIds = const [],
    this.availability = const StudyAvailability(),
    this.authUid,
  });

  /// المرحلة التعليمية المشتقة من رقم الصف.
  String stageKey() {
    if (gradeLevel <= 6) return 'primary';
    if (gradeLevel <= 9) return 'preparatory';
    return 'secondary';
  }

  /// عمر الطالب بالسنين، أو null لو تاريخ الميلاد مش مسجّل.
  int? get age {
    final birth = birthDate;
    if (birth == null) return null;
    final now = DateTime.now();
    var years = now.year - birth.year;
    final hadBirthdayThisYear =
        now.month > birth.month ||
        (now.month == birth.month && now.day >= birth.day);
    if (!hadBirthdayThisYear) years -= 1;
    return years < 0 ? null : years;
  }

  /// هل النهاردة عيد ميلاده؟ (نستخدمها في تهنئة على الشاشة الرئيسية)
  bool get isBirthdayToday {
    final birth = birthDate;
    if (birth == null) return false;
    final now = DateTime.now();
    return birth.month == now.month && birth.day == now.day;
  }

  StudentProfile copyWith({
    String? name,
    DateTime? birthDate,
    String? countryCode,
    String? schoolName,
    int? gradeLevel,
    EducationSystem? educationSystem,
    SchoolLanguage? schoolLanguage,
    Term? currentTerm,
    String? trackId,
    String? avatarPath,
    List<String>? subjectIds,
    StudyAvailability? availability,
    String? authUid,
  }) {
    return StudentProfile(
      id: id,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      countryCode: countryCode ?? this.countryCode,
      schoolName: schoolName ?? this.schoolName,
      gradeLevel: gradeLevel ?? this.gradeLevel,
      educationSystem: educationSystem ?? this.educationSystem,
      schoolLanguage: schoolLanguage ?? this.schoolLanguage,
      currentTerm: currentTerm ?? this.currentTerm,
      trackId: trackId ?? this.trackId,
      avatarPath: avatarPath ?? this.avatarPath,
      subjectIds: subjectIds ?? this.subjectIds,
      availability: availability ?? this.availability,
      authUid: authUid ?? this.authUid,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'birthDate': birthDate?.toIso8601String(),
    'countryCode': countryCode,
    'schoolName': schoolName,
    'gradeLevel': gradeLevel,
    'educationSystem': educationSystem.name,
    'schoolLanguage': schoolLanguage.name,
    'currentTerm': currentTerm.name,
    'trackId': trackId,
    'avatarPath': avatarPath,
    'subjectIds': subjectIds,
    'availability': availability.toJson(),
    'authUid': authUid,
  };

  factory StudentProfile.fromJson(Map<String, dynamic> json) => StudentProfile(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    birthDate: json['birthDate'] == null
        ? null
        : DateTime.tryParse(json['birthDate'] as String),
    countryCode: json['countryCode'] as String? ?? 'EG',
    schoolName: json['schoolName'] as String? ?? '',
    gradeLevel: json['gradeLevel'] as int? ?? 7,
    educationSystem: EducationSystemX.fromId(
      json['educationSystem'] as String?,
    ),
    schoolLanguage: SchoolLanguageX.fromId(json['schoolLanguage'] as String?),
    currentTerm: Term.fromId(json['currentTerm'] as String?),
    trackId: json['trackId'] as String? ?? '',
    avatarPath: json['avatarPath'] as String?,
    subjectIds: (json['subjectIds'] as List?)?.cast<String>() ?? const [],
    availability: json['availability'] == null
        ? const StudyAvailability()
        : StudyAvailability.fromJson(
            Map<String, dynamic>.from(json['availability'] as Map),
          ),
    authUid: json['authUid'] as String?,
  );
}
