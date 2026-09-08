import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../data/default_data.dart';
import '../../models/private_lesson.dart';
import '../../models/school_period.dart';
import '../../models/study_task.dart';
import '../../services/schedule_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import '../settings/settings_screen.dart';
import 'app_shell.dart';

/// الشاشة الرئيسية: ملخص ذكي + اختصارات الجداول والمهام.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNextRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// الشاشة بتحدّث نفسها عند لحظة التبديل (4 عصرًا ومنتصف الليل) من غير ما
  /// الطالب يقفل التطبيق ويفتحه تاني.
  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    final now = DateTime.now();
    var wait = ScheduleService.timeUntilNextSwitch(now);
    if (wait.isNegative || wait.inSeconds < 1) {
      wait = const Duration(seconds: 1);
    }
    // سقف ساعة عشان الحصة الجاية والعدادات تفضل محدّثة كمان.
    if (wait > const Duration(minutes: 1)) {
      wait = const Duration(minutes: 1);
    }
    _refreshTimer = Timer(wait, () {
      if (mounted) {
        setState(() {});
        _scheduleNextRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final profile = state.profile;
    final now = DateTime.now();
    final schedule = state.activeSchedule;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Greeting(now: now),
              const SizedBox(height: 16),

              if (profile != null && profile.isBirthdayToday) ...[
                _BirthdayCard(
                  name: profile.name,
                  message: s.get('happy_birthday'),
                ),
                const SizedBox(height: 12),
              ],

              _NowCard(state: state, strings: s, now: now),

              SectionHeader(
                schedule.isTomorrow
                    ? s.get('timetable_tomorrow')
                    : s.get('timetable_today'),
                trailing: TextButton(
                  onPressed: () => AppShell.goToTab(context, 1),
                  child: Text(s.get('nav_timetable')),
                ),
              ),
              _TimetableShortcut(schedule: schedule, strings: s),

              SectionHeader(
                s.get('next_lesson'),
                trailing: TextButton(
                  onPressed: () => AppShell.goToTab(context, 2),
                  child: Text(s.get('nav_lessons')),
                ),
              ),
              _NextLessonCard(state: state, strings: s),

              SectionHeader(
                s.get('tasks'),
                trailing: TextButton(
                  onPressed: () => AppShell.goToTab(context, 3),
                  child: Text(s.get('nav_tasks')),
                ),
              ),
              _TasksShortcut(state: state, strings: s),

              const SizedBox(height: 24),
              _QuickActions(strings: s),
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final DateTime now;

  const _Greeting({required this.now});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final profile = state.profile;

    final greetingKey = now.hour < 12
        ? 'greeting_morning'
        : (now.hour < 17 ? 'greeting_afternoon' : 'greeting_evening');

    final gradeLabel = profile == null
        ? ''
        : (state.isArabic
              ? DefaultData.gradeNameAr(profile.gradeLevel)
              : DefaultData.gradeNameEn(profile.gradeLevel));

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.get(greetingKey),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                profile?.name.isNotEmpty == true
                    ? profile!.name
                    : s.get('app_name'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (gradeLabel.isNotEmpty)
                Text(
                  '$gradeLabel · ${TimeUtils.formatDateWithDay(now)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12.5,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }
}

class _BirthdayCard extends StatelessWidget {
  final String name;
  final String message;

  const _BirthdayCard({required this.name, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('🎂', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$message  $name',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// كارت "دلوقتي": الحصة الجارية أو الجاية.
class _NowCard extends StatelessWidget {
  final AppState state;
  final AppStrings strings;
  final DateTime now;

  const _NowCard({
    required this.state,
    required this.strings,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final current = state.currentPeriod;
    final next = state.nextPeriodToday;
    final period = current ?? next;

    if (period == null) {
      return const SizedBox.shrink();
    }

    final isCurrent = current != null;
    final color = state.subjectColor(period.subjectId);
    final minutesNow = now.hour * 60 + now.minute;
    final minutesAway = period.startMinutes - minutesNow;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SubjectStripe(color: color, height: 54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pill(
                    isCurrent
                        ? strings.get('current_period')
                        : strings.get('next_period'),
                    color: isCurrent ? AppTheme.success : AppTheme.primary,
                    icon: isCurrent ? Icons.play_circle_fill : Icons.schedule,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.subjectName(period.subjectId),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '${TimeUtils.formatMinutes(period.startMinutes)} - ${TimeUtils.formatMinutes(period.endMinutes)}',
                      if (period.room.isNotEmpty) period.room,
                      if (period.teacherName.isNotEmpty) period.teacherName,
                    ].join(' · '),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                  if (!isCurrent && minutesAway > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'بعد $minutesAway دقيقة',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// اختصار جدول الحصص — بيعرض أول 3 حصص لليوم النشط.
class _TimetableShortcut extends StatelessWidget {
  final ActiveSchedule schedule;
  final AppStrings strings;

  const _TimetableShortcut({required this.schedule, required this.strings});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (schedule.periods.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              schedule.isTomorrow
                  ? strings.get('no_periods_tomorrow')
                  : strings.get('no_periods_today'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      );
    }

    final preview = schedule.periods.take(3).toList();
    final remaining = schedule.periods.length - preview.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.event_note,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    TimeUtils.formatDateWithDay(schedule.date),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12.5,
                    ),
                  ),
                  const Spacer(),
                  if (schedule.isTomorrow)
                    Pill(
                      strings.get('tomorrow'),
                      color: AppTheme.accent,
                      icon: Icons.arrow_forward,
                    ),
                ],
              ),
            ),
            for (final period in preview)
              _PeriodRow(period: period, state: state),
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '+ $remaining حصص كمان',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final SchoolPeriod period;
  final AppState state;

  const _PeriodRow({required this.period, required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          SubjectStripe(
            color: state.subjectColor(period.subjectId),
            height: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.subjectName(period.subjectId),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (period.room.isNotEmpty)
                  Text(
                    period.room,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            TimeUtils.formatMinutes(period.startMinutes),
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _NextLessonCard extends StatelessWidget {
  final AppState state;
  final AppStrings strings;

  const _NextLessonCard({required this.state, required this.strings});

  @override
  Widget build(BuildContext context) {
    final next = state.nextLesson;
    if (next == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              strings.get('no_lessons'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      );
    }

    final PrivateLesson lesson = next.lesson;
    final pending = state.unfinishedTasksForLesson(lesson.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SubjectStripe(
              color: state.subjectColor(lesson.subjectId),
              height: 50,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.subjectName(lesson.subjectId),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      TimeUtils.relativeDayLabel(next.date),
                      TimeUtils.formatMinutes(lesson.startMinutes),
                      if (lesson.teacherName.isNotEmpty) lesson.teacherName,
                      if (lesson.place.isNotEmpty) lesson.place,
                    ].join(' · '),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 13,
                    ),
                  ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Pill(
                      '${pending.length} مهمة لسه مخلصتش',
                      color: AppTheme.danger,
                      icon: Icons.warning_amber_rounded,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksShortcut extends StatelessWidget {
  final AppState state;
  final AppStrings strings;

  const _TasksShortcut({required this.state, required this.strings});

  @override
  Widget build(BuildContext context) {
    final pending = state.pendingTasks;
    if (pending.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              strings.get('no_tasks'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      );
    }

    final preview = pending.take(3).toList();

    return Card(
      child: Column(
        children: [
          if (state.overdueCount > 0 || state.dueTodayCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  if (state.overdueCount > 0)
                    Pill(
                      '${state.overdueCount} ${strings.get('overdue')}',
                      color: AppTheme.danger,
                      icon: Icons.error_outline,
                    ),
                  if (state.overdueCount > 0 && state.dueTodayCount > 0)
                    const SizedBox(width: 8),
                  if (state.dueTodayCount > 0)
                    Pill(
                      '${state.dueTodayCount} ${strings.get('due_today')}',
                      color: AppTheme.accent,
                      icon: Icons.today,
                    ),
                ],
              ),
            ),
          for (final task in preview) _TaskRow(task: task, state: state),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final StudyTask task;
  final AppState state;

  const _TaskRow({required this.task, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: task.isDone,
        onChanged: (_) => state.toggleTaskDone(task.id),
      ),
      title: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: task.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: task.dueDate == null
          ? null
          : Text(
              TimeUtils.relativeDayLabel(task.dueDate!),
              style: TextStyle(
                fontSize: 12,
                color: task.isOverdue
                    ? AppTheme.danger
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
      trailing: task.subjectId.isEmpty
          ? null
          : CircleAvatar(
              radius: 5,
              backgroundColor: state.subjectColor(task.subjectId),
            ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final AppStrings strings;

  const _QuickActions({required this.strings});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.calculate,
            label: strings.get('calculator'),
            onTap: () => AppShell.goToTab(context, 4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.add_task,
            label: strings.get('tasks'),
            onTap: () => AppShell.goToTab(context, 3),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(
                icon,
                size: 26,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
