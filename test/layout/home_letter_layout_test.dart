// Goldens: Home with the pig's monthly letter (every fact in it) at 320 dp ×2
// (decision 44), the screen's top and end and the letter card alone; and its
// layout in every case.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/goldens.dart';
import 'layout_matrix.dart';

/// L1: Home on 2 October (08:30 in Bangkok), and September's letter: a goal
/// reached, the saves, "Fun" felt most worth it, and the days noted.
void main() {
  setUpAll(loadAppFonts);

  Finder homeList() => find
      .descendant(of: byId('home-screen'), matching: find.byType(Scrollable))
      .first;

  for (final c in layoutCases) {
    testWidgets('L1 Home with the pig\'s letter about September ($c)', (tester) async {
      final clock = MovableClock(DateTime.utc(2026, 9, 5, 3));
      setLayout(tester, c);
      final app = TestApp(clock: clock, letters: true)..prefs.appearance = c.appearance;
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        Future<void> spend(String date, {Feeling? feeling, SpendCategory category = SpendCategory.food}) async {
          clock.now = clock.now.add(const Duration(hours: 1));
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: 32000,
            currency: 'THB',
            localDate: date,
            category: category,
            feeling: feeling,
          );
        }

        await spend('2026-09-05', feeling: Feeling.worthIt, category: SpendCategory.fun);
        await spend('2026-09-12', feeling: Feeling.worthIt, category: SpendCategory.fun);
        await spend('2026-09-12');
        await spend('2026-09-20', feeling: Feeling.notSure);
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 1250000,
          currency: 'THB',
          localDate: '2026-09-25',
        );
        final reached = DateTime.utc(2026, 9, 25, 5);
        await app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'A bike for long summer rides',
            targetMinor: 1250000,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: reached,
            status: GoalStatus.reached,
            reachedAt: reached,
          ),
        );
        await app.journal.markCelebrated('g1');
        clock.now = DateTime.utc(2026, 10, 2, 1, 30);
      });
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-letter').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      await tester.revealId('home-letter-thanks');
      for (final id in ['home-letter-goals', 'home-letter-saved', 'home-letter-worth', 'home-letter-days']) {
        expect(byId(id), findsOneWidget, reason: id);
      }
      await expectSoundLayout(tester, reason: 'L1');
      if (c.takesGolden) {
        await expectLayoutGoldens(
          tester,
          c,
          homeList(),
          screen: 'home',
          state: 'letter',
          stateId: 'L1',
        );
        // At text ×2 the letter's middle falls between those two shots: the
        // card alone, whole (its part below the screen's edge included).
        await settleForGolden(tester, homeList(), end: false);
        await tester.ensureVisible(byId('home-letter'));
        await tester.pumpAndSettle();
        await expectGolden(
          tester,
          byId('home-letter'),
          screen: 'home',
          state: 'letter-card',
          stateId: 'L1',
          brightness: c.brightness,
          width: c.width.toInt(),
          textScale: c.textScale.toInt(),
        );
      }
    });
  }
}
