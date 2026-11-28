import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:piggybow/summary/summary.dart';

import 'summary_test.dart' show label, s1, s1Plan, s1Summary, s1Today;

/// Money taken out of savings in Summary (feature 5): its own total, never
/// netted against Saved, never a spend; a period with only a withdrawal
/// isn't empty; anything that isn't spent, saved or withdraw is a bug, said
/// loudly.
void main() {
  setUpAll(() => initializeDateFormatting());

  Summary summary(
    List<SummaryEntry> entries, {
    PeriodKind kind = PeriodKind.week,
    String anyDay = s1Today,
    int? plan = s1Plan,
  }) => summarize(
    period: periodContaining(kind, anyDay),
    today: s1Today,
    entries: entries,
    planMinor: plan,
    locale: 'en_US',
    categoryLabel: label,
  );

  test("withdrawals are their own total: Spent, Saved, the categories, the "
      'feelings and the plan stay as they were', () {
    const out = [
      SummaryEntry(type: 'withdraw', amountMinor: 3000, localDate: '2026-12-01'),
      SummaryEntry(type: 'withdraw', amountMinor: 700, localDate: '2026-12-02'),
    ];
    final before = s1Summary(PeriodKind.week, s1Today);
    final after = summary([...s1, ...out]);
    expect(after.takenOutMinor, 3700);
    expect(before.takenOutMinor, 0);
    expect(
      (after.spentMinor, after.savedMinor, after.worth, after.notSure, after.notReally,
          after.showWorth, after.planPercent, after.isEmpty),
      (before.spentMinor, before.savedMinor, before.worth, before.notSure, before.notReally,
          before.showWorth, before.planPercent, before.isEmpty),
    );
    expect(after.categories, before.categories);
  });

  test('a withdraw-only period is not empty: nothing spent or saved, no '
      'categories, no Worth it card, and the plan bar at 0', () {
    final s = summary(const [
      SummaryEntry(type: 'withdraw', amountMinor: 1200, localDate: '2026-12-01'),
    ]);
    expect(s.isEmpty, isFalse);
    expect((s.spentMinor, s.savedMinor, s.takenOutMinor), (0, 0, 1200));
    expect(s.categories, isEmpty);
    expect(s.showWorth, isFalse);
    // The current week with a plan has its bar; only spends move it.
    expect(s.planPercent, 0);
  });

  test('a withdrawal counts as the oldest entry: the arrows reach its period', () {
    const entries = [
      SummaryEntry(type: 'withdraw', amountMinor: 500, localDate: '2026-11-10'),
      SummaryEntry(type: 'spent', amountMinor: 100, category: 'food', localDate: '2026-12-02'),
    ];
    // This week: Previous goes back as far as that withdrawal's week.
    expect(summary(entries).hasPrev, isTrue);
    final old = summary(entries, anyDay: '2026-11-10');
    expect(old.hasPrev, isFalse);
    expect(old.hasNext, isTrue);
    expect((old.isEmpty, old.takenOutMinor, old.spentMinor), (false, 500, 0));
  });

  test('a type that is not spent, saved or withdraw throws, loudly, in the '
      'period or not', () {
    expect(
      () => summary(const [
        SummaryEntry(type: 'spend', amountMinor: 100, category: 'food', localDate: '2026-12-01'),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'must be "spent", "saved" or "withdraw"',
        ),
      ),
    );
    // Long before the period shown: still checked.
    expect(
      () => summary(const [
        SummaryEntry(type: 'saved', amountMinor: 100, localDate: '2026-12-01'),
        SummaryEntry(type: 'spend', amountMinor: 100, category: 'food', localDate: '2025-01-06'),
      ]),
      throwsArgumentError,
    );
  });
}
