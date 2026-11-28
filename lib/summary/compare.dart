// Feature 13, gentle comparisons: in Summary's week, each category's spends
// against the week before, in words only ("A bit more", "A bit less", "About
// the same"): no number, no arrow, no colour, never a score.
//
// The current week, not over yet, is compared with the same days of the week
// before (Monday to today's weekday); a past week with the whole week before.
// A category with nothing in those days gets no comparison. Spends only.
// Integer maths on minor units; local dates are "YYYY-MM-DD".

import 'summary.dart';

enum Comparison { more, less, same }

/// Within this many percent of the week before: about the same.
const comparisonSameBand = 15;

/// [now] against [before], both in minor units: about the same within
/// [comparisonSameBand] % of [before], else more or less, however far.
/// Null when [before] is 0: nothing to compare with.
Comparison? compareSpends(int now, int before) {
  if (before <= 0) return null;
  final diff = now - before;
  if (diff.abs() * 100 <= before * comparisonSameBand) return Comparison.same;
  return diff > 0 ? Comparison.more : Comparison.less;
}

/// The days [week] is compared with: the week before it, cut to the same
/// weekdays when [week] holds [today] (it isn't over yet).
Period comparedWith(Period week, String today) {
  final before = periodShift(week, -1);
  if (!week.contains(today)) return before;
  final day = DateTime.parse(
    '${today}T00:00:00Z',
  ).subtract(const Duration(days: 7));
  final end =
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  return Period(PeriodKind.week, before.start, end);
}

/// Each category's spends in [period].
Map<String, int> spendsByCategory(
  Iterable<SummaryEntry> entries,
  Period period,
) {
  final byCategory = <String, int>{};
  for (final e in entries) {
    final category = e.category;
    if (e.type != 'spent' || category == null) continue;
    if (!period.contains(e.localDate)) continue;
    byCategory[category] = (byCategory[category] ?? 0) + e.amountMinor;
  }
  return byCategory;
}

/// How each of [rows] (the shown week's categories) compares with the days
/// [comparedWith] gives; a category with nothing in them isn't in the map.
Map<String, Comparison> compareCategories({
  required List<CategoryRow> rows,
  required Iterable<SummaryEntry> entries,
  required Period week,
  required String today,
}) {
  final before = spendsByCategory(entries, comparedWith(week, today));
  return {
    for (final row in rows)
      row.id: ?compareSpends(row.amountMinor, before[row.id] ?? 0),
  };
}
