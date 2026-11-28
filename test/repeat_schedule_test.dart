import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/repeat/repeat.dart';
import 'package:piggybow/repeat/schedule.dart';

/// The days a repeat falls on: every month on a day (the month's last day
/// when it's shorter), every week on a weekday; what a schedule change
/// keeps; and the catch-up's year back.
void main() {
  DateTime day(String s) => parseWireDate(s)!;
  List<String> days(RepeatSchedule s, String after, String through) => [
    for (final d in occurrences(s, after: day(after), through: day(through)))
      wireDate(d),
  ];

  group('every month', () {
    test('day 31: each month\'s last day, and the 31st again after a shorter month', () {
      expect(days(const RepeatSchedule.monthly(31), '2026-01-31', '2026-12-31'), [
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
        '2026-05-31',
        '2026-06-30',
        '2026-07-31',
        '2026-08-31',
        '2026-09-30',
        '2026-10-31',
        '2026-11-30',
        '2026-12-31',
      ]);
    });

    test('days 29 and 30 in February: the 28th, or the 29th in a leap year', () {
      expect(days(const RepeatSchedule.monthly(29), '2027-01-29', '2027-03-29'), [
        '2027-02-28',
        '2027-03-29',
      ]);
      expect(days(const RepeatSchedule.monthly(29), '2028-01-29', '2028-03-29'), [
        '2028-02-29',
        '2028-03-29',
      ]);
      expect(days(const RepeatSchedule.monthly(30), '2028-01-30', '2028-03-30'), [
        '2028-02-29',
        '2028-03-30',
      ]);
    });

    test('across a year end', () {
      expect(days(const RepeatSchedule.monthly(15), '2026-11-15', '2027-02-14'), [
        '2026-12-15',
        '2027-01-15',
      ]);
    });
  });

  group('every week', () {
    test('on its weekday, across a year end', () {
      // Sunday (7), from Saturday 26 December 2026.
      expect(days(const RepeatSchedule.weekly(7), '2026-12-26', '2027-01-10'), [
        '2026-12-27',
        '2027-01-03',
        '2027-01-10',
      ]);
    });

    test('the day after is never the day itself; the last day counts', () {
      // Monday (1), from Monday 2 November 2026.
      expect(days(const RepeatSchedule.weekly(1), '2026-11-02', '2026-11-16'), [
        '2026-11-09',
        '2026-11-16',
      ]);
      expect(days(const RepeatSchedule.weekly(1), '2026-11-02', '2026-11-02'), isEmpty);
      expect(days(const RepeatSchedule.monthly(2), '2026-11-02', '2026-11-01'), isEmpty);
    });
  });

  test('the schedule an entry starts, and which are valid', () {
    // Tuesday 3 November 2026.
    expect(RepeatSchedule.from(RepeatKind.monthly, day('2026-11-03')), const RepeatSchedule.monthly(3));
    expect(RepeatSchedule.from(RepeatKind.weekly, day('2026-11-03')), const RepeatSchedule.weekly(2));
    expect(RepeatSchedule.lastDay, const RepeatSchedule.monthly(31));
    expect(const RepeatSchedule.monthly(0).isValid, isFalse);
    expect(const RepeatSchedule.monthly(32).isValid, isFalse);
    expect(const RepeatSchedule.weekly(8).isValid, isFalse);
    expect(isLastDayOfMonth(day('2026-04-30')), isTrue);
    expect(isLastDayOfMonth(day('2028-02-29')), isTrue);
    expect(isLastDayOfMonth(day('2028-02-28')), isFalse);
  });

  test('the last day it fell on; the first entry\'s own day when none later', () {
    DateTime last(RepeatSchedule s, String first, String through) =>
        lastOccurrence(s, first: day(first), through: day(through));
    expect(last(const RepeatSchedule.monthly(1), '2026-10-01', '2026-11-03'), day('2026-11-01'));
    expect(last(const RepeatSchedule.monthly(10), '2026-10-10', '2026-11-03'), day('2026-10-10'));
    expect(last(const RepeatSchedule.weekly(7), '2026-10-25', '2026-11-03'), day('2026-11-01'));
    // "The last day", picked on 30 April: nothing after it by 15 May.
    expect(last(RepeatSchedule.lastDay, '2026-04-30', '2026-05-15'), day('2026-04-30'));
  });

  group('a schedule change', () {
    DateTime? changed(RepeatSchedule old, RepeatSchedule to, String first, String made) =>
        skipAfterChange(old: old, changed: to, first: day(first), madeThrough: day(made));

    test('rent from the 1st to the 5th on 3 November: November is skipped', () {
      expect(
        changed(const RepeatSchedule.monthly(1), const RepeatSchedule.monthly(5), '2026-10-01', '2026-11-03'),
        day('2026-11-30'),
      );
    });

    test('before this month\'s entry: nothing skipped, the new day still comes this month', () {
      expect(
        changed(const RepeatSchedule.monthly(10), const RepeatSchedule.monthly(5), '2026-10-10', '2026-11-03'),
        isNull,
      );
    });

    test('monthly to weekly and back go by the new kind\'s period', () {
      // Sunday 1 November had the monthly one; its week ended that day.
      expect(
        changed(const RepeatSchedule.monthly(1), const RepeatSchedule.weekly(7), '2026-10-01', '2026-11-03'),
        isNull,
      );
      // Sunday 1 November had the weekly one: November is done.
      expect(
        changed(const RepeatSchedule.weekly(7), const RepeatSchedule.monthly(5), '2026-10-25', '2026-11-03'),
        day('2026-11-30'),
      );
    });

    test('no change, no skip', () {
      expect(
        changed(const RepeatSchedule.monthly(1), const RepeatSchedule.monthly(1), '2026-10-01', '2026-11-03'),
        isNull,
      );
    });
  });

  test('a clock set ahead: more than any time zone explains', () {
    // A trip west moves today back by up to 2 days.
    expect(clockWasAhead(day('2026-11-05'), day('2026-11-03')), isFalse);
    expect(clockWasAhead(day('2026-11-06'), day('2026-11-03')), isTrue);
    // A schedule change's skip ends at most a month after the change.
    expect(skipFromClockAhead(day('2026-12-06'), day('2026-11-03')), isFalse);
    expect(skipFromClockAhead(day('2026-12-07'), day('2026-11-03')), isTrue);
  });

  group('a catch-up', () {
    var n = 0;
    Repeat repeat(RepeatSchedule s, String madeThrough, {String? stoppedOn, String? skipThrough}) => Repeat(
      id: 'r${++n}',
      type: EntryType.spent,
      amountMinor: 1000,
      currency: 'THB',
      category: SpendCategory.home,
      schedule: s,
      firstDate: madeThrough,
      startedOn: madeThrough,
      madeThrough: madeThrough,
      skipThrough: skipThrough,
      createdAt: DateTime.utc(2026).add(Duration(minutes: n)),
      updatedAt: DateTime.utc(2026),
      stoppedOn: stoppedOn,
    );

    test('after a schedule change\'s skip: nothing until it ends', () {
      final r = repeat(const RepeatSchedule.monthly(5), '2026-11-03', skipThrough: '2026-11-30');
      expect([for (final (_, d) in dueOccurrences([r], day('2026-11-30'))) wireDate(d)], isEmpty);
      expect([for (final (_, d) in dueOccurrences([r], day('2026-12-10'))) wireDate(d)], ['2026-12-05']);
    });

    test('goes a year back at most (28 February for 29 February)', () {
      expect(catchUpStart(day('2026-11-28')), day('2025-11-28'));
      expect(catchUpStart(day('2028-02-29')), day('2027-02-28'));
      final due = dueOccurrences([repeat(const RepeatSchedule.monthly(1), '2023-06-01')], day('2026-11-28'));
      expect([for (final (_, d) in due) wireDate(d)], [
        '2025-12-01',
        '2026-01-01',
        '2026-02-01',
        '2026-03-01',
        '2026-04-01',
        '2026-05-01',
        '2026-06-01',
        '2026-07-01',
        '2026-08-01',
        '2026-09-01',
        '2026-10-01',
        '2026-11-01',
      ]);
    });

    test('oldest day first; on one day, the older repeat first; none from a stopped one', () {
      final rent = repeat(const RepeatSchedule.monthly(2), '2026-10-31');
      final gym = repeat(const RepeatSchedule.weekly(1), '2026-10-31');
      final old = repeat(const RepeatSchedule.monthly(1), '2026-10-31', stoppedOn: '2026-10-31');
      final due = dueOccurrences([gym, old, rent], day('2026-11-09'));
      // Monday 2 November: rent (made first) before the gym.
      expect([for (final (r, d) in due) '${r.id} ${wireDate(d)}'], [
        '${rent.id} 2026-11-02',
        '${gym.id} 2026-11-02',
        '${gym.id} 2026-11-09',
      ]);
    });

    test('an entry\'s id is its repeat and day', () {
      expect(repeatEntryId('r1', day('2026-11-01')), 'repeat-r1-2026-11-01');
    });
  });

  test('a repeat record this build can\'t read is skipped, never half-read', () {
    final good = Repeat(
      id: 'r',
      type: EntryType.spent,
      amountMinor: 1200000,
      currency: 'THB',
      category: SpendCategory.home,
      note: 'Rent',
      schedule: const RepeatSchedule.monthly(1),
      firstDate: '2026-10-01',
      startedOn: '2026-10-01',
      madeThrough: '2026-10-01',
      skipThrough: '2026-10-31',
      createdAt: DateTime.utc(2026, 10),
      updatedAt: DateTime.utc(2026, 10),
    );
    final map = good.toMap();
    expect(Repeat.fromMap('r', map), good);
    expect(Repeat.fromMap('r', {...map, 'skip_through': null})?.skipThrough, isNull);
    expect(Repeat.fromMap('r', {...map, 'type': 'lent'}), isNull, reason: 'a spend or a save only');
    expect(Repeat.fromMap('r', {...map, 'started_on': null}), isNull);
    expect(Repeat.fromMap('r', {...map, 'skip_through': '31/10/2026'}), isNull);
    expect(Repeat.fromMap('r', {...map, 'amount_minor': 1.5}), isNull, reason: 'never a double');
    expect(Repeat.fromMap('r', {...map, 'amount_minor': 0}), isNull);
    expect(Repeat.fromMap('r', {...map, 'kind': 'yearly'}), isNull);
    expect(Repeat.fromMap('r', {...map, 'day': 32}), isNull);
    expect(Repeat.fromMap('r', {...map, 'category': null}), isNull, reason: 'a spend needs one');
    expect(Repeat.fromMap('r', {...map, 'made_through': '1/10/2026'}), isNull);
    expect(Repeat.fromMap('r', {...map, 'stopped_on': '2026-10-05'})?.running, isFalse);
  });

  test('a repeat in a category of your own: one field, as an entry\'s; a built-in replaces it and back', () {
    const tea = '${CustomCategory.idPrefix}tea';
    final mine = Repeat(
      id: 'r',
      type: EntryType.spent,
      amountMinor: 6500,
      currency: 'THB',
      customCategory: tea,
      schedule: const RepeatSchedule.weekly(5),
      firstDate: '2026-10-02',
      startedOn: '2026-10-02',
      madeThrough: '2026-10-02',
      createdAt: DateTime.utc(2026, 10),
      updatedAt: DateTime.utc(2026, 10),
    );
    final map = mine.toMap();
    expect(map['category'], tea);
    expect(Repeat.fromMap('r', map), mine);
    expect((mine.category, mine.customCategory, mine.categoryId), (null, tea, tea));
    expect(Repeat.fromMap('r', {...map, 'category': 'tea'}), isNull, reason: 'neither a built-in nor your own');

    final home = mine.copyWith(category: SpendCategory.home);
    expect((home.category, home.customCategory, home.categoryId), (SpendCategory.home, null, 'home'));
    final back = home.copyWith(customCategory: tea);
    expect((back.category, back.customCategory), (null, tea));
    expect(back.copyWith(note: 'Boba').customCategory, tea, reason: 'kept when not changed');

    // A save has neither.
    final save = Repeat.fromMap('r', {...map, 'type': EntryType.saved.id})!;
    expect((save.category, save.customCategory), (null, null));
    expect(save.copyWith(customCategory: tea).customCategory, isNull);
  });

  test("a save's repeat keeps its goal; a spend's has none; older records read as none", () {
    final save = Repeat(
      id: 's',
      type: EntryType.saved,
      amountMinor: 100000,
      currency: 'THB',
      goalId: 'g1',
      schedule: const RepeatSchedule.monthly(1),
      firstDate: '2026-10-01',
      startedOn: '2026-10-01',
      madeThrough: '2026-10-01',
      createdAt: DateTime.utc(2026, 10),
      updatedAt: DateTime.utc(2026, 10),
    );
    final map = save.toMap();
    expect(Repeat.fromMap('s', map), save);
    expect(Repeat.fromMap('s', map)?.goalId, 'g1');
    expect(Repeat.fromMap('s', {...map}..remove('goal_id'))?.goalId, isNull);
    expect(save.copyWith(madeThrough: '2026-11-01').goalId, 'g1');
    final spend = {...map, 'type': EntryType.spent.id, 'category': SpendCategory.home.id};
    expect(Repeat.fromMap('s', spend)?.goalId, isNull, reason: 'spends go to no goal');
  });
}
