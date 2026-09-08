import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:students_helper/app.dart';
import 'package:students_helper/data/local_store.dart';
import 'package:students_helper/state/app_state.dart';
import 'package:students_helper/state/calculator_state.dart';

/// يبني التطبيق فوق تخزين محلي وهمي للاختبارات.
Future<Widget> buildApp(Map<String, Object> initialValues) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final store = await LocalStore.open();
  final appState = AppState(store);
  await appState.load();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<CalculatorState>(
        create: (_) => CalculatorState(store),
      ),
    ],
    child: const StudentsHelperApp(),
  );
}

void main() {
  testWidgets('يفتح على شاشة إنشاء الحساب لما مفيش ملف شخصي', (tester) async {
    await tester.pumpWidget(await buildApp({}));
    await tester.pumpAndSettle();

    expect(find.text('الملف الشخصي'), findsOneWidget);
    expect(find.text('اسم الطالب'), findsOneWidget);
    // الحقول الأساسية المطلوبة كلها موجودة
    expect(find.text('تاريخ الميلاد'), findsOneWidget);
    expect(find.text('الدولة'), findsOneWidget);
    expect(find.text('المدرسة'), findsOneWidget);
    expect(find.text('الصف الدراسي'), findsOneWidget);

    // القائمة بتبني العناصر الظاهرة بس، فلازم نمرّر لبقية الحقول.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('نوع المدرسة'), findsOneWidget);
    expect(find.text('عربي'), findsOneWidget);
    expect(find.text('لغات'), findsOneWidget);
    expect(find.text('دولية'), findsOneWidget);
    expect(find.text('الترم الأول'), findsOneWidget);
    expect(find.text('الترم الثاني'), findsOneWidget);
  });

  testWidgets('الواجهة بتتقلب للإنجليزية لما اللغة تتغيّر', (tester) async {
    await tester.pumpWidget(await buildApp({'language_code': 'en'}));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Student name'), findsOneWidget);
  });

  testWidgets('اتجاه الواجهة من اليمين للشمال في العربية', (tester) async {
    await tester.pumpWidget(await buildApp({}));
    await tester.pumpAndSettle();

    final direction = Directionality.of(
      tester.element(find.text('اسم الطالب')),
    );
    expect(direction, TextDirection.rtl);
  });
}
