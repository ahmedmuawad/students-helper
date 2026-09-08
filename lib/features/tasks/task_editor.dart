import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/time_utils.dart';
import '../../models/enums.dart';
import '../../models/study_task.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';

/// إضافة أو تعديل مهمة، مع ربطها بحصة مدرسية أو درس خصوصي.
class TaskEditor extends StatefulWidget {
  final StudyTask task;
  final bool isNew;

  const TaskEditor({super.key, required this.task, required this.isNew});

  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

/// نوع الربط المختار في المحرر.
enum _LinkKind { none, period, lesson }

class _TaskEditorState extends State<TaskEditor> {
  late StudyTask _task;
  late final TextEditingController _title;
  late final TextEditingController _details;
  late _LinkKind _linkKind;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _title = TextEditingController(text: _task.title);
    _details = TextEditingController(text: _task.details);
    _linkKind = _task.linkedPeriodId != null
        ? _LinkKind.period
        : (_task.linkedLessonId != null ? _LinkKind.lesson : _LinkKind.none);
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isNew ? '${s.get('add')} ${s.get('task')}' : s.get('edit'),
        ),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDelete(context, 'تحذف المهمة دي؟');
                if (!ok || !context.mounted) return;
                await state.deleteTask(_task.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          TextField(
            controller: _title,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: s.get('task_title'),
              hintText: 'مثال: حل تمارين الوحدة الثانية',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _details,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: s.get('task_details'),
              hintText: s.get('optional'),
            ),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            initialValue: _task.subjectId.isEmpty ? null : _task.subjectId,
            decoration: InputDecoration(labelText: s.get('subjects')),
            items: [
              for (final subject in state.subjects)
                DropdownMenuItem(
                  value: subject.id,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 6,
                        backgroundColor: Color(subject.colorValue),
                      ),
                      const SizedBox(width: 8),
                      Text(subject.localizedName(state.languageCode)),
                    ],
                  ),
                ),
            ],
            onChanged: (value) =>
                setState(() => _task = _task.copyWith(subjectId: value ?? '')),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TaskType>(
                  initialValue: _task.type,
                  decoration: InputDecoration(labelText: s.get('task_type')),
                  items: [
                    for (final type in TaskType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(s.get('type_${type.name}')),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _task = _task.copyWith(type: value)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<TaskPriority>(
                  initialValue: _task.priority,
                  decoration: InputDecoration(labelText: s.get('priority')),
                  items: [
                    for (final priority in TaskPriority.values)
                      DropdownMenuItem(
                        value: priority,
                        child: Text(s.get('priority_${priority.name}')),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _task = _task.copyWith(priority: value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // موعد التسليم
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _task.dueDate ?? now,
                firstDate: now.subtract(const Duration(days: 90)),
                lastDate: now.add(const Duration(days: 730)),
              );
              if (picked != null) {
                setState(() => _task = _task.copyWith(dueDate: picked));
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: s.get('due_date'),
                suffixIcon: _task.dueDate == null
                    ? const Icon(Icons.event)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(
                          () => _task = _task.copyWith(clearDueDate: true),
                        ),
                      ),
              ),
              child: Text(
                _task.dueDate == null
                    ? s.get('none')
                    : TimeUtils.formatDateWithDay(_task.dueDate!),
              ),
            ),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<int>(
            initialValue: _task.estimatedMinutes,
            decoration: InputDecoration(labelText: s.get('estimated_time')),
            items: const [
              DropdownMenuItem(value: 15, child: Text('١٥ دقيقة')),
              DropdownMenuItem(value: 30, child: Text('٣٠ دقيقة')),
              DropdownMenuItem(value: 45, child: Text('٤٥ دقيقة')),
              DropdownMenuItem(value: 60, child: Text('ساعة')),
              DropdownMenuItem(value: 90, child: Text('ساعة ونص')),
              DropdownMenuItem(value: 120, child: Text('ساعتين')),
            ],
            onChanged: (value) =>
                setState(() => _task = _task.copyWith(estimatedMinutes: value)),
          ),

          const SizedBox(height: 18),
          const Divider(),
          SectionHeader(s.get('link_to')),
          Text(
            'لما تربط المهمة بحصة أو درس، التطبيق هيفكّرك بيها قبل الموعد '
            'وهيسألك خلصتها ولا لأ.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),

          SegmentedButton<_LinkKind>(
            segments: [
              ButtonSegment(value: _LinkKind.none, label: Text(s.get('none'))),
              ButtonSegment(
                value: _LinkKind.period,
                label: Text(s.get('link_period')),
              ),
              ButtonSegment(
                value: _LinkKind.lesson,
                label: Text(s.get('link_lesson')),
              ),
            ],
            selected: {_linkKind},
            onSelectionChanged: (selection) {
              setState(() {
                _linkKind = selection.first;
                _task = _task.copyWith(clearLinks: true);
              });
            },
          ),
          const SizedBox(height: 14),

          if (_linkKind == _LinkKind.period)
            DropdownButtonFormField<String>(
              initialValue: _task.linkedPeriodId,
              decoration: InputDecoration(labelText: s.get('link_period')),
              isExpanded: true,
              items: [
                for (final period in state.periods)
                  DropdownMenuItem(
                    value: period.id,
                    child: Text(
                      '${state.subjectName(period.subjectId)} · '
                      '${TimeUtils.weekdayName(period.weekday)} · '
                      '${TimeUtils.formatMinutes(period.startMinutes)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _task = _task.copyWith(linkedPeriodId: value)),
            ),

          if (_linkKind == _LinkKind.lesson)
            DropdownButtonFormField<String>(
              initialValue: _task.linkedLessonId,
              decoration: InputDecoration(labelText: s.get('link_lesson')),
              isExpanded: true,
              items: [
                for (final lesson in state.lessons)
                  DropdownMenuItem(
                    value: lesson.id,
                    child: Text(
                      '${state.subjectName(lesson.subjectId)}'
                      '${lesson.teacherName.isEmpty ? '' : ' · ${lesson.teacherName}'} · '
                      '${lesson.isWeekly ? TimeUtils.weekdayName(lesson.weekday) : TimeUtils.formatDate(lesson.specificDate ?? DateTime.now())}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _task = _task.copyWith(linkedLessonId: value)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => _save(context, state),
            child: Text(s.get('save')),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, AppState state) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, 'اكتب عنوان المهمة');
      return;
    }

    await state.upsertTask(
      _task.copyWith(title: title, details: _details.text.trim()),
    );

    await NotificationService.instance.rescheduleAll(
      lessons: state.lessons,
      periods: state.periods,
      tasks: state.tasks,
      subjectName: state.subjectName,
    );

    if (context.mounted) Navigator.pop(context);
  }
}
