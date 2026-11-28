import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/goal/rainbow.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/theme/theme.dart';

/// Piggybow's themes (plus-spec §1): Strawberry, the default, and the Plus
/// themes Plum, Apricot and Blueberry. Every theme passes WCAG AA (4.5:1) for
/// body text and buttons, light and dark: on its own colours and on the
/// Material colours the screens use (cards, the Add button). The rainbow's
/// arcs stay clear on their empty track in dark (3:1, a graphic). What's
/// shown follows Plus as it is now; only the choice's name is kept.
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

  const themes = <PlusPalette?>[null, ...PlusPalette.values];
  String nameOf(PlusPalette? p) => p?.name ?? 'strawberry';

  group('contrast', () {
    for (final p in themes) {
      for (final b in Brightness.values) {
        test('${nameOf(p)} ${b.name}: every text and button 4.5:1', () {
          final c = paletteColours(p, b);
          final s = buildTheme(b, plusPalette: p).colorScheme;
          for (final (name, fg, bg) in [
            // The theme's own colours.
            ('text/page', c.text, c.background),
            ('muted/page', c.mutedText, c.background),
            ('accent/page', c.accent, c.background),
            ('button label/button', c.onAccent, c.accent),
            ('text/pill', c.text, c.pillBackground),
            ('accent/pill', c.accent, c.pillBackground),
            ('muted/pill', c.mutedText, c.pillBackground),
            // Material's, seeded from the theme: Home's cards (Card's
            // colour) and Add button, the raised boxes.
            ('text/card', c.text, s.surfaceContainerLow),
            ('muted/card', c.mutedText, s.surfaceContainerLow),
            ('accent/card', c.accent, s.surfaceContainerLow),
            ('Add label/Add', s.onPrimaryContainer, s.primaryContainer),
            ('text/raised box', c.text, s.surfaceContainerHighest),
          ]) {
            expect(
              contrast(fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '${nameOf(p)} ${b.name}: $name',
            );
          }
        });
      }

      test('${nameOf(p)} dark: every rainbow arc 3:1 on its empty track', () {
        final track = paletteColours(p, Brightness.dark).rainbowTrack;
        for (final arc in Rainbow.arcColours) {
          expect(
            contrast(arc, track),
            greaterThanOrEqualTo(3),
            reason: '${nameOf(p)}: $arc',
          );
        }
      });
    }
  });

  group('Strawberry, the default, unchanged', () {
    test('its colours, its seed and its tracks', () {
      expect(paletteColours(null, Brightness.light), PiggybowPalette.light);
      expect(paletteColours(null, Brightness.dark), PiggybowPalette.dark);
      expect(paletteSeed(null), PiggybowColors.rose);
      expect(PiggybowPalette.light.rainbowTrack, const Color(0xFFECE6F0));
      expect(PiggybowPalette.dark.rainbowTrack, const Color(0xFF3A3350));
    });

    test('each Plus theme seeds its own colours, and its own dark track', () {
      final seeds = {for (final p in themes) paletteSeed(p)};
      expect(seeds, hasLength(themes.length));
      for (final p in PlusPalette.values) {
        expect(
          paletteColours(p, Brightness.dark).rainbowTrack,
          isNot(PiggybowPalette.dark.rainbowTrack),
          reason: p.name,
        );
      }
    });

    test('the Plus themes, by their Piggybow names', () {
      expect(PlusPalette.values.map((p) => p.name), [
        'plum',
        'apricot',
        'blueberry',
      ]);
    });
  });

  group('the choice', () {
    test('kept by name; anything else is Strawberry', () {
      expect(paletteByName('plum'), PlusPalette.plum);
      expect(paletteByName('blueberry'), PlusPalette.blueberry);
      expect(
        paletteByName('apricot@2027-01-01T00:00:00.000Z'),
        PlusPalette.apricot,
        reason: 'a value with a date after it reads as its name',
      );
      expect(paletteByName('mauve'), isNull, reason: 'not a Piggybow theme');
      expect(paletteByName(''), isNull);
      expect(paletteByName(null), isNull);
    });

    test('shown only while Plus is active', () {
      expect(
        appliedPalette(PlusPalette.plum, plusActive: true),
        PlusPalette.plum,
      );
      expect(appliedPalette(PlusPalette.plum, plusActive: false), isNull);
      expect(appliedPalette(null, plusActive: true), isNull);
    });
  });
}
