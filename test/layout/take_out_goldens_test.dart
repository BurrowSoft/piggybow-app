// Goldens: taking money out of savings (decision 44), at 320 dp ×2, light
// and dark, for PB UX & PM's look: the sheet (and its "more than you've
// saved"), the goal with Take out and a taken-out row, Timeline's row, and
// Summary's line.
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
  Future<TestApp> open(WidgetTester tester, LayoutCase c, {String location = '/home'}) async {
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
    });
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

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
  }
}
