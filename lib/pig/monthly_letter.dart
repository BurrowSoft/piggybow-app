// The pig's monthly letter: in the first days of a month, a short note about
// the month before, in facts that are only ever positive or neutral. Never a
// spending total, never "too much", nothing about the days nothing was noted.

import '../core/clock.dart';
import '../journal/category.dart';
import '../journal/entry.dart';
import '../journal/goal.dart';

/// The letter shows on the first [letterDays] days of a month, until "Thanks!".
const letterDays = 7;

/// What the letter says about one month. Each fact has its line, left out
/// when it doesn't apply; the days are always there (a month with no entries
/// has no letter).
class MonthlyLetter {
  const MonthlyLetter({
    required this.month,
    required this.goalsReached,
    required this.savedMinor,
    required this.worthCategory,
    required this.days,
  });

  /// The month written about, as its first day (local, no time).
  final DateTime month;

  /// The names of the goals reached that month, in the order they were.
  final List<String> goalsReached;

  /// That month's saves in the journal's currency; 0 leaves the line out.
  final int savedMinor;

  /// The category with strictly the most "worth it" spends, at least two of
  /// them; null (a tie, or fewer) leaves the line out.
  final SpendCategory? worthCategory;

  /// How many days had at least one entry.
  final int days;

  /// The month as stored when its letter is put away: `YYYY-MM`.
  String get key => wireDate(month).substring(0, 7);
}

/// The letter to show on [today] (the phone's date) about the month before,
/// or null: none when [on] is false, after the month's first [letterDays]
/// days, once [dismissed] holds that month, or when that month has no entries.
/// Saves count in [currency] only; a goal's reached time is dated in [zone].
MonthlyLetter? monthlyLetter({
  required DateTime today,
  required List<Entry> entries,
  required List<Goal> goals,
  required String currency,
  required String zone,
  required bool on,
  required String? dismissed,
}) {
  if (!on || today.day > letterDays) return null;
  final month = DateTime(today.year, today.month - 1);
  final prefix = '${wireDate(month).substring(0, 7)}-';
  if (dismissed == wireDate(month).substring(0, 7)) return null;

  final inMonth = [for (final e in entries) if (e.localDate.startsWith(prefix)) e];
  if (inMonth.isEmpty) return null;

  var saved = 0;
  final worth = <SpendCategory, int>{};
  for (final e in inMonth) {
    if (e.type == EntryType.saved && e.currency == currency) saved += e.amountMinor;
    final category = e.category;
    if (e.type == EntryType.spent && e.feeling == Feeling.worthIt && category != null) {
      worth[category] = (worth[category] ?? 0) + 1;
    }
  }
  final ranked = worth.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked.isNotEmpty &&
          ranked.first.value >= 2 &&
          (ranked.length == 1 || ranked[1].value < ranked.first.value)
      ? ranked.first.key
      : null;

  final reached = goals.where((g) => g.reachedAt != null).toList()
    ..sort((a, b) => a.reachedAt!.compareTo(b.reachedAt!));
  return MonthlyLetter(
    month: month,
    goalsReached: [
      for (final g in reached)
        if (wireDate(Clock.localDateOf(g.reachedAt!, zone)).startsWith(prefix)) g.name,
    ],
    savedMinor: saved,
    worthCategory: top,
    days: {for (final e in inMonth) e.localDate}.length,
  );
}
