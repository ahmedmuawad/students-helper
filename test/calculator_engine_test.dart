import 'package:flutter_test/flutter_test.dart';
import 'package:students_helper/calc/calculator_engine.dart';
import 'package:students_helper/calc/eval_context.dart';

/// يتأكد إن التعبير بيطلع النتيجة المتوقعة بالظبط بعد التنسيق.
void expectCalc(CalculatorEngine engine, String expression, String expected) {
  final result = engine.evaluate(expression, recordHistory: false);
  expect(result.display, expected, reason: 'التعبير: $expression');
}

void main() {
  test('محرك الآلة الحاسبة يطابق سلوك الكاسيو', () {
    final e = CalculatorEngine();

    // --- أساسيات وأولويات ---
    expectCalc(e, '2+3*4', '14');
    expectCalc(e, '(2+3)*4', '20');
    expectCalc(e, '2^3^2', '512'); // يمين لليسار
    expectCalc(e, '-2^2', '-4'); // السالب الأحادي أضعف من الأس
    expectCalc(e, '2^-1', '0.5');
    expectCalc(e, '10-2-3', '5');
    expectCalc(e, '100/4/5', '5');

    // --- سلوك الكاسيو: الضرب الضمني أقوى من القسمة ---
    expectCalc(e, '1/2pi', '0.1591549431');
    expectCalc(e, '6/2(1+2)', '1');
    expectCalc(e, '2pi', '6.283185307');

    // --- مثلثات بالدرجات ---
    expectCalc(e, 'sin(30)', '0.5');
    expectCalc(e, 'cos(60)', '0.5');
    expectCalc(e, 'sin(180)', '0'); // تنظيف خطأ الفاصلة العائمة
    expectCalc(e, 'tan(45)', '1');
    expectCalc(e, 'asin(0.5)', '30');
    expectCalc(e, 'sin30', '0.5'); // بدون أقواس زي الكاسيو
    expectCalc(e, '2sin(30)', '1');

    // --- راديان ---
    e.angleMode = AngleMode.radian;
    expectCalc(e, 'sin(pi/2)', '1');
    expectCalc(e, 'cos(0)', '1');
    e.angleMode = AngleMode.degree;

    // --- جذور ولوغاريتمات ---
    expectCalc(e, 'sqrt(9)', '3');
    expectCalc(e, '√9', '3');
    expectCalc(e, '√9+1', '4'); // الجذر ياخد المعامل التالي فقط
    expectCalc(e, '∛27', '3');
    expectCalc(e, 'root(4,16)', '2');
    expectCalc(e, 'log(100)', '2');
    expectCalc(e, 'ln(e)', '1');
    expectCalc(e, 'log(2,8)', '3');
    expectCalc(e, 'exp(0)', '1');

    // --- عوامل لاحقة ---
    expectCalc(e, '5!', '120');
    expectCalc(e, '2^3!', '64'); // ! أقوى من ^
    expectCalc(e, '5²', '25');
    expectCalc(e, '3³', '27');
    expectCalc(e, '50%', '0.5');

    // --- احتمالات ---
    expectCalc(e, '5nPr3', '60'); // صيغة العامل زي الكاسيو
    expectCalc(e, 'nPr(5,3)', '60'); // صيغة الدالة
    expectCalc(e, '5nCr3', '10');
    expectCalc(e, 'nCr(10,5)', '252');
    expectCalc(e, '10nCr0', '1');

    // --- تحليل عددي (اللي في صورة الكاسيو) ---
    expectCalc(e, 'integrate(X^2,0,3)', '9'); // مش متأثرة بوضع الزوايا
    expectCalc(e, 'derivative(X^2,3)', '6');
    expectCalc(e, 'Σ(X,1,100)', '5050');
    expectCalc(e, 'Σ(X^2,1,10)', '385');

    // الدوال المثلثية داخل التكامل/التفاضل تحتاج وضع RAD — نفس سلوك الكاسيو.
    e.angleMode = AngleMode.radian;
    expectCalc(e, '∫(cos(X),0,pi/2)', '1'); // التكامل في الصورة المرفقة = 1
    expectCalc(e, 'derivative(sin(X),0)', '1');
    e.angleMode = AngleMode.degree;
    // في وضع DEG نفس التكامل بيدي نتيجة مختلفة (وده صحيح رياضيًا)
    expectCalc(e, '∫(cos(X),0,pi/2)', '1.570599562');

    // --- إحصاء ---
    expectCalc(e, 'mean(2,4,6,8)', '5');
    expectCalc(e, 'median(1,3,5,7)', '4');
    expectCalc(e, 'max(3,9,2)', '9');
    expectCalc(e, 'gcd(12,18)', '6');
    expectCalc(e, 'lcm(4,6)', '12');
    expectCalc(e, 'mod(17,5)', '2');

    // --- متغيرات وذاكرة ---
    e.store('A', 7);
    expectCalc(e, 'A*2', '14');
    expectCalc(e, '2+3', '5');
    expectCalc(e, 'Ans*10', '50'); // Ans من العملية السابقة

    // --- أخطاء متوقعة ---
    expectCalc(e, '1/0', 'Math ERROR');
    expectCalc(e, 'sqrt(-4)', 'Math ERROR');
    expectCalc(e, '(-1)!', 'Math ERROR');
    expectCalc(e, 'log(0)', 'Math ERROR');
    expectCalc(e, '2+*3', 'Syntax ERROR');
    expectCalc(e, 'tan(90)', 'Math ERROR');

    // --- إصلاح الأقواس الناقصة والأرقام العربية ---
    expectCalc(e, 'sin(30', '0.5');
    expectCalc(e, '٢+٣', '5');

    // --- أعداد كبيرة/صغيرة ---
    expectCalc(e, '2^100', '1.267650600×10³⁰');
    expectCalc(e, '1/3', '0.3333333333');
  });
}
