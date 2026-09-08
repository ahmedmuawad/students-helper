import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../models/instructor.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';

/// إضافة أو تعديل بيانات مدرس / سنتر.
class InstructorEditor extends StatefulWidget {
  final Instructor instructor;
  final bool isNew;

  const InstructorEditor({
    super.key,
    required this.instructor,
    required this.isNew,
  });

  @override
  State<InstructorEditor> createState() => _InstructorEditorState();
}

class _InstructorEditorState extends State<InstructorEditor> {
  late Instructor _instructor;
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _area;
  late final TextEditingController _mapUrl;
  late final TextEditingController _cost;
  late final TextEditingController _notes;
  late List<ContactMethod> _contacts;

  @override
  void initState() {
    super.initState();
    _instructor = widget.instructor;
    _name = TextEditingController(text: _instructor.name);
    _address = TextEditingController(text: _instructor.address);
    _area = TextEditingController(text: _instructor.area);
    _mapUrl = TextEditingController(text: _instructor.mapUrl);
    _cost = TextEditingController(
      text: _instructor.sessionCost == 0
          ? ''
          : _instructor.sessionCost.toStringAsFixed(0),
    );
    _notes = TextEditingController(text: _instructor.notes);
    _contacts = List<ContactMethod>.from(_instructor.contacts);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _area.dispose();
    _mapUrl.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'مدرس / سنتر جديد' : 'تعديل البيانات'),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDelete(
                  context,
                  'تحذف البيانات دي؟ الدروس المرتبطة هتفضل موجودة.',
                );
                if (!ok || !context.mounted) return;
                await state.deleteInstructor(_instructor.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // النوع: مدرس / سنتر / أونلاين
          SegmentedButton<InstructorKind>(
            segments: const [
              ButtonSegment(
                value: InstructorKind.teacher,
                label: Text('مدرس'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: InstructorKind.center,
                label: Text('سنتر'),
                icon: Icon(Icons.apartment_outlined),
              ),
              ButtonSegment(
                value: InstructorKind.online,
                label: Text('أونلاين'),
                icon: Icon(Icons.videocam_outlined),
              ),
            ],
            selected: {_instructor.kind},
            onSelectionChanged: (selection) => setState(
              () => _instructor = _instructor.copyWith(kind: selection.first),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: _instructor.kind == InstructorKind.center
                  ? 'اسم السنتر'
                  : 'اسم المدرس',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            initialValue:
                _instructor.subjectId.isEmpty ? null : _instructor.subjectId,
            decoration: const InputDecoration(
              labelText: 'المادة',
              prefixIcon: Icon(Icons.menu_book_outlined),
            ),
            items: [
              for (final subject in state.subjects)
                DropdownMenuItem(
                  value: subject.id,
                  child: Text(subject.localizedName(state.languageCode)),
                ),
            ],
            onChanged: (value) => setState(
              () => _instructor = _instructor.copyWith(subjectId: value ?? ''),
            ),
          ),

          const SectionHeader('العنوان'),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'العنوان بالتفصيل',
              hintText: '٢٧ ش الجمهورية - أمام مسجد النور - الدور الثالث',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _area,
            decoration: const InputDecoration(
              labelText: 'المنطقة',
              hintText: 'المعادي / طنطا / مدينة نصر',
              prefixIcon: Icon(Icons.map_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _mapUrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'رابط الموقع على الخريطة',
              hintText: s.get('optional'),
              prefixIcon: const Icon(Icons.pin_drop_outlined),
            ),
          ),

          SectionHeader(
            'أرقام التواصل',
            trailing: TextButton.icon(
              onPressed: _addContact,
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.get('add')),
            ),
          ),
          if (_contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'مفيش أرقام مسجّلة — اضغط إضافة',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 13,
                ),
              ),
            ),
          for (var i = 0; i < _contacts.length; i++)
            _ContactRow(
              contact: _contacts[i],
              onChanged: (updated) => setState(() => _contacts[i] = updated),
              onDelete: () => setState(() => _contacts.removeAt(i)),
            ),

          const SectionHeader('بيانات إضافية'),
          TextField(
            controller: _cost,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'تكلفة الحصة',
              hintText: s.get('optional'),
              suffixText: 'ج.م',
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
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

  void _addContact() {
    setState(() {
      _contacts.add(const ContactMethod(kind: 'phone', value: ''));
    });
  }

  Future<void> _save(BuildContext context, AppState state) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'اكتب الاسم الأول');
      return;
    }

    await state.upsertInstructor(
      _instructor.copyWith(
        name: name,
        address: _address.text.trim(),
        area: _area.text.trim(),
        mapUrl: _mapUrl.text.trim(),
        sessionCost: double.tryParse(_cost.text.trim()) ?? 0,
        notes: _notes.text.trim(),
        contacts: _contacts
            .where((c) => c.value.trim().isNotEmpty)
            .toList(growable: false),
      ),
    );
    if (context.mounted) Navigator.pop(context);
  }
}

/// صف إدخال رقم تواصل واحد: النوع + الرقم + حذف.
class _ContactRow extends StatefulWidget {
  final ContactMethod contact;
  final ValueChanged<ContactMethod> onChanged;
  final VoidCallback onDelete;

  const _ContactRow({
    required this.contact,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_ContactRow> createState() => _ContactRowState();
}

class _ContactRowState extends State<_ContactRow> {
  late final TextEditingController _value;

  static const Map<String, ({String label, IconData icon})> _kinds = {
    'phone': (label: 'تليفون', icon: Icons.call_outlined),
    'whatsapp': (label: 'واتساب', icon: Icons.chat_outlined),
    'telegram': (label: 'تليجرام', icon: Icons.send_outlined),
    'link': (label: 'رابط', icon: Icons.link),
  };

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: widget.contact.value);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: DropdownButtonFormField<String>(
              initialValue: widget.contact.kind,
              isDense: true,
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              ),
              items: [
                for (final entry in _kinds.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Row(
                      children: [
                        Icon(entry.value.icon, size: 15),
                        const SizedBox(width: 6),
                        Text(entry.value.label,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                widget.onChanged(ContactMethod(
                  kind: value,
                  value: _value.text,
                  label: widget.contact.label,
                ));
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _value,
              keyboardType: widget.contact.isPhone
                  ? TextInputType.phone
                  : TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '01xxxxxxxxx',
              ),
              onChanged: (value) => widget.onChanged(ContactMethod(
                kind: widget.contact.kind,
                value: value,
                label: widget.contact.label,
              )),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: Theme.of(context).colorScheme.error,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
