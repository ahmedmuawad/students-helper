import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../calc/calculator_engine.dart';
import '../../core/l10n/app_strings.dart';
import '../../state/app_state.dart';
import '../../state/calculator_state.dart';
import '../common/ui_helpers.dart';
import 'calc_keypad.dart';

/// شاشة الآلة الحاسبة العلمية.
class CalculatorScreen extends StatelessWidget {
  const CalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final calc = context.watch<CalculatorState>();
    final s = AppStrings(context.watch<AppState>().languageCode);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.get('calculator')),
        actions: [
          IconButton(
            tooltip: s.get('calc_history'),
            icon: const Icon(Icons.history),
            onPressed: () => _showHistory(context, calc, s),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Column(
            children: [
              _Display(state: calc),
              const SizedBox(height: 10),
              Expanded(child: CalcKeypad(state: calc)),
            ],
          ),
        ),
      ),
    );
  }

  void _showHistory(BuildContext context, CalculatorState calc, AppStrings s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, controller) {
            final history = calc.history;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.get('calc_history'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (history.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            calc.clearHistory();
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text(s.get('calc_clear_history')),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: history.isEmpty
                      ? EmptyState(
                          icon: Icons.history,
                          message: s.get('empty_state'),
                        )
                      : ListView.separated(
                          controller: controller,
                          itemCount: history.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = history[index];
                            return _HistoryTile(
                              entry: entry,
                              onUseResult: () {
                                calc.useHistoryEntry(entry);
                                Navigator.pop(context);
                              },
                              onUseExpression: () {
                                calc.useHistoryExpression(entry);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// شاشة العرض: المعادلة فوق والنتيجة تحت مع مؤشرات الأوضاع.
class _Display extends StatelessWidget {
  final CalculatorState state;

  const _Display({required this.state});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10161A) : const Color(0xFFDDE7DC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3238) : const Color(0xFFB9C6B8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // مؤشرات الحالة أعلى الشاشة زي الكاسيو
          Row(
            children: [
              if (state.shift) const _Indicator('SHIFT'),
              if (state.alpha) const _Indicator('ALPHA'),
              if (state.hasMemory) const _Indicator('M'),
              const Spacer(),
              if (state.numberBase.radix != 10)
                _Indicator(state.numberBase.label),
              _Indicator(state.angleMode.shortLabel),
            ],
          ),
          const SizedBox(height: 6),

          // المعادلة المدخلة
          SizedBox(
            height: 26,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  state.input.isEmpty ? '0' : state.input,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 19,
                    fontFamily: 'monospace',
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // النتيجة
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: GestureDetector(
                  onLongPress: () async {
                    await Clipboard.setData(ClipboardData(text: state.result));
                    if (context.mounted) {
                      showSnack(context, 'اتنسخت');
                    }
                  },
                  child: Text(
                    state.result,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: state.hasError ? scheme.error : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  final String label;

  const _Indicator(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final CalcHistoryEntry entry;
  final VoidCallback onUseResult;
  final VoidCallback onUseExpression;

  const _HistoryTile({
    required this.entry,
    required this.onUseResult,
    required this.onUseExpression,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        entry.expression,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      subtitle: Text(
        '= ${entry.result}',
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
      onTap: onUseResult,
      trailing: IconButton(
        tooltip: 'تعديل المعادلة',
        icon: const Icon(Icons.edit_outlined, size: 19),
        onPressed: onUseExpression,
      ),
    );
  }
}
