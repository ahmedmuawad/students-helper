import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/time_utils.dart';
import '../../models/student_profile.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../../state/auth_state.dart';
import '../auth/sign_in_screen.dart';
import '../common/ui_helpers.dart';
import '../guardian/link_code_screen.dart';
import '../guardian/link_requests_screen.dart';
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
          const _AccountCard(),
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
          SectionHeader('ولي الأمر'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: const Text('ولّد كود ربط'),
                  subtitle: const Text('عشان ولي أمرك يتابع مذاكرتك'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LinkCodeScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.family_restroom_outlined),
                  title: const Text('أولياء الأمور المرتبطين'),
                  subtitle: const Text('الطلبات والصلاحيات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LinkRequestsScreen()),
                  ),
                ),
              ],
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
                final granted =
                    await NotificationService.instance.requestPermissions();
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


/// بطاقة الحساب والمزامنة.
///
/// التطبيق شغّال من غير حساب، فالبطاقة دي بتوضّح الفرق: من غير حساب
/// البيانات على الجهاز ده بس، وبحساب بتتزامن وولي الأمر يقدر يتابع.
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('الحساب والمزامنة'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    user == null ? Icons.cloud_off_outlined : Icons.cloud_done,
                  ),
                ),
                title: Text(user?.label ?? 'من غير حساب'),
                subtitle: Text(
                  user == null
                      ? 'بياناتك على الجهاز ده بس'
                      : _syncLabel(auth),
                ),
                trailing: user == null ? const Icon(Icons.chevron_right) : null,
                onTap: user != null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const SignInScreen(allowSkip: false),
                          ),
                        ),
              ),
              if (user != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: auth.isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  title: const Text('زامن دلوقتي'),
                  subtitle: auth.pendingCount > 0
                      ? Text('${auth.pendingCount} تعديل مستني')
                      : null,
                  onTap: () async {
                    final result = await context.read<AuthState>().syncNow();
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      result.offline
                          ? 'مفيش نت — هنزامن أول ما يرجع'
                          : result.ok
                              ? 'تمت المزامنة'
                              : result.error ?? 'المزامنة ما تمّتش',
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('تسجيل خروج'),
                  subtitle: const Text('بياناتك على الجهاز بتفضل زي ما هي'),
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _syncLabel(AuthState auth) {
    if (auth.pendingCount > 0) {
      return '${auth.pendingCount} تعديل لسه ما اتزامنش';
    }
    final at = auth.lastSyncAt;
    if (at == null) return 'متزامن';
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'اتزامن دلوقتي';
    if (ago.inHours < 1) return 'اتزامن من ${ago.inMinutes} دقيقة';
    if (ago.inDays < 1) return 'اتزامن من ${ago.inHours} ساعة';
    return 'اتزامن من ${ago.inDays} يوم';
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل خروج'),
        content: const Text(
          'بياناتك اللي على الجهاز هتفضل زي ما هي، والمزامنة هتقف لحد ما '
          'تسجّل دخول تاني.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('اخرج'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthState>().signOut();
    }
  }
}
