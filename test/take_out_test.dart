import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/router.dart';

import 'helpers.dart';

/// Take money out of savings (feature 5): a goal's Take out (while it has
/// some), at most what it has; it shows on Timeline as "Taken out of …",
/// −amount in ink, opens its own sheet, and Delete gives it back; Summary
/// gets its own line; a reached goal stays reached.
void main() {
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');
  final t = DateTime.utc(2026, 9, 20);

  Goal bike({int target = 100000, GoalStatus status = GoalStatus.active}) => Goal(
    id: 'goal-1',
    name: 'Bike',
    targetMinor: target,
    createdAt: t,
    updatedAt: t,
    status: status,
  );

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> open(
    WidgetTester tester, {
    required Future<void> Function(TestApp app) seed,
    String location = '/home',
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() => seed(app));
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> saved(TestApp app, int minor) => app.journal.addEntry(
    type: EntryType.saved,
    amountMinor: minor,
    currency: 'THB',
    localDate: '2026-10-01',
  );

  Future<int> progress(WidgetTester tester, TestApp app) async =>
      (await tester.runAsync(() async => app.journal.goalProgress((await app.journal.goal('goal-1'))!)))!;

  Future<List<Entry>> withdrawals(WidgetTester tester, TestApp app) async => [
    for (final e in (await tester.runAsync(app.journal.entries))!)
      if (e.type == EntryType.withdraw) e,
  ];

  testWidgets("a goal with savings has Take out: it's taken out, said so, and "
      'the rainbow goes down', (tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await saved(app, 30000);
      },
    );
    await tester.tapId('goal-card');
    await settle(tester, byId('goal-take-out'));
    await tester.tapId('goal-take-out');
    expect(find.text('Take out of Bike'), findsOneWidget);
    await tester.enterId('takeout-amount', '50');
    await tester.enterId('takeout-note', 'New tyre');
    await tester.tapId('takeout-save');
    expect(byId('takeout-save'), findsNothing);
    expect(find.text("Taken out. It's still your money."), findsOneWidget);

    final out = (await withdrawals(tester, app)).single;
    expect((out.goalId, out.amountMinor, out.note, out.localDate), ('goal-1', 5000, 'New tyre', '2026-10-02'));
    expect(await progress(tester, app), 25000);
    expect(find.text('${money(25000)} of ${money(100000)}'), findsOneWidget);
    // In the goal's own list: "New tyre", −amount.
    expect(
      find.descendant(of: byId('goal-save-${out.id}'), matching: find.text('$minusSign${money(5000)}')),
      findsOneWidget,
    );
  });

  testWidgets("more than it has: the sheet says so, and nothing's taken out", (tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await saved(app, 30000);
      },
    );
    await tester.tapId('goal-card');
    await settle(tester, byId('goal-take-out'));
    await tester.tapId('goal-take-out');
    await tester.enterId('takeout-amount', '300.01');
    expect(find.text("That's more than you've saved for this goal"), findsOneWidget);
    await tester.tapId('takeout-save');
    expect(byId('takeout-save'), findsOneWidget);
    expect(await withdrawals(tester, app), isEmpty);
    // All of it is fine.
    await tester.enterId('takeout-amount', '300');
    await tester.tapId('takeout-save');
    expect(await progress(tester, app), 0);
  });

  testWidgets('a goal with nothing saved has no Take out', (tester) async {
    await open(tester, seed: (app) => app.journal.putGoal(bike()));
    await tester.tapId('goal-card');
    await settle(tester, byId('goal-add-savings'));
    expect(byId('goal-take-out'), findsNothing);
  });

  testWidgets('Timeline: "Taken out of Bike", −amount in ink; it opens its own '
      'sheet, and Delete gives the money back', (tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await saved(app, 30000);
        await app.journal.takeOut(
          goalId: 'goal-1',
          amountMinor: 5000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      },
    );
    await tester.tapId('tab-timeline');
    final row = byId('tl-row-entry-2');
    expect(find.descendant(of: row, matching: find.text('Taken out of Bike')), findsOneWidget);
    final amount = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('$minusSign${money(5000)}')),
    );
    expect(amount.style?.color, Theme.of(tester.element(row)).colorScheme.onSurface);
    // The day's totals leave it out: its amount shows only on its row.
    expect(find.textContaining(money(5000)), findsOneWidget);

    await tester.tapId('tl-row-entry-2');
    expect(find.text('Take out of Bike'), findsOneWidget);
    await tester.tapId('takeout-delete');
    await tester.tapId('takeout-delete-confirm');
    expect(await withdrawals(tester, app), isEmpty);
    expect(await progress(tester, app), 30000);
  });

  testWidgets('Summary: Saved stays the saves; "Taken out" is its own line', (tester) async {
    await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await saved(app, 30000);
        await app.journal.takeOut(
          goalId: 'goal-1',
          amountMinor: 5000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      },
    );
    await tester.tapId('tab-summary');
    await settle(tester, byId('sum-taken-out'));
    expect(find.descendant(of: byId('sum-taken-out'), matching: find.text('Taken out ${money(5000)}')), findsOneWidget);
    expect(find.descendant(of: byId('sum-saved'), matching: find.text(money(30000))), findsOneWidget);
  });

  testWidgets('a reached goal stays reached when money is taken out of it', (tester) async {
    final app = await open(
      tester,
      location: GoalRoutes.detail('goal-1'),
      seed: (app) async {
        await app.journal.putGoal(bike(target: 20000));
        await saved(app, 20000);
        await app.journal.markCelebrated('goal-1');
      },
    );
    await settle(tester, byId('goal-take-out'));
    // Reached: no Add savings, but its money can be taken out.
    expect(byId('goal-add-savings'), findsNothing);
    await tester.tapId('goal-take-out');
    await tester.enterId('takeout-amount', '80');
    await tester.tapId('takeout-save');
    final goal = (await tester.runAsync(() => app.journal.goal('goal-1')))!;
    expect(goal.status, GoalStatus.reached);
    expect(await progress(tester, app), 12000);
  });
}
