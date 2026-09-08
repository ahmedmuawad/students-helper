enum TokenType {
  number,
  variable,
  constant,
  function,
  operator,
  lparen,
  rparen,
  comma,
  end,
}

class Token {
  final TokenType type;

  /// النص كما ظهر في المدخل (اسم الدالة، رمز العملية، اسم المتغير).
  final String text;

  /// قيمة الرقم لو [type] هو number.
  final double value;

  /// موضع بداية الرمز في النص.
  final int position;

  const Token(this.type, this.text, this.position, [this.value = 0]);

  @override
  String toString() => '${type.name}($text)';
}
