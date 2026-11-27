import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/fit_text.dart';
import 'package:piggybow/theme/theme.dart';

import 'helpers.dart';

/// At 320 dp / 200 %: titles and tabs never break mid-word and are never cut.
void main() {
  void screen(WidgetTester tester, double width, double scale) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1600);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// On one line, all of it: it needs no more width than it has, and isn't cut.
  void onOneLine(WidgetTester tester, Finder text, String why) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first,
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: why);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason: '$why: wraps',
    );
  }

  double scaleOf(WidgetTester tester, Finder text) => tester
      .widget<RichText>(
        find.descendant(of: text, matching: find.byType(RichText)).first,
      )
      .textScaler
      .scale(1);

  group('ScreenTitle', () {
    const word = 'Statistiques';

    Widget title(String text) => MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ScreenTitle(
            text,
            style: const TextStyle(fontSize: 28, height: 1),
          ),
        ),
      ),
    );

    testWidgets('a word that fits keeps the system size', (tester) async {
      screen(tester, 800, 2);
      await tester.pumpWidget(title(word));
      expect(scaleOf(tester, find.byType(ScreenTitle)), 2);
    });

    testWidgets('a word too long scales down, not broken', (tester) async {
      screen(tester, 400, 2);
      await tester.pumpWidget(title(word));
      expect(scaleOf(tester, find.byType(ScreenTitle)), lessThan(2));
      onOneLine(tester, find.byType(ScreenTitle), word);
    });

    testWidgets('it stops at normal size, however long the word', (
      tester,
    ) async {
      screen(tester, 320, 2);
      await tester.pumpWidget(title('Donaudampfschifffahrtsgesellschaft'));
      expect(scaleOf(tester, find.byType(ScreenTitle)), 1);
    });

    testWidgets('a no-break space holds words together', (tester) async {
      // Each part fits alone; joined they don't, so it must scale down.
      screen(tester, 400, 2);
      await tester.pumpWidget(title('Statist\u00A0iques'));
      expect(scaleOf(tester, find.byType(ScreenTitle)), lessThan(2));
    });

    testWidgets('Thai is not fitted as one long word', (tester) async {
      screen(tester, 320, 2);
      await tester.pumpWidget(title('\u0E2A\u0E23\u0E38\u0E1B' * 12));
      expect(scaleOf(tester, find.byType(ScreenTitle)), 2);
    });

    testWidgets('no width to fit to: no crash, the system size', (
      tester,
    ) async {
      screen(tester, 320, 2);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 0.5, child: ScreenTitle('Mot')),
            ),
          ),
        ),
      );
      expect(scaleOf(tester, find.byType(ScreenTitle)), 2);
    });

    testWidgets('several words wrap between words', (tester) async {
      screen(tester, 320, 2);
      await tester.pumpWidget(title('Un mot puis un mot puis un mot'));
      expect(scaleOf(tester, find.byType(ScreenTitle)), 2);
      final box = tester.getSize(find.byType(ScreenTitle));
      expect(box.height, greaterThan(56));
    });
  });

  testWidgets('AppBarTitle: one line, all of it', (tester) async {
    const long = 'Partager une carte du mois, en entier';
    screen(tester, 320, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(appBar: AppBar(title: const AppBarTitle(long))),
      ),
    );
    onOneLine(tester, find.byType(AppBarTitle), long);
    final bar = tester.getRect(find.byType(AppBar));
    final text = tester.getRect(find.text(long));
    expect(text.right, lessThanOrEqualTo(bar.right));
    expect(text.bottom, lessThanOrEqualTo(bar.bottom));
  });

  group('the bottom tabs', () {
    /// The last text in a tab: the first is its icon.
    Finder label(String id) => find
        .descendant(of: byId('tab-$id'), matching: find.byType(RichText))
        .last;

    for (final lang in const ['en']) {
      testWidgets('$lang at 320 dp / 200 %: one line each', (tester) async {
        screen(tester, 320, 2);
        final app = TestApp(chosenLocale: lang);
        await app.pump(tester);
        for (final id in const ['home', 'timeline', 'summary', 'me']) {
          final paragraph = tester.renderObject<RenderParagraph>(label(id));
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(paragraph.size.width + 0.5),
            reason: '$lang $id wraps',
          );
          expect(paragraph.didExceedMaxLines, isFalse);
        }
      });
    }

    testWidgets('normal text with room: the usual size', (tester) async {
      screen(tester, 1200, 1);
      final app = TestApp();
      await app.pump(tester);
      expect(tester.widget<RichText>(label('home')).textScaler.scale(1), 1);
    });

    testWidgets('large text with room: Flutter\'s own 130 %', (tester) async {
      screen(tester, 1200, 2);
      final app = TestApp();
      await app.pump(tester);
      expect(tester.widget<RichText>(label('home')).textScaler.scale(1), 1.3);
    });
  });

  group('the outlined button theme', () {
    Widget button(String text, {double width = 800}) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: OutlinedButton(onPressed: () {}, child: Text(text)),
          ),
        ),
      ),
    );

    testWidgets('one line at normal text stays 48 dp with its tap target', (
      tester,
    ) async {
      screen(tester, 800, 1);
      await tester.pumpWidget(button('Close'));
      expect(tester.getSize(find.byType(OutlinedButton)).height, 48);
    });

    testWidgets('a wrapped label keeps room above and below', (tester) async {
      screen(tester, 200, 1);
      await tester.pumpWidget(button('A long label that wraps', width: 180));
      final outer = tester.getRect(find.byType(OutlinedButton));
      final text = tester.getRect(find.byType(RichText).first);
      expect(text.top - outer.top, greaterThanOrEqualTo(10));
      expect(outer.bottom - text.bottom, greaterThanOrEqualTo(10));
    });
  });

  group('the button shape', () {
    testWidgets('one line: the same pill as before', (tester) async {
      for (final size in const [Size(240, 52), Size(120, 40)]) {
        final rect = Offset.zero & size;
        final was = const StadiumBorder().getOuterPath(rect);
        final now = appButtonShape.getOuterPath(rect);
        for (var x = 0.5; x < size.width; x += 3) {
          for (var y = 0.5; y < size.height; y += 3) {
            expect(
              now.contains(Offset(x, y)),
              was.contains(Offset(x, y)),
              reason: '$size at $x, $y',
            );
          }
        }
      }
    });
  });
}
