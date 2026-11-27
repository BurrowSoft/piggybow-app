import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/goldens.dart';

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
  if (c.takesGolden) {
    // A focused field's caret drawn steadily, never mid-blink: its phase
    // would otherwise depend on how many frames the test pumped. Set before
    // any field is focused, as the blink reads it when it starts.
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
  }
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
        _wordChar.hasMatch(before) && _wordChar.hasMatch(after),
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

/// Goldens (decision 44) are taken in two of the matrix's cases: 320 dp at
/// text ×2, light and dark.
extension LayoutGolden on LayoutCase {
  bool get takesGolden => width == 320 && textScale == 2;
}

/// The whole screen as a golden, named for [c] (call it only when
/// [LayoutGolden.takesGolden]); [stateId] is the state's id in PB Mobile
/// Tester's list. The file that calls it is tagged golden.
Future<void> expectLayoutGolden(
  WidgetTester tester,
  LayoutCase c, {
  required String screen,
  required String state,
  required String stateId,
}) {
  if (!c.takesGolden) {
    throw ArgumentError.value(c, 'c', 'goldens are taken at 320 dp ×2 only');
  }
  return expectGolden(
    tester,
    find.byType(MaterialApp),
    screen: screen,
    state: state,
    stateId: stateId,
    brightness: c.brightness,
    width: c.width.toInt(),
    textScale: c.textScale.toInt(),
  );
}

/// Takes the focus away (no caret in a golden), and scrolls [scrollable] to
/// its top or its end. Returns how far it can scroll.
Future<double> settleForGolden(
  WidgetTester tester,
  Finder scrollable, {
  required bool end,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(end ? position.maxScrollExtent : 0);
  await tester.pumpAndSettle();
  return position.maxScrollExtent;
}

/// A screen that scrolls, as goldens: its top as [state], and, when
/// [scrollable] can scroll at all, its end as "[state]-end".
Future<void> expectLayoutGoldens(
  WidgetTester tester,
  LayoutCase c,
  Finder scrollable, {
  required String screen,
  required String state,
  required String stateId,
}) async {
  final scrolls = await settleForGolden(tester, scrollable, end: false);
  await expectLayoutGolden(
    tester,
    c,
    screen: screen,
    state: state,
    stateId: stateId,
  );
  if (scrolls <= 0) return;
  await settleForGolden(tester, scrollable, end: true);
  await expectLayoutGolden(
    tester,
    c,
    screen: screen,
    state: '$state-end',
    stateId: stateId,
  );
}
