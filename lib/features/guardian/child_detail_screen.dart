import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_utils.dart';
import '../../models/study_task.dart';
import '../../services/api_client.dart';
import '../../services/child_service.dart';
import '../common/ui_helpers.dart';

/// متابعة ولي الأمر لابنه.
///
/// كل تبويب بيظهر بس لو الطالب سمح بيه — والفلترة على السيرفر أصلاً،
/// فالتطبيق مش بيستلم اللي مش مسموح ليه أساسًا.
class ChildDetailScreen extends StatefulWidget {
  final LinkedChild child;

  const ChildDetailScreen({super.key, required this.child});

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  ChildData _data = const ChildData();
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
      final data =
          await ChildService(context.read<ApiClient>()).dataFor(widget.child.studentId);
      if (!mounted) return;
      setState(() => _data = data);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Tab> get _tabs {
    final child = widget.child;
    return [
      if (child.canSeeTasks)
        _Tab('المهام', Icons.checklist, (_) => _tasksView()),
      if (child.canSeeTimetable)
        _Tab('الجدول', Icons.calendar_view_week, (_) => _timetableView()),
      if (child.canSeeLessons)
        _Tab('الدروس', Icons.school_outlined, (_) => _lessonsView()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.child.name)),
        body: const EmptyState(
          icon: Icons.lock_outline,
          message: 'ابنك ما سمحش بمتابعة أي حاجة لسه.\n'
              'اطلب منه يفتح الصلاحيات من إعدادات التطبيق.',
        ),
      );
    }

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.child.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
          bottom: TabBar(
            tabs: [
              for (final tab in tabs) Tab(icon: Icon(tab.icon), text: tab.label),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyState(icon: Icons.cloud_off, message: _error!)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: TabBarView(
                      children: [
                        for (final tab in tabs) tab.build(context),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ----- المهام -----

  Widget _tasksView() {
    final overdue = _data.overdueTasks;
    final pending =
        _data.pendingTasks.where((t) => !t.isOverdue).toList(growable: false);
    final done = _data.tasks.where((t) => t.isDone).toList(growable: false);

    if (_data.tasks.isEmpty) {
      return _emptyList('مفيش مهام مسجّلة');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _Summary(
          items: [
            ('متأخرة', overdue.length, Colors.red),
            ('لسه', pending.length, Colors.orange),
            ('خلصت', done.length, Colors.green),
          ],
        ),
        if (overdue.isNotEmpty) ...[
          const _GroupTitle('متأخرة'),
          for (final task in overdue) _TaskTile(task: task, late: true),
        ],
        if (pending.isNotEmpty) ...[
          const _GroupTitle('لسه مخلصتش'),
          for (final task in pending) _TaskTile(task: task),
        ],
        if (done.isNotEmpty) ...[
          const _GroupTitle('خلصت'),
          for (final task in done) _TaskTile(task: task),
        ],
      ],
    );
  }

  // ----- الجدول -----

  Widget _timetableView() {
    if (_data.periods.isEmpty) return _emptyList('الجدول لسه مش متسجّل');

    final byDay = <int, List<dynamic>>{};
    for (final period in _data.periods) {
      byDay.putIfAbsent(period.weekday, () => []).add(period);
    }
    final days = byDay.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final day in days) ...[
          _GroupTitle(TimeUtils.weekdayName(day)),
          for (final period in byDay[day]!)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  child: Text('${period.periodNumber}'),
                ),
                title: Text(period.subjectId),
                subtitle: Text(
                  '${TimeUtils.formatMinutes(period.startMinutes)}'
                  ' – ${TimeUtils.formatMinutes(period.endMinutes)}'
                  '${period.room.isEmpty ? '' : ' · ${period.room}'}',
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ----- الدروس -----

  Widget _lessonsView() {
    if (_data.lessons.isEmpty) return _emptyList('مفيش دروس خصوصية مسجّلة');

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        for (final lesson in _data.lessons)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(
                lesson.teacherName.isEmpty ? 'درس' : lesson.teacherName,
              ),
              subtitle: Text(
                '${TimeUtils.weekdayName(lesson.weekday)} · '
                '${TimeUtils.formatMinutes(lesson.startMinutes)}'
                ' – ${TimeUtils.formatMinutes(lesson.endMinutes)}'
                '${lesson.place.isEmpty ? '' : '\n${lesson.place}'}',
              ),
              isThreeLine: lesson.place.isNotEmpty,
              // المصاريف بتوصل بس لو الطالب سمح — لو مقفولة السيرفر
              // بيشيلها من الرد أصلاً فبتوصل صفر.
              trailing: widget.child.canSeeCosts && lesson.cost > 0
                  ? Text(
                      '${lesson.cost.toStringAsFixed(0)} ج',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _emptyList(String message) => ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(icon: Icons.inbox_outlined, message: message),
        ],
      );
}

class _Tab {
  final String label;
  final IconData icon;
  final Widget Function(BuildContext) _builder;

  const _Tab(this.label, this.icon, this._builder);

  Widget build(BuildContext context) => _builder(context);
}

class _GroupTitle extends StatelessWidget {
  final String text;

  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      );
}

class _Summary extends StatelessWidget {
  final List<(String, int, Color)> items;

  const _Summary({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (label, count, color) in items)
          Expanded(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  final StudyTask task;
  final bool late;

  const _TaskTile({required this.task, this.late = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(
          task.isDone
              ? Icons.check_circle
              : late
                  ? Icons.error_outline
                  : Icons.radio_button_unchecked,
          color: task.isDone
              ? Colors.green
              : late
                  ? scheme.error
                  : scheme.outline,
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontSize: 14,
            decoration: task.isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: task.dueDate == null
            ? null
            : Text(TimeUtils.relativeDayLabel(task.dueDate!)),
      ),
    );
  }
}
