import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Taking money out of savings in every layout case (plan §0.3, decision
/// 43), with a 40-character goal name and the largest amounts: the sheet
/// with "more than you've saved", the goal with Take out and a taken-out
/// row, Timeline's row, and Summary's line.
void main() {
  setUpAll(loadAppFonts);
  final t = DateTime.utc(2026, 9);
  const saved = 600000000000;
  const out = 99999999999;

  Future<TestApp> open(WidgetTester tester, LayoutCase c, {String location = '/home'}) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: goal40, targetMinor: amountMax, createdAt: t, updatedAt: t),
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: saved,
        currency: 'USD',
        localDate: '2026-10-01',
      );
      await app.journal.takeOut(
        goalId: 'goal-1',
        amountMinor: out,
        currency: 'USD',
        localDate: '2026-10-02',
        note: note80,
      );
    });
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

  for (final c in layoutCases) {
    testWidgets("T1 the take-out sheet: more than you've saved ($c)", (tester) async {
      await open(tester, c, location: GoalRoutes.detail('goal-1'));
      await tester.tapId('goal-take-out');
      await tester.enterId('takeout-amount', '9999999999');
      expect(find.text("That's more than you've saved for this goal"), findsOneWidget);
      await expectSoundLayout(tester, reason: 'T1');
    });

    testWidgets('T2 the goal: Take out, and a taken-out row ($c)', (tester) async {
      await open(tester, c, location: GoalRoutes.detail('goal-1'));
      await tester.revealId('goal-save-entry-2');
      await tester.pumpAndSettle();
      expect(byId('goal-take-out'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'T2');
    });

    testWidgets("T3 Timeline: the taken-out row ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tab-timeline');
      expect(byId('tl-row-entry-2'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'T3');
    });

    testWidgets("T4 Summary: Taken out, its own line ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tab-summary');
      await tester.revealId('sum-taken-out');
      await tester.pumpAndSettle();
      await expectSoundLayout(tester, reason: 'T4');
    });
  }
}
