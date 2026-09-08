import 'dart:math' as math;

/// وحدة قياس الزوايا — زي أوضاع DEG / RAD / GRAD في الكاسيو.
enum AngleMode {
  degree,
  radian,
  gradian;

  String get id => name;

  static AngleMode fromId(String? id) => AngleMode.values.firstWhere(
        (e) => e.name == id,
        orElse: () => AngleMode.degree,
      );

  String get shortLabel {
    switch (this) {
      case AngleMode.degree:
        return 'DEG';
      case AngleMode.radian:
        return 'RAD';
      case AngleMode.gradian:
        return 'GRA';
    }
  }

  /// تحويل من وحدة المستخدم إلى الراديان (مدخل دوال dart:math).
  double toRadians(double value) {
    switch (this) {
      case AngleMode.degree:
        return value * math.pi / 180.0;
      case AngleMode.radian:
        return value;
      case AngleMode.gradian:
        return value * math.pi / 200.0;
    }
  }

  /// تحويل من الراديان إلى وحدة المستخدم (مخرج الدوال العكسية).
  double fromRadians(double radians) {
    switch (this) {
      case AngleMode.degree:
        return radians * 180.0 / math.pi;
      case AngleMode.radian:
        return radians;
      case AngleMode.gradian:
        return radians * 200.0 / math.pi;
    }
  }
}

/// أساس العد في وضع BASE-N.
enum NumberBase {
  decimal(10, 'DEC'),
  hexadecimal(16, 'HEX'),
  binary(2, 'BIN'),
  octal(8, 'OCT');

  final int radix;
  final String label;

  const NumberBase(this.radix, this.label);

  static NumberBase fromRadix(int radix) => NumberBase.values.firstWhere(
        (e) => e.radix == radix,
        orElse: () => NumberBase.decimal,
      );
}

/// حالة الآلة الحاسبة أثناء التقييم: الزوايا، الأساس، الذاكرة، والمتغيرات.
class EvalContext {
  AngleMode angleMode;
  NumberBase numberBase;

  /// متغيرات STO/RCL: A B C D X Y M بالإضافة إلى Ans.
  final Map<String, double> variables;

  final math.Random random;

  EvalContext({
    this.angleMode = AngleMode.degree,
    this.numberBase = NumberBase.decimal,
    Map<String, double>? variables,
    math.Random? random,
  })  : variables = variables ??
            <String, double>{
              'A': 0,
              'B': 0,
              'C': 0,
              'D': 0,
              'X': 0,
              'Y': 0,
              'M': 0,
              'Ans': 0,
            },
        random = random ?? math.Random();

  double get ans => variables['Ans'] ?? 0;

  set ans(double value) => variables['Ans'] = value;

  double get memory => variables['M'] ?? 0;

  set memory(double value) => variables['M'] = value;

  double read(String name) => variables[name] ?? 0;

  void write(String name, double value) {
    variables[name] = value;
  }

  void clearMemory() => variables['M'] = 0;

  void clearAllVariables() {
    for (final key in variables.keys.toList()) {
      variables[key] = 0;
    }
  }

  EvalContext copy() => EvalContext(
        angleMode: angleMode,
        numberBase: numberBase,
        variables: Map<String, double>.from(variables),
        random: random,
      );
}
