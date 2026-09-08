import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/id_gen.dart';
import '../../core/utils/time_utils.dart';
import '../../models/private_lesson.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import 'lesson_editor.dart';

/// جدول الدروس الخصوصية، مجمّع حسب اليوم.
class LessonsScreen extends StatelessWidget {
  const LessonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final lessons = state.lessons;

    return Scaffold(
      appBar: AppBar(title: Text(s.get('lessons'))),
      body: lessons.isEmpty
          ? EmptyState(
              icon: Icons.school_outlined,
              message: s.get('no_lessons'),
              actionLabel: s.get('add'),
              onAction: () => _add(context, state),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                for (final weekday in TimeUtils.schoolWeek)
                  ..._dayGroup(context, state, s, weekday),
                ..._oneTimeGroup(context, state, s),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, state),
        icon: const Icon(Icons.add),
        label: Text(s.get('add')),
      ),
    );
  }

  List<Widget> _dayGroup(
    BuildContext context,
    AppState state,
    AppStrings s,
    int weekday,
  ) {
    final dayLessons = state.lessons
        .where((l) => l.isWeekly && l.weekday == weekday)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    if (dayLessons.isEmpty) return const [];

    return [
      SectionHeader(TimeUtils.weekdayName(weekday)),
      for (final lesson in dayLessons) ...[
        _LessonCard(lesson: lesson, state: state),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _oneTimeGroup(
    BuildContext context,
    AppState state,
    AppStrings s,
  ) {
    final oneTime = state.lessons.where((l) => !l.isWeekly).toList()
      ..sort((a, b) {
        final aDate = a.specificDate;
        final bDate = b.specificDate;
        if (aDate == null || bDate == null) return 0;
        return aDate.compareTo(bDate);
      });

    if (oneTime.isEmpty) return const [];

    return [
      SectionHeader(s.get('one_time')),
      for (final lesson in oneTime) ...[
        _LessonCard(lesson: lesson, state: state),
        const SizedBox(height: 10),
      ],
    ];
  }

  Future<void> _add(BuildContext context, AppState state) async {
    final lesson = PrivateLesson(
      id: IdGen.next('lesson'),
      subjectId: state.subjects.isNotEmpty ? state.subjects.first.id : '',
      startMinutes: 16 * 60,
      endMinutes: 17 * 60 + 30,
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LessonEditor(lesson: lesson, isNew: true),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final PrivateLesson lesson;
  final AppState state;

  const _LessonCard({required this.lesson, required this.state});

  @override
  Widget build(BuildContext context) {
    final pending = state.unfinishedTasksForLesson(lesson.id);
    final color = state.subjectColor(lesson.subjectId);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LessonEditor(lesson: lesson, isNew: false),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SubjectStripe(color: color, height: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.subjectName(lesson.subjectId),
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (lesson.remindDayBefore)
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      ],
                    ),
                    if (lesson.sessionTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        lesson.sessionTitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${TimeUtils.formatMinutes(lesson.startMinutes)} - ${TimeUtils.formatMinutes(lesson.endMinutes)}',
                        if (state.lessonTeacherName(lesson).isNotEmpty)
                          state.lessonTeacherName(lesson),
                        if (state.lessonPlace(lesson).isNotEmpty)
                          state.lessonPlace(lesson),
                        if (!lesson.isWeekly && lesson.specificDate != null)
                          TimeUtils.formatDate(lesson.specificDate!),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    if (pending.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Pill(
                        '${pending.length} مهمة لسه مخلصتش',
                        color: AppTheme.danger,
                        icon: Icons.assignment_late_outlined,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
