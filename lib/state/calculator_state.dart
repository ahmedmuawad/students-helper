import 'package:flutter/material.dart';

import '../calc/calculator_engine.dart';
import '../calc/eval_context.dart';
import '../data/local_store.dart';

/// حالة الآلة الحاسبة: النص المدخل، النتيجة، الأوضاع، والتاريخ.
class CalculatorState extends ChangeNotifier {
  final LocalStore _store;
  final CalculatorEngine engine = CalculatorEngine();

  String _input = '';
  String _result = '0';
  bool _hasError = false;

  /// مُعدِّلات لوحة المفاتيح زي الكاسيو.
  bool _shift = false;
  bool _alpha = false;

  /// موضع المؤشر داخل النص (عشان الإدخال في النص مش في الآخر بس).
  int _cursor = 0;

  CalculatorState(this._store);

  String get input => _input;
  String get result => _result;
  bool get hasError => _hasError;
  bool get shift => _shift;
  bool get alpha => _alpha;
  int get cursor => _cursor.clamp(0, _input.length);

  AngleMode get angleMode => engine.angleMode;
  NumberBase get numberBase => engine.numberBase;
  List<CalcHistoryEntry> get history => List.unmodifiable(engine.history);
  double get memoryValue => engine.memoryRecall();
  bool get hasMemory => engine.memoryRecall() != 0;

  Future<void> load() async {
    engine.angleMode = AngleMode.fromId(
      _store.readString(StoreKeys.calcAngleMode),
    );
    final baseRadix = _store.readInt(StoreKeys.calcBase, fallback: 10);
    engine.numberBase = NumberBase.fromRadix(baseRadix);

    final saved = _store.readList(
      StoreKeys.calcHistory,
      CalcHistoryEntry.fromJson,
    );
    engine.history
      ..clear()
      ..addAll(saved);

    final vars = _store.readObject(StoreKeys.calcVariables);
    if (vars != null) {
      vars.forEach((key, value) {
        final number =
            value is num ? value.toDouble() : double.tryParse('$value');
        if (number != null) engine.context.write(key, number);
      });
    }
    notifyListeners();
  }

  // ----- الإدخال -----

  /// إدخال نص عند موضع المؤشر.
  void insert(String text) {
    final position = cursor;
    _input = _input.substring(0, position) + text + _input.substring(position);
    _cursor = position + text.length;
    _hasError = false;
    _clearModifiers();
    notifyListeners();
  }

  /// حذف الحرف اللي قبل المؤشر (زر DEL).
  void deleteBackward() {
    final position = cursor;
    if (position == 0) return;
    _input = _input.substring(0, position - 1) + _input.substring(position);
    _cursor = position - 1;
    _hasError = false;
    notifyListeners();
  }

  /// مسح كامل (زر AC).
  void clearAll() {
    _input = '';
    _result = '0';
    _cursor = 0;
    _hasError = false;
    _clearModifiers();
    notifyListeners();
  }

  void moveCursor(int delta) {
    _cursor = (cursor + delta).clamp(0, _input.length);
    notifyListeners();
  }

  void setCursor(int position) {
    _cursor = position.clamp(0, _input.length);
    notifyListeners();
  }

  void toggleShift() {
    _shift = !_shift;
    if (_shift) _alpha = false;
    notifyListeners();
  }

  void toggleAlpha() {
    _alpha = !_alpha;
    if (_alpha) _shift = false;
    notifyListeners();
  }

  void _clearModifiers() {
    _shift = false;
    _alpha = false;
  }

  // ----- الحساب -----

  Future<void> evaluate() async {
    if (_input.trim().isEmpty) return;

    final outcome = engine.evaluate(_input);
    _result = outcome.display;
    _hasError = !outcome.isSuccess;
    _clearModifiers();
    notifyListeners();

    if (outcome.isSuccess) {
      await _persistHistory();
      await _persistVariables();
    }
  }

  /// استخدام نتيجة سابقة من شريط التاريخ.
  void useHistoryEntry(CalcHistoryEntry entry) {
    _input = entry.result;
    _cursor = _input.length;
    _result = entry.result;
    _hasError = false;
    notifyListeners();
  }

  void useHistoryExpression(CalcHistoryEntry entry) {
    _input = entry.expression;
    _cursor = _input.length;
    _hasError = false;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    engine.clearHistory();
    await _store.remove(StoreKeys.calcHistory);
    notifyListeners();
  }

  // ----- الأوضاع -----

  Future<void> setAngleMode(AngleMode mode) async {
    engine.angleMode = mode;
    await _store.writeString(StoreKeys.calcAngleMode, mode.id);
    notifyListeners();
  }

  Future<void> setNumberBase(NumberBase base) async {
    engine.numberBase = base;
    await _store.writeInt(StoreKeys.calcBase, base.radix);
    notifyListeners();
  }

  // ----- الذاكرة -----

  /// M+ و M− بيشتغلوا على النتيجة الحالية.
  Future<void> memoryAdd() async {
    final value = _currentValue();
    if (value == null) return;
    engine.memoryAdd(value);
    await _persistVariables();
    notifyListeners();
  }

  Future<void> memorySubtract() async {
    final value = _currentValue();
    if (value == null) return;
    engine.memorySubtract(value);
    await _persistVariables();
    notifyListeners();
  }

  void memoryRecall() => insert('M');

  Future<void> memoryClear() async {
    engine.memoryClear();
    await _persistVariables();
    notifyListeners();
  }

  Future<void> store(String variable) async {
    final value = _currentValue();
    if (value == null) return;
    engine.store(variable, value);
    await _persistVariables();
    notifyListeners();
  }

  /// قيمة النتيجة الحالية، أو نتيجة تقييم المدخل لو لسه ما اتحسبش.
  double? _currentValue() {
    if (_input.trim().isEmpty) return engine.context.ans;
    final outcome = engine.evaluate(_input, recordHistory: false);
    return outcome.isSuccess ? outcome.value : null;
  }

  Future<void> _persistHistory() => _store.writeList(
        StoreKeys.calcHistory,
        engine.history,
        (entry) => entry.toJson(),
      );

  Future<void> _persistVariables() =>
      _store.writeObject(StoreKeys.calcVariables, engine.context.variables);
}
