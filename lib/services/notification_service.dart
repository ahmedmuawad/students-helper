import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/time_utils.dart';
import '../models/private_lesson.dart';
import '../models/school_period.dart';
import '../models/study_task.dart';

/// إدارة التذكيرات المحلية.
///
/// التصميم مقصود إنه **متسامح مع الفشل**: لو صلاحية الإشعارات مرفوضة أو
/// الإعداد فشل لأي سبب، التطبيق بيكمل شغل عادي من غير ما يقع.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  bool get isReady => _ready;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'students_helper_reminders',
        'تذكيرات المذاكرة',
        channelDescription: 'تذكيرات الحصص والدروس والمهام والامتحانات',
        importance: Importance.high,
        priority: Priority.high,
      );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
  );

  Future<void> initialize() async {
    if (_ready) return;
    try {
      tz_data.initializeTimeZones();

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      );

      await _plugin.initialize(settings);
      _ready = true;
    } catch (error) {
      debugPrint('تعذّر إعداد الإشعارات: $error');
      _ready = false;
    }
  }

  Future<bool> requestPermissions() async {
    if (!_ready) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    } catch (error) {
      debugPrint('تعذّر طلب صلاحية الإشعارات: $error');
    }
    return false;
  }

  /// جدولة تنبيه في لحظة محددة. بيتجاهل المواعيد اللي فاتت.
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!_ready) return;
    if (!when.isAfter(DateTime.now())) return;

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (error) {
      debugPrint('تعذّر جدولة التنبيه: $error');
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  // -------------------------------------------------------------------
  // جدولة تذكيرات التطبيق
  // -------------------------------------------------------------------

  /// إعادة بناء كل التذكيرات من أول وجديد.
  ///
  /// بننادي دي بعد أي تعديل على الدروس أو المهام — أبسط وأأمن من محاولة
  /// تتبّع كل تنبيه على حدة.
  Future<void> rescheduleAll({
    required List<PrivateLesson> lessons,
    required List<SchoolPeriod> periods,
    required List<StudyTask> tasks,
    required String Function(String subjectId) subjectName,
    int daysAhead = 14,
  }) async {
    if (!_ready) return;
    await cancelAll();

    final now = DateTime.now();

    for (var offset = 0; offset <= daysAhead; offset++) {
      final day = TimeUtils.dateOnly(now).add(Duration(days: offset));

      for (final lesson in lessons) {
        if (!lesson.occursOn(day)) continue;

        final pendingTasks = tasks
            .where((t) => t.linkedLessonId == lesson.id && !t.isDone)
            .toList();

        // ✅ الشرط المطلوب: تذكير قبل الدرس بيوم **لو فيه مهام** تخصّه.
        if (lesson.remindDayBefore && pendingTasks.isNotEmpty) {
          final reminderDay = day.subtract(const Duration(days: 1));
          // التذكير الساعة 6 مساءً في اليوم اللي قبله.
          final when = TimeUtils.combine(reminderDay, 18 * 60);
          await scheduleAt(
            id: _idFor('lesson_day_before', lesson.id, day),
            title:
                'بكرة عندك ${subjectName(lesson.subjectId)} مع ${lesson.teacherName}',
            body: pendingTasks.length == 1
                ? 'مهمة لسه مخلصتش: ${pendingTasks.first.title}'
                : 'عندك ${pendingTasks.length} مهام لسه مخلصتش للدرس ده',
            when: when,
            payload: 'lesson:${lesson.id}',
          );
        }

        // تذكير قبل الدرس بعدد دقائق.
        if (lesson.remindBeforeMinutes > 0) {
          final start = TimeUtils.combine(day, lesson.startMinutes);
          final when = start.subtract(
            Duration(minutes: lesson.remindBeforeMinutes),
          );
          await scheduleAt(
            id: _idFor('lesson_soon', lesson.id, day),
            title:
                '${subjectName(lesson.subjectId)} بعد ${lesson.remindBeforeMinutes} دقيقة',
            body: lesson.place.isEmpty
                ? 'استعد للدرس'
                : 'المكان: ${lesson.place}',
            when: when,
            payload: 'lesson:${lesson.id}',
          );
        }
      }
    }

    // تذكير المهام في موعد تسليمها (الساعة 8 صباحًا في يوم الاستحقاق).
    for (final task in tasks) {
      final due = task.dueDate;
      if (due == null || task.isDone) continue;
      if (due.isBefore(now)) continue;
      if (TimeUtils.daysUntil(due, from: now) > daysAhead) continue;

      await scheduleAt(
        id: _idFor('task_due', task.id, due),
        title: 'مهمة مستحقة النهاردة',
        body: task.title,
        when: TimeUtils.combine(due, 8 * 60),
        payload: 'task:${task.id}',
      );
    }
  }

  /// معرّف رقمي ثابت لكل تنبيه — لازم يبقى ضمن نطاق 32 بت.
  int _idFor(String kind, String entityId, DateTime day) {
    final raw = '$kind|$entityId|${day.year}-${day.month}-${day.day}';
    return raw.hashCode & 0x7FFFFFFF;
  }
}
