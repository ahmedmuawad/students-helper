import 'package:flutter/material.dart';

import '../core/utils/id_gen.dart';
import '../core/utils/time_utils.dart';
import '../data/default_data.dart';
import '../data/local_store.dart';
import '../models/account.dart';
import '../models/instructor.dart';
import '../models/private_lesson.dart';
import '../models/school_period.dart';
import '../models/student_profile.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../services/schedule_service.dart';

/// الحالة المركزية للتطبيق — بيانات الطالب وجداوله ومهامه.
///
/// كل تعديل بيتحفظ محليًا على طول (أوفلاين أولًا) وبعدين بيتزامن مع السيرفر.
class AppState extends ChangeNotifier {
  final LocalStore _store;

  StudentProfile? _profile;
  AccountRole _role = AccountRole.student;
  List<Subject> _subjects = [];
  List<SchoolPeriod> _periods = [];
  List<PrivateLesson> _lessons = [];
  List<Instructor> _instructors = [];
  List<StudyTask> _tasks = [];
  List<GuardianLink> _guardianLinks = [];

  String _languageCode = 'ar';
  ThemeMode _themeMode = ThemeMode.system;
  bool _onboardingDone = false;

  AppState(this._store);

  // ----- قراءات -----

  StudentProfile? get profile => _profile;
  AccountRole get role => _role;
  List<Subject> get subjects => List.unmodifiable(_subjects);
  List<SchoolPeriod> get periods => List.unmodifiable(_periods);
  List<PrivateLesson> get lessons => List.unmodifiable(_lessons);
  List<Instructor> get instructors => List.unmodifiable(_instructors);
  List<StudyTask> get tasks => List.unmodifiable(_tasks);
  List<GuardianLink> get guardianLinks => List.unmodifiable(_guardianLinks);

  String get languageCode => _languageCode;
  ThemeMode get themeMode => _themeMode;
  bool get onboardingDone => _onboardingDone;
  bool get isArabic => _languageCode != 'en';

  /// ولي الأمر المرتبط بأكتر من طالب بيختار مين يتابع.
  List<GuardianLink> get activeChildren =>
      _guardianLinks.where((l) => l.isActive).toList(growable: false);

  // ----- التحميل -----

  Future<void> load() async {
    final profileJson = _store.readObject(StoreKeys.profile);
    _profile =
        profileJson == null ? null : StudentProfile.fromJson(profileJson);

    _role = AccountRole.fromId(_store.readString(StoreKeys.accountRole));
    _subjects = _store.readList(StoreKeys.subjects, Subject.fromJson);
    _periods = _store.readList(StoreKeys.periods, SchoolPeriod.fromJson);
    _lessons = _store.readList(StoreKeys.lessons, PrivateLesson.fromJson);
    _instructors = _store.readList(StoreKeys.instructors, Instructor.fromJson);
    _tasks = _store.readList(StoreKeys.tasks, StudyTask.fromJson);
    _guardianLinks = _store.readList(
      StoreKeys.guardianLinks,
      GuardianLink.fromJson,
    );

    _languageCode = _store.readString(StoreKeys.languageCode) ?? 'ar';
    _themeMode = _themeFromId(_store.readString(StoreKeys.themeMode));
    _onboardingDone = _store.readBool(StoreKeys.onboardingDone);

    notifyListeners();
  }

  // ----- الإعدادات العامة -----

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    await _store.writeString(StoreKeys.languageCode, code);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _store.writeString(StoreKeys.themeMode, mode.name);
    notifyListeners();
  }

  Future<void> setRole(AccountRole role) async {
    _role = role;
    await _store.writeString(StoreKeys.accountRole, role.id);
    notifyListeners();
  }

  static ThemeMode _themeFromId(String? id) => ThemeMode.values.firstWhere(
        (m) => m.name == id,
        orElse: () => ThemeMode.system,
      );

  // ----- الملف الشخصي -----

  Future<void> saveProfile(
    StudentProfile profile, {
    bool seedSubjects = false,
  }) async {
    _profile = profile;
    await _store.writeObject(StoreKeys.profile, profile.toJson());

    // أول مرة: نجهّز له مواده الافتراضية حسب صفه ونظامه عشان يلاقي التطبيق
    // جاهز بدل شاشة فاضية.
    if (seedSubjects && _subjects.isEmpty) {
      _subjects = DefaultData.subjectsFor(
        gradeLevel: profile.gradeLevel,
        system: profile.educationSystem,
        language: profile.schoolLanguage,
      );
      await _persistSubjects();
      _profile = profile.copyWith(
        subjectIds: _subjects.map((s) => s.id).toList(),
      );
      await _store.writeObject(StoreKeys.profile, _profile!.toJson());
    }

    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _onboardingDone = true;
    await _store.writeBool(StoreKeys.onboardingDone, true);
    notifyListeners();
  }

  // ----- المواد -----

  Subject? subjectById(String id) {
    for (final subject in _subjects) {
      if (subject.id == id) return subject;
    }
    return null;
  }

  String subjectName(String id) {
    final subject = subjectById(id);
    if (subject == null) return '';
    return subject.localizedName(_languageCode);
  }

  Color subjectColor(String id) {
    final subject = subjectById(id);
    return Color(subject?.colorValue ?? 0xFF2E7D91);
  }

  Future<void> upsertSubject(Subject subject) async {
    final index = _subjects.indexWhere((s) => s.id == subject.id);
    if (index >= 0) {
      _subjects[index] = subject;
    } else {
      _subjects.add(subject);
    }
    await _persistSubjects();
    notifyListeners();
  }

  Future<void> deleteSubject(String id) async {
    _subjects.removeWhere((s) => s.id == id);
    await _persistSubjects();
    notifyListeners();
  }

  Future<void> _persistSubjects() =>
      _store.writeList(StoreKeys.subjects, _subjects, (s) => s.toJson());

  // ----- الجدول المدرسي -----

  Future<void> upsertPeriod(SchoolPeriod period) async {
    final index = _periods.indexWhere((p) => p.id == period.id);
    if (index >= 0) {
      _periods[index] = period;
    } else {
      _periods.add(period);
    }
    await _store.writeList(StoreKeys.periods, _periods, (p) => p.toJson());
    notifyListeners();
  }

  Future<void> deletePeriod(String id) async {
    _periods.removeWhere((p) => p.id == id);
    // المهام المرتبطة بالحصة دي بتفضل موجودة بس من غير ربط.
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].linkedPeriodId == id) {
        _tasks[i] = _tasks[i].copyWith(clearLinks: true);
      }
    }
    await _store.writeList(StoreKeys.periods, _periods, (p) => p.toJson());
    await _persistTasks();
    notifyListeners();
  }

  /// الجدول النشط حسب قاعدة الـ4 عصرًا.
  ActiveSchedule get activeSchedule => ScheduleService.activeSchedule(_periods);

  List<SchoolPeriod> periodsForDay(DateTime day) =>
      ScheduleService.periodsForDay(_periods, day);

  SchoolPeriod? get nextPeriodToday =>
      ScheduleService.nextPeriodToday(_periods);

  SchoolPeriod? get currentPeriod => ScheduleService.currentPeriod(_periods);

  SchoolPeriod? periodById(String? id) {
    if (id == null) return null;
    for (final period in _periods) {
      if (period.id == id) return period;
    }
    return null;
  }

  // ----- الدروس الخصوصية -----

  Future<void> upsertLesson(PrivateLesson lesson) async {
    final index = _lessons.indexWhere((l) => l.id == lesson.id);
    if (index >= 0) {
      _lessons[index] = lesson;
    } else {
      _lessons.add(lesson);
    }
    await _store.writeList(StoreKeys.lessons, _lessons, (l) => l.toJson());
    notifyListeners();
  }

  Future<void> deleteLesson(String id) async {
    _lessons.removeWhere((l) => l.id == id);
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].linkedLessonId == id) {
        _tasks[i] = _tasks[i].copyWith(clearLinks: true);
      }
    }
    await _store.writeList(StoreKeys.lessons, _lessons, (l) => l.toJson());
    await _persistTasks();
    notifyListeners();
  }

  // ----- المدرسين والسناتر -----

  Instructor? instructorById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final instructor in _instructors) {
      if (instructor.id == id) return instructor;
    }
    return null;
  }

  /// المدرس المرتبط بالدرس، أو null لو الدرس مكتوب فيه اسم يدوي بس.
  Instructor? instructorForLesson(PrivateLesson lesson) =>
      instructorById(lesson.instructorId);

  /// الاسم المعروض للدرس: من جهة الاتصال المحفوظة أو الاسم اليدوي.
  String lessonTeacherName(PrivateLesson lesson) {
    final instructor = instructorForLesson(lesson);
    if (instructor != null && instructor.name.isNotEmpty) {
      return instructor.name;
    }
    return lesson.teacherName;
  }

  /// المكان المعروض للدرس: عنوان جهة الاتصال أو المكان اليدوي.
  String lessonPlace(PrivateLesson lesson) {
    final instructor = instructorForLesson(lesson);
    if (instructor != null && instructor.address.isNotEmpty) {
      return instructor.address;
    }
    return lesson.place;
  }

  Future<void> upsertInstructor(Instructor instructor) async {
    final index = _instructors.indexWhere((i) => i.id == instructor.id);
    if (index >= 0) {
      _instructors[index] = instructor;
    } else {
      _instructors.add(instructor);
    }
    await _store.writeList(
        StoreKeys.instructors, _instructors, (i) => i.toJson());
    notifyListeners();
  }

  Future<void> deleteInstructor(String id) async {
    _instructors.removeWhere((i) => i.id == id);
    // الدروس المرتبطة بتفضل موجودة بس من غير ربط بجهة الاتصال.
    for (var i = 0; i < _lessons.length; i++) {
      if (_lessons[i].instructorId == id) {
        _lessons[i] = _lessons[i].copyWith(instructorId: '');
      }
    }
    await _store.writeList(
        StoreKeys.instructors, _instructors, (i) => i.toJson());
    await _store.writeList(StoreKeys.lessons, _lessons, (l) => l.toJson());
    notifyListeners();
  }

  /// الدروس المرتبطة بمدرس معيّن.
  List<PrivateLesson> lessonsForInstructor(String instructorId) => _lessons
      .where((l) => l.instructorId == instructorId)
      .toList(growable: false);

  /// إجمالي تكلفة الدروس الأسبوعية عند مدرس معيّن.
  double weeklyCostForInstructor(String instructorId) {
    var total = 0.0;
    for (final lesson in lessonsForInstructor(instructorId)) {
      if (lesson.isWeekly) {
        total += lesson.cost;
      }
    }
    return total;
  }

  List<PrivateLesson> lessonsForDay(DateTime day) =>
      ScheduleService.lessonsForDay(_lessons, day);

  ({PrivateLesson lesson, DateTime date})? get nextLesson =>
      ScheduleService.nextLesson(_lessons);

  PrivateLesson? lessonById(String? id) {
    if (id == null) return null;
    for (final lesson in _lessons) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }

  // ----- المهام -----

  Future<void> upsertTask(StudyTask task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _tasks[index] = task;
    } else {
      _tasks.add(task);
    }
    await _persistTasks();
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _persistTasks();
    notifyListeners();
  }

  Future<void> toggleTaskDone(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final task = _tasks[index];
    _tasks[index] = task.copyWith(
      isDone: !task.isDone,
      completedAt: task.isDone ? null : DateTime.now(),
    );
    await _persistTasks();
    notifyListeners();
  }

  Future<void> _persistTasks() =>
      _store.writeList(StoreKeys.tasks, _tasks, (t) => t.toJson());

  /// المهام غير المنتهية مرتبة: المتأخرة الأول، بعدين الأقرب موعدًا.
  List<StudyTask> get pendingTasks {
    final pending = _tasks.where((t) => !t.isDone).toList();
    pending.sort((a, b) {
      final aDue = a.dueDate;
      final bDue = b.dueDate;
      if (aDue == null && bDue == null) {
        return b.priority.weight.compareTo(a.priority.weight);
      }
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });
    return pending;
  }

  /// مهام مستحقة في يوم معيّن.
  List<StudyTask> tasksDueOn(DateTime day) => _tasks
      .where((t) => t.dueDate != null && TimeUtils.isSameDay(t.dueDate!, day))
      .toList(growable: false);

  /// مهام مرتبطة بحصة مدرسية معيّنة.
  List<StudyTask> tasksForPeriod(String periodId) =>
      _tasks.where((t) => t.linkedPeriodId == periodId).toList(growable: false);

  /// مهام مرتبطة بدرس خصوصي معيّن.
  List<StudyTask> tasksForLesson(String lessonId) =>
      _tasks.where((t) => t.linkedLessonId == lessonId).toList(growable: false);

  /// المهام المرتبطة بدرس والمطلوب تذكير الطالب بيها قبله بيوم.
  ///
  /// دي اللي بتحقق الشرط المطلوب: "تذكير قبلها بيوم لو فيه تاسكات تخص الحصة دي".
  List<StudyTask> unfinishedTasksForLesson(String lessonId) => _tasks
      .where((t) => t.linkedLessonId == lessonId && !t.isDone)
      .toList(growable: false);

  int get overdueCount => _tasks.where((t) => t.isOverdue).length;

  int get dueTodayCount {
    final today = DateTime.now();
    return _tasks
        .where(
          (t) =>
              !t.isDone &&
              t.dueDate != null &&
              TimeUtils.isSameDay(t.dueDate!, today),
        )
        .length;
  }

  // ----- ربط ولي الأمر -----

  Future<void> upsertGuardianLink(GuardianLink link) async {
    final index = _guardianLinks.indexWhere((l) => l.id == link.id);
    if (index >= 0) {
      _guardianLinks[index] = link;
    } else {
      _guardianLinks.add(link);
    }
    await _store.writeList(
      StoreKeys.guardianLinks,
      _guardianLinks,
      (l) => l.toJson(),
    );
    notifyListeners();
  }

  Future<void> removeGuardianLink(String id) async {
    _guardianLinks.removeWhere((l) => l.id == id);
    await _store.writeList(
      StoreKeys.guardianLinks,
      _guardianLinks,
      (l) => l.toJson(),
    );
    notifyListeners();
  }

  // ----- مساعدات -----

  /// إنشاء ملف شخصي جديد بمعرّف فريد.
  StudentProfile newProfile() =>
      StudentProfile(id: IdGen.next('student'), name: '');

  Future<void> resetAllData() async {
    await _store.clearAll();
    _profile = null;
    _subjects = [];
    _periods = [];
    _lessons = [];
    _instructors = [];
    _tasks = [];
    _guardianLinks = [];
    _onboardingDone = false;
    notifyListeners();
  }
}
