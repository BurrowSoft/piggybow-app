import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/button_pair.dart';

/// ButtonPair (decision 57): one line, at the end, when both buttons fit;
/// else full width, the primary on top and the secondary 8 dp under it.
void main() {
  final taps = <String>[];
  setUp(taps.clear);

  Widget pair(double width, {TextDirection direction = TextDirection.ltr}) =>
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: ButtonPair(
                  secondary: TextButton(
                    key: const Key('no'),
                    onPressed: () => taps.add('no'),
                    child: const Text('No thanks'),
                  ),
                  primary: FilledButton(
                    key: const Key('yes'),
                    onPressed: () => taps.add('yes'),
                    child: const Text('Remind me at 8 PM'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Rect rect(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(Key(key)));
  RenderButtonRow render(WidgetTester tester) =>
      tester.renderObject<RenderButtonRow>(find.byType(ButtonPair));

  /// The width both need side by side: their own widths plus the 8 dp.
  Future<double> rowWidth(WidgetTester tester) async {
    await tester.pumpWidget(pair(600));
    return rect(tester, 'no').width + 8 + rect(tester, 'yes').width;
  }

  testWidgets('room for both: one line at the end, No thanks first', (
    tester,
  ) async {
    final needed = await rowWidth(tester);
    expect(needed, lessThan(600));
    final no = rect(tester, 'no'), yes = rect(tester, 'yes');
    expect(render(tester).stacked, isFalse);
    expect(yes.right, 600, reason: 'at the end of the line');
    expect(no.right + 8, moreOrLessEquals(yes.left));
    expect(no.center.dy, moreOrLessEquals(yes.center.dy));
    expect(render(tester).size, Size(600, yes.height));
    expect(render(tester).getMaxIntrinsicWidth(double.infinity), needed);
  });

  testWidgets('right to left: the end is the left, No thanks nearer start', (
    tester,
  ) async {
    await tester.pumpWidget(pair(600, direction: TextDirection.rtl));
    final no = rect(tester, 'no'), yes = rect(tester, 'yes');
    expect(render(tester).stacked, isFalse);
    expect(yes.left, 0);
    expect(no.left, moreOrLessEquals(yes.right + 8));
  });

  testWidgets('exactly the width both need: still one line', (tester) async {
    final needed = await rowWidth(tester);
    await tester.pumpWidget(pair(needed));
    expect(render(tester).stacked, isFalse);
    expect(rect(tester, 'no').left, moreOrLessEquals(0));
    expect(rect(tester, 'yes').right, moreOrLessEquals(needed));
  });

  testWidgets('a hair less: stacked full width, the yes on top, 8 dp gap', (
    tester,
  ) async {
    final needed = await rowWidth(tester);
    final width = needed - 1;
    await tester.pumpWidget(pair(width));
    final no = rect(tester, 'no'), yes = rect(tester, 'yes');
    expect(render(tester).stacked, isTrue);
    expect(yes.top, 0, reason: 'the filled button on top');
    expect(yes.left, 0);
    expect(yes.width, width);
    expect(no.left, 0);
    expect(no.width, width);
    expect(no.top, yes.bottom + 8);
    expect(render(tester).size, Size(width, yes.height + 8 + no.height));

    // Both still answer taps.
    await tester.tap(find.byKey(const Key('yes')));
    await tester.tap(find.byKey(const Key('no')));
    expect(taps, ['yes', 'no']);
  });

  testWidgets('dry layout and intrinsic heights agree with the layout', (
    tester,
  ) async {
    final needed = await rowWidth(tester);
    for (final width in [needed + 40, needed, needed - 1, needed / 2]) {
      await tester.pumpWidget(pair(width));
      final r = render(tester);
      final c = BoxConstraints.tightFor(width: width);
      expect(r.getDryLayout(c), r.size, reason: 'dry at $width');
      expect(r.getMinIntrinsicHeight(width), r.size.height, reason: '$width');
      expect(r.getMaxIntrinsicHeight(width), r.size.height, reason: '$width');
    }
    final r = render(tester);
    expect(
      r.getMinIntrinsicWidth(double.infinity),
      lessThan(r.getMaxIntrinsicWidth(double.infinity)),
      reason: 'stacking needs less width than one line',
    );
  });

  testWidgets('a label too long for the line wraps inside its full width', (
    tester,
  ) async {
    await tester.pumpWidget(pair(120));
    expect(render(tester).stacked, isTrue);
    expect(rect(tester, 'yes').width, 120);
    expect(tester.takeException(), isNull);
  });

  group('ButtonRow: three buttons (Forgot PIN, decision 71)', () {
    Widget three(double width, {TextDirection direction = TextDirection.ltr}) =>
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: ButtonRow(
                    children: [
                      TextButton(
                        key: const Key('cancel'),
                        onPressed: () {},
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        key: const Key('erase'),
                        onPressed: () {},
                        child: const Text('Erase'),
                      ),
                      FilledButton(
                        key: const Key('main'),
                        onPressed: () {},
                        child: const Text('Use the lock'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    RenderButtonRow row(WidgetTester tester) =>
        tester.renderObject<RenderButtonRow>(find.byType(ButtonRow));

    testWidgets('room for all: one line at the end, in order', (tester) async {
      await tester.pumpWidget(three(700));
      final c = rect(tester, 'cancel'),
          e = rect(tester, 'erase'),
          m = rect(tester, 'main');
      expect(row(tester).stacked, isFalse);
      expect(m.right, 700);
      expect(e.right + 8, moreOrLessEquals(m.left));
      expect(c.right + 8, moreOrLessEquals(e.left));
      expect(c.center.dy, moreOrLessEquals(m.center.dy));
    });

    testWidgets('right to left: the same order from the start (the right)', (
      tester,
    ) async {
      await tester.pumpWidget(three(700, direction: TextDirection.rtl));
      final c = rect(tester, 'cancel'),
          e = rect(tester, 'erase'),
          m = rect(tester, 'main');
      expect(m.left, 0);
      expect(e.left, moreOrLessEquals(m.right + 8));
      expect(c.left, moreOrLessEquals(e.right + 8));
    });

    testWidgets('no room: full width, the main one on top, then reversed', (
      tester,
    ) async {
      await tester.pumpWidget(three(160));
      final c = rect(tester, 'cancel'),
          e = rect(tester, 'erase'),
          m = rect(tester, 'main');
      expect(row(tester).stacked, isTrue);
      expect(m.top, 0);
      expect(e.top, m.bottom + 8);
      expect(c.top, e.bottom + 8);
      for (final r in [c, e, m]) {
        expect(r.left, 0);
        expect(r.width, 160);
      }
      final r = row(tester);
      expect(r.size.height, c.bottom);
      expect(r.getDryLayout(const BoxConstraints.tightFor(width: 160)), r.size);
      expect(r.getMinIntrinsicHeight(160), r.size.height);
    });
  });
}
