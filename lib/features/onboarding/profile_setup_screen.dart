import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/time_utils.dart';
import '../../data/default_data.dart';
import '../../models/enums.dart';
import '../../models/student_profile.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import '../home/app_shell.dart';

/// إنشاء الحساب الشخصي للطالب — أول شاشة يشوفها.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late StudentProfile _profile;
  final _name = TextEditingController();
  final _school = TextEditingController();
  bool _initialized = false;

  /// أشهر الدول العربية لطلاب التطبيق.
  static const List<({String code, String ar, String en})> _countries = [
    (code: 'EG', ar: 'مصر', en: 'Egypt'),
    (code: 'SA', ar: 'السعودية', en: 'Saudi Arabia'),
    (code: 'AE', ar: 'الإمارات', en: 'UAE'),
    (code: 'KW', ar: 'الكويت', en: 'Kuwait'),
    (code: 'QA', ar: 'قطر', en: 'Qatar'),
    (code: 'JO', ar: 'الأردن', en: 'Jordan'),
    (code: 'LY', ar: 'ليبيا', en: 'Libya'),
    (code: 'SD', ar: 'السودان', en: 'Sudan'),
    (code: 'OM', ar: 'عُمان', en: 'Oman'),
    (code: 'BH', ar: 'البحرين', en: 'Bahrain'),
    (code: 'OTHER', ar: 'دولة أخرى', en: 'Other'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final state = context.read<AppState>();
    _profile = state.profile ?? state.newProfile();
    _name.text = _profile.name;
    _school.text = _profile.schoolName;
  }

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final tracks = DefaultData.tracksFor(_profile.educationSystem);
    final showTracks =
        _profile.educationSystem.usesTracks && _profile.gradeLevel >= 10;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.get('profile')),
        actions: [
          // تبديل اللغة متاح من أول شاشة.
          TextButton(
            onPressed: () =>
                state.setLanguage(state.languageCode == 'ar' ? 'en' : 'ar'),
            child: Text(state.languageCode == 'ar' ? 'EN' : 'ع'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            s.isArabic
                ? 'بياناتك دي بتخلّي التطبيق يجهّزلك موادك وجدولك تلقائيًا.'
                : 'These details let the app prepare your subjects and schedule.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: s.get('student_name')),
          ),
          const SizedBox(height: 14),

          // تاريخ الميلاد
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _profile.birthDate ??
                    DateTime(now.year - 14, now.month, now.day),
                firstDate: DateTime(now.year - 30),
                lastDate: now,
              );
              if (picked != null) {
                setState(() => _profile = _profile.copyWith(birthDate: picked));
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: s.get('birth_date'),
                suffixIcon: const Icon(Icons.cake_outlined),
              ),
              child: Text(
                _profile.birthDate == null
                    ? s.get('none')
                    : TimeUtils.formatDate(_profile.birthDate!),
              ),
            ),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            initialValue: _profile.countryCode,
            decoration: InputDecoration(labelText: s.get('country')),
            items: [
              for (final country in _countries)
                DropdownMenuItem(
                  value: country.code,
                  child: Text(s.isArabic ? country.ar : country.en),
                ),
            ],
            onChanged: (value) => setState(
              () => _profile = _profile.copyWith(countryCode: value),
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _school,
            decoration: InputDecoration(labelText: s.get('school')),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<int>(
            initialValue: _profile.gradeLevel,
            decoration: InputDecoration(labelText: s.get('grade_level')),
            isExpanded: true,
            items: [
              for (var grade = 1; grade <= 12; grade++)
                DropdownMenuItem(
                  value: grade,
                  child: Text(
                    s.isArabic
                        ? DefaultData.gradeNameAr(grade)
                        : DefaultData.gradeNameEn(grade),
                  ),
                ),
            ],
            onChanged: (value) =>
                setState(() => _profile = _profile.copyWith(gradeLevel: value)),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<EducationSystem>(
            initialValue: _profile.educationSystem,
            decoration: InputDecoration(labelText: s.get('education_system')),
            isExpanded: true,
            items: [
              for (final system in EducationSystem.values)
                DropdownMenuItem(
                  value: system,
                  child: Text(s.get('sys_${system.name}')),
                ),
            ],
            onChanged: (value) => setState(
              () => _profile = _profile.copyWith(
                educationSystem: value,
                trackId: '',
              ),
            ),
          ),

          // تنبيه للبكالوريا — نظام جديد ومختلف عن اللي الأهل متعودين عليه.
          if (_profile.educationSystem == EducationSystem.egyptBaccalaureate)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'نظام تراكمي: درجات تانية وتالتة ثانوي بتتجمع من ٦٠٠ درجة.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          if (showTracks && tracks.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              initialValue: _profile.trackId.isEmpty ? null : _profile.trackId,
              decoration: InputDecoration(labelText: s.get('track')),
              isExpanded: true,
              items: [
                for (final track in tracks)
                  DropdownMenuItem(
                    value: track.id,
                    child: Text(track.localizedName(state.languageCode)),
                  ),
              ],
              onChanged: (value) => setState(
                () => _profile = _profile.copyWith(trackId: value ?? ''),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // عربي / لغات / دولية
          SectionHeader(s.get('school_language')),
          SegmentedButton<SchoolLanguage>(
            segments: [
              ButtonSegment(
                value: SchoolLanguage.arabic,
                label: Text(s.get('lang_arabic')),
              ),
              ButtonSegment(
                value: SchoolLanguage.languages,
                label: Text(s.get('lang_languages')),
              ),
              ButtonSegment(
                value: SchoolLanguage.international,
                label: Text(s.get('lang_international')),
              ),
            ],
            selected: {_profile.schoolLanguage},
            onSelectionChanged: (selection) => setState(
              () =>
                  _profile = _profile.copyWith(schoolLanguage: selection.first),
            ),
          ),
          const SizedBox(height: 18),

          // الترم
          SectionHeader(s.get('term')),
          SegmentedButton<Term>(
            segments: [
              ButtonSegment(
                value: Term.first,
                label: Text(s.get('term_first')),
              ),
              ButtonSegment(
                value: Term.second,
                label: Text(s.get('term_second')),
              ),
            ],
            selected: {_profile.currentTerm},
            onSelectionChanged: (selection) => setState(
              () => _profile = _profile.copyWith(currentTerm: selection.first),
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
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'اكتب اسمك الأول');
      return;
    }

    await state.saveProfile(
      _profile.copyWith(name: name, schoolName: _school.text.trim()),
      seedSubjects: true,
    );
    await state.completeOnboarding();
    await NotificationService.instance.requestPermissions();

    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }
}
