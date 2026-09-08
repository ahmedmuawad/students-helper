import 'package:flutter/material.dart';

/// أدوات التعامل مع الوقت والتاريخ داخل التطبيق.
class TimeUtils {
  /// تحويل [TimeOfDay] إلى عدد الدقائق منذ منتصف الليل (للتخزين).
  static int toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// تحويل عدد الدقائق منذ منتصف الليل إلى [TimeOfDay].
  static TimeOfDay fromMinutes(int minutes) {
    final safe = minutes.clamp(0, 24 * 60 - 1);
    return TimeOfDay(hour: safe ~/ 60, minute: safe % 60);
  }

  /// صيغة عربية 12 ساعة: 03:45 م
  static String formatMinutes(int minutes) {
    final t = fromMinutes(minutes);
    return formatTimeOfDay(t);
  }

  static String formatTimeOfDay(TimeOfDay t) {
    final isPm = t.hour >= 12;
    var hour12 = t.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final hh = hour12.toString().padLeft(2, '0');
    return '$hh:$mm ${isPm ? 'م' : 'ص'}';
  }

  /// دمج تاريخ مع دقائق اليوم للحصول على لحظة زمنية كاملة.
  static DateTime combine(DateTime day, int minutesOfDay) {
    return DateTime(day.year, day.month, day.day, minutesOfDay ~/ 60, minutesOfDay % 60);
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// عدد الأيام المتبقية حتى تاريخ معيّن (بالأيام الكاملة).
  static int daysUntil(DateTime target, {DateTime? from}) {
    final start = dateOnly(from ?? DateTime.now());
    final end = dateOnly(target);
    return end.difference(start).inDays;
  }

  /// اسم اليوم بالعربية اعتمادًا على [DateTime.weekday] (1=الاثنين ... 7=الأحد).
  static String weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      case DateTime.monday:
        return 'الاثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      default:
        return '';
    }
  }

  /// ترتيب أيام الأسبوع الدراسي في مصر والدول العربية (السبت أول يوم).
  static const List<int> schoolWeek = <int>[
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  static String formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  static String formatDateWithDay(DateTime d) =>
      '${weekdayName(d.weekday)} ${formatDate(d)}';

  /// نص وصفي مختصر للتاريخ (اليوم / بكرة / بعد كذا يوم).
  static String relativeDayLabel(DateTime target, {DateTime? from}) {
    final diff = daysUntil(target, from: from);
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'بكرة';
    if (diff == -1) return 'إمبارح';
    if (diff > 1) return 'بعد $diff يوم';
    return 'فات من ${-diff} يوم';
  }
}
