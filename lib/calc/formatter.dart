import 'dart:math' as math;

import 'eval_context.dart';

/// تنسيق نتائج الآلة الحاسبة بأسلوب الكاسيو (10 أرقام معنوية).
class CalcFormatter {
  /// عدد الأرقام المعنوية المعروضة.
  static const int significantDigits = 10;

  /// تنسيق قيمة عشرية للعرض.
  static String format(double value, {int? fixedDecimals}) {
    if (value.isNaN) return 'Math ERROR';
    if (value.isInfinite) return value.isNegative ? '-∞' : '∞';

    // تفادي عرض "-0".
    if (value == 0) return '0';

    if (fixedDecimals != null) {
      return _trimNegativeZero(value.toStringAsFixed(fixedDecimals));
    }

    final magnitude = value.abs();

    // أرقام كبيرة جدًا أو صغيرة جدًا ➜ صيغة علمية.
    if (magnitude >= 1e10 || magnitude < 1e-9) {
      return _scientific(value);
    }

    // عدد المنازل العشرية المتاحة ضمن 10 أرقام معنوية.
    //
    // الأصفار البادئة في الأعداد الأصغر من 1 مش أرقام معنوية، فـ 1÷3 لازم
    // تطلع 0.3333333333 (عشر ثلاثات) زي الكاسيو مش تسعة.
    final exponent = (math.log(magnitude) / math.ln10).floor();
    final decimals = (significantDigits - exponent - 1).clamp(0, 17);

    var text = value.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      text = text.replaceAll(RegExp(r'\.$'), '');
    }
    return _trimNegativeZero(text);
  }

  /// الصيغة العلمية: 1.234567891×10⁻⁵
  static String _scientific(double value) {
    // الكاسيو بيحافظ على العشر خانات المعنوية كاملة في الصيغة العلمية
    // (2^100 بتظهر 1.267650600×10³⁰ مش 1.2676506×10³⁰).
    final text = value.toStringAsExponential(significantDigits - 1);
    final parts = text.split('e');
    final mantissa = parts[0];
    final exponent = int.parse(parts[1]);
    return '$mantissa×10${_superscript(exponent)}';
  }

  static String _superscript(int exponent) {
    const digits = {
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
      '-': '⁻',
    };
    return exponent.toString().split('').map((ch) => digits[ch] ?? ch).join();
  }

  static String _trimNegativeZero(String text) {
    if (double.tryParse(text) == 0) return '0';
    return text;
  }

  /// تنسيق العدد في وضع BASE-N (ثنائي / ثماني / سداسي عشري).
  static String formatInBase(double value, NumberBase base) {
    if (base == NumberBase.decimal) return format(value);
    if (value.isNaN || value.isInfinite) return 'Math ERROR';

    var intValue = value.truncate();
    final isNegative = intValue < 0;

    // الكاسيو بيعرض السالب بالمتمم الثنائي على 32 بت.
    if (isNegative) {
      intValue = (0x100000000 + intValue) & 0xFFFFFFFF;
    }

    final text = intValue.toRadixString(base.radix).toUpperCase();
    if (base == NumberBase.binary) {
      // تجميع كل 4 خانات لسهولة القراءة.
      return _group(text, 4, ' ');
    }
    return text;
  }

  static String _group(String text, int size, String separator) {
    final buffer = StringBuffer();
    final remainder = text.length % size;
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (i - remainder) % size == 0) buffer.write(separator);
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  /// تحويل عدد عشري إلى كسر بسيط (زي زر S⇔D في الكاسيو).
  ///
  /// بيرجّع null لو مفيش كسر بمقام صغير يمثّل العدد بدقة.
  static ({int numerator, int denominator})? toFraction(
    double value, {
    int maxDenominator = 10000,
    double tolerance = 1e-10,
  }) {
    if (value.isNaN || value.isInfinite) return null;
    if (value == value.roundToDouble()) return null;

    final isNegative = value < 0;
    final target = value.abs();

    // خوارزمية الكسور المستمرة (Stern-Brocot).
    var lowerN = 0, lowerD = 1;
    var upperN = 1, upperD = 0;

    for (var i = 0; i < 64; i++) {
      final midN = lowerN + upperN;
      final midD = lowerD + upperD;
      if (midD > maxDenominator) break;

      final mid = midN / midD;
      if ((mid - target).abs() < tolerance) {
        return (numerator: isNegative ? -midN : midN, denominator: midD);
      }
      if (mid < target) {
        lowerN = midN;
        lowerD = midD;
      } else {
        upperN = midN;
        upperD = midD;
      }
    }
    return null;
  }

  /// صيغة هندسية (الأس من مضاعفات 3) — زر ENG في الكاسيو.
  static String engineering(double value) {
    if (value == 0) return '0';
    if (value.isNaN || value.isInfinite) return format(value);

    var exponent = (math.log(value.abs()) / math.ln10).floor();
    exponent = (exponent / 3).floor() * 3;
    final mantissa = value / math.pow(10, exponent);

    var text = mantissa.toStringAsFixed(6);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return exponent == 0 ? text : '$text×10${_superscript(exponent)}';
  }

  /// تحويل درجات عشرية إلى درجات/دقائق/ثواني — زر °’” في الكاسيو.
  static String toDegreesMinutesSeconds(double degrees) {
    final sign = degrees < 0 ? '-' : '';
    var remaining = degrees.abs();
    final d = remaining.floor();
    remaining = (remaining - d) * 60;
    final m = remaining.floor();
    final s = (remaining - m) * 60;
    final secondsText = s
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return '$sign$d°$m′$secondsText″';
  }
}
