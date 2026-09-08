import 'package:flutter_test/flutter_test.dart';
import 'package:students_helper/models/private_lesson.dart';
import 'package:students_helper/models/school_period.dart';
import 'package:students_helper/services/schedule_service.dart';

/// حصة تجريبية في يوم ووقت محددين.
SchoolPeriod period(
  String id,
  int weekday,
  int startHour, {
  int number = 1,
}) {
  return SchoolPeriod(
    id: id,
    weekday: weekday,
    periodNumber: number,
    subjectId: 'math',
    startMinutes: startHour * 60,
    endMinutes: startHour * 60 + 45,
  );
}

void main() {
  group('قاعدة الـ4 عصرًا', () {
    // ملاحظة: 2026-09-08 هو يوم الثلاثاء، وكل التواريخ تحته مبنية عليه.

    test('منتصف الليل بالظبط يعرض جدول النهاردة', () {
      final now = DateTime(2026, 9, 8, 0, 0);
      expect(ScheduleService.showsTomorrow(now), isFalse);
      expect(ScheduleService.focusDate(now), DateTime(2026, 9, 8));
    });

    test('الظهر يعرض جدول النهاردة', () {
      final now = DateTime(2026, 9, 8, 12, 30);
      expect(ScheduleService.focusOf(now), ScheduleFocus.today);
    });

    test('3:59 عصرًا لسه بيعرض النهاردة', () {
      final now = DateTime(2026, 9, 8, 15, 59);
      expect(ScheduleService.showsTomorrow(now), isFalse);
      expect(ScheduleService.focusDate(now), DateTime(2026, 9, 8));
    });

    test('4:00 عصرًا بالظبط بيتحوّل لجدول بكرة', () {
      final now = DateTime(2026, 9, 8, 16, 0);
      expect(ScheduleService.showsTomorrow(now), isTrue);
      expect(ScheduleService.focusOf(now), ScheduleFocus.tomorrow);
      expect(ScheduleService.focusDate(now), DateTime(2026, 9, 9));
    });

    test('11:59 مساءً بيعرض جدول بكرة', () {
      final now = DateTime(2026, 9, 8, 23, 59);
      expect(ScheduleService.focusDate(now), DateTime(2026, 9, 9));
    });

    test('التبديل بعد منتصف الليل بيرجع لليوم الجديد', () {
      final justAfterMidnight = DateTime(2026, 9, 9, 0, 1);
      expect(ScheduleService.showsTomorrow(justAfterMidnight), isFalse);
      expect(ScheduleService.focusDate(justAfterMidnight), DateTime(2026, 9, 9));
    });

    test('لحظة التبديل التالية قبل الرابعة هي الرابعة نفس اليوم', () {
      final now = DateTime(2026, 9, 8, 9, 0);
      expect(ScheduleService.nextSwitchTime(now), DateTime(2026, 9, 8, 16, 0));
    });

    test('لحظة التبديل التالية بعد الرابعة هي منتصف ليل بكرة', () {
      final now = DateTime(2026, 9, 8, 18, 0);
      expect(ScheduleService.nextSwitchTime(now), DateTime(2026, 9, 9));
    });

    test('الجدول النشط بيرجّع حصص بكرة بعد الرابعة', () {
      final periods = [
        period('t1', DateTime.tuesday, 8),
        period('w1', DateTime.wednesday, 9),
        period('w2', DateTime.wednesday, 10, number: 2),
      ];

      final before = ScheduleService.activeSchedule(
        periods,
        now: DateTime(2026, 9, 8, 10, 0),
      );
      expect(before.focus, ScheduleFocus.today);
      expect(before.periods.map((p) => p.id), ['t1']);

      final after = ScheduleService.activeSchedule(
        periods,
        now: DateTime(2026, 9, 8, 17, 0),
      );
      expect(after.focus, ScheduleFocus.tomorrow);
      expect(after.periods.map((p) => p.id), ['w1', 'w2']);
    });
  });

  group('ترتيب واستعلامات الجدول', () {
    test('حصص اليوم بترجع مرتبة بالوقت', () {
      final periods = [
        period('late', DateTime.tuesday, 11, number: 3),
        period('early', DateTime.tuesday, 8, number: 1),
        period('mid', DateTime.tuesday, 9, number: 2),
      ];
      final sorted =
          ScheduleService.periodsForDay(periods, DateTime(2026, 9, 8));
      expect(sorted.map((p) => p.id), ['early', 'mid', 'late']);
    });

    test('الحصة الحالية والجاية بتتحسبوا صح', () {
      final periods = [
        period('p1', DateTime.tuesday, 8),
        period('p2', DateTime.tuesday, 10, number: 2),
      ];
      // 8:20 يعني جوّه الحصة الأولى (8:00 - 8:45).
      final during = DateTime(2026, 9, 8, 8, 20);
      expect(ScheduleService.currentPeriod(periods, now: during)?.id, 'p1');
      expect(ScheduleService.nextPeriodToday(periods, now: during)?.id, 'p2');

      // بعد آخر حصة مفيش حصة جاية.
      final after = DateTime(2026, 9, 8, 14, 0);
      expect(ScheduleService.currentPeriod(periods, now: after), isNull);
      expect(ScheduleService.nextPeriodToday(periods, now: after), isNull);
    });
  });

  group('الدروس الخصوصية', () {
    PrivateLesson weekly(String id, int weekday, int startHour) => PrivateLesson(
          id: id,
          subjectId: 'physics',
          isWeekly: true,
          weekday: weekday,
          startMinutes: startHour * 60,
          endMinutes: startHour * 60 + 90,
        );

    test('الدرس الأسبوعي بيتكرر في يومه', () {
      final lesson = weekly('l1', DateTime.tuesday, 17);
      expect(lesson.occursOn(DateTime(2026, 9, 8)), isTrue); // ثلاثاء
      expect(lesson.occursOn(DateTime(2026, 9, 9)), isFalse); // أربعاء
    });

    test('الدرس لمرة واحدة بيحصل في تاريخه فقط', () {
      final lesson = PrivateLesson(
        id: 'l2',
        subjectId: 'chemistry',
        isWeekly: false,
        specificDate: DateTime(2026, 9, 10),
        startMinutes: 18 * 60,
        endMinutes: 19 * 60,
      );
      expect(lesson.occursOn(DateTime(2026, 9, 10)), isTrue);
      expect(lesson.occursOn(DateTime(2026, 9, 17)), isFalse);
    });

    test('الدرس الجاي بيتخطى الدروس اللي فاتت النهاردة', () {
      final lessons = [
        weekly('morning', DateTime.tuesday, 9),
        weekly('evening', DateTime.tuesday, 19),
      ];
      final next = ScheduleService.nextLesson(
        lessons,
        now: DateTime(2026, 9, 8, 12, 0),
      );
      expect(next?.lesson.id, 'evening');
    });

    test('دقائق الانشغال بتجمع المدرسة والدروس مع وقت الانتقال', () {
      final periods = [period('p1', DateTime.tuesday, 8)]; // 45 دقيقة
      final lessons = [weekly('l1', DateTime.tuesday, 17)]; // 90 + 30 انتقال
      final busy = ScheduleService.busyMinutesOn(
        DateTime(2026, 9, 8),
        periods,
        lessons,
      );
      expect(busy, 45 + 90 + 30);
    });
  });
}
