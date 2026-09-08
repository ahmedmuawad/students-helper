import '../models/enums.dart';
import '../models/subject.dart';

/// بيانات افتراضية تخلّي التطبيق مفيد من أول فتحة قبل ما يتوصّل بالسيرفر.
///
/// كل ده **قابل للتعديل من السيرفر** — الوزارة بتغيّر المواد والمسارات بين
/// السنين، فالتطبيق بيقرأ النسخة المحدّثة لو موجودة ويرجع للافتراضي لو مفيش نت.
class DefaultData {
  /// المواد الأساسية حسب المرحلة والنظام.
  ///
  /// المصادر: مواد الصف الأول الثانوي 2025/2026 معلنة رسميًا (قرار وزاري
  /// 234 لسنة 2025). باقي المراحل حسب الهيكل المعتاد للمناهج المصرية.
  static List<Subject> subjectsFor({
    required int gradeLevel,
    required EducationSystem system,
    required SchoolLanguage language,
  }) {
    final inEnglish = language != SchoolLanguage.arabic;

    // الصف الأول الثانوي في نظامي البكالوريا والثانوية العامة 2025/2026.
    if (gradeLevel == 10 &&
        (system == EducationSystem.egyptBaccalaureate ||
            system == EducationSystem.egyptGeneral)) {
      return [
        _s('arabic', 'اللغة العربية', 'Arabic', 0xFF1E88E5),
        _s('english', 'اللغة الإنجليزية', 'English', 0xFF43A047),
        _s(
          'integrated_science',
          'العلوم المتكاملة',
          'Integrated Science',
          0xFF8E24AA,
        ),
        _s(
          'egyptian_history',
          'التاريخ المصري',
          'Egyptian History',
          0xFFF4511E,
        ),
        _s(
          'philosophy_logic',
          'الفلسفة والمنطق',
          'Philosophy & Logic',
          0xFF6D4C41,
        ),
        _s('math', 'الرياضيات', 'Mathematics', 0xFFE53935),
        // مواد لا تُضاف للمجموع
        _s(
          'religion',
          'التربية الدينية',
          'Religious Education',
          0xFF00897B,
          counts: false,
        ),
        _s(
          'second_language',
          'اللغة الثانية',
          'Second Language',
          0xFF3949AB,
          counts: false,
        ),
        _s(
          'computer_science',
          'البرمجة وعلوم الحاسب',
          'Computer Science',
          0xFF546E7A,
          counts: false,
        ),
      ];
    }

    // المرحلة الابتدائية الدنيا (1-3): عربي، رياضيات، إنجليزي.
    if (gradeLevel <= 3) {
      return [
        _s('arabic', 'اللغة العربية', 'Arabic', 0xFF1E88E5),
        _s(
          'math',
          'الرياضيات',
          inEnglish ? 'Mathematics' : 'Mathematics',
          0xFFE53935,
        ),
        _s('english', 'اللغة الإنجليزية', 'English', 0xFF43A047),
        _s(
          'religion',
          'التربية الدينية',
          'Religious Education',
          0xFF00897B,
          counts: false,
        ),
        _s(
          'skills',
          'المهارات المهنية',
          'Life Skills',
          0xFF546E7A,
          counts: false,
        ),
      ];
    }

    // من الرابع الابتدائي حتى الثالث الإعدادي (4-9).
    if (gradeLevel <= 9) {
      return [
        _s('arabic', 'اللغة العربية', 'Arabic', 0xFF1E88E5),
        _s('math', 'الرياضيات', 'Mathematics', 0xFFE53935),
        _s('science', 'العلوم', 'Science', 0xFF8E24AA),
        _s('english', 'اللغة الإنجليزية', 'English', 0xFF43A047),
        _s(
          'social_studies',
          'الدراسات الاجتماعية',
          'Social Studies',
          0xFFF4511E,
        ),
        _s(
          'religion',
          'التربية الدينية',
          'Religious Education',
          0xFF00897B,
          counts: false,
        ),
        _s('computer', 'الحاسب الآلي', 'ICT', 0xFF546E7A, counts: false),
        if (gradeLevel >= 7)
          _s(
            'second_language',
            'اللغة الثانية',
            'Second Language',
            0xFF3949AB,
            counts: false,
          ),
      ];
    }

    // ثانوي (11-12) — المواد بتتحدد حسب المسار، فبنبدأ بالأساسي والطالب يضيف.
    return [
      _s('arabic', 'اللغة العربية', 'Arabic', 0xFF1E88E5),
      _s('english', 'اللغة الإنجليزية', 'English', 0xFF43A047),
      _s('math', 'الرياضيات', 'Mathematics', 0xFFE53935),
      _s('physics', 'الفيزياء', 'Physics', 0xFF00ACC1),
      _s('chemistry', 'الكيمياء', 'Chemistry', 0xFF8E24AA),
      _s('biology', 'الأحياء', 'Biology', 0xFF7CB342),
      _s(
        'religion',
        'التربية الدينية',
        'Religious Education',
        0xFF00897B,
        counts: false,
      ),
    ];
  }

  /// مسارات البكالوريا المصرية الأربعة (تبدأ من الصف الثاني الثانوي).
  ///
  /// ⚠️ التسميات الرسمية ممكن تتغيّر — التطبيق بيحمّل النسخة المحدّثة من
  /// السيرفر لو متاحة، ودي مجرد قيم مبدئية للعمل بدون نت.
  static List<AcademicTrack> tracksFor(EducationSystem system) {
    switch (system) {
      case EducationSystem.egyptBaccalaureate:
        return const [
          AcademicTrack(
            id: 'bacc_medical',
            nameAr: 'مسار الطب وعلوم الحياة',
            nameEn: 'Medicine & Life Sciences',
            systemId: 'egyptBaccalaureate',
          ),
          AcademicTrack(
            id: 'bacc_engineering',
            nameAr: 'مسار الهندسة وعلوم الحاسب',
            nameEn: 'Engineering & Computer Science',
            systemId: 'egyptBaccalaureate',
          ),
          AcademicTrack(
            id: 'bacc_business',
            nameAr: 'مسار الأعمال',
            nameEn: 'Business',
            systemId: 'egyptBaccalaureate',
          ),
          AcademicTrack(
            id: 'bacc_arts',
            nameAr: 'مسار الآداب والفنون',
            nameEn: 'Arts & Humanities',
            systemId: 'egyptBaccalaureate',
          ),
        ];
      case EducationSystem.egyptGeneral:
        return const [
          AcademicTrack(
            id: 'general_science',
            nameAr: 'علمي علوم',
            nameEn: 'Science (Biology)',
            systemId: 'egyptGeneral',
          ),
          AcademicTrack(
            id: 'general_math',
            nameAr: 'علمي رياضة',
            nameEn: 'Science (Mathematics)',
            systemId: 'egyptGeneral',
          ),
          AcademicTrack(
            id: 'general_literary',
            nameAr: 'أدبي',
            nameEn: 'Literary',
            systemId: 'egyptGeneral',
          ),
        ];
      default:
        return const [];
    }
  }

  /// اسم الصف الدراسي بالعربية.
  static String gradeNameAr(int gradeLevel) {
    const ordinals = [
      'الأول',
      'الثاني',
      'الثالث',
      'الرابع',
      'الخامس',
      'السادس',
    ];
    if (gradeLevel >= 1 && gradeLevel <= 6) {
      return '${ordinals[gradeLevel - 1]} الابتدائي';
    }
    if (gradeLevel >= 7 && gradeLevel <= 9) {
      return '${ordinals[gradeLevel - 7]} الإعدادي';
    }
    if (gradeLevel >= 10 && gradeLevel <= 12) {
      return '${ordinals[gradeLevel - 10]} الثانوي';
    }
    return 'الصف $gradeLevel';
  }

  static String gradeNameEn(int gradeLevel) => 'Grade $gradeLevel';

  /// أوقات الحصص الافتراضية في المدرسة المصرية (٧ حصص).
  static List<({int start, int end})> defaultPeriodTimes() => const [
        (start: 8 * 60, end: 8 * 60 + 45),
        (start: 8 * 60 + 50, end: 9 * 60 + 35),
        (start: 9 * 60 + 40, end: 10 * 60 + 25),
        (start: 10 * 60 + 45, end: 11 * 60 + 30),
        (start: 11 * 60 + 35, end: 12 * 60 + 20),
        (start: 12 * 60 + 25, end: 13 * 60 + 10),
        (start: 13 * 60 + 15, end: 14 * 60),
      ];

  static Subject _s(
    String id,
    String ar,
    String en,
    int color, {
    bool counts = true,
  }) =>
      Subject(
        id: id,
        nameAr: ar,
        nameEn: en,
        colorValue: color,
        countsTowardTotal: counts,
      );
}
