import 'calc_error.dart';
import 'eval_context.dart';
import 'evaluator.dart';
import 'formatter.dart';
import 'parser.dart';

/// نتيجة عملية حسابية.
class CalcResult {
  final String expression;
  final double? value;
  final String display;
  final CalcError? error;

  const CalcResult({
    required this.expression,
    required this.display,
    this.value,
    this.error,
  });

  bool get isSuccess => error == null && value != null;
}

/// سجل عملية سابقة (شريط التاريخ في التطبيق).
class CalcHistoryEntry {
  final String expression;
  final String result;
  final DateTime at;

  const CalcHistoryEntry({
    required this.expression,
    required this.result,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'expression': expression,
        'result': result,
        'at': at.toIso8601String(),
      };

  factory CalcHistoryEntry.fromJson(Map<String, dynamic> json) =>
      CalcHistoryEntry(
        expression: json['expression'] as String? ?? '',
        result: json['result'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// واجهة الآلة الحاسبة: تحليل ➜ تقييم ➜ تنسيق، مع الذاكرة والتاريخ.
class CalculatorEngine {
  final EvalContext context;
  final List<CalcHistoryEntry> history = [];

  /// أقصى عدد عمليات محفوظة في التاريخ.
  static const int maxHistory = 100;

  CalculatorEngine({EvalContext? context}) : context = context ?? EvalContext();

  AngleMode get angleMode => context.angleMode;
  set angleMode(AngleMode mode) => context.angleMode = mode;

  NumberBase get numberBase => context.numberBase;
  set numberBase(NumberBase base) => context.numberBase = base;

  /// حساب تعبير نصي وإرجاع النتيجة منسّقة.
  CalcResult evaluate(String expression, {bool recordHistory = true}) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return const CalcResult(expression: '', display: '0', value: 0);
    }

    try {
      final normalized = _normalize(trimmed);
      final parser = Parser.fromSource(
        normalized,
        base: context.numberBase.radix,
      );
      final ast = parser.parse();
      final value = Evaluator(context).evaluate(ast);

      if (value.isNaN) {
        throw CalcError.math('النتيجة غير معرّفة');
      }
      if (value.isInfinite) {
        throw CalcError.range('النتيجة خارج نطاق الحساب');
      }

      context.ans = value;

      final display = context.numberBase == NumberBase.decimal
          ? CalcFormatter.format(value)
          : CalcFormatter.formatInBase(value, context.numberBase);

      if (recordHistory) {
        _record(trimmed, display);
      }

      return CalcResult(expression: trimmed, display: display, value: value);
    } on CalcError catch (error) {
      return CalcResult(
        expression: trimmed,
        display: _errorLabel(error),
        error: error,
      );
    } catch (error) {
      final wrapped = CalcError('math', error.toString());
      return CalcResult(
        expression: trimmed,
        display: _errorLabel(wrapped),
        error: wrapped,
      );
    }
  }

  /// إصلاح مدخلات شائعة: أقواس ناقصة في النهاية، ورموز بديلة.
  String _normalize(String input) {
    var text = input;

    // الأرقام العربية الهندية ➜ أرقام لاتينية.
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < arabicDigits.length; i++) {
      text = text.replaceAll(arabicDigits[i], i.toString());
    }
    text = text.replaceAll('٫', '.').replaceAll('،', ',');

    // إغلاق الأقواس المفتوحة تلقائيًا (الكاسيو بيعمل كده عند الضغط على =).
    var open = 0;
    for (final ch in text.split('')) {
      if (ch == '(') open++;
      if (ch == ')') open--;
    }
    if (open > 0) text += ')' * open;

    return text;
  }

  String _errorLabel(CalcError error) {
    switch (error.kind) {
      case 'syntax':
        return 'Syntax ERROR';
      case 'range':
        return 'Range ERROR';
      case 'stack':
        return 'Stack ERROR';
      case 'argument':
        return 'Argument ERROR';
      default:
        return 'Math ERROR';
    }
  }

  void _record(String expression, String result) {
    history.insert(
      0,
      CalcHistoryEntry(
        expression: expression,
        result: result,
        at: DateTime.now(),
      ),
    );
    if (history.length > maxHistory) {
      history.removeRange(maxHistory, history.length);
    }
  }

  void clearHistory() => history.clear();

  // ----- الذاكرة -----

  /// M+ : إضافة قيمة للذاكرة.
  void memoryAdd(double value) => context.memory = context.memory + value;

  /// M− : طرح قيمة من الذاكرة.
  void memorySubtract(double value) => context.memory = context.memory - value;

  /// MR : قراءة الذاكرة.
  double memoryRecall() => context.memory;

  /// MC : تصفير الذاكرة.
  void memoryClear() => context.clearMemory();

  /// STO : تخزين قيمة في متغيّر.
  void store(String variable, double value) => context.write(variable, value);

  /// RCL : استرجاع قيمة متغيّر.
  double recall(String variable) => context.read(variable);

  void resetAll() {
    context.clearAllVariables();
    clearHistory();
  }
}
