import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/time_utils.dart';
import '../../models/student_profile.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../common/ui_helpers.dart';
import '../onboarding/profile_setup_screen.dart';

/// إعدادات التطبيق: اللغة، المظهر، أوقات المذاكرة، والإشعارات.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = AppStrings(state.languageCode);
    final profile = state.profile;
    final availability = profile?.availability ?? const StudyAvailability();

    return Scaffold(
      appBar: AppBar(title: Text(s.get('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionHeader(s.get('profile')),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(profile?.name ?? s.get('none')),
              subtitle: Text(profile?.schoolName ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
              ),
            ),
          ),

          SectionHeader(s.get('language')),
          Card(
            child: RadioGroup<String>(
              groupValue: state.languageCode,
              onChanged: (value) {
                if (value != null) state.setLanguage(value);
              },
              child: const Column(
                children: [
                  RadioListTile<String>(
                    value: 'ar',
                    title: Text('العربية'),
                  ),
                  RadioListTile<String>(
                    value: 'en',
                    title: Text('English'),
                  ),
                ],
              ),
            ),
          ),

          SectionHeader(s.get('theme')),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: state.themeMode,
              onChanged: (value) {
                if (value != null) state.setThemeMode(value);
              },
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(_themeLabel(mode, s)),
                    ),
                ],
              ),
            ),
          ),

          SectionHeader(s.get('study_availability')),
          Card(
            child: Column(
              children: [
                _TimeTile(
                  label: s.get('sleep_time'),
                  minutes: availability.sleepStartMinutes,
                  onChanged: (value) => _updateAvailability(
                    state,
                    availability.copyWith(sleepStartMinutes: value),
                  ),
                ),
                const Divider(height: 1),
                _TimeTile(
                  label: s.get('wake_time'),
                  minutes: availability.wakeUpMinutes,
                  onChanged: (value) => _updateAvailability(
                    state,
                    availability.copyWith(wakeUpMinutes: value),
                  ),
                ),
                const Divider(height: 1),
                _MinutesTile(
                  label: s.get('daily_break'),
                  minutes: availability.dailyBreakMinutes,
                  options: const [60, 90, 120, 150, 180, 240],
                  onChanged: (value) => _updateAvailability(
                    state,
                    availability.copyWith(dailyBreakMinutes: value),
                  ),
                ),
                const Divider(height: 1),
                _MinutesTile(
                  label: s.get('max_daily_study'),
                  minutes: availability.maxDailyStudyMinutes,
                  options: const [120, 180, 240, 300, 360, 420],
                  onChanged: (value) => _updateAvailability(
                    state,
                    availability.copyWith(maxDailyStudyMinutes: value),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'التطبيق بيحسب وقتك المتاح للمذاكرة تلقائيًا من جدول المدرسة '
              'والدروس، وبيطرح النوم والراحة. الأرقام دي بتظبط الحساب.',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),

          SectionHeader(s.get('notifications')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(
                NotificationService.instance.isReady
                    ? 'الإشعارات مفعّلة'
                    : 'تفعيل الإشعارات',
              ),
              subtitle: const Text('تذكير الدروس والمهام قبل موعدها'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final granted = await NotificationService.instance
                    .requestPermissions();
                if (!context.mounted) return;
                showSnack(
                  context,
                  granted
                      ? 'تم تفعيل الإشعارات'
                      : 'الإشعارات مرفوضة من إعدادات الجهاز',
                );
              },
            ),
          ),

          const SizedBox(height: 28),
          Card(
            child: ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'مسح كل البيانات',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                final ok = await confirmDelete(
                  context,
                  'ده هيمسح كل بياناتك من الجهاز. متأكد؟',
                );
                if (!ok || !context.mounted) return;
                await state.resetAllData();
                await NotificationService.instance.cancelAll();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _updateAvailability(AppState state, StudyAvailability availability) {
    final profile = state.profile;
    if (profile == null) return;
    state.saveProfile(profile.copyWith(availability: availability));
  }

  static String _themeLabel(ThemeMode mode, AppStrings s) {
    switch (mode) {
      case ThemeMode.system:
        return s.isArabic ? 'حسب النظام' : 'System';
      case ThemeMode.light:
        return s.isArabic ? 'فاتح' : 'Light';
      case ThemeMode.dark:
        return s.isArabic ? 'داكن' : 'Dark';
    }
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  const _TimeTile({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Text(
        TimeUtils.formatMinutes(minutes),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeUtils.fromMinutes(minutes),
        );
        if (picked != null) onChanged(TimeUtils.toMinutes(picked));
      },
    );
  }
}

class _MinutesTile extends StatelessWidget {
  final String label;
  final int minutes;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _MinutesTile({
    required this.label,
    required this.minutes,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<int>(
        value: options.contains(minutes) ? minutes : options.first,
        underline: const SizedBox.shrink(),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(_format(option))),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }

  static String _format(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '$hours ساعة';
    return '$hours:${rest.toString().padLeft(2, '0')} ساعة';
  }
}
