import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';

import 'helpers.dart';

/// Taking money out of savings (feature 5), in the store: a withdrawal is
/// its own type, out of one goal, at most what that goal has; the goal's
/// progress is its saves less its withdrawals (never below 0); a reached
/// goal stays reached, a stamped band stays stamped; deleting one gives it
/// back.
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

  Goal bike({int target = 100000, int start = 0}) => Goal(
    id: 'g1',
    name: 'Bike',
    targetMinor: target,
    startMinor: start,
    createdAt: DateTime.utc(2026, 9),
    updatedAt: DateTime.utc(2026, 9),
  );

  Future<Goal> g1() async => (await store.goal('g1'))!;
  Future<int> progress() async => store.goalProgress(await g1());

  Future<Entry> save(int minor, {String date = '2026-10-01'}) => store.addEntry(
    type: EntryType.saved,
    amountMinor: minor,
    currency: 'USD',
    localDate: date,
  );

  Future<Entry> takeOut(int minor, {String note = ''}) => store.takeOut(
    goalId: 'g1',
    amountMinor: minor,
    currency: 'USD',
    localDate: '2026-10-02',
    note: note,
  );

  test('a withdrawal: its own type, out of the goal, a positive amount; the '
      'progress goes down by it', () async {
    await store.putGoal(bike(start: 1000));
    await save(4000);
    final w = await takeOut(1500, note: ' New tyre ');
    expect((w.type, w.goalId, w.amountMinor, w.note), (EntryType.withdraw, 'g1', 1500, 'New tyre'));
    expect(w.category, isNull);
    expect(w.feeling, isNull);
    expect(await progress(), 1000 + 4000 - 1500);
    final read = (await store.entry(w.id))!;
    expect(read, w);
    expect(read.toMap()['type'], 'withdraw');
  });

  test('at most what the goal has, the start included; exactly all of it is fine', () async {
    await store.putGoal(bike(start: 1000));
    await save(2000);
    await expectLater(takeOut(3001), throwsStateError);
    expect(await store.takeOutLimit('g1'), 3000);
    await takeOut(3000);
    expect(await progress(), 0);
    await expectLater(takeOut(1), throwsStateError);
    expect((await store.entries()).where((e) => e.type == EntryType.withdraw).length, 1);
  });

  test('only through takeOut: addEntry refuses a withdrawal; a goal that '
      "isn't there has nothing", () async {
    await store.putGoal(bike());
    await save(2000);
    await expectLater(
      store.addEntry(type: EntryType.withdraw, amountMinor: 100, currency: 'USD', localDate: '2026-10-02'),
      throwsArgumentError,
    );
    await expectLater(
      store.takeOut(goalId: 'nope', amountMinor: 100, currency: 'USD', localDate: '2026-10-02'),
      throwsArgumentError,
    );
  });

  test('an edit stays within what the goal has, its own amount counted back; '
      'it stays a withdrawal out of the same goal', () async {
    await store.putGoal(bike());
    await save(5000);
    final w = await takeOut(2000);
    // 5000 saved, 2000 out: 3000 left, so the edit can go up to 5000.
    expect(await store.takeOutLimit('g1', countedBack: w.amountMinor), 5000);
    final edited = await store.updateEntry(w.copyWith(amountMinor: 5000, note: 'All of it'));
    expect((edited.type, edited.goalId, edited.amountMinor), (EntryType.withdraw, 'g1', 5000));
    expect(await progress(), 0);
    await expectLater(store.updateEntry(edited.copyWith(amountMinor: 5001)), throwsStateError);
    await expectLater(store.updateEntry(edited.copyWith(type: EntryType.saved)), throwsArgumentError);
    final s = (await store.entries()).firstWhere((e) => e.type == EntryType.saved);
    await expectLater(store.updateEntry(s.copyWith(type: EntryType.withdraw)), throwsArgumentError);
  });

  test('deleting a withdrawal gives the goal its money back', () async {
    await store.putGoal(bike());
    await save(5000);
    final w = await takeOut(2000);
    expect(await progress(), 3000);
    await store.deleteEntry(w.id);
    expect(await progress(), 5000);
  });

  test('the progress never goes below 0, even if a save is deleted after a '
      'withdrawal', () async {
    await store.putGoal(bike());
    final s = await save(1000);
    await takeOut(1000);
    await store.deleteEntry(s.id);
    expect(await progress(), 0);
    expect(await store.takeOutLimit('g1'), 0);
  });

  test("a reached goal stays reached, and a band stays stamped; the goal's "
      'list has its withdrawals too, newest first', () async {
    await store.putGoal(bike(target: 1000));
    await save(1000);
    expect((await g1()).status, GoalStatus.reached);
    final stamps = (await g1()).bandReachedAt;
    await takeOut(600);
    final after = await g1();
    expect(after.status, GoalStatus.reached);
    expect(after.bandReachedAt, stamps);
    expect(await progress(), 400);
    final list = await store.goalSaves('g1');
    expect(list.map((e) => e.type), [EntryType.withdraw, EntryType.saved]);
  });

  test("an active goal's band, taken out and saved back, is stamped once", () async {
    await store.putGoal(bike(target: 1000));
    await save(250, date: '2026-09-30'); // band 1 (20%) stamped
    final first = (await g1()).bandReachedAt[0];
    expect(first, isNotNull);
    await takeOut(200);
    clock.now = DateTime.utc(2026, 10, 3, 1);
    await save(200);
    expect((await g1()).bandReachedAt[0], first);
    expect((await g1()).status, GoalStatus.active);
  });

  test('a withdrawal read back keeps its goal; a spend never has one', () {
    final now = DateTime.utc(2026, 10, 2);
    final w = Entry.fromMap('w1', {
      'type': 'withdraw',
      'amount_minor': 500,
      'currency': 'USD',
      'goal_id': 'g1',
      'note': '',
      'local_date': '2026-10-02',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    })!;
    expect((w.type, w.goalId), (EntryType.withdraw, 'g1'));
    final s = Entry.fromMap('s1', {
      'type': 'spent',
      'amount_minor': 500,
      'currency': 'USD',
      'category': 'food',
      'goal_id': 'g1',
      'note': '',
      'local_date': '2026-10-02',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    })!;
    expect(s.goalId, isNull);
  });
}
