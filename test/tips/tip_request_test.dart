import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;
import 'package:piggybow/tips/tip_request.dart';

/// A written pig tip's request (decision 79): its shape is the contract's,
/// shared with the server, and nothing private ever goes in it: no note, no
/// goal's or category's name, no amount, no date, no currency, no id.
void main() {
  final contract =
      jsonDecode(File('supabase/contracts/pig-tip-request.json').readAsStringSync())
          as Map<String, dynamic>;
  List<String> list(String key) => (contract[key] as List).cast<String>();

  var ids = 0;
  Entry entry(
    String date,
    int minor, {
    EntryType type = EntryType.spent,
    SpendCategory? category,
    String? custom,
    Feeling? feeling,
    String note = '',
  }) => Entry(
    id: 'entry-${++ids}',
    type: type,
    amountMinor: minor,
    currency: 'THB',
    localDate: date,
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 1),
    category: type == EntryType.spent && custom == null
        ? (category ?? SpendCategory.other)
        : null,
    customCategory: custom,
    feeling: feeling,
    note: note,
    goalId: type == EntryType.saved ? 'goal-secret' : null,
  );

  // Friday 2 October 2026: the week is Monday 28 September to Sunday 4 October.
  const today = '2026-10-02';

  TipRequest build(
    List<Entry> entries, {
    int? planMinor,
    int? goalPercent,
    int activeGoals = 0,
    Set<HappyPick> picks = const {},
  }) => buildTipRequest(
    language: 'en',
    todayWire: today,
    entries: entries,
    planMinor: planMinor,
    goalPercent: goalPercent,
    activeGoals: activeGoals,
    picks: picks,
  );

  group("the contract's shape", () {
    test('exactly its keys: the required ones, and the optional only when set', () {
      final bare = build(const []).toJson();
      expect(bare.keys.toSet(), list('required').toSet());
      final full = build(const [], planMinor: 100, goalPercent: 40).toJson();
      expect(full.keys.toSet(), {...list('required'), ...list('optional')});
    });

    test("its category keys are the app's built-ins and the bucket for your own", () {
      expect(list('category_keys'), [
        for (final c in SpendCategory.values) c.id,
        tipYoursBucket,
      ]);
      expect(contract['max_built_in_categories'], tipTopCategories);
    });

    test('its feelings, picks and languages are what the app sends', () {
      expect(build(const []).feelings.keys.toList(), list('feelings'));
      expect(list('picks'), [for (final p in HappyPick.values) p.name]);
      expect(list('languages'), contains('en'));
    });

    test('every value has its kind and range', () {
      final r = build(
        [
          entry('2026-09-28', 100000, category: SpendCategory.food, feeling: Feeling.worthIt),
          entry('2026-09-29', 50000, category: SpendCategory.fun, feeling: Feeling.notReally),
          entry('2026-09-30', 30000, category: SpendCategory.transport),
          entry('2026-10-01', 20000, category: SpendCategory.health),
          entry('2026-10-02', 9000, custom: 'c:1', feeling: Feeling.notSure),
          entry('2026-10-01', 70000, type: EntryType.saved),
        ],
        planMinor: 150000,
        goalPercent: 40,
        activeGoals: 2,
        picks: {HappyPick.worth, HappyPick.save},
      ).toJson();
      final percent = contract['percent'] as Map<String, dynamic>;
      final shares = r['category_shares']! as Map<String, int>;
      expect(shares.keys, everyElement(isIn(list('category_keys'))));
      expect(shares.keys.where((k) => k != tipYoursBucket).length,
          lessThanOrEqualTo(tipTopCategories));
      for (final v in [...shares.values, r['plan_percent'], r['goal_percent']]) {
        expect(v, isA<int>());
        expect(v as int, inInclusiveRange(percent['min'] as int, percent['max'] as int));
      }
      final weekday = contract['weekday'] as Map<String, dynamic>;
      expect(r['weekday'], inInclusiveRange(weekday['min'] as int, weekday['max'] as int));
      expect(r['language'], isIn(list('languages')));
      expect(r['picks'], everyElement(isIn(list('picks'))));
      expect((r['feelings']! as Map<String, int>).values, everyElement(greaterThanOrEqualTo(0)));
    });
  });

  test('nothing private: no note, name, amount, date, currency or id', () {
    final r = build(
      [
        entry('2026-09-28', 987654, category: SpendCategory.gifts, note: 'A ring for Anna'),
        entry('2026-09-29', 123457, custom: 'c:9f2b', note: 'Doctor visit'),
        entry('2026-09-30', 55501, type: EntryType.saved, note: 'Bike money'),
      ],
      planMinor: 4444444,
      goalPercent: 31,
      activeGoals: 1,
      picks: {HappyPick.plan},
    );
    final sent = jsonEncode(r.toJson());
    for (final secret in [
      'Anna', 'ring', 'Doctor', 'Bike', // notes
      'goal-secret', 'c:', '9f2b', 'entry-', // ids
      'THB', '2026', '09-', // currency, dates
      '987654', '9876', '123457', '55501', '4444444', // amounts
    ]) {
      expect(sent, isNot(contains(secret)), reason: secret);
    }
  });

  test("shares: this week so far, whole percents of it, the 3 largest built-ins by amount, "
      'then your own as one bucket', () {
    final r = build([
      entry('2026-09-27', 999999, category: SpendCategory.home), // last Sunday: out
      entry('2026-10-03', 999999, category: SpendCategory.home), // tomorrow: out
      entry('2026-09-28', 40000, category: SpendCategory.food),
      entry('2026-09-29', 20000, category: SpendCategory.fun),
      entry('2026-09-30', 10000, category: SpendCategory.transport),
      entry('2026-09-30', 10000, category: SpendCategory.groceries),
      entry('2026-10-01', 5000, category: SpendCategory.health),
      entry('2026-10-02', 9000, custom: 'c:1'),
      entry('2026-10-02', 6000, custom: 'c:2'),
    ]);
    // 100000 spent: food 40%, fun 20%, then a 10% tie broken by id
    // (groceries before transport); health is fourth; yours 15%.
    expect(r.categoryShares, {'food': 40, 'fun': 20, 'groceries': 10, tipYoursBucket: 15});
  });

  test('shares are floored, never rounded up', () {
    final r = build([
      entry('2026-09-28', 2, category: SpendCategory.food),
      entry('2026-09-28', 1, category: SpendCategory.fun),
    ]);
    expect(r.categoryShares, {'food': 66, 'fun': 33});
  });

  test('feelings and saves are counted; a spend not answered is "none"', () {
    final r = build([
      entry('2026-09-28', 100, feeling: Feeling.worthIt),
      entry('2026-09-28', 100, feeling: Feeling.worthIt),
      entry('2026-09-29', 100, feeling: Feeling.notSure),
      entry('2026-09-29', 100, feeling: Feeling.notReally),
      entry('2026-09-30', 100),
      entry('2026-09-30', 100, type: EntryType.saved),
      entry('2026-10-01', 100, type: EntryType.saved),
      entry('2026-09-21', 100, type: EntryType.saved), // last week: out
    ]);
    expect(r.feelings, {'worth_it': 2, 'not_sure': 1, 'not_really': 1, 'none': 1});
    expect(r.saves, 2);
  });

  test('the plan in whole percent, at most 100 (as Summary); none without a plan', () {
    final spends = [entry('2026-09-28', 30000, category: SpendCategory.food)];
    expect(build(spends, planMinor: 100000).planPercent, 30);
    expect(build(spends, planMinor: 20000).planPercent, 100);
    expect(build(spends).planPercent, isNull);
    expect(build(spends, planMinor: 0).planPercent, isNull);
  });

  test('the weekday, the goal, the goals and the picks, as given', () {
    final r = build(
      const [],
      goalPercent: 57,
      activeGoals: 3,
      picks: {HappyPick.worth, HappyPick.save},
    );
    expect(r.weekday, 5); // Friday
    expect(r.goalPercent, 57);
    expect(r.activeGoals, 3);
    expect(r.picks, ['save', 'worth']);
    expect(r.language, 'en');
  });

  test('a quiet week: no shares, every feeling at 0', () {
    final r = build(const []);
    expect(r.categoryShares, isEmpty);
    expect(r.feelings.values, everyElement(0));
    expect(r.saves, 0);
  });

  test("goal_percent stays within 0 to 100, as the contract allows, whatever is passed", () {
    expect(build(const [], goalPercent: 150).goalPercent, 100);
    expect(build(const [], goalPercent: -5).goalPercent, 0);
    expect(build(const [], goalPercent: 42).goalPercent, 42);
    expect(build(const []).goalPercent, isNull);
  });
}
