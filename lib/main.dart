import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/local_store.dart';
import 'services/api_client.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'state/calculator_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();
  final appState = AppState(store);
  await appState.load();

  // الإشعارات اختيارية: لو الإعداد فشل التطبيق بيكمل شغل عادي من غيرها.
  await NotificationService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>(
          create: (_) => ApiClient(),
          dispose: (_, client) => client.dispose(),
        ),
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<CalculatorState>(
          create: (_) => CalculatorState(store)..load(),
        ),
      ],
      child: const StudentsHelperApp(),
    ),
  );
}
