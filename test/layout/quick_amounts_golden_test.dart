@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/goldens.dart';

/// Feature 3, quick amounts: the Add sheet for a spend in Food, with its
/// three chips under the amount; 360 dp at text ×1 and 320 dp at ×2, light
/// and dark. The keyboard is down, so the chips and the categories show.
void main() {
  setUpAll(loadAppFonts);
  final t0 = DateTime.utc(2026, 10, 1, 1);

  for (final (width, scale) in [(360, 1), (320, 2)]) {
    for (final brightness in Brightness.values) {
      final appearance = brightness == Brightness.dark ? 'dark' : 'light';
      testWidgets('the Add sheet with 3 quick amounts, $width dp ×$scale, '
          '$appearance', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = Size(width * 3.0, 780 * 3.0);
        tester.platformDispatcher.textScaleFactorTestValue = scale.toDouble();
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // A steady caret, whatever the frame count.
        EditableText.debugDeterministicCursor = true;
        addTearDown(() => EditableText.debugDeterministicCursor = false);
        final clock = MovableClock(t0);
        final app = TestApp(currency: 'USD', clock: clock)
          ..prefs.appearance = appearance;
        await tester.runAsync(app.openJournal);
        await tester.runAsync(() async {
          for (final (i, amount) in [450, 1250, 450, 800].indexed) {
            clock.now = t0.add(Duration(minutes: i));
            await app.journal.addEntry(
              type: EntryType.spent,
              amountMinor: amount,
              currency: 'USD',
              localDate: '2026-10-01',
              category: SpendCategory.food,
            );
          }
        });
        await app.pump(tester);
        await tester.tapId('home-add');
        await tester.tapId('add-cat-food');
        // The keyboard down, the sheet at its top.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(byId('add-quick-2'), findsOneWidget);
        await expectGolden(
          tester,
          find.byType(MaterialApp),
          screen: 'add-sheet',
          state: 'quick-amounts',
          stateId: 'Q1',
          brightness: brightness,
          width: width,
          textScale: scale,
        );
      });
    }
  }
}
