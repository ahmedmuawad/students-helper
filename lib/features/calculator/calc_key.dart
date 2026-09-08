import 'package:flutter/material.dart';

import '../../state/calculator_state.dart';

/// وصف زر في لوحة مفاتيح الآلة الحاسبة.
///
/// كل زر له لحد 3 وظائف زي الكاسيو: الوظيفة الأساسية، ووظيفة مع SHIFT
/// (بتظهر فوق الزر بلون مميز)، ووظيفة مع ALPHA.
class CalcKey {
  final String label;
  final String? shiftLabel;
  final String? alphaLabel;

  final void Function(CalculatorState state) onPrimary;
  final void Function(CalculatorState state)? onShift;
  final void Function(CalculatorState state)? onAlpha;

  /// لون خلفية مخصص (للأزرار المميزة زي AC و =).
  final Color? background;
  final Color? foreground;

  /// حجم الخط للنص الأساسي.
  final double fontSize;

  const CalcKey({
    required this.label,
    required this.onPrimary,
    this.shiftLabel,
    this.alphaLabel,
    this.onShift,
    this.onAlpha,
    this.background,
    this.foreground,
    this.fontSize = 16,
  });

  /// زر بسيط بيدخل نص في المعادلة.
  factory CalcKey.insert(
    String label,
    String text, {
    String? shiftLabel,
    String? shiftText,
    String? alphaLabel,
    String? alphaText,
    double fontSize = 16,
    Color? background,
    Color? foreground,
  }) {
    return CalcKey(
      label: label,
      shiftLabel: shiftLabel,
      alphaLabel: alphaLabel,
      fontSize: fontSize,
      background: background,
      foreground: foreground,
      onPrimary: (state) => state.insert(text),
      onShift: shiftText == null ? null : (state) => state.insert(shiftText),
      onAlpha: alphaText == null ? null : (state) => state.insert(alphaText),
    );
  }

  /// تنفيذ الضغطة حسب المُعدِّل النشط حاليًا.
  void press(CalculatorState state) {
    if (state.shift && onShift != null) {
      onShift!(state);
      return;
    }
    if (state.alpha && onAlpha != null) {
      onAlpha!(state);
      return;
    }
    onPrimary(state);
  }

  /// النص المعروض على الزر حسب المُعدِّل النشط.
  String displayLabel(CalculatorState state) {
    if (state.shift && shiftLabel != null) return shiftLabel!;
    if (state.alpha && alphaLabel != null) return alphaLabel!;
    return label;
  }
}
