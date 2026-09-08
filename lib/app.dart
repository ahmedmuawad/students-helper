import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/home/app_shell.dart';
import 'features/onboarding/profile_setup_screen.dart';
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
      home: state.onboardingDone && state.profile != null
          ? const AppShell()
          : const ProfileSetupScreen(),
    );
  }
}

/// اختصار للوصول للنصوص من أي widget.
extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings(read<AppState>().languageCode);

  /// نص مترجم مباشرة: context.tr('save')
  String tr(String key) => AppStrings(watch<AppState>().languageCode).get(key);
}
