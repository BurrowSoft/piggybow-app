// Goldens: C1 and C2 at 320 dp ×2 (decision 44). Their tab bar, with
// Timeline selected, is D1's golden.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/no_error_colour.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Timeline in every layout case (plan §0.3, decision 43): the empty state,
/// and three days with the longest notes, the largest amount, emoji, Thai
/// and a save to an ended goal with a 40-character name.
void main() {
  setUpAll(loadAppFonts);
  String usd(int minor) => formatMoney(minor, 'USD', 'en_US');

  Future<TestApp> open(
    WidgetTester tester,
    LayoutCase c, {
    Future<void> Function(TestApp)? seed,
  }) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> threeDays(TestApp app) async {
    final t = DateTime.utc(2026, 9);
    // A save to a goal that later ended ("Saved for …"), on an older day.
    await app.journal.putGoal(
      Goal(
        id: 'goal-1',
        name: goal40,
        targetMinor: 1000000,
        createdAt: t,
        updatedAt: t,
      ),
    );
    await app.journal.addEntry(
      type: EntryType.saved,
      amountMinor: 250000,
      currency: 'USD',
      localDate: '2026-09-28',
    );
    await app.journal.putGoal(
      Goal(
        id: 'goal-1',
        name: goal40,
        targetMinor: 1000000,
        createdAt: t,
        updatedAt: t,
        status: GoalStatus.ended,
      ),
    );
    // Yesterday: spends only, with emoji and Thai notes.
    await app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: 1250,
      currency: 'USD',
      localDate: '2026-10-01',
      category: SpendCategory.food,
      feeling: Feeling.worthIt,
      note: noteEmoji,
    );
    await app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: 990,
      currency: 'USD',
      localDate: '2026-10-01',
      category: SpendCategory.transport,
      note: noteThai,
    );
    // Today: both totals; the largest amount with the longest note.
    await app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: amountMax,
      currency: 'USD',
      localDate: '2026-10-02',
      category: SpendCategory.fun,
      feeling: Feeling.notReally,
      note: note80,
    );
    await app.journal.addEntry(
      type: EntryType.saved,
      amountMinor: 5000,
      currency: 'USD',
      localDate: '2026-10-02',
    );
  }

  final amounts = [
    usd(amountMax),
    '+${usd(5000)}',
    usd(1250),
    usd(990),
    '+${usd(250000)}',
  ];

  /// The checks on the whole list, scrolled through top to bottom.
  Future<void> checkList(WidgetTester tester, String state) async {
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(list).position;
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(
        tester,
        reason: '$state at ${position.pixels.round()}',
      );
      for (final a in amounts) {
        if (find.text(a).evaluate().isNotEmpty) {
          expectOneLine(tester, a, reason: state);
        }
      }
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
  }

  for (final c in layoutCases) {
    testWidgets('C1 empty: the pig and the first-entry button ($c)', (
      tester,
    ) async {
      await open(tester, c);
      expect(find.text('Nothing here yet'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'C1');
      if (c.takesGolden) {
        await expectLayoutGolden(
          tester,
          c,
          screen: 'timeline',
          state: 'empty',
          stateId: 'C1',
        );
      }
    });

    testWidgets('C2 three days with the stress data ($c)', (tester) async {
      await open(tester, c, seed: threeDays);
      expect(find.text('Today'), findsOneWidget);
      expectOnlyAllowedColours(
        tester,
        [usd(amountMax), usd(5000)],
        extra: (t) => {t.colorScheme.primary},
        reason: 'C2 today',
      );
      await checkList(tester, 'C2');
      expect(
        find.text('Saved for $goal40'),
        findsOneWidget,
        reason: 'the ended goal, at the bottom',
      );
      // At the end of the list the last row clears the + (decision 55).
      expect(
        tester.getRect(find.text('+${usd(250000)}')).bottom,
        lessThanOrEqualTo(tester.getRect(byId('tl-add')).top),
        reason: 'C2: the last row above the +',
      );
      if (c.takesGolden) {
        // The top (Today) and the end (the ended goal's "Saved for").
        await expectLayoutGoldens(
          tester,
          c,
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
          screen: 'timeline',
          state: 'full',
          stateId: 'C2',
        );
      }
    });

    testWidgets('C3 / C4 the Spent and Saved filters ($c)', (tester) async {
      await open(tester, c, seed: threeDays);
      await tester.tap(byId('tl-filter-spent'));
      await tester.pumpAndSettle();
      await checkList(tester, 'C3');
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      tester.state<ScrollableState>(list).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(byId('tl-filter-saved'));
      await tester.pumpAndSettle();
      await checkList(tester, 'C4');
    });
  }
}
