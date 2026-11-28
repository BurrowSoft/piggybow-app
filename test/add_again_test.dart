import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import 'helpers.dart';

/// Add again today (feature 4): a long-press on a Timeline row, or the edit
/// sheet's menu, adds a copy dated today (same type, amount, category and
/// note; the feeling asked fresh), with "Added again for today" and Undo. A
/// save whose goal is no longer active doesn't offer it.
void main() {
  final bikeAt = DateTime.utc(2026, 9);
  Goal bike({GoalStatus status = GoalStatus.active}) => Goal(
    id: 'goal-1',
    name: 'Bike',
    targetMinor: 10000000,
    createdAt: bikeAt,
    updatedAt: bikeAt,
    status: status,
  );

  Future<TestApp> open(
    WidgetTester tester, {
    required Future<void> Function(TestApp app) seed,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
    return app;
  }

  Future<List<Entry>> entries(WidgetTester tester, TestApp app) async =>
      (await tester.runAsync(app.journal.entries))!;

  Future<void> lunch(TestApp app) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: 4500,
    currency: 'THB',
    localDate: '2026-09-28',
    category: SpendCategory.food,
    feeling: Feeling.worthIt,
    note: 'Lunch with Mai',
  );

  Future<void> longPress(WidgetTester tester, String id) async {
    await tester.revealId(id);
    await tester.longPress(byId(id));
    await tester.pumpAndSettle();
  }

  testWidgets('a long-press offers Add again today: the copy is dated today, with the '
      'same type, amount, category and note, and no feeling yet', (tester) async {
    final app = await open(tester, seed: lunch);
    await longPress(tester, 'tl-row-entry-1');
    expect(find.text('Add again today'), findsOneWidget);
    await tester.tapId('tl-repeat');
    expect(find.text('Added again for today'), findsOneWidget);

    final all = await entries(tester, app);
    expect(all.length, 2);
    final copy = all.firstWhere((e) => e.id != 'entry-1');
    expect(copy.localDate, '2026-10-02');
    expect(copy.type, EntryType.spent);
    expect(copy.amountMinor, 4500);
    expect(copy.currency, 'THB');
    expect(copy.category, SpendCategory.food);
    expect(copy.note, 'Lunch with Mai');
    expect(copy.feeling, isNull);
    // The original is as it was.
    final original = all.firstWhere((e) => e.id == 'entry-1');
    expect((original.localDate, original.feeling), ('2026-09-28', Feeling.worthIt));
  });

  testWidgets('Undo takes back the copy, and only the copy', (tester) async {
    final app = await open(tester, seed: lunch);
    await longPress(tester, 'tl-row-entry-1');
    await tester.tapId('tl-repeat');
    expect((await entries(tester, app)).length, 2);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final all = await entries(tester, app);
    expect(all.map((e) => e.id), ['entry-1']);
  });

  testWidgets('the long-press sheet closed without a choice adds nothing', (tester) async {
    final app = await open(tester, seed: lunch);
    await longPress(tester, 'tl-row-entry-1');
    expect(byId('tl-repeat'), findsOneWidget);
    // The scrim, above the sheet.
    await tester.tapAt(const Offset(180, 100));
    await tester.pumpAndSettle();
    expect(byId('tl-repeat'), findsNothing);
    expect((await entries(tester, app)).length, 1);
  });

  testWidgets("a save goes again to its goal while it's active", (tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 20000,
          currency: 'THB',
          localDate: '2026-09-29',
          note: 'Coins',
        );
      },
    );
    await longPress(tester, 'tl-row-entry-1');
    await tester.tapId('tl-repeat');
    final copy = (await entries(tester, app)).firstWhere((e) => e.id != 'entry-1');
    expect((copy.type, copy.goalId, copy.amountMinor, copy.note),
        (EntryType.saved, 'goal-1', 20000, 'Coins'));
    expect(copy.localDate, '2026-10-02');
  });

  testWidgets('a save whose goal ended offers no Add again: not on a long-press, '
      'not in its edit sheet', (tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 20000,
          currency: 'THB',
          localDate: '2026-09-29',
        );
        await app.journal.putGoal(bike(status: GoalStatus.ended));
      },
    );
    await longPress(tester, 'tl-row-entry-1');
    expect(byId('tl-repeat'), findsNothing);
    await tester.tapId('tl-row-entry-1');
    tester.expectScreen('edit-save');
    expect(byId('edit-more'), findsNothing);
    expect((await entries(tester, app)).length, 1);
  });

  testWidgets("the edit sheet's menu: Add again today closes the sheet and adds "
      'the entry as saved', (tester) async {
    final app = await open(tester, seed: lunch);
    await tester.tapId('tl-row-entry-1');
    // A change not saved is left, as when the sheet is closed.
    await tester.enterId('add-amount', '99');
    await tester.tapId('edit-more');
    await tester.tapId('edit-repeat');
    expect(byId('edit-save'), findsNothing);
    expect(find.text('Added again for today'), findsOneWidget);
    final all = await entries(tester, app);
    expect(all.length, 2);
    expect(all.every((e) => e.amountMinor == 4500), isTrue);
  });
}
