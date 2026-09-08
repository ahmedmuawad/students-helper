import 'package:flutter/material.dart';

import '../../calc/eval_context.dart';
import '../../state/calculator_state.dart';
import 'calc_key.dart';

/// لوحة مفاتيح الآلة الحاسبة بتخطيط قريب من كاسيو fx-991ES PLUS.
class CalcKeypad extends StatelessWidget {
  final CalculatorState state;

  const CalcKeypad({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // ارتفاع الصف يتوزّع على المساحة المتاحة مع حد أدنى مريح للإصبع.
        final rowHeight =
            ((constraints.maxHeight - (rows.length - 1) * 6) / rows.length)
                .clamp(44.0, 70.0);

        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    for (var j = 0; j < rows[i].length; j++) ...[
                      Expanded(
                        child: _KeyButton(spec: rows[i][j], state: state),
                      ),
                      if (j != rows[i].length - 1) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              if (i != rows.length - 1) const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }

  List<List<CalcKey>> _buildRows(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = const Color(0xFFF5A623);
    final danger = const Color(0xFFE53935);

    return [
      // ---- صف المُعدِّلات والتنقل ----
      [
        CalcKey(
          label: 'SHIFT',
          fontSize: 12,
          background: const Color(0xFFB08968),
          foreground: Colors.white,
          onPrimary: (s) => s.toggleShift(),
        ),
        CalcKey(
          label: 'ALPHA',
          fontSize: 12,
          background: const Color(0xFF7C9BB5),
          foreground: Colors.white,
          onPrimary: (s) => s.toggleAlpha(),
        ),
        CalcKey(label: '◀', fontSize: 15, onPrimary: (s) => s.moveCursor(-1)),
        CalcKey(label: '▶', fontSize: 15, onPrimary: (s) => s.moveCursor(1)),
        CalcKey(
          label: 'MODE',
          fontSize: 12,
          onPrimary: (s) => _showModeSheet(context, s),
        ),
      ],

      // ---- دوال متقدمة (اللي في صورة الكاسيو) ----
      [
        CalcKey.insert(
          '∫dx',
          'integrate(',
          fontSize: 13,
          shiftLabel: 'd/dx',
          shiftText: 'derivative(',
        ),
        CalcKey.insert('Σ', 'Σ(', fontSize: 15),
        CalcKey.insert(
          'x⁻¹',
          '^-1',
          fontSize: 13,
          shiftLabel: 'x!',
          shiftText: '!',
        ),
        CalcKey.insert(
          'nPr',
          'nPr',
          fontSize: 12,
          shiftLabel: 'nCr',
          shiftText: 'nCr',
        ),
        CalcKey.insert(
          'log□',
          'log(',
          fontSize: 12,
          shiftLabel: '10ˣ',
          shiftText: '10^',
        ),
      ],

      // ---- أسس وجذور ولوغاريتمات ----
      [
        CalcKey.insert(
          '√',
          'sqrt(',
          fontSize: 17,
          shiftLabel: '∛',
          shiftText: 'cbrt(',
        ),
        CalcKey.insert(
          'x²',
          '²',
          fontSize: 14,
          shiftLabel: 'x³',
          shiftText: '³',
        ),
        CalcKey.insert(
          'xʸ',
          '^',
          fontSize: 14,
          shiftLabel: 'ˣ√y',
          shiftText: 'root(',
        ),
        CalcKey.insert(
          'log',
          'log(',
          fontSize: 14,
          shiftLabel: '10ˣ',
          shiftText: '10^',
        ),
        CalcKey.insert(
          'ln',
          'ln(',
          fontSize: 14,
          shiftLabel: 'eˣ',
          shiftText: 'exp(',
        ),
      ],

      // ---- مثلثات ----
      [
        CalcKey.insert('(-)', '-', fontSize: 14),
        CalcKey.insert(
          'hyp',
          'sinh(',
          fontSize: 12,
          shiftLabel: 'hyp⁻¹',
          shiftText: 'asinh(',
        ),
        CalcKey.insert(
          'sin',
          'sin(',
          fontSize: 14,
          shiftLabel: 'sin⁻¹',
          shiftText: 'asin(',
          alphaLabel: 'sinh',
          alphaText: 'sinh(',
        ),
        CalcKey.insert(
          'cos',
          'cos(',
          fontSize: 14,
          shiftLabel: 'cos⁻¹',
          shiftText: 'acos(',
          alphaLabel: 'cosh',
          alphaText: 'cosh(',
        ),
        CalcKey.insert(
          'tan',
          'tan(',
          fontSize: 14,
          shiftLabel: 'tan⁻¹',
          shiftText: 'atan(',
          alphaLabel: 'tanh',
          alphaText: 'tanh(',
        ),
      ],

      // ---- ذاكرة وأقواس ----
      [
        CalcKey(
          label: 'RCL',
          fontSize: 12,
          shiftLabel: 'STO',
          onPrimary: (s) => _showVariablesSheet(context, s, store: false),
          onShift: (s) => _showVariablesSheet(context, s, store: true),
        ),
        CalcKey.insert(
          'π',
          'pi',
          fontSize: 16,
          shiftLabel: 'e',
          shiftText: 'e',
        ),
        CalcKey.insert('(', '(', fontSize: 16),
        CalcKey.insert(')', ')', fontSize: 16),
        CalcKey(
          label: 'M+',
          fontSize: 13,
          shiftLabel: 'M−',
          alphaLabel: 'MC',
          onPrimary: (s) => s.memoryAdd(),
          onShift: (s) => s.memorySubtract(),
          onAlpha: (s) => s.memoryClear(),
        ),
      ],

      // ---- الأرقام ----
      [
        CalcKey.insert('7', '7', fontSize: 19),
        CalcKey.insert('8', '8', fontSize: 19),
        CalcKey.insert('9', '9', fontSize: 19),
        CalcKey(
          label: 'DEL',
          fontSize: 13,
          background: scheme.surfaceContainerHighest,
          onPrimary: (s) => s.deleteBackward(),
        ),
        CalcKey(
          label: 'AC',
          fontSize: 14,
          background: danger,
          foreground: Colors.white,
          onPrimary: (s) => s.clearAll(),
        ),
      ],
      [
        CalcKey.insert('4', '4', fontSize: 19),
        CalcKey.insert('5', '5', fontSize: 19),
        CalcKey.insert('6', '6', fontSize: 19),
        CalcKey.insert('×', '*', fontSize: 19),
        CalcKey.insert('÷', '/', fontSize: 19),
      ],
      [
        CalcKey.insert('1', '1', fontSize: 19),
        CalcKey.insert('2', '2', fontSize: 19),
        CalcKey.insert('3', '3', fontSize: 19),
        CalcKey.insert('+', '+', fontSize: 19),
        CalcKey.insert('−', '-', fontSize: 19),
      ],
      [
        CalcKey.insert('0', '0', fontSize: 19),
        CalcKey.insert('.', '.', fontSize: 19),
        CalcKey.insert('×10ˣ', 'E', fontSize: 12),
        CalcKey.insert(
          'Ans',
          'Ans',
          fontSize: 13,
          shiftLabel: '%',
          shiftText: '%',
        ),
        CalcKey(
          label: '=',
          fontSize: 21,
          background: accent,
          foreground: Colors.white,
          onPrimary: (s) => s.evaluate(),
        ),
      ],
    ];
  }

  // ---- أوراق الإعدادات ----

  void _showModeSheet(BuildContext context, CalculatorState state) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'وحدة الزوايا',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in AngleMode.values)
                    ChoiceChip(
                      label: Text(mode.shortLabel),
                      selected: state.angleMode == mode,
                      onSelected: (_) {
                        state.setAngleMode(mode);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'أساس العد',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final base in NumberBase.values)
                    ChoiceChip(
                      label: Text(base.label),
                      selected: state.numberBase == base,
                      onSelected: (_) {
                        state.setNumberBase(base);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVariablesSheet(
    BuildContext context,
    CalculatorState state, {
    required bool store,
  }) {
    const variables = ['A', 'B', 'C', 'D', 'X', 'Y', 'M'];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store
                    ? 'تخزين النتيجة في متغيّر (STO)'
                    : 'استدعاء متغيّر (RCL)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final variable in variables)
                    ActionChip(
                      label: Text(
                        '$variable = ${state.engine.recall(variable)}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      onPressed: () {
                        if (store) {
                          state.store(variable);
                        } else {
                          state.insert(variable);
                        }
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final CalcKey spec;
  final CalculatorState state;

  const _KeyButton({required this.spec, required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final background =
        spec.background ?? (isDark ? const Color(0xFF23272C) : Colors.white);
    final foreground = spec.foreground ?? scheme.onSurface;

    // النص الثانوي (وظيفة SHIFT) بيظهر فوق الزر بلون مميز زي الكاسيو.
    final secondary = spec.shiftLabel;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => spec.press(state),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF32373D) : const Color(0xFFDFE4E9),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (secondary != null)
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1,
                    color: Color(0xFFC08552),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                spec.displayLabel(state),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: spec.fontSize,
                  height: 1.15,
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
