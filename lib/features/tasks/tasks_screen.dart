import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/id_gen.dart';
import '../../core/utils/time_utils.dart';
import '../../models/enums.dart';
import '../../models/study_task.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import 'task_editor.dart';

/// قائمة المهام: مقسّمة لمتأخرة / النهاردة / جاية / خلصت.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);

    final pending = state.pendingTasks;
    final done = state.tasks.where((t) => t.isDone).toList()
      ..sort(
        (a, b) => (b.completedAt ?? b.createdAt).compareTo(
          a.completedAt ?? a.createdAt,
        ),
      );

    final now = DateTime.now();
    final overdue = pending.where((t) => t.isOverdue).toList();
    final today = pending
        .where(
          (t) =>
              !t.isOverdue &&
              t.dueDate != null &&
              TimeUtils.isSameDay(t.dueDate!, now),
        )
        .toList();
    final upcoming = pending
        .where(
          (t) =>
              !t.isOverdue &&
              (t.dueDate == null || !TimeUtils.isSameDay(t.dueDate!, now)),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.get('tasks')),
        actions: [
          IconButton(
            tooltip: _showDone ? 'إخفاء المنتهية' : 'إظهار المنتهية',
            icon: Icon(_showDone ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ],
      ),
      body: state.tasks.isEmpty
          ? EmptyState(
              icon: Icons.checklist_rtl,
              message: s.get('no_tasks'),
              actionLabel: s.get('add'),
              onAction: () => _add(context, state),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                if (overdue.isNotEmpty) ...[
                  SectionHeader('${s.get('overdue')} (${overdue.length})'),
                  for (final task in overdue) _TaskTile(task: task),
                ],
                if (today.isNotEmpty) ...[
                  SectionHeader('${s.get('due_today')} (${today.length})'),
                  for (final task in today) _TaskTile(task: task),
                ],
                if (upcoming.isNotEmpty) ...[
                  SectionHeader('جاية (${upcoming.length})'),
                  for (final task in upcoming) _TaskTile(task: task),
                ],
                if (_showDone && done.isNotEmpty) ...[
                  SectionHeader('خلصت (${done.length})'),
                  for (final task in done) _TaskTile(task: task),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, state),
        icon: const Icon(Icons.add),
        label: Text(s.get('add')),
      ),
    );
  }

  Future<void> _add(BuildContext context, AppState state) async {
    final task = StudyTask(
      id: IdGen.next('task'),
      title: '',
      subjectId: state.subjects.isNotEmpty ? state.subjects.first.id : '',
      createdAt: DateTime.now(),
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => TaskEditor(task: task, isNew: true)),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final StudyTask task;

  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);

    final linkedPeriod = state.periodById(task.linkedPeriodId);
    final linkedLesson = state.lessonById(task.linkedLessonId);

    String? linkLabel;
    if (linkedPeriod != null) {
      linkLabel =
          '${s.get('link_period')}: ${state.subjectName(linkedPeriod.subjectId)} '
          '${TimeUtils.weekdayName(linkedPeriod.weekday)}';
    } else if (linkedLesson != null) {
      linkLabel =
          '${s.get('link_lesson')}: ${state.subjectName(linkedLesson.subjectId)}'
          '${linkedLesson.teacherName.isEmpty ? '' : ' - ${linkedLesson.teacherName}'}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => TaskEditor(task: task, isNew: false),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: task.isDone,
                  onChanged: (_) => state.toggleTaskDone(task.id),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          decoration:
                              task.isDone ? TextDecoration.lineThrough : null,
                          color: task.isDone
                              ? Theme.of(context).colorScheme.outline
                              : null,
                        ),
                      ),
                      if (task.details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Pill(
                            s.get('type_${task.type.name}'),
                            color: state.subjectColor(task.subjectId),
                          ),
                          if (task.priority == TaskPriority.high)
                            Pill(
                              s.get('priority_high'),
                              color: AppTheme.danger,
                              icon: Icons.priority_high,
                            ),
                          if (task.dueDate != null)
                            Pill(
                              TimeUtils.relativeDayLabel(task.dueDate!),
                              color: task.isOverdue
                                  ? AppTheme.danger
                                  : AppTheme.accent,
                              icon: Icons.event,
                            ),
                        ],
                      ),
                      if (linkLabel != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.link,
                              size: 13,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                linkLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
