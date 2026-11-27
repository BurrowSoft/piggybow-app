import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';

/// The journal on the phone: integer money, the day the person picked, a
/// save going to the active goal, Spent ↔ Saved edits, and a full wipe.
void main() {
  late MovableClock clock;
  late JournalStore store;
  var ids = 0;

  setUp(() async {
    ids = 0;
    clock = MovableClock(DateTime.utc(2026, 11, 28, 2, 0));
    store = await JournalStore.inMemory(clock: clock, newId: () => 'e${++ids}');
  });

  tearDown(() => store.close());

  Future<Entry> spend(int minor, String day, {String note = ''}) => store.addEntry(
    type: EntryType.spent,
    amountMinor: minor,
    currency: 'THB',
    localDate: day,
    category: SpendCategory.food,
    feeling: Feeling.worthIt,
    note: note,
  );

  Goal goal(String id, {GoalStatus status = GoalStatus.active}) => Goal(
    id: id,
    name: 'Bike',
    targetMinor: 100000,
    status: status,
    createdAt: clock.nowUtc(),
    updatedAt: clock.nowUtc(),
  );

  test('a spend: integer minor units, its day, category and feeling', () async {
    final e = await spend(12550, '2026-11-27', note: '  Coffee ☕  ');
    expect(e.id, 'e1');
    expect(e.amountMinor, 12550);
    expect(e.currency, 'THB');
    expect(e.localDate, '2026-11-27');
    expect(e.category, SpendCategory.food);
    expect(e.feeling, Feeling.worthIt);
    expect(e.note, 'Coffee ☕', reason: 'trimmed');
    expect(e.goalId, isNull);
    expect(e.createdAt, clock.nowUtc());
    expect(await store.entry('e1'), e, reason: 'read back as written');
  });

  test('a save goes to the active goal; with none, to no goal', () async {
    final none = await store.addEntry(
      type: EntryType.saved,
      amountMinor: 5000,
      currency: 'THB',
      localDate: '2026-11-28',
      category: SpendCategory.food,
      feeling: Feeling.notSure,
    );
    expect(none.goalId, isNull);
    expect(none.category, isNull, reason: 'saves have no category');
    expect(none.feeling, isNull, reason: 'or feeling');

    await store.putGoal(goal('old', status: GoalStatus.ended));
    await store.putGoal(goal('bike'));
    final save = await store.addEntry(
      type: EntryType.saved,
      amountMinor: 5000,
      currency: 'THB',
      localDate: '2026-11-28',
    );
    expect(save.goalId, 'bike');
  });

  test('newest day first; within a day, the newest added first', () async {
    await spend(100, '2026-11-26');
    clock.now = clock.now.add(const Duration(minutes: 1));
    await spend(200, '2026-11-28');
    clock.now = clock.now.add(const Duration(minutes: 1));
    await spend(300, '2026-11-28');
    clock.now = clock.now.add(const Duration(minutes: 1));
    await spend(400, '2026-11-27');
    expect([for (final e in await store.entries()) e.amountMinor], [300, 200, 400, 100]);
  });

  test('edit: Spent → Saved drops the category and finds the goal; back again drops the goal', () async {
    await store.putGoal(goal('bike'));
    final e = await spend(900, '2026-11-28');
    clock.now = clock.now.add(const Duration(hours: 1));
    final saved = await store.updateEntry(e.copyWith(type: EntryType.saved));
    expect(saved.category, isNull);
    expect(saved.feeling, isNull);
    expect(saved.goalId, 'bike');
    expect(saved.createdAt, e.createdAt);
    expect(saved.updatedAt, clock.nowUtc());
    expect(saved.currency, 'THB');

    final back = await store.updateEntry(
      saved.copyWith(type: EntryType.spent, category: SpendCategory.fun),
    );
    expect(back.goalId, isNull);
    expect(back.category, SpendCategory.fun);
  });

  test('delete; and every change tells the listeners', () async {
    var heard = 0;
    store.addListener(() => heard++);
    final e = await spend(100, '2026-11-28');
    await store.updateEntry(e.copyWith(amountMinor: 200));
    await store.deleteEntry(e.id);
    expect(await store.entry(e.id), isNull);
    expect(await store.entries(), isEmpty);
    expect(heard, 3);
  });

  test('refused: zero or less, a spend with no category, a note over 80 characters', () async {
    expect(() => spend(0, '2026-11-28'), throwsArgumentError);
    expect(
      () => store.addEntry(
        type: EntryType.spent,
        amountMinor: 100,
        currency: 'THB',
        localDate: '2026-11-28',
      ),
      throwsArgumentError,
    );
    // 80 characters as a person counts them: emoji with joiners are one each
    // (woman, joiner, woman, joiner, girl), built from code points so the
    // source holds no hidden character.
    final family =
        String.fromCharCodes([0x1F469, 0x200D, 0x1F469, 0x200D, 0x1F467]) * 80;
    expect((await spend(1, '2026-11-28', note: family)).note, family);
    expect(() => spend(1, '2026-11-28', note: '${family}x'), throwsArgumentError);
    expect(await store.entries(), hasLength(1), reason: 'nothing refused was stored');
  });

  test('the currency is a journal setting', () async {
    expect(await store.currency(), isNull);
    await store.setCurrency('JPY');
    expect(await store.currency(), 'JPY');
  });

  test('wipe erases entries, goals and settings', () async {
    await spend(100, '2026-11-28');
    await store.putGoal(goal('bike'));
    await store.setCurrency('THB');
    await store.wipe();
    expect(await store.entries(), isEmpty);
    expect(await store.activeGoal(), isNull);
    expect(await store.currency(), isNull);
  });

  test('a record this build cannot read is skipped, never half-read', () {
    final good = Entry(
      id: 'x',
      type: EntryType.spent,
      amountMinor: 1,
      currency: 'THB',
      category: SpendCategory.other,
      localDate: '2026-11-28',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ).toMap();
    expect(Entry.fromMap('x', good), isNotNull);
    expect(Entry.fromMap('x', {...good, 'amount_minor': 1.5}), isNull, reason: 'never a double');
    expect(Entry.fromMap('x', {...good, 'amount_minor': -3}), isNull);
    expect(Entry.fromMap('x', {...good, 'type': 'lent'}), isNull);
    expect(Entry.fromMap('x', {...good, 'local_date': '28/11/2026'}), isNull);
  });
}

class MovableClock extends Clock {
  MovableClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}
