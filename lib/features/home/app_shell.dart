import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../state/app_state.dart';
import '../books/library_screen.dart';
import '../calculator/calculator_screen.dart';
import '../lessons/lessons_screen.dart';
import '../tasks/tasks_screen.dart';
import '../timetable/timetable_screen.dart';
import 'home_screen.dart';

/// الهيكل الرئيسي بشريط تنقل سفلي.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// تنقّل لتبويب معيّن من أي شاشة جوّه الهيكل (اختصارات الشاشة الرئيسية).
  static void goToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_AppShellState>()?.selectTab(index);
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  static const List<Widget> _screens = [
    HomeScreen(),
    TimetableScreen(),
    LessonsScreen(),
    TasksScreen(),
    LibraryScreen(),
    CalculatorScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(context.watch<AppState>().languageCode);

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: s.get('nav_home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_view_week_outlined),
            selectedIcon: const Icon(Icons.calendar_view_week),
            label: s.get('nav_timetable'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: s.get('nav_lessons'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            label: s.get('nav_tasks'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: s.get('nav_library'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calculate_outlined),
            selectedIcon: const Icon(Icons.calculate),
            label: s.get('nav_calculator'),
          ),
        ],
      ),
    );
  }
}
