@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Feature 6, the days noted this week: Home's This week card with a plan, a
/// spend that felt worth it, and "You noted 3 days this week" under them, the
/// card in the middle of the screen; 360 dp at text ×1 and 320 dp at ×2,
/// light and dark.
void main() {
  setUpAll(loadAppFonts);

  final cases = [
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0)])
      for (final brightness in Brightness.values)
        LayoutCase(width, scale, brightness),
  ];

  for (final c in cases) {
    testWidgets('W1 the week card with the days noted ($c)', (tester) async {
      setLayout(tester, c);
      final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        await app.journal.setPlanMinor(20000);
        await app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 1250,
          currency: 'USD',
          localDate: '2026-09-28',
          category: SpendCategory.food,
          feeling: Feeling.worthIt,
        );
        await app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 3400,
          currency: 'USD',
          localDate: '2026-09-30',
          category: SpendCategory.transport,
        );
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 5000,
          currency: 'USD',
          localDate: '2026-10-02',
        );
      });
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-pig-line').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      final list = find
          .descendant(of: byId('home-screen'), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        byId('home-week-noted'),
        200,
        scrollable: list,
      );
      await Scrollable.ensureVisible(
        tester.element(byId('home-week')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await expectSoundLayout(tester, reason: 'W1');
      expect(find.text('You noted 3 days this week'), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'home',
        state: 'week-noted',
        stateId: 'W1',
      );
    });
  }
}
