import 'package:flutter/material.dart';

import '../../core/app_dialog.dart';
import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/palettes.dart';
import '../../theme/theme.dart';

/// Me → Theme (plus-spec §1): Strawberry, the default, and the Plus themes.

/// Every theme the picker offers, Strawberry (null) first.
const pickerThemes = <PlusPalette?>[null, ...PlusPalette.values];

/// A theme's name.
String themeName(AppLocalizations l10n, PlusPalette? theme) => switch (theme) {
  null => l10n.themeStrawberry,
  PlusPalette.plum => l10n.themePlum,
  PlusPalette.apricot => l10n.themeApricot,
  PlusPalette.blueberry => l10n.themeBlueberry,
};

/// Me → Theme's subtitle: the theme shown; when Plus has ended and a Plus
/// theme is still chosen, that it comes back with Plus.
String themeRowSubtitle(
  AppLocalizations l10n, {
  required PlusPalette? chosen,
  required bool plusActive,
}) => chosen != null && !plusActive
    ? l10n.meThemeComesBack(themeName(l10n, chosen))
    : themeName(l10n, appliedPalette(chosen, plusActive: plusActive));

/// The id of a theme's row in the picker.
String themeRowId(PlusPalette? theme) => 'theme-${theme?.name ?? 'strawberry'}';

/// The picker, with [shown] selected. Returns the tapped theme (a record, so
/// Strawberry, null, isn't a dismissal), or null when dismissed.
Future<({PlusPalette? theme})?> pickTheme(
  BuildContext context, {
  required PlusPalette? shown,
}) => showAppSheet<({PlusPalette? theme})>(
  context: context,
  builder: (context) => _ThemeSheet(shown: shown),
);

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.shown});

  final PlusPalette? shown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return TestId.container(
      'theme-sheet',
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(l10n.meTheme, style: theme.textTheme.titleLarge),
              ),
              // An index, not the theme: Strawberry is null, which a radio
              // group reads as "nothing selected".
              RadioGroup<int>(
                groupValue: pickerThemes.indexOf(shown),
                onChanged: (i) {
                  if (i != null) {
                    Navigator.of(context).pop((theme: pickerThemes[i]));
                  }
                },
                child: Column(
                  children: [
                    for (final (i, option) in pickerThemes.indexed)
                      TestId(
                        themeRowId(option),
                        child: RadioListTile<int>(
                          value: i,
                          title: _ThemeTitle(theme: option),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A theme's colour, its name, and "Plus" beside a Plus theme.
class _ThemeTitle extends StatelessWidget {
  const _ThemeTitle({required this.theme});

  final PlusPalette? theme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final colours = paletteColours(theme, Theme.of(context).brightness);
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colours.accent,
              shape: BoxShape.circle,
              border: Border.all(color: palette.mutedText),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(themeName(l10n, theme))),
        if (theme != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.pillBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              l10n.themePlusLabel,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: palette.accent),
            ),
          ),
        ],
      ],
    );
  }
}
