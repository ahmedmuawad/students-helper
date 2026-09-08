/// الأنظمة التعليمية المدعومة.
enum EducationSystem {
  /// الثانوية العامة / التعليم العام المصري (النظام القديم).
  egyptGeneral,

  /// البكالوريا المصرية (قرار وزاري 234 لسنة 2025، من العام الدراسي 2025/2026).
  egyptBaccalaureate,

  /// التعليم الأزهري.
  azhar,

  /// كامبريدج IGCSE / A-Level.
  igcse,

  /// البكالوريا الدولية IB.
  ib,

  /// الدبلومة الأمريكية.
  american,

  other,
}

extension EducationSystemX on EducationSystem {
  String get id => name;

  static EducationSystem fromId(String? id) {
    return EducationSystem.values.firstWhere(
      (e) => e.name == id,
      orElse: () => EducationSystem.egyptGeneral,
    );
  }

  /// الأنظمة اللي بتستخدم مسارات تخصصية بدل شعبة علمي/أدبي.
  bool get usesTracks =>
      this == EducationSystem.egyptBaccalaureate ||
      this == EducationSystem.igcse ||
      this == EducationSystem.ib ||
      this == EducationSystem.american;

  /// البكالوريا المصرية بتجمع درجات الصفين الثاني والثالث الثانوي تراكميًا.
  bool get usesCumulativeGrades => this == EducationSystem.egyptBaccalaureate;
}

/// لغة الدراسة في المدرسة.
enum SchoolLanguage {
  /// مدارس عربي (المواد كلها بالعربية).
  arabic,

  /// مدارس لغات / تجريبي لغات (الرياضيات والعلوم والحاسب بالإنجليزية).
  languages,

  /// مدارس دولية.
  international,
}

extension SchoolLanguageX on SchoolLanguage {
  String get id => name;

  static SchoolLanguage fromId(String? id) {
    return SchoolLanguage.values.firstWhere(
      (e) => e.name == id,
      orElse: () => SchoolLanguage.arabic,
    );
  }
}

/// الفصل الدراسي.
enum Term {
  first,
  second;

  String get id => name;

  static Term fromId(String? id) {
    return Term.values.firstWhere(
      (e) => e.name == id,
      orElse: () => Term.first,
    );
  }

  int get number => this == Term.first ? 1 : 2;
}

/// نوع المهمة الدراسية.
enum TaskType {
  homework,
  study,
  revision,
  project,
  reading,
  submission,
  other;

  String get id => name;

  static TaskType fromId(String? id) {
    return TaskType.values.firstWhere(
      (e) => e.name == id,
      orElse: () => TaskType.other,
    );
  }
}

/// أولوية المهمة.
enum TaskPriority {
  low,
  normal,
  high;

  String get id => name;

  static TaskPriority fromId(String? id) {
    return TaskPriority.values.firstWhere(
      (e) => e.name == id,
      orElse: () => TaskPriority.normal,
    );
  }

  int get weight =>
      this == TaskPriority.high ? 3 : (this == TaskPriority.normal ? 2 : 1);
}

/// نوع التقييم أو الامتحان.
enum ExamKind {
  quiz,
  monthly,
  midterm,
  finalExam,
  practical,
  other;

  String get id => name;

  static ExamKind fromId(String? id) {
    return ExamKind.values.firstWhere(
      (e) => e.name == id,
      orElse: () => ExamKind.other,
    );
  }
}
