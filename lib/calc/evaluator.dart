import 'dart:math' as math;

import 'ast.dart';
import 'calc_error.dart';
import 'eval_context.dart';

/// يقيّم شجرة التعبير إلى قيمة عددية.
class Evaluator {
  final EvalContext context;

  /// عمق التعاود الحالي — حماية من التعبيرات المتداخلة أكتر من اللازم.
  int _depth = 0;
  static const int _maxDepth = 200;

  Evaluator(this.context);

  double evaluate(Expr expr) {
    if (_depth > _maxDepth) {
      throw const CalcError('stack', 'التعبير متداخل أكتر من اللازم');
    }
    _depth++;
    try {
      return _eval(expr);
    } finally {
      _depth--;
    }
  }

  double _eval(Expr expr) {
    if (expr is NumberExpr) return expr.value;
    if (expr is ConstantExpr) return _constant(expr.name);
    if (expr is VariableExpr) return context.read(expr.name);
    if (expr is UnaryExpr) return _unary(expr);
    if (expr is PostfixExpr) return _postfix(expr);
    if (expr is BinaryExpr) return _binary(expr);
    if (expr is CallExpr) return _call(expr);
    throw const CalcError('syntax', 'عقدة غير معروفة في التعبير');
  }

  double _constant(String name) {
    switch (name) {
      case 'pi':
      case 'π':
        return math.pi;
      case 'e':
        return math.e;
      case 'Ans':
      case 'ans':
        return context.ans;
      case 'Ran#':
      case 'rand':
        return context.random.nextDouble();
      // ثوابت فيزيائية شائعة في مسائل الطالب
      case 'g':
        return 9.80665;
      case 'c0':
        return 299792458.0;
      case 'h_planck':
        return 6.62607015e-34;
      case 'N_A':
        return 6.02214076e23;
      default:
        throw CalcError.syntax('ثابت غير معروف: $name');
    }
  }

  double _unary(UnaryExpr expr) {
    final value = evaluate(expr.operand);
    return expr.op == '-' ? -value : value;
  }

  double _postfix(PostfixExpr expr) {
    final value = evaluate(expr.operand);
    switch (expr.op) {
      case '!':
        return _factorial(value);
      case '²':
        return value * value;
      case '³':
        return value * value * value;
      case '%':
        return value / 100.0;
      case '°':
        // تحويل درجات إلى الوحدة الحالية (يفيد لما الوضع RAD).
        return context.angleMode == AngleMode.radian
            ? value * math.pi / 180.0
            : value;
      default:
        throw CalcError.syntax('عامل لاحق غير معروف: ${expr.op}');
    }
  }

  double _binary(BinaryExpr expr) {
    // العمليات المنطقية بتشتغل على أعداد صحيحة (وضع BASE-N).
    switch (expr.op) {
      case 'and':
        return (_toInt(evaluate(expr.left)) & _toInt(evaluate(expr.right)))
            .toDouble();
      case 'or':
        return (_toInt(evaluate(expr.left)) | _toInt(evaluate(expr.right)))
            .toDouble();
      case 'xor':
        return (_toInt(evaluate(expr.left)) ^ _toInt(evaluate(expr.right)))
            .toDouble();
      case 'xnor':
        return (~(_toInt(evaluate(expr.left)) ^ _toInt(evaluate(expr.right))))
            .toDouble();
    }

    final left = evaluate(expr.left);
    final right = evaluate(expr.right);

    switch (expr.op) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '*':
        return left * right;
      case '/':
        if (right == 0) {
          throw CalcError.math('القسمة على صفر غير معرّفة');
        }
        return left / right;
      case '^':
        return _power(left, right);
      default:
        throw CalcError.syntax('عملية غير معروفة: ${expr.op}');
    }
  }

  double _power(double base, double exponent) {
    if (base < 0 && exponent != exponent.roundToDouble()) {
      throw CalcError.math('أساس سالب مع أس غير صحيح ينتج عددًا تخيليًا');
    }
    if (base == 0 && exponent < 0) {
      throw CalcError.math('صفر مرفوع لأس سالب غير معرّف');
    }
    final result = math.pow(base, exponent);
    if (result is! num || result.isNaN) {
      throw CalcError.math('نتيجة الأس غير معرّفة');
    }
    return result.toDouble();
  }

  int _toInt(double value) {
    if (value.isNaN || value.isInfinite) {
      throw CalcError.math('قيمة غير صالحة للعمليات المنطقية');
    }
    if (value.abs() > 9.0e15) {
      throw CalcError.range('العدد كبير جدًا للعمليات المنطقية');
    }
    return value.truncate();
  }

  double _factorial(double value) {
    if (value < 0 || value != value.roundToDouble()) {
      throw CalcError.math('المضروب يتطلب عددًا صحيحًا غير سالب');
    }
    if (value > 170) {
      throw CalcError.range('المضروب أكبر من قدرة العرض (الحد 170)');
    }
    var result = 1.0;
    for (var i = 2; i <= value.round(); i++) {
      result *= i;
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // الدوال
  // ---------------------------------------------------------------------

  double _call(CallExpr expr) {
    final name = expr.name;

    // دوال خاصة: بتحتاج التعبير نفسه من غير تقييم مسبق (بتغيّر قيمة X).
    switch (name) {
      case 'integrate':
        return _integrate(expr);
      case 'derivative':
        return _derivative(expr);
      case 'sum':
        return _summation(expr);
    }

    final args = expr.args.map(evaluate).toList(growable: false);

    switch (name) {
      // ----- مثلثية -----
      case 'sin':
        return _trig(args, (x) => math.sin(x));
      case 'cos':
        return _trig(args, (x) => math.cos(x));
      case 'tan':
        return _tan(args);
      case 'asin':
        _arity(name, args, 1);
        if (args[0] < -1 || args[0] > 1) {
          throw CalcError.math('نطاق sin⁻¹ من -1 إلى 1');
        }
        return context.angleMode.fromRadians(math.asin(args[0]));
      case 'acos':
        _arity(name, args, 1);
        if (args[0] < -1 || args[0] > 1) {
          throw CalcError.math('نطاق cos⁻¹ من -1 إلى 1');
        }
        return context.angleMode.fromRadians(math.acos(args[0]));
      case 'atan':
        _arity(name, args, 1);
        return context.angleMode.fromRadians(math.atan(args[0]));

      // ----- زائدية -----
      case 'sinh':
        _arity(name, args, 1);
        return (math.exp(args[0]) - math.exp(-args[0])) / 2;
      case 'cosh':
        _arity(name, args, 1);
        return (math.exp(args[0]) + math.exp(-args[0])) / 2;
      case 'tanh':
        _arity(name, args, 1);
        final e2 = math.exp(2 * args[0]);
        return (e2 - 1) / (e2 + 1);
      case 'asinh':
        _arity(name, args, 1);
        return math.log(args[0] + math.sqrt(args[0] * args[0] + 1));
      case 'acosh':
        _arity(name, args, 1);
        if (args[0] < 1) throw CalcError.math('نطاق cosh⁻¹ يبدأ من 1');
        return math.log(args[0] + math.sqrt(args[0] * args[0] - 1));
      case 'atanh':
        _arity(name, args, 1);
        if (args[0] <= -1 || args[0] >= 1) {
          throw CalcError.math('نطاق tanh⁻¹ بين -1 و 1');
        }
        return 0.5 * math.log((1 + args[0]) / (1 - args[0]));

      // ----- لوغاريتمات وأسس -----
      case 'log':
        // log(x) بأساس 10، و log(a, b) لوغاريتم b بالأساس a (زي logab في الكاسيو).
        if (args.length == 2) return _logBase(args[0], args[1]);
        _arity(name, args, 1);
        if (args[0] <= 0) throw CalcError.math('اللوغاريتم يتطلب عددًا موجبًا');
        return math.log(args[0]) / math.ln10;
      case 'logab':
        _arity(name, args, 2);
        return _logBase(args[0], args[1]);
      case 'ln':
        _arity(name, args, 1);
        if (args[0] <= 0) throw CalcError.math('اللوغاريتم يتطلب عددًا موجبًا');
        return math.log(args[0]);
      case 'exp':
        _arity(name, args, 1);
        return math.exp(args[0]);

      // ----- جذور وقيم -----
      case 'sqrt':
        _arity(name, args, 1);
        if (args[0] < 0) throw CalcError.math('الجذر التربيعي لعدد سالب');
        return math.sqrt(args[0]);
      case 'cbrt':
        _arity(name, args, 1);
        return args[0] < 0
            ? -math.pow(-args[0], 1 / 3).toDouble()
            : math.pow(args[0], 1 / 3).toDouble();
      case 'root':
        // root(n, x) = الجذر النوني للعدد x
        _arity(name, args, 2);
        return _nthRoot(args[0], args[1]);
      case 'abs':
        _arity(name, args, 1);
        return args[0].abs();

      // ----- تقريب -----
      case 'floor':
        _arity(name, args, 1);
        return args[0].floorToDouble();
      case 'ceil':
        _arity(name, args, 1);
        return args[0].ceilToDouble();
      case 'round':
        if (args.length == 2) {
          final factor = math.pow(10, args[1].round()).toDouble();
          return (args[0] * factor).roundToDouble() / factor;
        }
        _arity(name, args, 1);
        return args[0].roundToDouble();
      case 'frac':
        _arity(name, args, 1);
        return args[0] - args[0].truncateToDouble();

      // ----- احتمالات -----
      case 'nPr':
        _arity(name, args, 2);
        return _permutations(args[0], args[1]);
      case 'nCr':
        _arity(name, args, 2);
        return _combinations(args[0], args[1]);
      case 'RanInt':
        _arity(name, args, 2);
        final low = args[0].round();
        final high = args[1].round();
        if (high < low)
          throw CalcError.argument('RanInt: الحد الأعلى أصغر من الأدنى');
        return (low + context.random.nextInt(high - low + 1)).toDouble();

      // ----- قواسم -----
      case 'gcd':
        _arity(name, args, 2);
        return _gcd(args[0].abs().round(), args[1].abs().round()).toDouble();
      case 'lcm':
        _arity(name, args, 2);
        final a = args[0].abs().round();
        final b = args[1].abs().round();
        if (a == 0 || b == 0) return 0;
        return (a ~/ _gcd(a, b) * b).toDouble();
      case 'mod':
        _arity(name, args, 2);
        if (args[1] == 0) throw CalcError.math('باقي القسمة على صفر');
        return args[0] % args[1];

      // ----- إحصاء -----
      case 'count':
        return args.length.toDouble();
      case 'min':
        _atLeast(name, args, 1);
        return args.reduce(math.min);
      case 'max':
        _atLeast(name, args, 1);
        return args.reduce(math.max);
      case 'mean':
        _atLeast(name, args, 1);
        return args.reduce((a, b) => a + b) / args.length;
      case 'median':
        _atLeast(name, args, 1);
        final sorted = List<double>.from(args)..sort();
        final mid = sorted.length ~/ 2;
        return sorted.length.isOdd
            ? sorted[mid]
            : (sorted[mid - 1] + sorted[mid]) / 2;
      case 'stdev':
        // الانحراف المعياري للعيّنة (بقسمة n-1) — زي sx في الكاسيو.
        _atLeast(name, args, 2);
        return _stdev(args, sample: true);
      case 'stdevp':
        // الانحراف المعياري للمجتمع (بقسمة n) — زي σx في الكاسيو.
        _atLeast(name, args, 1);
        return _stdev(args, sample: false);

      // ----- إحداثيات -----
      case 'Pol':
        // Pol(x, y) بترجّع نصف القطر r وتخزّن الزاوية θ في المتغير Y.
        _arity(name, args, 2);
        final r = math.sqrt(args[0] * args[0] + args[1] * args[1]);
        final theta = context.angleMode.fromRadians(
          math.atan2(args[1], args[0]),
        );
        context.write('X', r);
        context.write('Y', theta);
        return r;
      case 'Rec':
        // Rec(r, θ) بترجّع x وتخزّن y في المتغير Y.
        _arity(name, args, 2);
        final radians = context.angleMode.toRadians(args[1]);
        final x = args[0] * math.cos(radians);
        final y = args[0] * math.sin(radians);
        context.write('X', x);
        context.write('Y', y);
        return x;

      // ----- منطقية -----
      case 'not':
        _arity(name, args, 1);
        return (~_toInt(args[0])).toDouble();
      case 'neg':
        _arity(name, args, 1);
        return -args[0];

      default:
        throw CalcError.syntax('دالة غير معروفة: $name');
    }
  }

  double _trig(List<double> args, double Function(double) fn) {
    _arity('trig', args, 1);
    final result = fn(context.angleMode.toRadians(args[0]));
    // تنظيف أخطاء الفاصلة العائمة: sin(180) المفروض 0 مش 1.2e-16
    return _snapToZero(result);
  }

  double _tan(List<double> args) {
    _arity('tan', args, 1);
    final radians = context.angleMode.toRadians(args[0]);
    final cosine = math.cos(radians);
    if (_snapToZero(cosine) == 0) {
      throw CalcError.math('tan غير معرّفة عند هذه الزاوية');
    }
    return _snapToZero(math.sin(radians) / cosine);
  }

  /// قيم أصغر من عتبة دقة الحساب بتترجّع صفر — عشان نتائج زي sin(180)
  /// تطلع 0 بدل 1.2246e-16.
  static double _snapToZero(double value) => value.abs() < 1e-13 ? 0.0 : value;

  double _logBase(double base, double value) {
    if (base <= 0 || base == 1) {
      throw CalcError.math('أساس اللوغاريتم لازم يكون موجبًا ولا يساوي 1');
    }
    if (value <= 0) throw CalcError.math('اللوغاريتم يتطلب عددًا موجبًا');
    return math.log(value) / math.log(base);
  }

  double _nthRoot(double n, double x) {
    if (n == 0) throw CalcError.math('الجذر النوني لا يقبل n = 0');
    if (x < 0) {
      final isOddInteger = n == n.roundToDouble() && n.round().isOdd;
      if (!isOddInteger) {
        throw CalcError.math('جذر زوجي لعدد سالب غير معرّف');
      }
      return -math.pow(-x, 1 / n).toDouble();
    }
    return math.pow(x, 1 / n).toDouble();
  }

  double _permutations(double n, double r) {
    _requireCountArgs(n, r);
    var result = 1.0;
    for (var i = 0; i < r.round(); i++) {
      result *= (n - i);
    }
    return result;
  }

  double _combinations(double n, double r) {
    _requireCountArgs(n, r);
    final rr = math.min(r.round(), n.round() - r.round());
    var result = 1.0;
    for (var i = 0; i < rr; i++) {
      result = result * (n - i) / (i + 1);
    }
    return result.roundToDouble();
  }

  void _requireCountArgs(double n, double r) {
    if (n != n.roundToDouble() || r != r.roundToDouble()) {
      throw CalcError.math('nPr و nCr تتطلب أعدادًا صحيحة');
    }
    if (n < 0 || r < 0) throw CalcError.math('nPr و nCr لا تقبل أعدادًا سالبة');
    if (r > n) throw CalcError.math('r لا يمكن أن يكون أكبر من n');
  }

  static int _gcd(int a, int b) {
    while (b != 0) {
      final temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

  double _stdev(List<double> values, {required bool sample}) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sumSquares = 0.0;
    for (final value in values) {
      final diff = value - mean;
      sumSquares += diff * diff;
    }
    final divisor = sample ? values.length - 1 : values.length;
    return math.sqrt(sumSquares / divisor);
  }

  // ---------------------------------------------------------------------
  // التحليل العددي: التكامل والتفاضل والمجموع (اللي في صورة الكاسيو)
  // ---------------------------------------------------------------------

  /// تقييم تعبير بعد ضبط المتغير [variable] على [value] مؤقتًا.
  double _evalWith(Expr body, String variable, double value) {
    final saved = context.read(variable);
    context.write(variable, value);
    try {
      return evaluate(body);
    } finally {
      context.write(variable, saved);
    }
  }

  /// ∫(f(X), a, b) — التكامل المحدد بقاعدة سيمبسون المركّبة.
  double _integrate(CallExpr expr) {
    if (expr.args.length < 3 || expr.args.length > 4) {
      throw CalcError.argument('التكامل: ∫(الدالة, البداية, النهاية)');
    }
    final body = expr.args[0];
    final lower = evaluate(expr.args[1]);
    final upper = evaluate(expr.args[2]);
    if (lower == upper) return 0;

    // عدد الفترات لازم يكون زوجي في قاعدة سيمبسون.
    var intervals = 1000;
    if (expr.args.length == 4) {
      final requested = evaluate(expr.args[3]).round();
      intervals = requested.clamp(2, 100000);
      if (intervals.isOdd) intervals++;
    }

    final h = (upper - lower) / intervals;
    var total = _evalWith(body, 'X', lower) + _evalWith(body, 'X', upper);

    for (var i = 1; i < intervals; i++) {
      final x = lower + i * h;
      final weight = i.isOdd ? 4.0 : 2.0;
      total += weight * _evalWith(body, 'X', x);
    }

    final result = total * h / 3.0;
    if (result.isNaN || result.isInfinite) {
      throw CalcError.math('التكامل غير متقارب في هذا النطاق');
    }
    return _snapToZero(result);
  }

  /// d/dx(f(X), a) — المشتقة عند نقطة بالفرق المركزي مع تحسين ريتشاردسون.
  double _derivative(CallExpr expr) {
    if (expr.args.length < 2 || expr.args.length > 3) {
      throw CalcError.argument('التفاضل: d/dx(الدالة, النقطة)');
    }
    final body = expr.args[0];
    final point = evaluate(expr.args[1]);
    final h = expr.args.length == 3
        ? evaluate(expr.args[2]).abs()
        : math.max(1e-5, point.abs() * 1e-5);

    if (h == 0) throw CalcError.argument('خطوة التفاضل لا يمكن أن تكون صفرًا');

    double centralDifference(double step) {
      final forward = _evalWith(body, 'X', point + step);
      final backward = _evalWith(body, 'X', point - step);
      return (forward - backward) / (2 * step);
    }

    // تحسين ريتشاردسون: يقلّل خطأ التقريب بدرجة كبيرة.
    final coarse = centralDifference(h);
    final fine = centralDifference(h / 2);
    final result = (4 * fine - coarse) / 3;

    if (result.isNaN || result.isInfinite) {
      throw CalcError.math('المشتقة غير معرّفة عند هذه النقطة');
    }
    return _snapToZero(result);
  }

  /// Σ(f(X), a, b) — مجموع الدالة والمتغير X يتحرك من a إلى b بخطوة 1.
  double _summation(CallExpr expr) {
    if (expr.args.length != 3) {
      throw CalcError.argument('المجموع: Σ(الدالة, من, إلى)');
    }
    final body = expr.args[0];
    final start = evaluate(expr.args[1]).round();
    final end = evaluate(expr.args[2]).round();
    if (end < start)
      throw CalcError.argument('حد المجموع الأعلى أصغر من الأدنى');
    if (end - start > 100000) {
      throw CalcError.range('عدد حدود المجموع كبير جدًا');
    }

    var total = 0.0;
    for (var i = start; i <= end; i++) {
      total += _evalWith(body, 'X', i.toDouble());
    }
    return total;
  }

  void _arity(String name, List<double> args, int expected) {
    if (args.length != expected) {
      throw CalcError.argument('$name تحتاج $expected معامل');
    }
  }

  void _atLeast(String name, List<double> args, int minimum) {
    if (args.length < minimum) {
      throw CalcError.argument('$name تحتاج $minimum معامل على الأقل');
    }
  }
}
