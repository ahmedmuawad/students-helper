import 'calc_error.dart';
import 'token.dart';

/// المتغيّرات المتاحة للتخزين (زي أزرار STO/RCL في الكاسيو).
const Set<String> kVariableNames = {'A', 'B', 'C', 'D', 'X', 'Y', 'M'};

/// الثوابت المعروفة.
const Set<String> kConstantNames = {
  'pi', 'π', 'e', 'Ans', 'ans', 'Ran#', 'rand',
  // ثوابت فيزيائية مفيدة للطالب
  'g', 'c0', 'h_planck', 'N_A',
};

/// أسماء الدوال المدعومة.
const Set<String> kFunctionNames = {
  // مثلثية
  'sin', 'cos', 'tan',
  'asin', 'acos', 'atan',
  'sinh', 'cosh', 'tanh',
  'asinh', 'acosh', 'atanh',
  // لوغاريتمات وأسس
  'log', 'ln', 'logab', 'exp',
  // جذور وقيم
  'sqrt', 'cbrt', 'root', 'abs', 'Abs',
  // تقريب وأعداد صحيحة
  'floor', 'ceil', 'round', 'Rnd', 'Int', 'Intg', 'frac',
  // احتمالات
  'nPr', 'nCr', 'RanInt', 'ranint',
  // قواسم
  'gcd', 'lcm', 'mod',
  // إحصاء
  'mean', 'median', 'stdev', 'stdevp', 'sum', 'count', 'min', 'max',
  // تحليل عددي (اللي في صورة الكاسيو)
  'integrate', '∫', 'derivative', 'dydx', 'Σ', 'sigma',
  // إحداثيات
  'Pol', 'Rec',
  // منطقية (وضع BASE-N)
  'not', 'neg',
};

/// عمليات نصية (كلمات تشتغل كعوامل بين تعبيرين).
const Set<String> kWordOperators = {'and', 'or', 'xor', 'xnor', 'nPr', 'nCr'};

/// محلّل لفظي يحوّل نص المعادلة إلى رموز.
class Lexer {
  final String source;

  /// أساس العد الحالي (10 عادي، 2/8/16 في وضع BASE-N).
  final int base;

  int _pos = 0;

  Lexer(this.source, {this.base = 10});

  /// كل الكلمات المعروفة مرتبة من الأطول للأقصر عشان المطابقة تكون صحيحة
  /// (مثلاً "asinh" لازم تتطابق قبل "asin" وقبل "sin").
  static final List<String> _words = () {
    final all = <String>{
      ...kFunctionNames,
      ...kConstantNames,
      ...kWordOperators,
      ...kVariableNames,
    }.toList();
    all.sort((a, b) => b.length.compareTo(a.length));
    return all;
  }();

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (true) {
      final token = _next();
      tokens.add(token);
      if (token.type == TokenType.end) break;
    }
    return tokens;
  }

  Token _next() {
    _skipSpaces();
    if (_pos >= source.length) {
      return Token(TokenType.end, '', _pos);
    }

    final start = _pos;
    final ch = source[_pos];

    if (_isDigitInBase(ch) || (ch == '.' && base == 10)) {
      return _readNumber();
    }

    // مطابقة أطول كلمة معروفة عند الموضع الحالي.
    for (final word in _words) {
      if (source.startsWith(word, _pos)) {
        // لا نطابق كلمة لو بعدها حرف يكمّل اسم أطول (مثل "sin" داخل "sinx").
        _pos += word.length;
        // nPr و nCr بيشتغلوا بالشكلين: عامل بين تعبيرين زي الكاسيو (5 nPr 3)
        // أو استدعاء دالة nPr(5,3). لو بعدها قوس فهي دالة.
        if (kWordOperators.contains(word)) {
          final isCall = _peekNonSpace() == '(';
          if (!isCall || !kFunctionNames.contains(word)) {
            return Token(TokenType.operator, word, start);
          }
        }
        if (kFunctionNames.contains(word)) {
          return Token(TokenType.function, word, start);
        }
        if (kConstantNames.contains(word)) {
          return Token(TokenType.constant, word, start);
        }
        return Token(TokenType.variable, word, start);
      }
    }

    // في وضع BASE-N الحروف A..F أرقام مش متغيّرات، وده متعامل معاه في _readNumber.
    _pos++;
    switch (ch) {
      case '(':
        return Token(TokenType.lparen, '(', start);
      case ')':
        return Token(TokenType.rparen, ')', start);
      case ',':
      case '،':
        return Token(TokenType.comma, ',', start);
      case '+':
        return Token(TokenType.operator, '+', start);
      case '-':
      case '−': // علامة الطرح الرياضية
      case '–':
        return Token(TokenType.operator, '-', start);
      case '*':
      case '×':
        return Token(TokenType.operator, '*', start);
      case '/':
      case '÷':
      case '⁄':
        return Token(TokenType.operator, '/', start);
      case '^':
        return Token(TokenType.operator, '^', start);
      case '!':
        return Token(TokenType.operator, '!', start);
      case '%':
        return Token(TokenType.operator, '%', start);
      case '√':
        return Token(TokenType.function, 'sqrt', start);
      case '∛':
        return Token(TokenType.function, 'cbrt', start);
      case '²':
        return Token(TokenType.operator, '²', start);
      case '³':
        return Token(TokenType.operator, '³', start);
      case '°':
        return Token(TokenType.operator, '°', start);
    }

    throw CalcError.syntax('رمز غير معروف: $ch', start);
  }

  /// أول حرف غير مسافة بعد الموضع الحالي (بدون تحريك المؤشر).
  String? _peekNonSpace() {
    var i = _pos;
    while (i < source.length && (source[i] == ' ' || source[i] == '\t')) {
      i++;
    }
    return i < source.length ? source[i] : null;
  }

  void _skipSpaces() {
    while (
        _pos < source.length && (source[_pos] == ' ' || source[_pos] == '\t')) {
      _pos++;
    }
  }

  bool _isDigitInBase(String ch) {
    final code = ch.codeUnitAt(0);
    // أرقام 0-9
    if (code >= 0x30 && code <= 0x39) {
      final digit = code - 0x30;
      return digit < base || base == 10;
    }
    // حروف A-F في الوضع السداسي عشري
    if (base == 16) {
      final upper = ch.toUpperCase().codeUnitAt(0);
      if (upper >= 0x41 && upper <= 0x46) return true;
    }
    return false;
  }

  Token _readNumber() {
    final start = _pos;
    final buffer = StringBuffer();

    while (_pos < source.length && _isDigitInBase(source[_pos])) {
      buffer.write(source[_pos]);
      _pos++;
    }

    if (base != 10) {
      final text = buffer.toString();
      final parsed = int.tryParse(text, radix: base);
      if (parsed == null) {
        throw CalcError.syntax('رقم غير صالح في الأساس $base: $text', start);
      }
      return Token(TokenType.number, text, start, parsed.toDouble());
    }

    // الجزء العشري
    if (_pos < source.length && source[_pos] == '.') {
      buffer.write('.');
      _pos++;
      while (_pos < source.length && _isDigitInBase(source[_pos])) {
        buffer.write(source[_pos]);
        _pos++;
      }
    }

    // الأس العلمي: 1.5E3 أو 1.5E-3 (زر ×10ˣ في الكاسيو)
    if (_pos < source.length && (source[_pos] == 'E')) {
      final save = _pos;
      var exponent = StringBuffer('E');
      _pos++;
      if (_pos < source.length &&
          (source[_pos] == '+' || source[_pos] == '-')) {
        exponent.write(source[_pos]);
        _pos++;
      }
      if (_pos < source.length && _isDigitInBase(source[_pos])) {
        while (_pos < source.length && _isDigitInBase(source[_pos])) {
          exponent.write(source[_pos]);
          _pos++;
        }
        buffer.write(exponent);
      } else {
        // مش أس حقيقي — نرجع الموضع زي ما كان.
        _pos = save;
      }
    }

    final text = buffer.toString();
    final value = double.tryParse(text);
    if (value == null) {
      throw CalcError.syntax('رقم غير صالح: $text', start);
    }
    return Token(TokenType.number, text, start, value);
  }
}
