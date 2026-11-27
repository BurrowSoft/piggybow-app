import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:piggybow/summary/summary.dart';

/// The plan's category labels (§2), standing in for the ARB lookup.
const labels = {
  'food': 'Food & drinks',
  'groceries': 'Groceries',
  'transport': 'Transport',
  'home': 'Home & bills',
  'shopping': 'Shopping',
  'fun': 'Fun & going out',
  'health': 'Health & care',
  'gifts': 'Gifts & giving',
  'other': 'Other',
};
String label(String id) => labels[id]!;

/// PB Mobile Tester's fixture S1 (testing/pr4-flows-layout-golden-list.md): today Wednesday
/// 2 December 2026, USD, plan 150.00.
const s1Today = '2026-12-02';
const s1Plan = 15000;
const s1 = [
  SummaryEntry(type: 'spent', amountMinor: 10000, category: 'home', localDate: '2026-11-30'),
  SummaryEntry(type: 'spent', amountMinor: 1250, category: 'food', feeling: 'worth_it', localDate: '2026-12-01'),
  SummaryEntry(type: 'spent', amountMinor: 320, category: 'transport', feeling: 'not_sure', localDate: '2026-12-02'),
  SummaryEntry(type: 'saved', amountMinor: 5000, localDate: '2026-12-01'),
  SummaryEntry(type: 'spent', amountMinor: 4500, category: 'fun', feeling: 'not_really', localDate: '2026-11-24'),
  SummaryEntry(type: 'saved', amountMinor: 2000, localDate: '2026-11-25'),
];

Summary s1Summary(PeriodKind kind, String anyDay) => summarize(
  period: periodContaining(kind, anyDay),
  today: s1Today,
  entries: s1,
  planMinor: s1Plan,
  locale: 'en_US',
  categoryLabel: label,
);

void main() {
  setUpAll(() => initializeDateFormatting());

  group('fixture S1', () {
    test('the current week, Nov 30 – Dec 6', () {
      final s = s1Summary(PeriodKind.week, s1Today);
      expect(s.label, 'Nov 30 – Dec 6');
      expect(s.spentMinor, 11570);
      expect(s.savedMinor, 5000);
      expect(s.categories, const [
        CategoryRow('home', 10000, 86),
        CategoryRow('food', 1250, 10),
        CategoryRow('transport', 320, 2),
      ]);
      expect(s.categories.fold<int>(0, (t, r) => t + r.percent), 98);
      expect([s.worth, s.notSure, s.notReally], [1, 1, 0]);
      expect(s.showWorth, isTrue);
      expect(s.planPercent, 77);
      expect(s.hasPrev, isTrue);
      expect(s.hasNext, isFalse, reason: 'the current period');
      expect(s.isEmpty, isFalse);
    });

    test('the oldest week, Nov 23 – Nov 29: no plan bar, previous disabled', () {
      final s = s1Summary(PeriodKind.week, '2026-11-26');
      expect(s.label, 'Nov 23 – Nov 29');
      expect(s.spentMinor, 4500);
      expect(s.savedMinor, 2000);
      expect(s.categories, const [CategoryRow('fun', 4500, 100)]);
      expect([s.worth, s.notSure, s.notReally], [0, 0, 1]);
      expect(s.planPercent, isNull, reason: 'the plan bar is for the current week only');
      expect(s.hasPrev, isFalse, reason: "the oldest entry's period");
      expect(s.hasNext, isTrue);
    });

    test('December 2026: the Monday spend is November\'s, never December\'s', () {
      final s = s1Summary(PeriodKind.month, s1Today);
      expect(s.label, 'December 2026');
      expect(s.spentMinor, 1570);
      expect(s.savedMinor, 5000);
      expect(s.categories, const [CategoryRow('food', 1250, 79), CategoryRow('transport', 320, 20)]);
      expect([s.worth, s.notSure, s.notReally], [1, 1, 0]);
      expect(s.planPercent, isNull, reason: 'week view only');
      expect(s.hasPrev, isTrue);
      expect(s.hasNext, isFalse);
    });

    test('November 2026', () {
      final s = s1Summary(PeriodKind.month, '2026-11-01');
      expect(s.label, 'November 2026');
      expect(s.spentMinor, 14500);
      expect(s.savedMinor, 2000);
      expect(s.categories, const [CategoryRow('home', 10000, 68), CategoryRow('fun', 4500, 31)]);
      expect([s.worth, s.notSure, s.notReally], [0, 0, 1]);
      expect(s.hasPrev, isFalse);
      expect(s.hasNext, isTrue);
    });
  });

  group('periods', () {
    test('weeks start on Monday whatever the day given', () {
      for (final day in ['2026-11-30', '2026-12-02', '2026-12-06']) {
        expect(periodContaining(PeriodKind.week, day), const Period(PeriodKind.week, '2026-11-30', '2026-12-06'));
      }
    });

    test('months, including February in a leap year', () {
      expect(periodContaining(PeriodKind.month, '2028-02-15'), const Period(PeriodKind.month, '2028-02-01', '2028-02-29'));
      expect(periodContaining(PeriodKind.month, '2027-02-15'), const Period(PeriodKind.month, '2027-02-01', '2027-02-28'));
      expect(periodContaining(PeriodKind.month, '2026-12-31'), const Period(PeriodKind.month, '2026-12-01', '2026-12-31'));
    });

    test('shifting crosses years both ways', () {
      final jan = periodContaining(PeriodKind.month, '2027-01-10');
      expect(periodShift(jan, -1), const Period(PeriodKind.month, '2026-12-01', '2026-12-31'));
      expect(periodShift(periodShift(jan, -1), 1), jan);
      final week = periodContaining(PeriodKind.week, '2026-12-30');
      expect(week, const Period(PeriodKind.week, '2026-12-28', '2027-01-03'));
      expect(periodShift(week, 1), const Period(PeriodKind.week, '2027-01-04', '2027-01-10'));
      expect(periodShift(week, -1), const Period(PeriodKind.week, '2026-12-21', '2026-12-27'));
    });

    test('a malformed date throws', () {
      expect(() => periodContaining(PeriodKind.week, '2026-2-1'), throwsArgumentError);
      expect(() => periodContaining(PeriodKind.month, '2026-02-30'), throwsArgumentError);
    });
  });

  group('labels', () {
    String week(String day, {String today = s1Today, String locale = 'en_US'}) =>
        periodLabel(periodContaining(PeriodKind.week, day), today, locale);

    test('en_US pins (decision 29)', () {
      expect(week('2026-11-23'), 'Nov 23 – Nov 29');
      expect(week('2026-11-30'), 'Nov 30 – Dec 6');
      expect(week('2026-12-28'), 'Dec 28, 2026 – Jan 3, 2027');
      expect(periodLabel(periodContaining(PeriodKind.month, '2026-11-01'), s1Today, 'en_US'), 'November 2026');
    });

    test('a week in another year carries the year on both ends', () {
      expect(week('2025-03-05'), 'Mar 3, 2025 – Mar 9, 2025');
    });

    test('en_GB puts the day first', () {
      expect(week('2026-11-30', locale: 'en_GB'), '30 Nov – 6 Dec');
    });

    test('device locale shapes work, and an unknown locale falls back to en_US', () {
      expect(week('2026-11-30', locale: 'en-GB'), week('2026-11-30', locale: 'en_GB'));
      expect(week('2026-11-30', locale: 'xx_YY'), 'Nov 30 – Dec 6');
    });
  });

  group('rules', () {
    Summary run(List<SummaryEntry> entries, {int? plan, PeriodKind kind = PeriodKind.week, String day = s1Today}) => summarize(
      period: periodContaining(kind, day),
      today: s1Today,
      entries: entries,
      planMinor: plan,
      locale: 'en_US',
      categoryLabel: label,
    );

    test('equal amounts sort by label', () {
      final s = run(const [
        SummaryEntry(type: 'spent', amountMinor: 1000, category: 'transport', localDate: '2026-12-01'),
        SummaryEntry(type: 'spent', amountMinor: 1000, category: 'groceries', localDate: '2026-12-01'),
        SummaryEntry(type: 'spent', amountMinor: 1000, category: 'fun', localDate: '2026-12-01'),
      ]);
      expect(s.categories.map((r) => r.id), ['fun', 'groceries', 'transport']); // Fun, Groceries, Transport
      expect(s.categories.map((r) => r.percent), [33, 33, 33]);
    });

    test('saves never make a category row; only categories with spends appear', () {
      final s = run(const [
        SummaryEntry(type: 'saved', amountMinor: 1000, localDate: '2026-12-01'),
        SummaryEntry(type: 'spent', amountMinor: 500, category: 'food', localDate: '2026-12-01'),
      ]);
      expect(s.categories, const [CategoryRow('food', 500, 100)]);
    });

    test('the worth card hides when no spend in the period has a feeling', () {
      final s = run(const [SummaryEntry(type: 'spent', amountMinor: 500, category: 'food', localDate: '2026-12-01')]);
      expect(s.showWorth, isFalse);
    });

    test('the plan bar caps at 100 and starts at 0', () {
      final over = run(const [SummaryEntry(type: 'spent', amountMinor: 40000, category: 'home', localDate: '2026-12-01')], plan: s1Plan);
      expect(over.planPercent, 100);
      final none = run(const [SummaryEntry(type: 'saved', amountMinor: 100, localDate: '2026-12-01')], plan: s1Plan);
      expect(none.planPercent, 0);
      expect(run(s1, plan: null).planPercent, isNull, reason: 'no plan, no bar');
    });

    test('no entries at all: both arrows disabled, the period is empty', () {
      final s = run(const []);
      expect(s.hasPrev, isFalse);
      expect(s.hasNext, isFalse);
      expect(s.isEmpty, isTrue);
      expect(s.categories, isEmpty);
    });

    test('floored percents never total more than 100, and are exact past 2^53', () {
      final r = Random(33);
      for (var i = 0; i < 2000; i++) {
        final entries = [
          for (final id in labels.keys)
            if (r.nextBool())
              SummaryEntry(type: 'spent', amountMinor: 1 + r.nextInt(1 << 30) * 1000, category: id, localDate: '2026-12-01'),
        ];
        final s = run(entries);
        final total = s.categories.fold<int>(0, (t, row) => t + row.percent);
        expect(total, lessThanOrEqualTo(100));
        if (entries.isNotEmpty) expect(total, greaterThan(100 - entries.length));
      }
      final huge = run([
        for (var i = 0; i < 9000; i++)
          const SummaryEntry(type: 'spent', amountMinor: 999999999999, category: 'home', localDate: '2026-12-01'),
        const SummaryEntry(type: 'spent', amountMinor: 999999999999, category: 'food', localDate: '2026-12-01'),
      ]);
      expect(huge.categories.map((r) => r.percent), [99, 0]);
    });
  });
}
