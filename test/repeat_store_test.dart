import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/repeat/repeat.dart';

/// Repeats in the journal: the person's first entry starts one; each missed
/// day is added once, marked, never ahead of today or before the repeat
/// existed; edits apply forward; stopping keeps what was added.
void main() {
  late MovableClock clock;
  late JournalStore store;
  var ids = 0;

  setUp(() async {
    ids = 0;
    clock = MovableClock(DateTime.utc(2026, 10, 1, 2));
    store = await JournalStore.inMemory(clock: clock, newId: () => 'e${++ids}');
  });

  tearDown(() => store.close());

  /// Rent, ฿12,000 every month on the 1st, first added on [day].
  Future<Entry> rent({
    String day = '2026-10-01',
    String today = '2026-10-01',
    RepeatSchedule schedule = const RepeatSchedule.monthly(1),
  }) => store.addEntry(
    type: EntryType.spent,
    amountMinor: 1200000,
    currency: 'THB',
    localDate: day,
    category: SpendCategory.home,
    feeling: Feeling.worthIt,
    note: 'Rent',
    repeat: schedule,
    today: today,
  );

  Future<List<String>> catchUp(String today) async => [
    for (final e in await store.catchUpRepeats(today: today)) e.localDate,
  ];

  Future<Repeat> theRepeat() async => (await store.repeats()).single;

  test('the first entry is the person\'s own, and starts the repeat', () async {
    final first = await rent();
    expect(first.repeatId, isNotNull);
    expect(first.auto, isFalse);
    expect(first.feeling, Feeling.worthIt);
    final r = await theRepeat();
    expect(r.id, first.repeatId);
    expect(r.type, EntryType.spent);
    expect(r.amountMinor, 1200000);
    expect(r.currency, 'THB');
    expect(r.category, SpendCategory.home);
    expect(r.note, 'Rent');
    expect(r.schedule, const RepeatSchedule.monthly(1));
    expect(r.firstDate, '2026-10-01');
    expect(r.startedOn, '2026-10-01');
    expect(r.madeThrough, '2026-10-01');
    expect(r.skipThrough, isNull);
    expect(r.running, isTrue);
    expect(await store.entries(), [first]);
  });

  test('never a day before the repeat was made, even after a back-dated first entry', () async {
    await rent(day: '2026-08-01', today: '2026-10-05');
    expect((await theRepeat()).startedOn, '2026-10-05');
    expect((await theRepeat()).madeThrough, '2026-10-05');
    expect(await catchUp('2026-11-01'), ['2026-11-01'], reason: 'not 1 September or 1 October');
  });

  test('each missed day once, marked, with the repeat\'s values and no feeling', () async {
    final first = await rent();
    clock.now = DateTime.utc(2026, 12, 15, 2);
    final added = await store.catchUpRepeats(today: '2026-12-15');
    expect([for (final e in added) e.localDate], ['2026-11-01', '2026-12-01']);
    for (final e in added) {
      expect(e.auto, isTrue);
      expect(e.repeatId, first.repeatId);
      expect(e.type, EntryType.spent);
      expect(e.amountMinor, 1200000);
      expect(e.currency, 'THB');
      expect(e.category, SpendCategory.home);
      expect(e.note, 'Rent');
      expect(e.feeling, isNull, reason: 'never a feeling the person didn\'t give');
      expect(e.createdAt, clock.now);
      expect(await store.entry(e.id), e, reason: 'stored as returned');
    }
    expect(await catchUp('2026-12-15'), isEmpty, reason: 'a second run adds nothing');
    expect((await store.entries()).length, 3);
    expect((await theRepeat()).madeThrough, '2026-12-15');
  });

  test('every week, on its weekday', () async {
    // Monday 5 October 2026.
    await store.addEntry(
      type: EntryType.spent,
      amountMinor: 50000,
      currency: 'THB',
      localDate: '2026-10-05',
      category: SpendCategory.health,
      note: 'Gym',
      repeat: const RepeatSchedule.weekly(1),
      today: '2026-10-05',
    );
    expect(await catchUp('2026-10-25'), ['2026-10-12', '2026-10-19']);
  });

  test('two runs at once add each day once', () async {
    await rent();
    final runs = await Future.wait([
      store.catchUpRepeats(today: '2026-12-15'),
      store.catchUpRepeats(today: '2026-12-15'),
    ]);
    expect(runs[0].length + runs[1].length, 2);
    expect((await store.entries()).length, 3);
  });

  test('a deleted day never comes back; an edited one stays as edited', () async {
    await rent();
    final added = await store.catchUpRepeats(today: '2026-12-01');
    await store.deleteEntry(added.first.id);
    final edited = await store.updateEntry(
      added.last.copyWith(amountMinor: 1150000, feeling: Feeling.notSure),
    );
    expect(edited.auto, isTrue, reason: 'still added by the repeat');
    expect(edited.repeatId, added.last.repeatId);
    expect(await catchUp('2026-12-20'), isEmpty);
    expect(await store.entry(added.first.id), isNull);
    expect(await store.entry(edited.id), edited);
  });

  test('an edit to the repeat applies from its next entry on', () async {
    final first = await rent();
    final november = (await store.catchUpRepeats(today: '2026-11-01')).single;
    await store.updateRepeat(
      (await theRepeat()).copyWith(amountMinor: 1300000, note: '  New rent  '),
    );
    final december = (await store.catchUpRepeats(today: '2026-12-01')).single;
    expect(december.amountMinor, 1300000);
    expect(december.note, 'New rent');
    expect((await store.entry(november.id))!.amountMinor, 1200000);
    expect((await store.entry(first.id))!.amountMinor, 1200000);
  });

  test('a new day in a month that has its entry starts next month', () async {
    await rent();
    expect(await catchUp('2026-11-03'), ['2026-11-01']);
    await store.updateRepeat(
      (await theRepeat()).copyWith(schedule: const RepeatSchedule.monthly(5)),
    );
    expect((await theRepeat()).madeThrough, '2026-11-03', reason: 'only real catch-ups move it');
    expect((await theRepeat()).skipThrough, '2026-11-30');
    expect(await catchUp('2026-11-30'), isEmpty, reason: 'no second November rent');
    expect(await catchUp('2026-12-05'), ['2026-12-05']);
  });

  test('stopped: nothing more, and what it added stays', () async {
    await rent();
    await store.catchUpRepeats(today: '2026-11-01');
    await store.stopRepeat((await theRepeat()).id, today: '2026-11-02');
    expect(await catchUp('2027-01-15'), isEmpty);
    expect((await store.entries()).length, 2);
    final stopped = await theRepeat();
    expect(stopped.running, isFalse);
    expect(stopped.stoppedOn, '2026-11-02');
  });

  test('a trip west, today a day or two back: nothing added, nothing moved', () async {
    await rent();
    expect(await catchUp('2026-11-03'), ['2026-11-01']);
    expect(await catchUp('2026-11-01'), isEmpty);
    expect((await theRepeat()).madeThrough, '2026-11-03');
    expect((await store.entries()).length, 2);
  });

  test('a clock set back weeks: nothing added now, and nothing twice when the days come again', () async {
    await rent();
    expect(await catchUp('2026-12-15'), ['2026-11-01', '2026-12-01']);
    expect(await catchUp('2026-11-20'), isEmpty);
    expect(await catchUp('2026-12-20'), isEmpty, reason: '1 December is there already');
    expect((await store.entries()).length, 3);
  });

  test('a clock years ahead adds a year\'s worth at most', () async {
    await rent();
    final added = await catchUp('2029-10-15');
    expect(added.length, 12);
    expect(added.first, '2028-11-01');
    expect(added.last, '2029-10-01');
  });

  test('a clock years ahead, then put right: the repeat carries on from its last real entry', () async {
    await rent();
    expect(await catchUp('2029-10-15'), hasLength(12));
    expect(await catchUp('2026-11-02'), ['2026-11-01'], reason: 'November\'s rent, once');
    expect((await theRepeat()).madeThrough, '2026-11-02');
    expect(await catchUp('2026-11-02'), isEmpty);
    expect(await catchUp('2026-12-01'), ['2026-12-01']);
  });

  test('a repeat made while the clock was ahead: once put right, it starts from today', () async {
    await rent(day: '2029-10-01', today: '2029-10-15');
    expect(await catchUp('2026-11-02'), isEmpty);
    expect((await theRepeat()).madeThrough, '2026-11-02');
    expect(await catchUp('2026-12-01'), ['2026-12-01']);
  });

  test('a schedule change made while the clock was ahead: its skip goes once put right', () async {
    await rent();
    await store.catchUpRepeats(today: '2029-10-15');
    await store.updateRepeat(
      (await theRepeat()).copyWith(schedule: const RepeatSchedule.monthly(5)),
    );
    expect((await theRepeat()).skipThrough, '2029-10-31');
    // October had its rent on the 1st: no second one on the 5th.
    expect(await catchUp('2026-11-06'), ['2026-11-05']);
    expect((await theRepeat()).skipThrough, '2026-10-31');
  });

  test("a repeating save goes to its first entry's goal; once reached, the next to none", () async {
    await store.putGoal(
      Goal(
        id: 'g1',
        name: 'Bike',
        targetMinor: 300000,
        createdAt: clock.nowUtc(),
        updatedAt: clock.nowUtc(),
      ),
    );
    final first = await store.addEntry(
      type: EntryType.saved,
      amountMinor: 100000,
      currency: 'THB',
      localDate: '2026-10-01',
      repeat: const RepeatSchedule.monthly(1),
      today: '2026-10-01',
    );
    expect(first.goalId, 'g1');
    final added = await store.catchUpRepeats(today: '2027-01-01');
    expect([for (final e in added) e.localDate], ['2026-11-01', '2026-12-01', '2027-01-01']);
    expect([for (final e in added) e.goalId], ['g1', 'g1', null]);
    final goal = (await store.goal('g1'))!;
    expect(goal.status, GoalStatus.reached);
    expect(goal.reachedAt, isNotNull);
    expect(await store.goalProgress(goal), 300000);
  });

  group("with two goals, a repeating save never goes to a goal the person didn't pick", () {
    Goal goal(String id, String name, int target) => Goal(
      id: id,
      name: name,
      targetMinor: target,
      createdAt: clock.nowUtc(),
      updatedAt: clock.nowUtc(),
    );

    /// ฿1,000 saved every month on the 1st, the first to [goalId].
    Future<Entry> monthlySave({String? goalId, bool noGoal = false}) => store.addEntry(
      type: EntryType.saved,
      amountMinor: 100000,
      currency: 'THB',
      localDate: '2026-10-01',
      goalId: goalId,
      noGoal: noGoal,
      repeat: const RepeatSchedule.monthly(1),
      today: '2026-10-01',
    );

    test("its first entry's goal, even when another is the default", () async {
      await store.putGoal(goal('g1', 'Bike', 10000000));
      await store.putGoal(goal('g2', 'Trip', 10000000), allowAnother: true);
      expect((await monthlySave(goalId: 'g2')).goalId, 'g2');
      expect((await theRepeat()).goalId, 'g2');
      // A save of the person's own to Bike makes Bike the default.
      clock.now = DateTime.utc(2026, 10, 2, 2);
      await store.addEntry(
        type: EntryType.saved,
        amountMinor: 500,
        currency: 'THB',
        localDate: '2026-10-02',
        goalId: 'g1',
      );
      expect((await store.activeGoal())?.id, 'g1');
      final added = await store.catchUpRepeats(today: '2026-12-01');
      expect([for (final e in added) e.goalId], ['g2', 'g2']);
    });

    test('once its goal is reached, none: never the other goal', () async {
      await store.putGoal(goal('g1', 'Bike', 10000000));
      await store.putGoal(goal('g2', 'Trip', 150000), allowAnother: true);
      await monthlySave(goalId: 'g2');
      final added = await store.catchUpRepeats(today: '2026-12-01');
      expect([for (final e in added) e.goalId], ['g2', null]);
      expect((await store.goal('g2'))!.status, GoalStatus.reached);
      expect((await store.goal('g1'))!.status, GoalStatus.active);
    });

    test('a first save to no goal: its repeats go to none, even once a goal exists', () async {
      expect((await monthlySave()).goalId, isNull);
      expect((await theRepeat()).goalId, isNull);
      await store.putGoal(goal('g1', 'Bike', 10000000));
      final added = await store.catchUpRepeats(today: '2026-11-01');
      expect([for (final e in added) e.goalId], [null]);
    });

    test('a first save kept out of the goal: its repeats stay out', () async {
      await store.putGoal(goal('g1', 'Bike', 10000000));
      expect((await monthlySave(noGoal: true)).goalId, isNull);
      final added = await store.catchUpRepeats(today: '2026-11-01');
      expect([for (final e in added) e.goalId], [null]);
    });
  });

  test('a repeat needs today and a valid schedule; nothing is written without', () async {
    Future<Entry> add({RepeatSchedule? repeat, String? today}) => store.addEntry(
      type: EntryType.spent,
      amountMinor: 1000,
      currency: 'THB',
      localDate: '2026-10-01',
      category: SpendCategory.food,
      repeat: repeat,
      today: today,
    );
    await expectLater(add(repeat: const RepeatSchedule.monthly(1)), throwsArgumentError);
    await expectLater(add(repeat: const RepeatSchedule.monthly(32), today: '2026-10-01'), throwsArgumentError);
    expect(await store.entries(), isEmpty);
    expect(await store.repeats(), isEmpty);
    expect(await store.isBlank(), isTrue);
  });

  test('a repeating spend in a category of your own is refused, and nothing is written', () async {
    final mine = CustomCategory(
      id: '${CustomCategory.idPrefix}a',
      name: 'Coffee',
      icon: CategoryIcon.coffee,
      createdAt: clock.nowUtc(),
    );
    await store.putCustomCategory(mine);
    await expectLater(
      store.addEntry(
        type: EntryType.spent,
        amountMinor: 450,
        currency: 'THB',
        localDate: '2026-10-01',
        customCategory: mine.id,
        repeat: const RepeatSchedule.monthly(1),
        today: '2026-10-01',
      ),
      throwsArgumentError,
    );
    expect(await store.entries(), isEmpty);
    expect(await store.repeats(), isEmpty);
  });

  test('Delete everything erases the repeats too', () async {
    await rent();
    expect(await store.isBlank(), isFalse);
    await store.wipe();
    expect(await store.repeats(), isEmpty);
    expect(await catchUp('2026-12-01'), isEmpty);
    expect(await store.isBlank(), isTrue);
  });

  test('an entry\'s repeat fields: kept by an edit, read back, absent from older records', () async {
    final first = await rent();
    final edited = await store.updateEntry(first.copyWith(amountMinor: 1, note: 'x'));
    expect(edited.repeatId, first.repeatId);
    expect(edited.auto, isFalse);

    final auto = Entry(
      id: 'a',
      type: EntryType.saved,
      amountMinor: 5,
      currency: 'THB',
      localDate: '2026-11-01',
      createdAt: DateTime.utc(2026, 11),
      updatedAt: DateTime.utc(2026, 11),
      repeatId: 'r1',
      auto: true,
    );
    expect(Entry.fromMap('a', auto.toMap()), auto);
    final older = {...auto.toMap()}
      ..remove('repeat_id')
      ..remove('auto');
    final read = Entry.fromMap('a', older)!;
    expect(read.repeatId, isNull);
    expect(read.auto, isFalse);
  });
}

class MovableClock extends Clock {
  MovableClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}
