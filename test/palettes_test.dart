import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/theme/theme.dart';

/// Plus's extra themes (the plumbing; no Plus UI in v0.1): 4.5:1 for every
/// text on every background it sits on; the date rule.
void main() {
  double luminance(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  group('colours', () {
    for (final p in PlusPalette.values) {
      for (final b in Brightness.values) {
        test('${p.name} ${b.name}: every text 4.5:1 on its backgrounds', () {
          final c = paletteColours(p, b);
          for (final (name, fg, bg) in [
            ('text/background', c.text, c.background),
            ('text/pill', c.text, c.pillBackground),
            ('muted/background', c.mutedText, c.background),
            ('muted/pill', c.mutedText, c.pillBackground),
            ('accent/background', c.accent, c.background),
            ('accent/pill', c.accent, c.pillBackground),
            ('onAccent/accent', c.onAccent, c.accent),
          ]) {
            expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
          }
        });
      }
    }

    test('null is the default', () {
      expect(paletteColours(null, Brightness.light), PiggybowPalette.light);
      expect(paletteColours(null, Brightness.dark), PiggybowPalette.dark);
    });
  });

  group('the date rule', () {
    final now = DateTime.utc(2026, 10, 2);
    test('a palette while its date is ahead, the default past it', () {
      expect(parsePalette('dusk@2027-01-01T00:00:00.000Z', now), PlusPalette.dusk);
      expect(parsePalette('dusk@2026-10-01T00:00:00.000Z', now), isNull);
      expect(parsePalette('dusk', now), isNull);
      expect(parsePalette('mauve@2027-01-01T00:00:00.000Z', now), isNull);
      expect(parsePalette(null, now), isNull);
    });

    test('the name survives its date (a renewal brings it back)', () {
      expect(storedPaletteName('sea@2020-01-01T00:00:00.000Z'), PlusPalette.sea);
      expect(encodePalette(PlusPalette.sea, DateTime.utc(2027)), 'sea@2027-01-01T00:00:00.000Z');
    });
  });
}
