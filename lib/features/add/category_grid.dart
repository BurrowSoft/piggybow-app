import 'package:flutter/material.dart';

import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/theme.dart';

/// One cell of the category grid: a category, or Add category ([selected]
/// null: an action, never picked).
class CategoryTile {
  const CategoryTile({
    required this.id,
    required this.label,
    required this.icon,
    this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool? selected;
  final VoidCallback onTap;
}

/// A tile for each of [ids] (offeredCategories), [picked] selected. Each
/// cell's Semantics id is `<idPrefix>-<built-in id>`, or for your own
/// `<idPrefix>-custom-<n>`, n counting [customs] from 1, oldest first.
List<CategoryTile> categoryTiles(
  AppLocalizations l10n, {
  required List<String> ids,
  required List<CustomCategory> customs,
  required String? picked,
  required String idPrefix,
  required ValueChanged<String> onPick,
}) {
  final byId = {for (final c in customs) c.id: c};
  final number = {for (final (i, c) in customs.indexed) c.id: i + 1};
  return [
    for (final id in ids)
      CategoryTile(
        id: number.containsKey(id)
            ? '$idPrefix-custom-${number[id]}'
            : '$idPrefix-$id',
        label: categoryName(l10n, id, byId),
        icon: categoryIcon(id, byId),
        selected: id == picked,
        onTap: () => onPick(id),
      ),
  ];
}

/// The tiles, three to a row (a short last row keeps the same cell width);
/// each row as tall as its tallest label (large text wraps, never cuts).
/// The Add sheet and a repeat's page use it.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, required this.tiles});

  final List<CategoryTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    // One size for every label: each word whole in its cell (a third of the
    // row, less the gaps and padding), smaller only when it must.
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = wholeWordsScaler(
          context,
          texts: [for (final t in tiles) t.label],
          style: theme.textTheme.bodySmall,
          available: (box.maxWidth - 16) / 3 - 16,
        );
        Widget cell(CategoryTile t) {
          final on = t.selected ?? false;
          return TestId(
            t.id,
            button: true,
            selected: t.selected,
            child: Material(
              color: on
                  ? context.palette.pillBackground
                  : theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: on ? accent : theme.colorScheme.outlineVariant,
                  width: on ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: t.onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.icon, color: on ? accent : null),
                        const SizedBox(height: 4),
                        Text(
                          t.label,
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
          );
        }

        return Column(
          children: [
            for (var row = 0; row < tiles.length; row += 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: row + i < tiles.length
                              ? cell(tiles[row + i])
                              : const SizedBox.shrink(),
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
