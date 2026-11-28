// Goldens: taking money out of savings (decision 44), at 320 dp ×2, light
// and dark, for PB UX & PM's look: the sheet (and its "more than you've
// saved"), the goal with Take out and a taken-out row, Timeline's row,
// Summary's line, and the locks: a save the goal needs, with Delete tapped
// or its amount lowered, and the goal's Already saved.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);
  final t = DateTime.utc(2026, 9);

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  /// Bike: 1,000.00, with 300.00 saved and 50.00 taken out today.
  Future<TestApp> open(
    WidgetTester tester,
    LayoutCase c, {
    String location = '/home',
    Future<void> Function(TestApp app)? more,
  }) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, createdAt: t, updatedAt: t),
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 30000,
        currency: 'USD',
        localDate: '2026-10-01',
      );
      await app.journal.takeOut(
        goalId: 'goal-1',
        amountMinor: 5000,
        currency: 'USD',
        localDate: '2026-10-02',
        note: 'New tyre',
      );
      await more?.call(app);
    });
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

  /// Pumps until [done], at most 2 s: a screen reads the store before it
  /// shows its fields.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Opens the 300.00 save (the one the goal needs: 50.00 was taken out)
  /// from Timeline, tapped near its top (a tall row's middle can sit under
  /// the tab bar), and waits for its amount.
  Future<void> openTheSave(WidgetTester tester) async {
    await tester.tapId('tab-timeline');
    await tester.revealId('tl-row-entry-1');
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(byId('tl-row-entry-1')).topLeft + const Offset(24, 16));
    await tester.pumpAndSettle();
    await settleUntil(tester, () => find.text('300.00').evaluate().isNotEmpty);
    expect(find.text('300.00'), findsOneWidget, reason: 'the save, loaded');
  }

  const saveLocked = 'Some of this money was taken out of Bike. Change or remove that first.';

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets("TG1 the take-out sheet: more than you've saved ($c)", (tester) async {
      await open(tester, c, location: GoalRoutes.detail('goal-1'));
      await tester.tapId('goal-take-out');
      await tester.enterId('takeout-amount', '300');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'take-out',
        state: 'too-much',
        stateId: 'TG1',
      );
    });

    testWidgets('TG2 the goal: Take out, and a taken-out row ($c)', (tester) async {
      await open(tester, c, location: GoalRoutes.detail('goal-1'));
      await expectLayoutGoldens(
        tester,
        c,
        listIn('goal-screen'),
        screen: 'goal-detail',
        state: 'taken-out',
        stateId: 'TG2',
      );
    });

    testWidgets("TG3 Timeline: the taken-out row ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tab-timeline');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'timeline',
        state: 'taken-out',
        stateId: 'TG3',
      );
    });

    testWidgets("TG4 Summary: Taken out, its own line ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tab-summary');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'summary',
        state: 'taken-out',
        stateId: 'TG4',
      );
    });

    testWidgets('TG5 a save the goal needs: Delete tapped, the sheet says '
        'why ($c)', (tester) async {
      await open(tester, c);
      await openTheSave(tester);
      await tester.tapId('edit-delete');
      expect(find.text(saveLocked), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'add-sheet',
        state: 'edit-locked',
        stateId: 'TG5',
      );
    });

    testWidgets('TG6 a save the goal needs: lowered below it, the amount says '
        'why ($c)', (tester) async {
      await open(tester, c);
      await openTheSave(tester);
      await tester.enterId('add-amount', '10');
      expect(find.text(saveLocked), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'add-sheet',
        state: 'edit-lowered',
        stateId: 'TG6',
      );
    });

    testWidgets("TG7 the goal's editor: Already saved below what was taken "
        'out beyond its saves ($c)', (tester) async {
      await open(
        tester,
        c,
        location: GoalRoutes.edit('goal-1'),
        more: (app) async {
          // Already saved 100.00, then the rest taken out too (400.00 in
          // all): the saves cover 300.00, so Already saved stays 100.00.
          final goal = (await app.journal.goal('goal-1'))!;
          await app.journal.putGoal(goal.copyWith(startMinor: 10000));
          await app.journal.takeOut(
            goalId: 'goal-1',
            amountMinor: 35000,
            currency: 'USD',
            localDate: '2026-10-02',
          );
        },
      );
      await settleUntil(tester, () => byId('goal-start').evaluate().isNotEmpty);
      await tester.enterId('goal-start', '50');
      await tester.ensureVisible(byId('goal-start'));
      await tester.pumpAndSettle();
      expect(
        find.text('Some of this money was taken out of this goal. Change or remove that first.'),
        findsOneWidget,
      );
      await expectLayoutGolden(
        tester,
        c,
        screen: 'goal-edit',
        state: 'start-locked',
        stateId: 'TG7',
      );
    });
  }
}
