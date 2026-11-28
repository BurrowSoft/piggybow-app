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
    // In the goal's own list: "New tyre" over "Taken out · Today", −amount.
    expect(
      find.descendant(of: byId('goal-save-${out.id}'), matching: find.text('$minusSign${money(5000)}')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: byId('goal-save-${out.id}'), matching: find.text('Taken out · Today')),
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
    // With no note: "Taken out" over its day.
    final row = byId('goal-save-entry-2');
    expect(find.descendant(of: row, matching: find.text('Taken out')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Today')), findsOneWidget);
  });

  const lockedLine = 'Some of this money was taken out of Bike. Change or remove that first.';

  /// Bike: 300 saved (entry-1), 200 of it taken out; the save, opened from
  /// Timeline, is the one the goal needs: it keeps at least 200.
  Future<TestApp> openLockedSave(WidgetTester tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await saved(app, 30000);
        await app.journal.takeOut(
          goalId: 'goal-1',
          amountMinor: 20000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      },
    );
    await tester.tapId('tab-timeline');
    await tester.tapId('tl-row-entry-1');
    await settle(tester, find.text('300.00'));
    final field = tester.widget<TextField>(
      find.descendant(of: byId('add-amount'), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, '300.00', reason: 'the save, loaded');
    expect(find.text(lockedLine), findsNothing);
    return app;
  }

  Future<Entry?> theSave(WidgetTester tester, TestApp app) =>
      tester.runAsync<Entry?>(() => app.journal.entry('entry-1'));

  testWidgets("a save the goal needs can't be deleted: the sheet says why at "
      'once, and asks nothing', (tester) async {
    final app = await openLockedSave(tester);
    await tester.tapId('edit-delete');
    expect(byId('delete-confirm'), findsNothing);
    expect(find.text(lockedLine), findsOneWidget);
    expect(byId('edit-save'), findsOneWidget);
    expect(await theSave(tester, app), isNotNull);
    expect(await progress(tester, app), 10000);
  });

  testWidgets('a save the goal needs goes no lower than that: 150 is said at '
      'once and not saved; 200 is fine', (tester) async {
    final app = await openLockedSave(tester);
    await tester.enterId('add-amount', '150');
    expect(find.text(lockedLine), findsOneWidget);
    await tester.tapId('edit-save');
    expect(byId('edit-save'), findsOneWidget);
    expect((await theSave(tester, app))!.amountMinor, 30000);
    await tester.enterId('add-amount', '200');
    expect(find.text(lockedLine), findsNothing);
    await tester.tapId('edit-save');
    expect(byId('edit-save'), findsNothing);
    expect((await theSave(tester, app))!.amountMinor, 20000);
    expect(await progress(tester, app), 0);
  });

  testWidgets("a save the goal needs can't become a spend: the sheet says why", (tester) async {
    final app = await openLockedSave(tester);
    await tester.tapId('add-seg-spent');
    await tester.tapId('add-cat-food');
    await tester.tapId('edit-save');
    expect(find.text(lockedLine), findsOneWidget);
    expect(byId('edit-save'), findsOneWidget);
    final s = (await theSave(tester, app))!;
    expect((s.type, s.goalId, s.amountMinor), (EntryType.saved, 'goal-1', 30000));
  });

  testWidgets("the goal's Already saved goes no lower than what was taken out "
      'beyond its saves: the field says why', (tester) async {
    final app = await open(
      tester,
      location: GoalRoutes.edit('goal-1'),
      seed: (app) async {
        await app.journal.putGoal(
          Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, startMinor: 10000, createdAt: t, updatedAt: t),
        );
        await saved(app, 3000);
        // 100 + 30 saved, 120 taken out: Already saved can go down to 90.
        await app.journal.takeOut(
          goalId: 'goal-1',
          amountMinor: 12000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      },
    );
    Future<int> start() async => (await tester.runAsync(() => app.journal.goal('goal-1')))!.startMinor;
    const line = 'Some of this money was taken out of this goal. Change or remove that first.';
    await settle(tester, byId('goal-start'));
    expect(find.text(line), findsNothing);
    await tester.enterId('goal-start', '');
    expect(find.text(line), findsOneWidget, reason: 'empty is 0');
    await tester.enterId('goal-start', '80');
    expect(find.text(line), findsOneWidget);
    await tester.tapId('goal-submit');
    expect(byId('goal-submit'), findsOneWidget);
    expect(await start(), 10000);
    await tester.enterId('goal-start', '90');
    expect(find.text(line), findsNothing);
    await tester.tapId('goal-submit');
    expect(byId('goal-submit'), findsNothing);
    expect(await start(), 9000);
    expect(await progress(tester, app), 0);
  });
}
