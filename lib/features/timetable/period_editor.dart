import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/time_utils.dart';
import '../../models/school_period.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';

/// إضافة أو تعديل حصة في الجدول المدرسي.
class PeriodEditor extends StatefulWidget {
  final SchoolPeriod period;
  final bool isNew;

  const PeriodEditor({super.key, required this.period, required this.isNew});

  @override
  State<PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<PeriodEditor> {
  late SchoolPeriod _period;
  late final TextEditingController _teacher;
  late final TextEditingController _room;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _period = widget.period;
    _teacher = TextEditingController(text: _period.teacherName);
    _room = TextEditingController(text: _period.room);
    _note = TextEditingController(text: _period.note);
  }

  @override
  void dispose() {
    _teacher.dispose();
    _room.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isNew ? '${s.get('add')} ${s.get('period')}' : s.get('edit'),
        ),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDelete(context, 'تحذف الحصة دي؟');
                if (!ok || !context.mounted) return;
                await state.deletePeriod(_period.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // المادة
          DropdownButtonFormField<String>(
            initialValue: _period.subjectId.isEmpty ? null : _period.subjectId,
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
              () => _period = _period.copyWith(subjectId: value ?? ''),
            ),
          ),
          const SizedBox(height: 14),

          // اليوم ورقم الحصة
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _period.weekday,
                  decoration: const InputDecoration(labelText: 'اليوم'),
                  items: [
                    for (final day in TimeUtils.schoolWeek)
                      DropdownMenuItem(
                        value: day,
                        child: Text(TimeUtils.weekdayName(day)),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => _period = _period.copyWith(weekday: value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _period.periodNumber,
                  decoration: InputDecoration(
                    labelText: s.get('period_number'),
                  ),
                  items: [
                    for (var i = 1; i <= 10; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (value) => setState(
                    () => _period = _period.copyWith(periodNumber: value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // المواعيد
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: s.get('from'),
                  minutes: _period.startMinutes,
                  onChanged: (value) => setState(
                    () => _period = _period.copyWith(startMinutes: value),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: s.get('to'),
                  minutes: _period.endMinutes,
                  onChanged: (value) => setState(
                    () => _period = _period.copyWith(endMinutes: value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _teacher,
            decoration: InputDecoration(labelText: s.get('teacher')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _room,
            decoration: InputDecoration(labelText: s.get('room')),
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
            onPressed: () => _save(context, state, s),
            child: Text(s.get('save')),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, AppState state, AppStrings s) async {
    if (_period.subjectId.isEmpty) {
      showSnack(context, 'اختار المادة الأول');
      return;
    }
    if (_period.endMinutes <= _period.startMinutes) {
      showSnack(context, 'وقت النهاية لازم يكون بعد وقت البداية');
      return;
    }

    await state.upsertPeriod(
      _period.copyWith(
        teacherName: _teacher.text.trim(),
        room: _room.text.trim(),
        note: _note.text.trim(),
      ),
    );
    if (context.mounted) Navigator.pop(context);
  }
}

/// حقل اختيار وقت بصيغة عربية 12 ساعة.
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
