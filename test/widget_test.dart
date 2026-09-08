import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:students_helper/app.dart';
import 'package:students_helper/data/local_store.dart';
import 'package:students_helper/services/api_client.dart';
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
      Provider<ApiClient>(create: (_) => ApiClient()),
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<CalculatorState>(
        create: (_) => CalculatorState(store),
      ),
    ],
    child: const StudentsHelperApp(),
  );
}

/// حالة مستخدم أنهى التهيئة بالفعل.
Map<String, Object> onboardedStudent() => {
      'onboarding_done': true,
      'account_role': 'student',
      'profile': '{"id":"s1","name":"أحمد","gradeLevel":7,'
          '"educationSystem":"egyptGeneral","schoolLanguage":"arabic",'
          '"currentTerm":"first","countryCode":"EG","schoolName":"مدرسة"}',
    };

void main() {
  group('التهيئة', () {
    testWidgets('يفتح على شاشة الترحيب باختيار الدور', (tester) async {
      await tester.pumpWidget(await buildApp({}));
      await tester.pumpAndSettle();

      expect(find.text('دراستك كلها في مكان واحد'), findsOneWidget);
      expect(find.text('أنا طالب'), findsOneWidget);
      expect(find.text('أنا ولي أمر'), findsOneWidget);
    });

    testWidgets('اختيار "طالب" يوصّل لشاشة الخصوصية', (tester) async {
      await tester.pumpWidget(await buildApp({}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('أنا طالب'));
      await tester.pumpAndSettle();

      expect(find.text('الخصوصية والبيانات'), findsOneWidget);
      expect(find.text('موافق، كمّل'), findsOneWidget);

      // مفتاح الإعلانات تحت حدود شاشة الاختبار، فبنمرّر له.
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('إعلانات مخصّصة'), findsOneWidget);
    });

    testWidgets('الخصوصية توصّل لبيانات الطالب', (tester) async {
      await tester.pumpWidget(await buildApp({}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('أنا طالب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('موافق، كمّل'));
      await tester.pumpAndSettle();

      expect(find.text('اسم الطالب'), findsOneWidget);
      expect(find.text('الصف الدراسي'), findsOneWidget);
    });

    testWidgets('ولي الأمر يروح لشاشة إدخال كود الربط', (tester) async {
      await tester.pumpWidget(await buildApp({}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('أنا ولي أمر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('موافق، كمّل'));
      await tester.pumpAndSettle();

      expect(find.text('ربط بطالب'), findsOneWidget);
      expect(find.text('اكتب الكود اللي ابنك أو بنتك ولّدوه'), findsOneWidget);
    });
  });

  group('الملف الشخصي', () {
    testWidgets('كل حقول البيانات موجودة', (tester) async {
      await tester.pumpWidget(await buildApp({}));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أنا طالب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('موافق، كمّل'));
      await tester.pumpAndSettle();

      expect(find.text('تاريخ الميلاد'), findsOneWidget);
      expect(find.text('الدولة'), findsOneWidget);
      expect(find.text('المدرسة'), findsOneWidget);
      expect(find.text('النظام التعليمي'), findsOneWidget);

      // باقي الحقول تحت حدود الشاشة، فبنمرّر لها.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('عربي'), findsOneWidget);
      expect(find.text('لغات'), findsOneWidget);
      expect(find.text('الترم الأول'), findsOneWidget);
    });
  });

  group('اللغة والاتجاه', () {
    testWidgets('الاتجاه من اليمين للشمال في العربية', (tester) async {
      await tester.pumpWidget(await buildApp({}));
      await tester.pumpAndSettle();

      final direction = Directionality.of(
        tester.element(find.text('أنا طالب')),
      );
      expect(direction, TextDirection.rtl);
    });

    testWidgets('التبديل للإنجليزية بيغيّر الاتجاه', (tester) async {
      await tester.pumpWidget(await buildApp({'language_code': 'en'}));
      await tester.pumpAndSettle();

      final direction = Directionality.of(
        tester.element(find.text('أنا طالب')),
      );
      expect(direction, TextDirection.ltr);
    });
  });

  group('الشاشة الرئيسية', () {
    testWidgets('الطالب اللي خلّص التهيئة بيروح للتطبيق', (tester) async {
      await tester.pumpWidget(await buildApp(onboardedStudent()));
      await tester.pumpAndSettle();

      // شريط التنقل موجود بتبويباته. بعض الأسماء بتتكرر في اختصارات
      // الشاشة الرئيسية كمان، فبنتأكد إنها موجودة مرة على الأقل.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('الرئيسية'), findsAtLeastNWidgets(1));
      expect(find.text('الجدول'), findsAtLeastNWidgets(1));
      expect(find.text('الحاسبة'), findsAtLeastNWidgets(1));
    });

    testWidgets('ولي الأمر بيروح لشاشة أبنائه', (tester) async {
      await tester.pumpWidget(await buildApp({
        'onboarding_done': true,
        'account_role': 'guardian',
      }));
      await tester.pump();

      expect(find.text('أبنائي'), findsOneWidget);
    });
  });
}
