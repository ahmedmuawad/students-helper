import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/local_store.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/books_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';
import 'state/calculator_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();
  final api = ApiClient();
  final sync = SyncService(api, store);
  final books = BooksService(api, store);
  final appState = AppState(store, sync: sync);
  await appState.load();

  // الإشعارات اختيارية: لو الإعداد فشل التطبيق بيكمل شغل عادي من غيرها.
  await NotificationService.instance.initialize();

  // Firebase للهوية بس. لو ملف الإعدادات لسه مش موجود (google-services.json)
  // التطبيق بيفتح عادي أوفلاين بدل ما يقع على شاشة سودا — تسجيل الدخول
  // بس هو اللي بيتعطّل، والشاشة بتقول السبب.
  AuthService? auth;
  String? setupProblem;
  try {
    await Firebase.initializeApp();
    auth = AuthService(api);
    await auth.refreshToken();
  } on FirebaseException catch (error) {
    setupProblem = 'إعدادات Firebase ناقصة (${error.code}). راجع '
        'docs/FIREBASE.md.';
    debugPrint('Firebase مش متظبط: ${error.code} — ${error.message}');
  } catch (error) {
    setupProblem = 'ما قدرناش نشغّل تسجيل الدخول على الجهاز ده.';
    debugPrint('Firebase مش متظبط: $error');
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<SyncService>.value(value: sync),
        Provider<BooksService>.value(value: books),
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<AuthState>(
          create: (_) => AuthState(
            app: appState,
            auth: auth,
            setupProblem: setupProblem,
          ),
        ),
        ChangeNotifierProvider<CalculatorState>(
          create: (_) => CalculatorState(store)..load(),
        ),
      ],
      child: const StudentsHelperApp(),
    ),
  );
}
