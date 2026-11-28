// Goldens: Home asking how yesterday felt (two of yesterday's spends with no
// feeling yet) at 320 dp ×2 (decision 44), and its layout in every case.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// H12: Home on 2 October (08:30 in Bangkok) with two spends from the 1st and
/// no feeling on either: a note and an amount, and a category and an amount.
void main() {
  setUpAll(loadAppFonts);

  Finder homeList() => find
      .descendant(of: byId('home-screen'), matching: find.byType(Scrollable))
      .first;

  for (final c in layoutCases) {
    testWidgets('H12 Home asks how yesterday felt ($c)', (tester) async {
      final clock = MovableClock(DateTime.utc(2026, 10, 1, 4));
      setLayout(tester, c);
      final app = TestApp(clock: clock)..prefs.appearance = c.appearance;
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        await app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 18500,
          currency: 'THB',
          localDate: '2026-10-01',
          category: SpendCategory.food,
          note: 'Lunch out',
        );
        clock.now = clock.now.add(const Duration(hours: 6));
        await app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 4500,
          currency: 'THB',
          localDate: '2026-10-01',
          category: SpendCategory.transport,
        );
        clock.now = DateTime.utc(2026, 10, 2, 1, 30);
      });
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-week').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      await tester.revealId('home-yesterday');
      await expectSoundLayout(tester, reason: 'H12');
      if (c.takesGolden) {
        await expectLayoutGoldens(
          tester,
          c,
          homeList(),
          screen: 'home',
          state: 'yesterday',
          stateId: 'H12',
        );
      }
    });
  }
}
