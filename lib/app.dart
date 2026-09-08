import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/home/app_shell.dart';
import 'features/guardian/children_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'models/account.dart';
import 'state/app_state.dart';

class StudentsHelperApp extends StatelessWidget {
  const StudentsHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final locale = Locale(state.languageCode);

    return MaterialApp(
      title: AppStrings(state.languageCode).get('app_name'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: state.themeMode,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _homeFor(state),
    );
  }

  /// الشاشة الأولى حسب حالة المستخدم ودوره.
  Widget _homeFor(AppState state) {
    if (!state.onboardingDone) return const WelcomeScreen();
    // ولي الأمر مالوش ملف دراسي — شاشته الرئيسية هي متابعة أبنائه.
    if (state.role == AccountRole.guardian) return const ChildrenScreen();
    if (state.profile == null) return const WelcomeScreen();
    return const AppShell();
  }
}

/// اختصار للوصول للنصوص من أي widget.
extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings(read<AppState>().languageCode);

  /// نص مترجم مباشرة: context.tr('save')
  String tr(String key) => AppStrings(watch<AppState>().languageCode).get(key);
}
