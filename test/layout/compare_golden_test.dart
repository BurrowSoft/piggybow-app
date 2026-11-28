@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Feature 13, gentle comparisons: Summary's week, By category in the middle
/// of the screen, with "About the same as", "A bit more than" and "A bit less
/// than this time last week" under three categories and nothing under a new
/// one (SC1). 360 dp at text ×1 and 320 dp at ×2, light and dark.
void main() {
  setUpAll(loadAppFonts);

  final cases = [
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0)])
      for (final brightness in Brightness.values)
        LayoutCase(width, scale, brightness),
  ];

  for (final c in cases) {
    testWidgets('SC1 By category with this time last week ($c)', (
      tester,
    ) async {
      setLayout(tester, c);
      final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        Future<void> spend(int minor, SpendCategory category, String day) =>
            app.journal.addEntry(
              type: EntryType.spent,
              amountMinor: minor,
              currency: 'USD',
              localDate: day,
              category: category,
            );
        // This week (28 September to Friday 2 October).
        await spend(2000, SpendCategory.transport, '2026-09-30');
        await spend(1000, SpendCategory.food, '2026-09-29');
        await spend(500, SpendCategory.groceries, '2026-10-02');
        await spend(300, SpendCategory.fun, '2026-10-01');
        // This time last week (21 to 25 September).
        await spend(1000, SpendCategory.transport, '2026-09-23');
        await spend(1000, SpendCategory.food, '2026-09-22');
        await spend(1000, SpendCategory.fun, '2026-09-24');
      });
      await app.pump(tester);
      await tester.tapId('tab-summary');
      for (var i = 0; i < 40 && byId('sum-period-label').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      final list = find
          .descendant(
            of: byId('summary-screen'),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        byId('sum-cat-fun-compare'),
        200,
        scrollable: list,
      );
      await Scrollable.ensureVisible(
        tester.element(byId('sum-by-category')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await expectSoundLayout(tester, reason: 'SC1');
      expect(find.textContaining('this time last week'), findsNWidgets(3));
      await expectLayoutGolden(
        tester,
        c,
        screen: 'summary',
        state: 'compare',
        stateId: 'SC1',
      );
    });
  }
}
