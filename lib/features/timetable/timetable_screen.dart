import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/id_gen.dart';
import '../../core/utils/time_utils.dart';
import '../../data/default_data.dart';
import '../../models/school_period.dart';
import '../../services/schedule_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import 'period_editor.dart';

/// جدول الحصص المدرسية الأسبوعي.
///
/// بيفتح تلقائيًا على اليوم النشط حسب قاعدة الـ4 عصرًا: قبل 4 عصرًا يفتح على
/// النهاردة، وبعدها يفتح على بكرة.
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with SingleTickerProviderStateMixin {
  late TabController _controller;

  static const List<int> _days = TimeUtils.schoolWeek;

  @override
  void initState() {
    super.initState();
    final focusDate = ScheduleService.focusDate(DateTime.now());
    final initial = _days.indexOf(focusDate.weekday);
    _controller = TabController(
      length: _days.length,
      vsync: this,
      initialIndex: initial < 0 ? 0 : initial,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final now = DateTime.now();
    final focusDate = ScheduleService.focusDate(now);
    final showsTomorrow = ScheduleService.showsTomorrow(now);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.get('timetable')),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final day in _days)
              Tab(
                child: Row(
                  children: [
                    Text(TimeUtils.weekdayName(day)),
                    if (day == focusDate.weekday) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // شريط توضيحي لقاعدة الـ4 عصرًا — الطالب لازم يفهم ليه بيشوف بكرة.
          Container(
            width: double.infinity,
            color: showsTomorrow
                ? AppTheme.accent.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Icon(
                  showsTomorrow ? Icons.wb_twilight : Icons.today,
                  size: 17,
                  color: showsTomorrow
                      ? AppTheme.accent
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showsTomorrow
                        ? '${s.get('timetable_tomorrow')} · ${TimeUtils.formatDateWithDay(focusDate)}'
                        : '${s.get('timetable_today')} · ${TimeUtils.formatDateWithDay(focusDate)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  s.get('switches_at_four'),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: [for (final day in _days) _DaySchedule(weekday: day)],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPeriod(context, state),
        icon: const Icon(Icons.add),
        label: Text(s.get('add')),
      ),
    );
  }

  Future<void> _addPeriod(BuildContext context, AppState state) async {
    final weekday = _days[_controller.index];
    final existing = state.periodsForDay(_dateForWeekday(weekday));
    final defaults = DefaultData.defaultPeriodTimes();
    final slot = existing.length < defaults.length
        ? defaults[existing.length]
        : (start: 8 * 60, end: 8 * 60 + 45);

    final period = SchoolPeriod(
      id: IdGen.next('period'),
      weekday: weekday,
      periodNumber: existing.length + 1,
      subjectId: state.subjects.isNotEmpty ? state.subjects.first.id : '',
      startMinutes: slot.start,
      endMinutes: slot.end,
    );

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodEditor(period: period, isNew: true),
      ),
    );
  }

  /// أقرب تاريخ ليوم أسبوع معيّن — بنستخدمه للاستعلام عن حصص اليوم ده.
  static DateTime _dateForWeekday(int weekday) {
    final today = TimeUtils.dateOnly(DateTime.now());
    final diff = (weekday - today.weekday + 7) % 7;
    return today.add(Duration(days: diff));
  }
}

class _DaySchedule extends StatelessWidget {
  final int weekday;

  const _DaySchedule({required this.weekday});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final date = _TimetableScreenState._dateForWeekday(weekday);
    final periods = state.periodsForDay(date);

    if (periods.isEmpty) {
      return EmptyState(
        icon: Icons.event_available,
        message: 'مفيش حصص مسجّلة يوم ${TimeUtils.weekdayName(weekday)}',
        actionLabel: s.get('add'),
        onAction: () {},
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: periods.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final period = periods[index];
        final tasks = state.tasksForPeriod(period.id);
        final pending = tasks.where((t) => !t.isDone).length;

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => PeriodEditor(period: period, isNew: false),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: state
                              .subjectColor(period.subjectId)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${period.periodNumber}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: state.subjectColor(period.subjectId),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.subjectName(period.subjectId),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            '${TimeUtils.formatMinutes(period.startMinutes)} - ${TimeUtils.formatMinutes(period.endMinutes)}',
                            if (period.teacherName.isNotEmpty)
                              period.teacherName,
                            if (period.room.isNotEmpty) period.room,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        if (pending > 0) ...[
                          const SizedBox(height: 8),
                          Pill(
                            '$pending مهمة مرتبطة',
                            color: AppTheme.danger,
                            icon: Icons.assignment_late_outlined,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
