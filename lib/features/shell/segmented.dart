import 'package:flutter/material.dart';

import '../../core/semantics_id.dart';
import '../../theme/theme.dart';

/// A row of equal segments in one pill (the approved review: Timeline's
/// All days / Moments, Insights' ranges). The selected one takes the accent
/// (colour-roles §3); each segment is a ≥ 48 dp button exposing selected.
class PiggybowSegmented<T> extends StatelessWidget {
  const PiggybowSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  /// (id, label, value) per segment, in order.
  final List<(String, String, T)> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme.labelLarge;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.pillBackground,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          for (final (id, label, value) in segments)
            Expanded(
              child: TestId(
                id,
                button: true,
                selected: value == selected,
                child: Material(
                  color: value == selected
                      ? palette.accent
                      : Colors.transparent,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(value),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          // One line that shrinks to fit at large text, never
                          // broken mid-word ("Calend / ar", 03 M15).
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              softWrap: false,
                              style: text?.copyWith(
                                color: value == selected
                                    ? palette.onAccent
                                    : palette.text,
                              ),
                            ),
                          ),
                        ),
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
