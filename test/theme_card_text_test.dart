import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/theme/theme.dart';

/// The cards' body text (onSurfaceVariant: a card's line under its title,
/// and today's idea, decision 57) is 4.5:1 on a card in every palette, light
/// and dark, with dark mode's lighter cards (decision 58).
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
    for (final brightness in Brightness.values) {
      final name = '${plus?.name ?? 'default'} ${brightness.name}';
      test('$name: the cards\' body text 4.5:1 on a card', () {
        final s = buildTheme(brightness, plusPalette: plus).colorScheme;
        expect(
          contrast(s.onSurfaceVariant, s.surfaceContainerLow),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  }
}
