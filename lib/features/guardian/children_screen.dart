import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../services/api_client.dart';
import '../../services/guardian_service.dart';
import '../common/ui_helpers.dart';
import 'enter_code_screen.dart';

/// الشاشة الرئيسية لولي الأمر: أبناؤه المرتبطين.
class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
  List<GuardianLinkSummary> _links = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await GuardianService(context.read<ApiClient>()).myLinks();
      if (!mounted) return;
      setState(() => _links = links);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addChild() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EnterCodeScreen()),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _links.where((l) => l.isActive).toList();
    final pending = _links.where((l) => l.isPending).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('أبنائي'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                children: [
                  if (_error != null)
                    Card(
                      color: scheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off,
                                color: scheme.onErrorContainer),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (pending.isNotEmpty) ...[
                    SectionHeader('في انتظار الموافقة (${pending.length})'),
                    for (final link in pending)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppTheme.accent.withValues(alpha: 0.15),
                              child: const Icon(Icons.hourglass_top,
                                  color: AppTheme.accent, size: 20),
                            ),
                            title: Text(
                              link.studentName.isEmpty
                                  ? 'طالب'
                                  : link.studentName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              'اتبعت ${TimeUtils.relativeDayLabel(link.createdAt)}'
                              ' — مستني موافقته',
                              style: TextStyle(
                                  fontSize: 12.5, color: scheme.outline),
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (active.isNotEmpty) ...[
                    SectionHeader('متابعة (${active.length})'),
                    for (final link in active) _ChildCard(link: link),
                  ],
                  if (_error == null && _links.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 50),
                      child: EmptyState(
                        icon: Icons.family_restroom_outlined,
                        message: 'مفيش أبناء مرتبطين بحسابك لسه.\n'
                            'اطلب من ابنك يولّد كود ربط من تطبيقه.',
                        actionLabel: 'إضافة ابن',
                        onAction: _addChild,
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: _links.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addChild,
              icon: const Icon(Icons.add),
              label: const Text('إضافة ابن'),
            ),
    );
  }
}

/// كارت الابن — ملخص سريع وبوابة لتفاصيله.
class _ChildCard extends StatelessWidget {
  final GuardianLinkSummary link;

  const _ChildCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      link.studentName.isEmpty
                          ? '؟'
                          : link.studentName.characters.first,
                      style: TextStyle(
                        fontSize: 18,
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
                          link.studentName.isEmpty ? 'طالب' : link.studentName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Pill('مرتبط',
                            color: AppTheme.success,
                            icon: Icons.verified_user_outlined),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'الصلاحيات اللي وافق عليها بتحدد اللي بتشوفه هنا. '
                'لو محتاج تشوف حاجة زيادة، اطلب منه يفعّلها من تطبيقه.',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
