import 'package:flutter/material.dart';

/// The weekly plan's bar (plan §3.3, §3.7): spent ÷ plan as a whole
/// [percent], simply full at or over the plan, always the accent (never a
/// warning colour). Home's week card and Summary's plan card show it; the
/// amounts beside it carry the meaning, so the bar itself is silent.
class PlanBar extends StatelessWidget {
  const PlanBar({super.key, required this.percent});

  /// floor(spent × 100 ÷ plan); anything over 100 draws as 100.
  final int percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: LinearProgressIndicator(
        value: percent.clamp(0, 100) / 100,
        color: scheme.primary,
        backgroundColor: scheme.surfaceContainerHighest,
        minHeight: 8,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
