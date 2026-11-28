import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/summary/patterns.dart';
import 'package:piggybow/summary/summary.dart' show SummaryEntry;

/// Feature 20, Patterns (specs/insights-plan.md): up to 3 facts about how
/// spends felt in the last 8 weeks, by category and by weekday. Nothing below
/// 20 spends with a feeling; 5 per category; 4 per weekday over 3 different
/// days; "mostly worth it" at 60 % and 15 points above all spends; "mixed"
/// when no feeling has half and two have a quarter. "Not really" is never a
/// pattern. Only the type, category, feeling and day are read: the input has
/// no notes, no time of day, and amounts don't count.
void main() {
  // Friday 2 October 2026; the window is Saturday 8 August to today.
  const today = '2026-10-02';
  const labels = {
    'food': 'Food',
    'fun': 'Fun',
    'health': 'Health',
    'other': 'Other',
    'shopping': 'Shopping',
    'transport': 'Transport',
    'c:abc': 'Bike parts',
  };

  SummaryEntry spend(
    String feeling, {
    String category = 'food',
    String day = '2026-10-01',
    int amount = 500,
    String type = 'spent',
  }) => SummaryEntry(
    type: type,
    amountMinor: amount,
    category: category,
    feeling: feeling,
    localDate: day,
  );

  List<SummaryEntry> times(int n, SummaryEntry e) => List.filled(n, e);

  /// Spends that felt "not sure", in Other, on one Wednesday: they count
  /// towards the 20 and make no pattern of their own.
  List<SummaryEntry> filler(int n) =>
      times(n, spend('not_sure', category: 'other', day: '2026-09-30'));

  FeelingPatterns patterns(List<SummaryEntry> entries) => feelingPatterns(
    entries: entries,
    today: today,
    categoryLabel: (id) => labels[id] ?? id,
  );

  FeelingPatterns found(List<FeelingPattern> p) =>
      FeelingPatterns(PatternsState.found, p);
  const notYet = FeelingPatterns(PatternsState.notYet);
  const none = FeelingPatterns(PatternsState.none);

  group('enough to go on', () {
    test('fewer than 20 spends with a feeling: not yet', () {
      expect(patterns(filler(19)), notYet);
      expect(patterns(filler(20)), none);
    });

    test('spends without a feeling, saves and withdrawals never count', () {
      expect(
        patterns([
          ...filler(19),
          for (var i = 0; i < 5; i++)
            const SummaryEntry(
              type: 'spent',
              amountMinor: 500,
              category: 'food',
              localDate: '2026-10-01',
            ),
          spend('worth_it', type: 'saved'),
          spend('worth_it', type: 'withdraw'),
        ]),
        notYet,
      );
    });

    test('the last 8 weeks, today included: from 8 August', () {
      expect(
        patterns([...filler(19), spend('not_sure', day: '2026-08-08')]),
        none,
      );
      expect(
        patterns([...filler(19), spend('not_sure', day: '2026-08-07')]),
        notYet,
      );
      expect(
        patterns([...filler(19), spend('not_sure', day: '2026-10-03')]),
        notYet,
        reason: 'after today',
      );
    });
  });

  group('by category', () {
    test('mostly worth it: at least 60 %, 15 points above all spends', () {
      expect(
        patterns([
          ...filler(15),
          ...times(6, spend('worth_it')),
          spend('not_really'),
        ]),
        found([const FeelingPattern.categoryWorth('food')]),
      );
    });

    test('at least 5 spends with a feeling in the category', () {
      expect(patterns([...filler(16), ...times(4, spend('worth_it'))]), none);
      expect(
        patterns([...filler(15), ...times(5, spend('worth_it'))]),
        found([const FeelingPattern.categoryWorth('food')]),
      );
    });

    test('not far enough above all spends: the overall line instead', () {
      // Food 90 %, Fun 80 %, all 85 %: neither is 15 points above.
      expect(
        patterns([
          ...times(9, spend('worth_it')),
          spend('not_sure'),
          ...times(8, spend('worth_it', category: 'fun')),
          ...times(2, spend('not_sure', category: 'fun')),
        ]),
        found([const FeelingPattern.overallWorth()]),
      );
    });

    test('mixed: no feeling has half, and two have a quarter', () {
      expect(
        patterns([
          ...filler(15),
          ...times(2, spend('worth_it', category: 'shopping')),
          ...times(2, spend('not_sure', category: 'shopping')),
          spend('not_really', category: 'shopping'),
        ]),
        found([const FeelingPattern.categoryMixed('shopping')]),
      );
    });

    test('"not really" is never a pattern of its own', () {
      expect(
        patterns([
          ...filler(15),
          ...times(5, spend('not_really', category: 'fun')),
        ]),
        none,
      );
      expect(
        patterns([
          ...filler(15),
          ...times(2, spend('worth_it', category: 'fun')),
          ...times(3, spend('not_really', category: 'fun')),
        ]),
        none,
        reason: '60 % not really: neither mostly worth it nor mixed',
      );
    });

    test('custom categories by their id', () {
      expect(
        patterns([
          ...filler(15),
          ...times(5, spend('worth_it', category: 'c:abc')),
        ]),
        found([const FeelingPattern.categoryWorth('c:abc')]),
      );
    });
  });

  group('by weekday', () {
    test('at least 4 spends over 3 different days', () {
      expect(
        patterns([
          ...filler(16),
          for (final day in const [
            '2026-09-26',
            '2026-09-19',
            '2026-09-12',
            '2026-09-12',
          ])
            spend('worth_it', category: 'other', day: day),
        ]),
        found([const FeelingPattern.weekdayWorth(DateTime.saturday)]),
      );
    });

    test('one busy weekend is not a pattern', () {
      expect(
        patterns([
          ...filler(16),
          for (final day in const [
            '2026-09-26',
            '2026-09-26',
            '2026-09-19',
            '2026-09-19',
          ])
            spend('worth_it', category: 'other', day: day),
        ]),
        none,
      );
    });
  });

  group('the order', () {
    test('the larger share first, ties by label, at most 3; mixed after', () {
      expect(
        patterns([
          ...filler(10),
          ...times(5, spend('worth_it', category: 'health')),
          ...times(5, spend('worth_it')),
          ...times(4, spend('worth_it', category: 'fun')),
          spend('not_sure', category: 'fun'),
          ...times(2, spend('worth_it', category: 'shopping')),
          ...times(2, spend('not_sure', category: 'shopping')),
          spend('not_really', category: 'shopping'),
        ]),
        found([
          const FeelingPattern.categoryWorth('food'),
          const FeelingPattern.categoryWorth('health'),
          const FeelingPattern.categoryWorth('fun'),
        ]),
      );
    });

    test('the same share: more spends first', () {
      expect(
        patterns([
          ...filler(15),
          ...times(5, spend('worth_it')),
          ...times(6, spend('worth_it', category: 'fun')),
        ]),
        found([
          const FeelingPattern.categoryWorth('fun'),
          const FeelingPattern.categoryWorth('food'),
        ]),
      );
    });

    test('the same share and count: the category before the weekday', () {
      expect(
        patterns([
          ...filler(15),
          for (final day in [
            '2026-09-26',
            '2026-09-19',
            '2026-09-12',
            '2026-09-05',
            '2026-08-29',
          ])
            spend('worth_it', day: day),
        ]),
        found([
          const FeelingPattern.categoryWorth('food'),
          const FeelingPattern.weekdayWorth(DateTime.saturday),
        ]),
      );
    });

    test('the overall line only when nothing more specific shows', () {
      expect(
        patterns(times(20, spend('worth_it'))),
        found([const FeelingPattern.overallWorth()]),
      );
    });
  });

  test('amounts never count: only how many spends', () {
    List<SummaryEntry> journal(int amount) => [
      ...filler(15),
      ...times(5, spend('worth_it', amount: amount)),
      spend('not_really', category: 'fun', amount: amount * 1000),
    ];
    expect(patterns(journal(1)), patterns(journal(999999999)));
  });
}
