import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The layout matrix (plan §0.3, decision 43): every state runs at 320 and
/// 360 dp, text ×1 and ×2, light and dark (through the app's own setting).
class LayoutCase {
  const LayoutCase(this.width, this.textScale, this.brightness);

  final double width;
  final double textScale;
  final Brightness brightness;

  /// The app's appearance setting for [brightness].
  String get appearance => brightness == Brightness.dark ? 'dark' : 'light';

  @override
  String toString() =>
      '${width.toInt()} dp, text ×${textScale.toInt()}, ${brightness.name}';
}

final layoutCases = [
  for (final width in [320.0, 360.0])
    for (final scale in [1.0, 2.0])
      for (final brightness in [Brightness.light, Brightness.dark])
        LayoutCase(width, scale, brightness),
];

/// A phone of [c]'s width (780 dp tall), at its text scale; [keyboard] dp of
/// on-screen keyboard at the bottom.
void setLayout(WidgetTester tester, LayoutCase c, {double keyboard = 0}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(c.width * 3, 780 * 3);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
  tester.platformDispatcher.textScaleFactorTestValue = c.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// What every state must hold: no overflow or layout error; every tap area
/// at least 48 × 48 dp, with a label; no word broken in the middle; no line
/// that is only "?" or "…".
Future<void> expectSoundLayout(WidgetTester tester, {String? reason}) async {
  expect(
    tester.takeException(),
    isNull,
    reason: 'no overflow or layout error: $reason',
  );
  await expectLater(
    tester,
    meetsGuideline(androidTapTargetGuideline),
    reason: reason,
  );
  await expectLater(
    tester,
    meetsGuideline(labeledTapTargetGuideline),
    reason: reason,
  );
  expectWholeWords(tester, reason: reason);
}

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// What a formatted amount is made of: digits, its separators, its symbol.
final _amountChar = RegExp(r'[\p{N}\p{Sc},.]', unicode: true);
final _digit = RegExp(r'\p{N}', unicode: true);

/// Whether a soft line break between [before] and [after] splits a word or
/// an amount: letters or digits on both sides, or an amount's characters on
/// both sides with a digit next to the break ("$9" | ",999").
bool splitsAWord(String before, String after) =>
    (_wordChar.hasMatch(before) && _wordChar.hasMatch(after)) ||
    (_amountChar.hasMatch(before) &&
        _amountChar.hasMatch(after) &&
        (_digit.hasMatch(before) || _digit.hasMatch(after)));

bool _isThai(String text) => text.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F);

/// Every soft line break on screen falls between words: never with a letter
/// or a digit on both sides. Thai is exempt (no spaces; it breaks by
/// dictionary).
void expectWholeWords(WidgetTester tester, {String? reason}) {
  var paragraphs = 0;
  for (final element in find.byType(RichText).evaluate()) {
    final p = element.renderObject;
    if (p is! RenderParagraph || !p.hasSize) continue;
    final text = p.text.toPlainText();
    if (text.isEmpty || _isThai(text)) continue;
    final painter = _painterOf(p);
    if (painter == null) continue;
    paragraphs++;
    var offset = 0;
    while (offset < text.length) {
      final line = painter.getLineBoundary(TextPosition(offset: offset));
      final content = text.substring(line.start, line.end).trim();
      expect(
        content == '?' || content == '…',
        isFalse,
        reason: 'a line of only "$content" in "$text" ($reason)',
      );
      if (line.end <= offset || line.end >= text.length) break;
      final before = text[line.end - 1];
      final after = text[line.end];
      expect(
        splitsAWord(before, after),
        isFalse,
        reason:
            'a word broken after "${text.substring(line.start, line.end)}" in "$text" ($reason)',
      );
      offset = line.end;
      while (offset < text.length && text[offset].trim().isEmpty) {
        offset++;
      }
    }
    painter.dispose();
  }
  expect(paragraphs, greaterThan(0), reason: 'some text was checked ($reason)');
}

/// [text] is on screen and on one line (an amount with its symbol).
void expectOneLine(WidgetTester tester, String text, {String? reason}) {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: '$text on screen ($reason)');
  for (final element in finder.evaluate()) {
    final p = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(RichText),
          )
          .first,
    );
    final painter = _painterOf(p)!;
    expect(
      painter.computeLineMetrics(),
      hasLength(1),
      reason: '"$text" on one line ($reason)',
    );
    painter.dispose();
  }
}

/// [p]'s text laid out again as it is on screen (same style, scale, width
/// and line limit), for its line breaks; null if it holds a widget.
TextPainter? _painterOf(RenderParagraph p) {
  var widgets = false;
  p.text.visitChildren((span) => !(widgets = span is PlaceholderSpan));
  if (widgets) return null;
  return TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textAlign: p.textAlign,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
    textHeightBehavior: p.textHeightBehavior,
    ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
  )..layout(maxWidth: p.softWrap ? p.size.width + 0.5 : double.infinity);
}
