import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_matrix.dart';

/// The layout check's own controls: a word or an amount split across lines
/// fails it, and text broken only between words passes.
void main() {
  test('a break inside an amount counts as a broken word', () {
    expect(splitsAWord('9', ','), isTrue, reason: '"\$9" | ",999"');
    expect(splitsAWord('\$', '9'), isTrue);
    expect(splitsAWord('.', '9'), isTrue);
    expect(splitsAWord('o', 'r'), isTrue);
    expect(splitsAWord(' ', '\$'), isFalse);
    expect(splitsAWord(',', ' '), isFalse);
    expect(splitsAWord(':', ' '), isFalse);
  });

  Future<void> pumpText(WidgetTester tester, String text, double width) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              child: Text(text, style: const TextStyle(fontSize: 20)),
            ),
          ),
        ),
      );

  testWidgets('an amount wider than its line fails the check', (tester) async {
    await pumpText(tester, '\$9,999,999,999.99', 60);
    expect(
      () => expectWholeWords(tester, reason: 'control'),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('text broken only between words passes', (tester) async {
    await pumpText(tester, 'Every bit of it was you', 120);
    expectWholeWords(tester, reason: 'control');
  });
}
