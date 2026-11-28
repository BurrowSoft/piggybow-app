import 'package:flutter/material.dart';

import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/theme.dart';

/// The nine categories, three to a row; each row as tall as its tallest
/// label (large text wraps, never cuts). The Add sheet and a repeat's page
/// use it; each cell's Semantics id is `<idPrefix>-<category id>`.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.selected,
    required this.onPick,
    this.idPrefix = 'add-cat',
  });

  final SpendCategory? selected;
  final ValueChanged<SpendCategory> onPick;
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    const all = SpendCategory.values;
    // One size for the nine labels: each word whole in its cell (a third of
    // the row, less the gaps and padding), smaller only when it must.
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = wholeWordsScaler(
          context,
          texts: [for (final c in all) c.label(l10n)],
          style: theme.textTheme.bodySmall,
          available: (box.maxWidth - 16) / 3 - 16,
        );
        return Column(
          children: [
            for (var row = 0; row < all.length; row += 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, c) in all.skip(row).take(3).indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: TestId(
                            '$idPrefix-${c.id}',
                            button: true,
                            selected: selected == c,
                            child: Material(
                              color: selected == c
                                  ? context.palette.pillBackground
                                  : theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: selected == c
                                      ? accent
                                      : theme.colorScheme.outlineVariant,
                                  width: selected == c ? 2 : 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onPick(c),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 72,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          c.icon,
                                          color: selected == c ? accent : null,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          c.label(l10n),
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall,
                                          textScaler: scaler,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
