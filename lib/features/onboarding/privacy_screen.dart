import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../state/app_state.dart';
import '../guardian/enter_code_screen.dart';
import 'profile_setup_screen.dart';

/// شاشة الخصوصية والإعلانات.
///
/// بنشرح صراحة إيه اللي بنجمعه وليه — ده مطلوب قانونيًا (موافقة المستخدم)
/// وكمان بيخلي الطالب مايزعلش من الإعلانات لما يفهم إنها اللي بتخلّي
/// التطبيق مجاني.
class PrivacyScreen extends StatefulWidget {
  final AccountRole role;

  const PrivacyScreen({super.key, required this.role});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _allowPersonalizedAds = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الخصوصية والبيانات')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  Text(
                    'إحنا بنوضّح بالظبط بنجمع إيه وليه — من غير لف ودوران.',
                    style: TextStyle(
                        fontSize: 14, color: scheme.outline, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  const _Section(
                    title: 'بياناتك الدراسية',
                    items: [
                      'جدولك ومهامك ودرجاتك بتتخزّن على جهازك',
                      'بتتزامن مع حسابك عشان تلاقيها لو غيّرت موبايل',
                      'محدش يشوفها غيرك — إلا لو انت وافقت على ربط ولي أمرك',
                    ],
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 20),
                  const _Section(
                    title: 'بيانات الاستخدام',
                    items: [
                      'إحصائيات مجهّلة عن الشاشات اللي بتتفتح، لتحسين التطبيق',
                      'معلومات الجهاز لحل مشاكل التوافق',
                    ],
                    icon: Icons.insights_outlined,
                  ),
                  const SizedBox(height: 20),
                  const _Section(
                    title: 'الإعلانات',
                    items: [
                      'الإعلانات هي اللي بتخلّي النسخة المجانية مجانية',
                      'مفيش إعلانات أثناء المذاكرة أو الامتحانات أو الحاسبة',
                      'تقدر تشيلها نهائيًا بالاشتراك في أي وقت',
                    ],
                    icon: Icons.campaign_outlined,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: SwitchListTile(
                      value: _allowPersonalizedAds,
                      onChanged: (value) =>
                          setState(() => _allowPersonalizedAds = value),
                      title: const Text(
                        'إعلانات مخصّصة',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'لو قفلتها هتشوف إعلانات عامة. '
                        'للطلاب تحت ١٣ سنة بتتقفل تلقائيًا.',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'إحنا مبنبيعش بياناتك الشخصية لأي حد.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: _continue,
                    child: const Text('موافق، كمّل'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تقدر تغيّر دي كلها من الإعدادات في أي وقت',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _continue() {
    context.read<AppState>().setPersonalizedAds(_allowPersonalizedAds);

    // ولي الأمر مالوش ملف دراسي — بيروح على طول لربط ابنه.
    final next = widget.role == AccountRole.guardian
        ? const EnterCodeScreen()
        : const ProfileSetupScreen();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => next),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;

  const _Section({
    required this.title,
    required this.items,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final item in items)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 27, bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                        fontSize: 13.5, color: scheme.onSurface, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
