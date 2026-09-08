import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../services/api_client.dart';
import '../../services/guardian_service.dart';
import '../common/ui_helpers.dart';

/// شاشة ولي الأمر: يدخّل الكود اللي أخده من ابنه.
class EnterCodeScreen extends StatefulWidget {
  const EnterCodeScreen({super.key});

  @override
  State<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends State<EnterCodeScreen> {
  final _code = TextEditingController();
  GuardianRelation _relation = GuardianRelation.father;
  bool _sending = false;
  String? _error;
  GuardianLinkSummary? _result;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (code.length < 4) {
      setState(() => _error = 'اكتب الكود كامل');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final service = GuardianService(context.read<ApiClient>());
      final link = await service.redeemCode(code: code, relation: _relation);
      if (!mounted) return;
      setState(() => _result = link);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_result != null) {
      return _SentScreen(link: _result!);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ربط بطالب')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Icon(Icons.qr_code_2, size: 46, color: scheme.primary),
          const SizedBox(height: 14),
          const Text(
            'اكتب الكود اللي ابنك أو بنتك ولّدوه',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'الكود بيظهر عندهم في: الإعدادات ← ربط ولي الأمر',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.outline),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            maxLength: 7,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              hintText: '000000',
              counterText: '',
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 17, color: scheme.error),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const SectionHeader('صلتك بالطالب'),
          Wrap(
            spacing: 8,
            children: [
              for (final relation in GuardianRelation.values)
                ChoiceChip(
                  label: Text(_relationLabel(relation)),
                  selected: _relation == relation,
                  onSelected: (_) => setState(() => _relation = relation),
                ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إرسال طلب الربط'),
          ),
          const SizedBox(height: 14),
          Text(
            'الطالب لازم يوافق على الطلب قبل ما تشوف أي بيانات.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  static String _relationLabel(GuardianRelation relation) {
    switch (relation) {
      case GuardianRelation.father:
        return 'الأب';
      case GuardianRelation.mother:
        return 'الأم';
      case GuardianRelation.brother:
        return 'أخ';
      case GuardianRelation.sister:
        return 'أخت';
      case GuardianRelation.other:
        return 'أخرى';
    }
  }
}

/// شاشة التأكيد بعد إرسال الطلب.
class _SentScreen extends StatelessWidget {
  final GuardianLinkSummary link;

  const _SentScreen({required this.link});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('تم إرسال الطلب')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_read_outlined,
                size: 60, color: scheme.primary),
            const SizedBox(height: 20),
            Text(
              'الطلب اتبعت لـ ${link.studentName}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'هيوصلك إشعار أول ما يوافق. لحد كده مش هتقدر تشوف أي بيانات.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: scheme.outline),
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تمام'),
            ),
          ],
        ),
      ),
    );
  }
}
