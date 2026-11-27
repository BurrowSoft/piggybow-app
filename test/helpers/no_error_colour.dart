import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The no-error-colour check, as an allow-list: every span of any text on
/// screen that contains one of [texts] (formatted amounts, the pig's line…)
/// must be painted in an allowed colour, or the test fails.
///
/// Allowed, read from each paragraph's own Theme (so a nested Theme counts):
/// the ink (`colorScheme.onSurface`), the muted ink
/// (`colorScheme.onSurfaceVariant`), and whatever [extra] adds for that theme,
/// e.g. the save accent: `extra: (t) => {t.colorScheme.primary}`.
///
/// Everything else fails: the error colours, a hard-coded red, a palette
/// colour, an allowed colour at another alpha, a `foreground` paint, and a
/// span whose colour can't be known (a root span with no colour).
///
/// Fails closed: if no paragraph contains any of [texts], nothing was
/// checked, and that is a failure too.
void expectOnlyAllowedColours(
  WidgetTester tester,
  Iterable<String> texts, {
  Set<Color> Function(ThemeData theme)? extra,
  String? reason,
}) {
  final wanted = texts.toList();
  final why = reason == null ? '' : ': $reason';
  var checked = 0;
  for (final element in find.byType(RichText).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph) continue;
    final plain = paragraph.text.toPlainText();
    if (!wanted.any(plain.contains)) continue;
    checked++;
    final theme = Theme.of(element);
    final allowed = <Color>{
      theme.colorScheme.onSurface,
      theme.colorScheme.onSurfaceVariant,
      ...?extra?.call(theme),
    };
    final root = paragraph.text;
    if (root.style?.color == null && root.style?.foreground == null) {
      fail('"$plain" has no known colour (root span without a colour)$why');
    }
    root.visitChildren((span) {
      final style = span.style;
      if (style == null) return true; // inherits from its parent, checked already
      if (style.foreground != null) {
        fail('"$plain" uses a foreground paint, which this check can\'t verify$why');
      }
      final colour = style.color;
      if (colour != null && !allowed.contains(colour)) {
        fail('"$plain" uses $colour, not ink, muted ink or an allowed accent$why');
      }
      return true;
    });
  }
  if (checked == 0) {
    fail('none of $wanted is on screen, so nothing was checked$why');
  }
}
