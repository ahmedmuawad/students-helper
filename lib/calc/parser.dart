import 'ast.dart';
import 'calc_error.dart';
import 'lexer.dart';
import 'token.dart';

/// محلّل نحوي نازل تعاوديًا (Recursive Descent) بأولويات مطابقة للكاسيو.
///
/// ترتيب الأولويات من الأضعف للأقوى:
///   or / xor / xnor  →  and  →  + -  →  × ÷  →  nPr / nCr
///   →  سالب أحادي  →  ^ (يمين لليسار)  →  عوامل لاحقة (! ² ³ % °)  →  أولية
class Parser {
  final List<Token> _tokens;
  int _index = 0;

  Parser(this._tokens);

  factory Parser.fromSource(String source, {int base = 10}) =>
      Parser(Lexer(source, base: base).tokenize());

  Token get _current => _tokens[_index];

  Token _advance() => _tokens[_index++];

  Expr parse() {
    final expr = _parseOr();
    if (_current.type != TokenType.end) {
      throw CalcError.syntax(
        'رمز زائد بعد نهاية التعبير: "${_current.text}"',
        _current.position,
      );
    }
    return expr;
  }

  Expr _parseOr() {
    var left = _parseAnd();
    while (true) {
      final token = _current;
      if (token.type == TokenType.operator &&
          (token.text == 'or' || token.text == 'xor' || token.text == 'xnor')) {
        _index++;
        left = BinaryExpr(token.text, left, _parseAnd());
      } else {
        return left;
      }
    }
  }

  Expr _parseAnd() {
    var left = _parseAdditive();
    while (_current.type == TokenType.operator && _current.text == 'and') {
      _index++;
      left = BinaryExpr('and', left, _parseAdditive());
    }
    return left;
  }

  Expr _parseAdditive() {
    var left = _parseMultiplicative();
    while (true) {
      final token = _current;
      if (token.type == TokenType.operator &&
          (token.text == '+' || token.text == '-')) {
        _index++;
        left = BinaryExpr(token.text, left, _parseMultiplicative());
      } else {
        return left;
      }
    }
  }

  Expr _parseMultiplicative() {
    var left = _parseImplicitProduct();
    while (true) {
      final token = _current;
      if (token.type == TokenType.operator &&
          (token.text == '*' || token.text == '/')) {
        _index++;
        left = BinaryExpr(token.text, left, _parseImplicitProduct());
      } else {
        return left;
      }
    }
  }

  /// الضرب الضمني: 2π  ·  3(4+1)  ·  2sin(30)  ·  AB
  ///
  /// أولويته **أعلى** من × و ÷ عشان يطابق سلوك الكاسيو:
  /// 1÷2π = 1÷(2π) = 0.159 وليس (1÷2)π.
  Expr _parseImplicitProduct() {
    var left = _parsePermutation();
    while (_startsImplicitMultiplication(_current)) {
      left = BinaryExpr('*', left, _parsePermutation());
    }
    return left;
  }

  /// هل الرمز الحالي ممكن يبدأ تعبير جديد يتضرب ضمنيًا في اللي قبله؟
  bool _startsImplicitMultiplication(Token token) {
    switch (token.type) {
      case TokenType.number:
      case TokenType.variable:
      case TokenType.constant:
      case TokenType.function:
      case TokenType.lparen:
        return true;
      default:
        return false;
    }
  }

  Expr _parsePermutation() {
    var left = _parseUnary();
    while (true) {
      final token = _current;
      if (token.type == TokenType.operator &&
          (token.text == 'nPr' || token.text == 'nCr')) {
        _index++;
        left = CallExpr(token.text, [left, _parseUnary()]);
      } else {
        return left;
      }
    }
  }

  Expr _parseUnary() {
    final token = _current;
    if (token.type == TokenType.operator &&
        (token.text == '-' || token.text == '+')) {
      _index++;
      final operand = _parseUnary();
      return token.text == '-' ? UnaryExpr('-', operand) : operand;
    }
    return _parsePower();
  }

  Expr _parsePower() {
    final base = _parsePostfix();
    if (_current.type == TokenType.operator && _current.text == '^') {
      _index++;
      // الأس يمين لليسار: 2^3^2 = 2^(3^2)
      final exponent = _parseUnary();
      return BinaryExpr('^', base, exponent);
    }
    return base;
  }

  Expr _parsePostfix() {
    var expr = _parsePrimary();
    while (true) {
      final token = _current;
      if (token.type == TokenType.operator &&
          (token.text == '!' ||
              token.text == '²' ||
              token.text == '³' ||
              token.text == '%' ||
              token.text == '°')) {
        _index++;
        expr = PostfixExpr(token.text, expr);
      } else {
        return expr;
      }
    }
  }

  Expr _parsePrimary() {
    final token = _current;

    switch (token.type) {
      case TokenType.number:
        _index++;
        return NumberExpr(token.value);

      case TokenType.constant:
        _index++;
        return ConstantExpr(token.text);

      case TokenType.variable:
        _index++;
        return VariableExpr(token.text);

      case TokenType.lparen:
        _index++;
        final inner = _parseOr();
        _expect(TokenType.rparen, 'قوس إغلاق ")" ناقص');
        return inner;

      case TokenType.function:
        return _parseFunction();

      case TokenType.operator:
        throw CalcError.syntax(
          'عامل بدون معامل قبله: "${token.text}"',
          token.position,
        );

      case TokenType.end:
        throw CalcError.syntax('التعبير ناقص', token.position);

      default:
        throw CalcError.syntax(
          'رمز غير متوقع: "${token.text}"',
          token.position,
        );
    }
  }

  Expr _parseFunction() {
    final nameToken = _advance();
    final name = _normalizeFunctionName(nameToken.text);

    // دوال بقوس صريح: sin(30) و integrate(X^2, 0, 1)
    if (_current.type == TokenType.lparen) {
      _index++;
      final args = <Expr>[];
      if (_current.type != TokenType.rparen) {
        args.add(_parseOr());
        while (_current.type == TokenType.comma) {
          _index++;
          args.add(_parseOr());
        }
      }
      _expect(TokenType.rparen, 'قوس إغلاق ")" ناقص بعد $name');
      return CallExpr(name, args);
    }

    // دوال بدون أقواس زي الكاسيو: √9  ·  sin30  ·  ln100
    // بتاخد المعامل التالي بأولوية عالية (أقوى من × ÷).
    final argument = _parsePower();
    return CallExpr(name, [argument]);
  }

  /// توحيد الأسماء المترادفة لاسم داخلي واحد.
  static String _normalizeFunctionName(String raw) {
    switch (raw) {
      case '∫':
        return 'integrate';
      case 'dydx':
        return 'derivative';
      case 'Σ':
      case 'sigma':
        return 'sum';
      case 'Abs':
        return 'abs';
      case 'Rnd':
        return 'round';
      case 'Int':
      case 'Intg':
        return 'floor';
      case 'ranint':
        return 'RanInt';
      default:
        return raw;
    }
  }

  void _expect(TokenType type, String message) {
    if (_current.type != type) {
      throw CalcError.syntax(message, _current.position);
    }
    _index++;
  }
}
