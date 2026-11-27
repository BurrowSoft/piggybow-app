import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/theme/theme.dart';

/// Dark mode's raised surfaces (decision 58): cards, sheets, dialogs and
/// menus a step lighter than the page, never darker, in every palette, with
/// every text still 4.5:1 on them. Light mode is unchanged.
void main() {
  double luminance(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final plus in [null, ...PlusPalette.values]) {
    final name = plus?.name ?? 'default';
    test(
      '$name dark: every raised surface lighter than the page, stepping up',
      () {
        final theme = buildTheme(Brightness.dark, plusPalette: plus);
        final s = theme.colorScheme;
        final page = theme.scaffoldBackgroundColor;
        final steps = [
          ('lowest', s.surfaceContainerLowest),
          ('low (cards, sheets)', s.surfaceContainerLow),
          ('container (menus)', s.surfaceContainer),
          ('high (dialogs)', s.surfaceContainerHigh),
          ('highest', s.surfaceContainerHighest),
        ];
        var below = luminance(page);
        for (final (which, color) in steps) {
          expect(luminance(color), greaterThan(below), reason: which);
          below = luminance(color);
        }
      },
    );

    test('$name dark: every text still 4.5:1 on the raised surfaces', () {
      final theme = buildTheme(Brightness.dark, plusPalette: plus);
      final palette = paletteColours(plus, Brightness.dark);
      final s = theme.colorScheme;
      // Cards and sheets (low) carry body, muted and accent text (a saved
      // amount); dialogs (high) carry body and muted text.
      for (final (which, bg, colours) in [
        (
          'low',
          s.surfaceContainerLow,
          [palette.text, palette.mutedText, palette.accent],
        ),
        ('high', s.surfaceContainerHigh, [palette.text, palette.mutedText]),
      ]) {
        for (final color in colours) {
          expect(
            contrast(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$color on $which',
          );
        }
      }
    });
  }

  test('light mode keeps the seeded surfaces', () {
    final theme = buildTheme(Brightness.light);
    final seeded = ColorScheme.fromSeed(
      seedColor: PiggybowColors.rose,
      brightness: Brightness.light,
    );
    expect(theme.colorScheme.surfaceContainerLow, seeded.surfaceContainerLow);
    expect(
      theme.colorScheme.surfaceContainerHighest,
      seeded.surfaceContainerHighest,
    );
  });

  testWidgets('a dark Card and a dark sheet are lighter than the page', (
    tester,
  ) async {
    final theme = buildTheme(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Card(child: SizedBox(width: 50, height: 50)),
        ),
      ),
    );
    final card = tester.widget<Material>(
      find.descendant(of: find.byType(Card), matching: find.byType(Material)),
    );
    expect(
      luminance(card.color!),
      greaterThan(luminance(theme.scaffoldBackgroundColor)),
    );
    // A modal bottom sheet takes the same tone (Material 3's default).
    final sheet =
        theme.bottomSheetTheme.backgroundColor ??
        theme.colorScheme.surfaceContainerLow;
    expect(
      luminance(sheet),
      greaterThan(luminance(theme.scaffoldBackgroundColor)),
    );
  });
}
