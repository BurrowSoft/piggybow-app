import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/no_error_colour.dart';

/// Self-tests of [expectOnlyAllowedColours]: it passes on ink, muted ink and
/// a named accent, and fails on every other way an amount or a line can be
/// coloured.
void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  // A Text whose colour is computed from the ambient theme.
  Widget coloured(String text, Color Function(ThemeData t) pick) => Builder(
        builder: (context) =>
            Text(text, style: TextStyle(color: pick(Theme.of(context)))),
      );

  Future<void> expectFails(WidgetTester tester, List<String> texts,
      {Set<Color> Function(ThemeData)? extra}) async {
    expect(
      () => expectOnlyAllowedColours(tester, texts, extra: extra),
      throwsA(isA<TestFailure>()),
    );
  }

  group('passes', () {
    testWidgets('an amount in the default ink', (tester) async {
      await tester.pumpWidget(app(const Text(r'$12.50')));
      expectOnlyAllowedColours(tester, [r'$12.50']);
    });

    testWidgets('an amount in the muted ink', (tester) async {
      await tester
          .pumpWidget(app(coloured(r'$12.50', (t) => t.colorScheme.onSurfaceVariant)));
      expectOnlyAllowedColours(tester, [r'$12.50']);
    });

    testWidgets('a save in the accent the caller allows', (tester) async {
      await tester.pumpWidget(app(coloured(r'+$5.00', (t) => t.colorScheme.primary)));
      expectOnlyAllowedColours(tester, [r'+$5.00'],
          extra: (t) => {t.colorScheme.primary});
    });
  });

  group('controls: each must fail', () {
    testWidgets('the error colour', (tester) async {
      await tester.pumpWidget(app(coloured(r'$12.50', (t) => t.colorScheme.error)));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('the error colour at 80 % alpha', (tester) async {
      await tester.pumpWidget(app(coloured(
          r'$12.50', (t) => t.colorScheme.error.withValues(alpha: 0.8))));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('a hard-coded Colors.red', (tester) async {
      await tester.pumpWidget(app(coloured(r'$12.50', (_) => Colors.red)));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('a palette colour (the rainbow rose) not allowed by the caller',
        (tester) async {
      await tester
          .pumpWidget(app(coloured(r'$12.50', (_) => const Color(0xFFE27D9A))));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('the accent when the caller did not allow it', (tester) async {
      await tester.pumpWidget(app(coloured(r'$12.50', (t) => t.colorScheme.primary)));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('an error-coloured span inside a sentence', (tester) async {
      await tester.pumpWidget(app(Builder(
        builder: (context) => Text.rich(TextSpan(
          text: 'Spent ',
          children: [
            TextSpan(
              text: r'$12.50',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        )),
      )));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('a foreground paint', (tester) async {
      await tester.pumpWidget(app(Text(
        r'$12.50',
        style: TextStyle(foreground: Paint()..color = const Color(0xFF2B2438)),
      )));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets('a raw RichText with no colour (unknown)', (tester) async {
      await tester.pumpWidget(app(RichText(
        text: const TextSpan(text: r'$12.50'),
      )));
      await expectFails(tester, [r'$12.50']);
    });

    testWidgets("a nested Theme's own ink is the one allowed", (tester) async {
      // The outer theme's ink is not allowed inside a Theme whose ink differs.
      await tester.pumpWidget(app(Builder(
        builder: (outer) => Theme(
          data: Theme.of(outer).copyWith(
            colorScheme: Theme.of(outer)
                .colorScheme
                .copyWith(onSurface: const Color(0xFF123456)),
          ),
          child: Text(
            'Your week fits your plan so far.',
            style: TextStyle(color: Theme.of(outer).colorScheme.onSurface),
          ),
        ),
      )));
      await expectFails(tester, ['Your week fits your plan']);
    });

    testWidgets('nothing to check (fails closed)', (tester) async {
      await tester.pumpWidget(app(const Text('Hello')));
      await expectFails(tester, [r'$12.50']);
    });
  });
}
