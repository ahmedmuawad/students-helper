/// خطأ حسابي بصيغة تشبه أخطاء الكاسيو (Math ERROR / Syntax ERROR ...).
class CalcError implements Exception {
  /// مفتاح الخطأ: syntax, math, range, stack, argument.
  final String kind;

  /// رسالة تفصيلية للمطوّر / للعرض.
  final String message;

  /// موضع الخطأ في النص المدخل (لو معروف).
  final int? position;

  const CalcError(this.kind, this.message, [this.position]);

  const CalcError.syntax(String message, [int? position])
    : this('syntax', message, position);

  const CalcError.math(String message) : this('math', message);

  const CalcError.range(String message) : this('range', message);

  const CalcError.argument(String message) : this('argument', message);

  @override
  String toString() => 'CalcError($kind): $message';
}
