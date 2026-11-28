import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';

import 'helpers.dart';

/// Several goals at a time with Plus (decision 79), in the store: more than
/// one active goal only when asked for (Plus), the goal a save goes to (the
/// one chosen, else the one last saved to, else the oldest), and goals kept
/// after Plus ends stay editable but no new one starts beside them.
void main() {
  late JournalStore store;
  late MovableClock clock;
  var ids = 0;

  setUp(() async {
    clock = MovableClock(DateTime.utc(2026, 10, 2, 1));
    ids = 0;
    store = await JournalStore.inMemory(clock: clock, newId: () => 'e${++ids}');
  });
  tearDown(() => store.close());

  Goal goal(String id, String name, {int day = 1}) => Goal(
    id: id,
    name: name,
    targetMinor: 100000,
    createdAt: DateTime.utc(2026, 9, day),
    updatedAt: DateTime.utc(2026, 9, day),
  );

  Future<Entry> save(int minor, {String? goalId}) => store.addEntry(
    type: EntryType.saved,
    amountMinor: minor,
    currency: 'USD',
    localDate: '2026-10-02',
    goalId: goalId,
  );

  test('a second active goal only with Plus; oldest first', () async {
    await store.putGoal(goal('g2', 'Trip', day: 5));
    await expectLater(store.putGoal(goal('g1', 'Bike', day: 1)), throwsStateError);
    expect(await store.goal('g1'), isNull, reason: 'nothing written');
    await store.putGoal(goal('g1', 'Bike', day: 1), allowAnother: true);
    await store.putGoal(goal('g3', 'Sofa', day: 9), allowAnother: true);
    expect((await store.activeGoals()).map((g) => g.id), ['g1', 'g2', 'g3']);
  });

  test('goals kept after Plus ends: each stays editable, no new one beside them', () async {
    await store.putGoal(goal('g1', 'Bike'));
    await store.putGoal(goal('g2', 'Trip', day: 5), allowAnother: true);
    // Plus has ended: nothing asks for another.
    await store.putGoal((await store.goal('g2'))!.copyWith(name: 'Trip to Japan'));
    await store.putGoal((await store.goal('g1'))!.copyWith(name: 'Red bike'));
    expect((await store.activeGoals()).map((g) => g.name), ['Red bike', 'Trip to Japan']);
    await expectLater(store.putGoal(goal('g3', 'Sofa', day: 9)), throwsStateError);
  });

  test('a save goes to the goal chosen; else to the one last saved to, else the oldest', () async {
    await store.putGoal(goal('g1', 'Bike'));
    await store.putGoal(goal('g2', 'Trip', day: 5), allowAnother: true);
    expect((await store.activeGoal())?.id, 'g1', reason: 'nothing saved yet: the oldest');
    expect((await save(500)).goalId, 'g1');
    clock.now = clock.now.add(const Duration(minutes: 1));
    expect((await save(700, goalId: 'g2')).goalId, 'g2');
    expect((await store.activeGoal())?.id, 'g2', reason: 'the goal last saved to');
    clock.now = clock.now.add(const Duration(minutes: 1));
    expect((await save(300)).goalId, 'g2');
    expect(await store.goalProgress((await store.goal('g2'))!), 1000);
    expect(await store.goalProgress((await store.goal('g1'))!), 500);
  });

  test('a save goes only to an active goal', () async {
    await store.putGoal(goal('g1', 'Bike'));
    await store.putGoal(goal('g2', 'Trip', day: 5), allowAnother: true);
    await store.putGoal((await store.goal('g2'))!.copyWith(status: GoalStatus.ended));
    await expectLater(save(100, goalId: 'g2'), throwsArgumentError);
    await expectLater(save(100, goalId: 'nope'), throwsArgumentError);
    expect(await store.entries(), isEmpty, reason: 'nothing written');
  });

  test("an edit: a spend made a save goes to the goal chosen; a save moves only to an active goal", () async {
    await store.putGoal(goal('g1', 'Bike'));
    await store.putGoal(goal('g2', 'Trip', day: 5), allowAnother: true);
    final spend = await store.addEntry(
      type: EntryType.spent,
      amountMinor: 400,
      currency: 'USD',
      localDate: '2026-10-02',
      category: SpendCategory.food,
    );
    final made = await store.updateEntry(
      spend.copyWith(type: EntryType.saved, goalId: 'g2'),
    );
    expect(made.goalId, 'g2');
    final moved = await store.updateEntry(made.copyWith(goalId: 'g1'));
    expect(moved.goalId, 'g1');
    await store.putGoal((await store.goal('g2'))!.copyWith(status: GoalStatus.ended));
    await expectLater(store.updateEntry(moved.copyWith(goalId: 'g2')), throwsArgumentError);
    // A save kept by a goal that's no longer active stays there when edited.
    final kept = await save(100, goalId: 'g1');
    await store.putGoal((await store.goal('g1'))!.copyWith(status: GoalStatus.ended));
    expect((await store.updateEntry(kept.copyWith(amountMinor: 150))).goalId, 'g1');
  });

  test('reached goals: the latest reached first; active and ended ones not', () async {
    Goal reached(String id, int day) => goal(id, id).copyWith(
      status: GoalStatus.reached,
      reachedAt: DateTime.utc(2026, 9, day),
    );
    await store.putGoal(reached('early', 3));
    await store.putGoal(reached('late', 20));
    await store.putGoal(goal('open', 'Open'));
    await store.putGoal(goal('gone', 'Gone', day: 2).copyWith(status: GoalStatus.ended));
    expect((await store.reachedGoals()).map((g) => g.id), ['late', 'early']);
  });
}
