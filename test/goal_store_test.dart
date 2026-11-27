import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';

import 'helpers.dart';

/// A goal's progress and its sticky stamps in the store (plan §3.4, the
/// tester's PR 3 rows): every save added, edited, moved or deleted, and
/// every goal edit, goes through the goal maths; a reached goal is no longer
/// the active one.
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

  Goal bike({int target = 1000, int start = 0}) => Goal(
    id: 'g1',
    name: 'Bike',
    targetMinor: target,
    startMinor: start,
    createdAt: DateTime.utc(2026, 10),
    updatedAt: DateTime.utc(2026, 10),
  );

  Future<Entry> save(int minor) => store.addEntry(
    type: EntryType.saved,
    amountMinor: minor,
    currency: 'USD',
    localDate: '2026-10-02',
  );

  Future<Goal> g1() async => (await store.goal('g1'))!;
  Future<List<int>> stamped() async => [
    for (final (i, t) in (await g1()).bandReachedAt.indexed)
      if (t != null) i + 1,
  ];

  test(
    'progress is what was already saved plus the saves that name it',
    () async {
      await store.putGoal(bike(start: 150));
      await save(100);
      await store.addEntry(
        type: EntryType.saved,
        amountMinor: 999,
        currency: 'USD',
        localDate: '2026-10-02',
      );
      expect(await store.goalProgress(await g1()), 150 + 100 + 999);
      expect(
        (await store.goalSaves('g1')).map((e) => e.amountMinor),
        unorderedEquals([100, 999]),
      );
    },
  );

  test('bands are stamped as they complete: 199 none, 200 the first, 1000 all and reached', () async {
    await store.putGoal(bike());
    await save(199);
    expect(await stamped(), isEmpty);
    clock.now = DateTime.utc(2026, 10, 2, 2);
    await save(1);
    expect(await stamped(), [1]);
    expect((await g1()).bandReachedAt.first, DateTime.utc(2026, 10, 2, 2));
    await save(799);
    expect(await stamped(), [1, 2, 3, 4]);
    expect((await g1()).status, GoalStatus.active);
    await save(1);
    expect(await stamped(), [1, 2, 3, 4, 5]);
    expect((await g1()).reachedAt, isNotNull);
    expect((await g1()).status, GoalStatus.reached);
  });

  test(
    'after reaching: no active goal, and the next save goes to no goal',
    () async {
      await store.putGoal(bike(target: 100));
      await save(100);
      expect(await store.activeGoal(), isNull);
      final next = await save(50);
      expect(next.goalId, isNull);
    },
  );

  test('sticky: deleting the save that completed band 2 keeps its stamp; a re-cross stamps nothing new', () async {
    await store.putGoal(bike());
    await save(200);
    clock.now = DateTime.utc(2026, 10, 2, 3);
    final second = await save(200);
    final band2 = (await g1()).bandReachedAt[1];
    expect(band2, DateTime.utc(2026, 10, 2, 3));
    await store.deleteEntry(second.id);
    expect(
      await store.goalProgress(await g1()),
      200,
      reason: 'the rainbow draws band 1 again',
    );
    expect((await g1()).bandReachedAt[1], band2, reason: 'the stamp stays');
    clock.now = DateTime.utc(2026, 10, 2, 4);
    await save(200);
    expect(
      (await g1()).bandReachedAt[1],
      band2,
      reason: 're-crossing stamps nothing new',
    );
  });

  test(
    'reaching never unstamps, even when the target is raised later',
    () async {
      await store.putGoal(bike(target: 100));
      await save(100);
      final reached = (await g1()).reachedAt;
      expect(reached, isNotNull);
      await store.putGoal((await g1()).copyWith(targetMinor: 5000));
      expect((await g1()).reachedAt, reached);
      expect((await g1()).status, GoalStatus.reached);
    },
  );

  test(
    'lowering the target below the progress reaches the goal, once',
    () async {
      await store.putGoal(bike());
      await save(600);
      expect((await g1()).reachedAt, isNull);
      clock.now = DateTime.utc(2026, 10, 2, 5);
      await store.putGoal((await g1()).copyWith(targetMinor: 500));
      expect((await g1()).reachedAt, DateTime.utc(2026, 10, 2, 5));
      expect((await g1()).status, GoalStatus.reached);
      expect(await store.celebrated('g1'), isFalse, reason: 'not yet shown');
      await store.markCelebrated('g1');
      expect(await store.celebrated('g1'), isTrue);
    },
  );

  test('a save edited into a spend leaves its goal; a spend edited into a save joins the active goal', () async {
    await store.putGoal(bike());
    final s = await save(300);
    expect(await store.goalProgress(await g1()), 300);
    final spend = await store.updateEntry(
      s.copyWith(type: EntryType.spent, category: SpendCategory.food),
    );
    expect(spend.goalId, isNull);
    expect(await store.goalProgress(await g1()), 0);
    expect(await stamped(), [1], reason: 'band 1 was stamped at 300 and stays');
  });

  test('an ended goal keeps its saves and is no longer active', () async {
    await store.putGoal(bike());
    await save(100);
    await store.putGoal((await g1()).copyWith(status: GoalStatus.ended));
    expect(await store.activeGoal(), isNull);
    expect((await store.goalSaves('g1')).single.goalId, 'g1');
    expect((await store.goals()).single.status, GoalStatus.ended);
  });

  test(
    'an ended goal is never stamped: its save edited past the target',
    () async {
      await store.putGoal(bike());
      final s = await save(300); // 30 %: band 1
      await store.putGoal((await g1()).copyWith(status: GoalStatus.ended));
      await store.updateEntry(s.copyWith(amountMinor: 1500));
      final g = await g1();
      expect(g.status, GoalStatus.ended);
      expect(g.reachedAt, isNull, reason: 'so Home never celebrates it');
      expect(await stamped(), [1], reason: 'band 1 from while it was active');
    },
  );

  test('a goal needs a target above 0 and a start of 0 or more', () async {
    expect(() => store.putGoal(bike(target: 0)), throwsArgumentError);
    expect(() => store.putGoal(bike(start: -1)), throwsArgumentError);
  });
}
