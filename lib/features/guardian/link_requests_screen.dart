import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/time_utils.dart';
import '../../models/account.dart';
import '../../services/api_client.dart';
import '../../services/guardian_service.dart';
import '../common/ui_helpers.dart';

/// شاشة الطالب: طلبات الربط والروابط المفعّلة.
///
/// الطالب هو صاحب القرار — بيوافق أو يرفض، وبيحدد ولي الأمر يشوف إيه
/// بالظبط، وبيقدر يفك الربط في أي وقت.
class LinkRequestsScreen extends StatefulWidget {
  const LinkRequestsScreen({super.key});

  @override
  State<LinkRequestsScreen> createState() => _LinkRequestsScreenState();
}

class _LinkRequestsScreenState extends State<LinkRequestsScreen> {
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
      final service = GuardianService(context.read<ApiClient>());
      final links = await service.myLinks();
      if (!mounted) return;
      setState(() => _links = links);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(GuardianLinkSummary link, bool accept) async {
    GuardianPermissions? permissions;

    if (accept) {
      // الموافقة مش زر واحد — الطالب بيحدد الصلاحيات الأول.
      permissions = await showModalBottomSheet<GuardianPermissions>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PermissionsSheet(guardianName: link.guardianName),
      );
      if (permissions == null || !mounted) return;
    }

    try {
      final service = GuardianService(context.read<ApiClient>());
      await service.respond(
        linkId: link.id,
        accept: accept,
        permissions: permissions,
      );
      if (!mounted) return;
      showSnack(context, accept ? 'تم الربط' : 'تم رفض الطلب');
      await _load();
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message);
    }
  }

  Future<void> _revoke(GuardianLinkSummary link) async {
    final confirmed = await confirmDelete(
      context,
      'تفك الربط مع ${link.guardianName}؟ مش هيقدر يشوف بياناتك تاني.',
    );
    if (!confirmed || !mounted) return;

    try {
      await GuardianService(context.read<ApiClient>()).revoke(link.id);
      if (!mounted) return;
      showSnack(context, 'تم فك الربط');
      await _load();
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _links.where((l) => l.isPending).toList();
    final active = _links.where((l) => l.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('أولياء الأمور'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_error != null) _ErrorCard(message: _error!),
                  if (pending.isNotEmpty) ...[
                    SectionHeader('طلبات في انتظار ردّك (${pending.length})'),
                    for (final link in pending)
                      _PendingCard(
                        link: link,
                        onAccept: () => _respond(link, true),
                        onReject: () => _respond(link, false),
                      ),
                  ],
                  if (active.isNotEmpty) ...[
                    SectionHeader('مرتبطين بحسابك (${active.length})'),
                    for (final link in active)
                      _ActiveCard(link: link, onRevoke: () => _revoke(link)),
                  ],
                  if (_error == null && pending.isEmpty && active.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: EmptyState(
                        icon: Icons.family_restroom_outlined,
                        message: 'مفيش أولياء أمور مرتبطين بحسابك',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final GuardianLinkSummary link;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _PendingCard({
    required this.link,
    required this.onAccept,
    required this.onReject,
  });

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
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                    child: const Icon(Icons.person_add_alt,
                        color: AppTheme.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.guardianName.isEmpty
                              ? 'ولي أمر'
                              : link.guardianName,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${_relationLabel(link.relation)} · '
                          '${TimeUtils.relativeDayLabel(link.createdAt)}',
                          style:
                              TextStyle(fontSize: 12.5, color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                        foregroundColor: scheme.error,
                      ),
                      child: const Text('رفض'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                      ),
                      child: const Text('موافقة'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final GuardianLinkSummary link;
  final VoidCallback onRevoke;

  const _ActiveCard({required this.link, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.success.withValues(alpha: 0.15),
            child: const Icon(Icons.verified_user_outlined,
                color: AppTheme.success, size: 20),
          ),
          title: Text(
            link.guardianName.isEmpty ? 'ولي أمر' : link.guardianName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            _relationLabel(link.relation),
            style: TextStyle(fontSize: 12.5, color: scheme.outline),
          ),
          trailing: TextButton(
            onPressed: onRevoke,
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('فك الربط'),
          ),
        ),
      ),
    );
  }
}

/// ورقة اختيار الصلاحيات قبل الموافقة.
class _PermissionsSheet extends StatefulWidget {
  final String guardianName;

  const _PermissionsSheet({required this.guardianName});

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  GuardianPermissions _permissions = const GuardianPermissions();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.guardianName} هيشوف إيه؟',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'انت اللي بتحدد. تقدر تغيّرها أو تفك الربط في أي وقت.',
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _toggle(
                        'جدول الحصص',
                        Icons.calendar_view_week,
                        _permissions.viewTimetable,
                        (v) => _permissions =
                            _permissions.copyWith(viewTimetable: v)),
                    _toggle(
                        'الدروس الخصوصية',
                        Icons.school_outlined,
                        _permissions.viewLessons,
                        (v) => _permissions =
                            _permissions.copyWith(viewLessons: v)),
                    _toggle(
                        'المهام والواجبات',
                        Icons.checklist,
                        _permissions.viewTasks,
                        (v) =>
                            _permissions = _permissions.copyWith(viewTasks: v)),
                    _toggle(
                        'الدرجات',
                        Icons.grade_outlined,
                        _permissions.viewGrades,
                        (v) => _permissions =
                            _permissions.copyWith(viewGrades: v)),
                    _toggle(
                        'الحضور والغياب',
                        Icons.event_available,
                        _permissions.viewAttendance,
                        (v) => _permissions =
                            _permissions.copyWith(viewAttendance: v)),
                    _toggle(
                        'إحصائيات المذاكرة',
                        Icons.timer_outlined,
                        _permissions.viewStudyStats,
                        (v) => _permissions =
                            _permissions.copyWith(viewStudyStats: v)),
                    _toggle(
                        'مصاريف الدروس',
                        Icons.payments_outlined,
                        _permissions.viewLessonCosts,
                        (v) => _permissions =
                            _permissions.copyWith(viewLessonCosts: v)),
                    const Divider(height: 24),
                    _toggle(
                        'يستقبل تنبيه لو مهمة اتأخرت',
                        Icons.notifications_outlined,
                        _permissions.receiveAlerts,
                        (v) => _permissions =
                            _permissions.copyWith(receiveAlerts: v)),
                    _toggle(
                        'يقدر يضيفلك مهام',
                        Icons.add_task,
                        _permissions.canAssignTasks,
                        (v) => _permissions =
                            _permissions.copyWith(canAssignTasks: v)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, _permissions),
              child: const Text('موافقة وربط الحساب'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(
    String label,
    IconData icon,
    bool value,
    void Function(bool) apply,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: (next) => setState(() => apply(next)),
    );
  }
}

String _relationLabel(GuardianRelation relation) {
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
      return 'صلة أخرى';
  }
}
