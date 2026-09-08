import '../core/utils/time_utils.dart';
import '../models/private_lesson.dart';
import '../models/school_period.dart';

/// أي جدول بيتعرض دلوقتي: بتاع النهاردة ولا بتاع بكرة.
enum ScheduleFocus { today, tomorrow }

/// نتيجة حساب الجدول النشط.
class ActiveSchedule {
  final ScheduleFocus focus;

  /// اليوم اللي الجدول بتاعه معروض.
  final DateTime date;

  final List<SchoolPeriod> periods;

  const ActiveSchedule({
    required this.focus,
    required this.date,
    required this.periods,
  });

  bool get isTomorrow => focus == ScheduleFocus.tomorrow;
}

/// منطق عرض الجداول.
///
/// القاعدة المطلوبة:
/// - من 12:00 منتصف الليل حتى 3:59 مساءً  ➜ يعرض جدول **النهاردة**.
/// - من 4:00 عصرًا حتى 11:59 مساءً        ➜ يعرض جدول **بكرة** تلقائيًا.
class ScheduleService {
  /// الساعة اللي بعدها التطبيق بيحوّل لجدول اليوم التالي (4 عصرًا).
  static const int switchToTomorrowHour = 16;

  const ScheduleService();

  /// هل الوقت الحالي بعد ساعة التحويل؟
  static bool showsTomorrow(DateTime now) => now.hour >= switchToTomorrowHour;

  /// اليوم اللي المفروض يتعرض جدوله دلوقتي.
  static DateTime focusDate(DateTime now) {
    final today = TimeUtils.dateOnly(now);
    return showsTomorrow(now) ? today.add(const Duration(days: 1)) : today;
  }

  static ScheduleFocus focusOf(DateTime now) =>
      showsTomorrow(now) ? ScheduleFocus.tomorrow : ScheduleFocus.today;

  /// اللحظة الجاية اللي التطبيق هيبدّل فيها العرض — بنستخدمها عشان نعمل
  /// تحديث تلقائي للشاشة الرئيسية بدل ما الطالب يقفل التطبيق ويفتحه.
  static DateTime nextSwitchTime(DateTime now) {
    if (now.hour < switchToTomorrowHour) {
      // التبديل التالي: النهاردة الساعة 4 عصرًا.
      return DateTime(now.year, now.month, now.day, switchToTomorrowHour);
    }
    // التبديل التالي: منتصف ليل بكرة (رجوع لجدول اليوم).
    final tomorrow = TimeUtils.dateOnly(now).add(const Duration(days: 1));
    return tomorrow;
  }

  /// المدة المتبقية حتى التبديل التالي.
  static Duration timeUntilNextSwitch(DateTime now) =>
      nextSwitchTime(now).difference(now);

  /// حصص يوم معيّن مرتبة بالوقت.
  static List<SchoolPeriod> periodsForDay(
    List<SchoolPeriod> allPeriods,
    DateTime day,
  ) {
    final result = allPeriods
        .where((p) => p.weekday == day.weekday)
        .toList(growable: false);
    final sorted = List<SchoolPeriod>.from(result);
    sorted.sort((a, b) {
      final byTime = a.startMinutes.compareTo(b.startMinutes);
      return byTime != 0 ? byTime : a.periodNumber.compareTo(b.periodNumber);
    });
    return sorted;
  }

  /// الجدول المدرسي النشط حسب قاعدة الـ4 عصرًا.
  static ActiveSchedule activeSchedule(
    List<SchoolPeriod> allPeriods, {
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final date = focusDate(moment);
    return ActiveSchedule(
      focus: focusOf(moment),
      date: date,
      periods: periodsForDay(allPeriods, date),
    );
  }

  /// دروس خصوصية في يوم معيّن مرتبة بالوقت.
  static List<PrivateLesson> lessonsForDay(
    List<PrivateLesson> allLessons,
    DateTime day,
  ) {
    final result = allLessons.where((l) => l.occursOn(day)).toList();
    result.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return result;
  }

  /// الحصة الجاية النهاردة (اللي لسه مبدأتش)، أو null لو اليوم خلص.
  static SchoolPeriod? nextPeriodToday(
    List<SchoolPeriod> allPeriods, {
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final minutesNow = moment.hour * 60 + moment.minute;
    final today = periodsForDay(allPeriods, moment);
    for (final period in today) {
      if (period.startMinutes > minutesNow) return period;
    }
    return null;
  }

  /// الحصة الجارية دلوقتي، أو null.
  static SchoolPeriod? currentPeriod(
    List<SchoolPeriod> allPeriods, {
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final minutesNow = moment.hour * 60 + moment.minute;
    for (final period in periodsForDay(allPeriods, moment)) {
      if (minutesNow >= period.startMinutes && minutesNow < period.endMinutes) {
        return period;
      }
    }
    return null;
  }

  /// الدرس الخصوصي الجاي خلال الأيام السبعة القادمة.
  static ({PrivateLesson lesson, DateTime date})? nextLesson(
    List<PrivateLesson> allLessons, {
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final minutesNow = moment.hour * 60 + moment.minute;
    for (var offset = 0; offset <= 7; offset++) {
      final day = TimeUtils.dateOnly(moment).add(Duration(days: offset));
      for (final lesson in lessonsForDay(allLessons, day)) {
        if (offset == 0 && lesson.startMinutes <= minutesNow) continue;
        return (lesson: lesson, date: day);
      }
    }
    return null;
  }

  /// إجمالي دقائق الانشغال (مدرسة + دروس) في يوم معيّن.
  ///
  /// دي المدخل الأساسي لحساب الوقت المتاح للمذاكرة في خطة الامتحانات.
  static int busyMinutesOn(
    DateTime day,
    List<SchoolPeriod> periods,
    List<PrivateLesson> lessons,
  ) {
    var total = 0;
    for (final period in periodsForDay(periods, day)) {
      total += period.durationMinutes;
    }
    for (final lesson in lessonsForDay(lessons, day)) {
      // بنضيف 30 دقيقة انتقال لكل درس خصوصي (رايح جاي).
      total += lesson.durationMinutes + 30;
    }
    return total;
  }
}
