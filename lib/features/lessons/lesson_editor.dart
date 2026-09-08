import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/time_utils.dart';
import '../../models/private_lesson.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';

/// إضافة أو تعديل درس خصوصي.
class LessonEditor extends StatefulWidget {
  final PrivateLesson lesson;
  final bool isNew;

  const LessonEditor({super.key, required this.lesson, required this.isNew});

  @override
  State<LessonEditor> createState() => _LessonEditorState();
}

class _LessonEditorState extends State<LessonEditor> {
  late PrivateLesson _lesson;
  late final TextEditingController _teacher;
  late final TextEditingController _place;
  late final TextEditingController _session;
  late final TextEditingController _cost;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _lesson = widget.lesson;
    _teacher = TextEditingController(text: _lesson.teacherName);
    _place = TextEditingController(text: _lesson.place);
    _session = TextEditingController(text: _lesson.sessionTitle);
    _cost = TextEditingController(
      text: _lesson.cost == 0 ? '' : _lesson.cost.toStringAsFixed(0),
    );
    _note = TextEditingController(text: _lesson.note);
  }

  @override
  void dispose() {
    _teacher.dispose();
    _place.dispose();
    _session.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final linkedTasks = state.tasksForLesson(_lesson.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? s.get('private_lesson') : s.get('edit')),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDelete(context, 'تحذف الدرس ده؟');
                if (!ok || !context.mounted) return;
                await state.deleteLesson(_lesson.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _lesson.subjectId.isEmpty ? null : _lesson.subjectId,
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
            onChanged: (value) => setState(
              () => _lesson = _lesson.copyWith(subjectId: value ?? ''),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _session,
            decoration: InputDecoration(
              labelText: s.get('session_title'),
              hintText: 'مثال: حصة 5 - المتتابعات',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _teacher,
            decoration: InputDecoration(labelText: s.get('teacher')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _place,
            decoration: InputDecoration(
              labelText: s.get('place'),
              hintText: 'سنتر / بيت المدرس / أونلاين',
            ),
          ),
          const SizedBox(height: 18),

          // التكرار
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(s.get('weekly'))),
              ButtonSegment(value: false, label: Text(s.get('one_time'))),
            ],
            selected: {_lesson.isWeekly},
            onSelectionChanged: (selection) => setState(
              () => _lesson = _lesson.copyWith(isWeekly: selection.first),
            ),
          ),
          const SizedBox(height: 14),

          if (_lesson.isWeekly)
            DropdownButtonFormField<int>(
              initialValue: _lesson.weekday,
              decoration: const InputDecoration(labelText: 'اليوم'),
              items: [
                for (final day in TimeUtils.schoolWeek)
                  DropdownMenuItem(
                    value: day,
                    child: Text(TimeUtils.weekdayName(day)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _lesson = _lesson.copyWith(weekday: value)),
            )
          else
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _lesson.specificDate ?? now,
                  firstDate: now.subtract(const Duration(days: 30)),
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(
                    () => _lesson = _lesson.copyWith(specificDate: picked),
                  );
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'التاريخ'),
                child: Text(
                  _lesson.specificDate == null
                      ? s.get('none')
                      : TimeUtils.formatDateWithDay(_lesson.specificDate!),
                ),
              ),
            ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: s.get('from'),
                  minutes: _lesson.startMinutes,
                  onChanged: (value) => setState(
                    () => _lesson = _lesson.copyWith(startMinutes: value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: s.get('to'),
                  minutes: _lesson.endMinutes,
                  onChanged: (value) => setState(
                    () => _lesson = _lesson.copyWith(endMinutes: value),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          const Divider(),

          // ✅ الشرط المطلوب: تذكير قبل الدرس بيوم لو فيه مهام مرتبطة بيه.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _lesson.remindDayBefore,
            title: Text(s.get('remind_day_before')),
            subtitle: Text(
              linkedTasks.isEmpty
                  ? 'مفيش مهام مربوطة بالدرس ده لسه'
                  : '${linkedTasks.where((t) => !t.isDone).length} مهمة لسه مخلصتش',
              style: const TextStyle(fontSize: 12),
            ),
            onChanged: (value) => setState(
              () => _lesson = _lesson.copyWith(remindDayBefore: value),
            ),
          ),

          DropdownButtonFormField<int>(
            initialValue: _lesson.remindBeforeMinutes,
            decoration: InputDecoration(labelText: s.get('remind_before')),
            items: const [
              DropdownMenuItem(value: 0, child: Text('بدون تذكير')),
              DropdownMenuItem(value: 15, child: Text('١٥ دقيقة')),
              DropdownMenuItem(value: 30, child: Text('٣٠ دقيقة')),
              DropdownMenuItem(value: 60, child: Text('ساعة')),
              DropdownMenuItem(value: 120, child: Text('ساعتين')),
            ],
            onChanged: (value) => setState(
              () => _lesson = _lesson.copyWith(remindBeforeMinutes: value),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _cost,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: s.get('cost'),
              hintText: s.get('optional'),
              suffixText: 'ج.م',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'ملاحظات',
              hintText: s.get('optional'),
            ),
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
    if (_lesson.subjectId.isEmpty) {
      showSnack(context, 'اختار المادة الأول');
      return;
    }
    if (_lesson.endMinutes <= _lesson.startMinutes) {
      showSnack(context, 'وقت النهاية لازم يكون بعد وقت البداية');
      return;
    }
    if (!_lesson.isWeekly && _lesson.specificDate == null) {
      showSnack(context, 'اختار تاريخ الدرس');
      return;
    }

    await state.upsertLesson(
      _lesson.copyWith(
        teacherName: _teacher.text.trim(),
        place: _place.text.trim(),
        sessionTitle: _session.text.trim(),
        cost: double.tryParse(_cost.text.trim()) ?? 0,
        note: _note.text.trim(),
      ),
    );

    // إعادة جدولة التذكيرات بعد أي تعديل.
    await NotificationService.instance.rescheduleAll(
      lessons: state.lessons,
      periods: state.periods,
      tasks: state.tasks,
      subjectName: state.subjectName,
    );

    if (context.mounted) Navigator.pop(context);
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  const _TimeField({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeUtils.fromMinutes(minutes),
        );
        if (picked != null) onChanged(TimeUtils.toMinutes(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(TimeUtils.formatMinutes(minutes)),
      ),
    );
  }
}
