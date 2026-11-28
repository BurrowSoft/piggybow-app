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
  RenderButtonPair render(WidgetTester tester) =>
      tester.renderObject<RenderButtonPair>(find.byType(ButtonPair));

  /// The width both need side by side: their own widths plus the 8 dp.
  Future<double> rowWidth(WidgetTester tester) async {
    await tester.pumpWidget(pair(1000));
    return rect(tester, 'no').width + 8 + rect(tester, 'yes').width;
  }

  testWidgets('room for both: one line at the end, No thanks first', (
    tester,
  ) async {
    final needed = await rowWidth(tester);
    expect(needed, lessThan(1000));
    final no = rect(tester, 'no'), yes = rect(tester, 'yes');
    expect(render(tester).stacked, isFalse);
    expect(yes.right, 1000, reason: 'at the end of the line');
    expect(no.right + 8, moreOrLessEquals(yes.left));
    expect(no.center.dy, moreOrLessEquals(yes.center.dy));
    expect(render(tester).size, Size(1000, yes.height));
    expect(render(tester).getMaxIntrinsicWidth(double.infinity), needed);
  });

  testWidgets('right to left: the end is the left, No thanks nearer start', (
    tester,
  ) async {
    await tester.pumpWidget(pair(1000, direction: TextDirection.rtl));
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
}
