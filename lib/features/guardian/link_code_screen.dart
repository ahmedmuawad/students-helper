import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_client.dart';
import '../../services/guardian_service.dart';
import '../common/ui_helpers.dart';

/// شاشة الطالب: يولّد كود ويدّيه لولي أمره.
class LinkCodeScreen extends StatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  State<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends State<LinkCodeScreen> {
  LinkCode? _code;
  bool _loading = false;
  String? _error;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = GuardianService(context.read<ApiClient>());
      final code = await service.generateCode();
      if (!mounted) return;
      setState(() => _code = code);
      _startCountdown();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// عدّاد تنازلي بيحدّث كل ثانية ويقف لما الكود ينتهي.
  void _startCountdown() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_code?.isExpired ?? true) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = _code;

    return Scaffold(
      appBar: AppBar(title: const Text('ربط ولي الأمر')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Icon(Icons.family_restroom, size: 42, color: scheme.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'اربط حسابك بولي أمرك',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ولّد كود وادّيه لوالدك أو والدتك. هما بيدخّلوه من حسابهم، '
                    'وانت اللي بتوافق وتحدد يشوفوا إيه بالظبط.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (code != null && !code.isExpired)
            _CodeCard(code: code)
          else ...[
            if (_error != null) ...[
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: scheme.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (code != null && code.isExpired) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_off_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'الكود انتهت صلاحيته — ولّد كود جديد',
                          style: TextStyle(color: scheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.vpn_key_outlined),
              label: Text(code == null ? 'ولّد كود الربط' : 'ولّد كود جديد'),
            ),
          ],
          const SizedBox(height: 26),
          const _HowItWorks(),
        ],
      ),
    );
  }
}

/// كارت عرض الكود مع العدّاد التنازلي.
class _CodeCard extends StatelessWidget {
  final LinkCode code;

  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = code.remaining;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;

    // بيتحوّل أحمر في آخر دقيقة كتنبيه بصري.
    final isUrgent = remaining.inSeconds < 60;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
        child: Column(
          children: [
            Text(
              'الكود',
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            SelectableText(
              code.formatted,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 14),
            Pill(
              'صالح لمدة $minutes:${seconds.toString().padLeft(2, '0')}',
              color: isUrgent ? AppTheme.danger : AppTheme.accent,
              icon: Icons.timer_outlined,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code.code));
                      if (context.mounted) showSnack(context, 'الكود اتنسخ');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('نسخ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _share(context, code.code),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('إرسال'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// مشاركة الكود عبر تطبيقات الجهاز (واتساب مثلاً).
  static void _share(BuildContext context, String code) {
    final text = 'كود ربط حسابي في تطبيق مساعد الطالب: $code\n'
        '(صالح لمدة ربع ساعة)';
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, 'الرسالة اتنسخت — ابعتها لولي أمرك');
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const List<({String title, String detail})> _steps = [
    (title: 'ولّد الكود', detail: 'الكود بيفضل صالح ربع ساعة بس'),
    (title: 'ابعته لولي أمرك', detail: 'واتساب أو شفهي — زي ما تحب'),
    (title: 'هو يدخّله من حسابه', detail: 'من شاشة "ربط بطالب"'),
    (title: 'انت توافق', detail: 'وتحدد يشوف إيه، وتقدر تفك الربط أي وقت'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('إزاي بيشتغل'),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i].title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _steps[i].detail,
                        style: TextStyle(fontSize: 12.5, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
