import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
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

  const owned = PlusProof(token: 't1', productId: plusPlayProductId);

  /// The app on Timeline; [plusOn] null is a build without Plus.
  Future<TestApp> open(
    WidgetTester tester, {
    required Future<void> Function(TestApp app) seed,
    bool? plusOn,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = plusOn == null
        ? TestApp()
        : TestApp(
            config: const AppConfig(flavor: Flavor.staging, plusEnabled: true),
            plus: PlusEntitlement(
              store: FakePlusStore()..owns = plusOn ? const [owned] : const [],
              hint: MemoryPlusHint(),
              clock: testClock,
            ),
          );
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

  testWidgets('a save that had no goal stays with no goal, even with a goal '
      'active now', (tester) async {
    final app = await open(
      tester,
      seed: (app) async {
        // Saved before any goal: it went to none.
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 30000,
          currency: 'THB',
          localDate: '2026-09-29',
        );
        await app.journal.putGoal(bike());
      },
    );
    await longPress(tester, 'tl-row-entry-1');
    await tester.tapId('tl-repeat');
    final copy = (await entries(tester, app)).firstWhere((e) => e.id != 'entry-1');
    expect((copy.type, copy.goalId, copy.amountMinor), (EntryType.saved, null, 30000));
    // The goal's progress didn't move.
    final goal = (await tester.runAsync(() => app.journal.goal('goal-1')))!;
    expect((await tester.runAsync(() => app.journal.goalProgress(goal)))!, 0);
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

  // Wiring item 6 (#56 with #49): a spend in a category of your own.
  final bubbleTea = CustomCategory(
    id: '${CustomCategory.idPrefix}bubble',
    name: 'Bubble tea',
    icon: CategoryIcon.coffee,
    createdAt: DateTime.utc(2026, 9),
  );
  Future<void> bubble(TestApp app) async {
    await app.journal.putCustomCategory(bubbleTea);
    await app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: 6500,
      currency: 'THB',
      localDate: '2026-09-28',
      customCategory: bubbleTea.id,
      note: 'Brown sugar',
    );
  }

  testWidgets('with Plus, a spend in your own category goes again in it', (tester) async {
    final app = await open(tester, plusOn: true, seed: bubble);
    await longPress(tester, 'tl-row-entry-1');
    await tester.tapId('tl-repeat');
    final copy = (await entries(tester, app)).firstWhere((e) => e.id != 'entry-1');
    expect((copy.category, copy.customCategory, copy.amountMinor, copy.note),
        (null, bubbleTea.id, 6500, 'Brown sugar'));
    expect(copy.localDate, '2026-10-02');
  });

  testWidgets('without Plus, a spend in your own category offers no Add again', (tester) async {
    final app = await open(tester, plusOn: false, seed: bubble);
    await longPress(tester, 'tl-row-entry-1');
    expect(byId('tl-repeat'), findsNothing);
    expect(await entries(tester, app), hasLength(1));
  });

  // Wiring item 7 (#56 with #47): with two goals, a save goes again to its
  // own goal, never to the one a new save goes to by default.
  testWidgets('with two goals, a save goes again to its own goal', (tester) async {
    final app = await open(
      tester,
      plusOn: true,
      seed: (app) async {
        await app.journal.putGoal(bike());
        await app.journal.putGoal(
          Goal(
            id: 'goal-2',
            name: 'Laptop',
            targetMinor: 5000000,
            createdAt: bikeAt.add(const Duration(days: 1)),
            updatedAt: bikeAt.add(const Duration(days: 1)),
          ),
          allowAnother: true,
        );
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 20000,
          currency: 'THB',
          localDate: '2026-09-29',
          goalId: 'goal-2',
        );
      },
    );
    expect((await entries(tester, app)).single.goalId, 'goal-2');
    await longPress(tester, 'tl-row-entry-1');
    await tester.tapId('tl-repeat');
    final copy = (await entries(tester, app)).firstWhere((e) => e.id != 'entry-1');
    expect((copy.type, copy.goalId, copy.amountMinor), (EntryType.saved, 'goal-2', 20000));
  });
}
