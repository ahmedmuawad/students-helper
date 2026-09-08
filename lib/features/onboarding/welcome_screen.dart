import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../state/app_state.dart';
import 'privacy_screen.dart';

/// أول شاشة: القيمة ثم اختيار الدور.
///
/// الترتيب مقصود — الطالب بيشوف التطبيق بيعمل إيه قبل ما نطلب منه أي بيانات،
/// وإنشاء الحساب متأخّر لآخر خطوة عشان ما يهربش من أول شاشة.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              // تبديل اللغة متاح من أول لحظة
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => state
                      .setLanguage(state.languageCode == 'ar' ? 'en' : 'ar'),
                  child:
                      Text(state.languageCode == 'ar' ? 'English' : 'العربية'),
                ),
              ),

              const Spacer(flex: 2),

              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.school, size: 44, color: scheme.primary),
              ),
              const SizedBox(height: 22),

              const Text(
                'دراستك كلها في مكان واحد',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'الحصص والدروس والمهام والامتحانات — منظّمين ومعاك تذكير '
                'قبل كل حاجة. الإعداد بياخد دقيقتين.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14.5, color: scheme.outline, height: 1.6),
              ),

              const Spacer(flex: 2),

              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'مين اللي هيستخدم التطبيق؟',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              _RoleCard(
                icon: Icons.school_outlined,
                title: 'أنا طالب',
                subtitle: 'جدولي ومهامي وامتحاناتي في مكان واحد',
                highlighted: true,
                onTap: () => _continue(context, AccountRole.student),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.family_restroom_outlined,
                title: 'أنا ولي أمر',
                subtitle: 'أتابع ابني وأشوف مستواه أول بأول',
                highlighted: false,
                onTap: () => _continue(context, AccountRole.guardian),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _continue(BuildContext context, AccountRole role) {
    context.read<AppState>().setRole(role);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PrivacyScreen(role: role)),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = highlighted ? scheme.primary : scheme.surface;
    final foreground = highlighted ? scheme.onPrimary : scheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: foreground, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left,
                  color: foreground.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
