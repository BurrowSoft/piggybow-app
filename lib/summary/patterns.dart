// Feature 20, Patterns (a Plus perk; specs/insights-plan.md, approved by PB UX
// & PM): up to 3 calm facts about how spends felt over the last 8 weeks, by
// category and by day of the week. Words only, never a number.
//
// What it reads: spends with a feeling, their category id and their day (the
// one picked in the Add sheet). What it never reads: notes (a SummaryEntry
// has none), the time a spend was noted (back-dated entries would mislead),
// amounts (only counts matter), saves and withdrawals.
//
// "Not really" is never a pattern of its own: a category can only be "mostly
// worth it" or "mixed". Summary's Worth it? card keeps every count visible.
//
// Integer maths only; local dates are "YYYY-MM-DD".

import 'summary.dart' show SummaryEntry;

/// The window: the last 8 weeks, today included.
const patternsWindowDays = 56;

/// Nothing shows with fewer spends that have a feeling in the window.
const patternsMinFelt = 20;

/// A category's floor.
const patternsMinPerCategory = 5;

/// A weekday's floor: this many spends on at least [patternsMinWeekdayWeeks]
/// different days (one busy Saturday isn't a pattern).
const patternsMinPerWeekday = 4;
const patternsMinWeekdayWeeks = 3;

/// "Mostly worth it": at least this share (%) of the group's felt spends…
const patternsShare = 60;

/// …and at least this many points above the share across all of them.
const patternsAboveOverall = 15;

/// "Mixed": no feeling at this share (%) or more, and at least two at
/// [patternsMixedEach] % or more.
const patternsMixedTop = 50;
const patternsMixedEach = 25;

/// At most this many patterns show.
const patternsMax = 3;

enum PatternKind { overallWorth, categoryWorth, categoryMixed, weekdayWorth }

/// One pattern: [category] is a category id (built-in or custom), [weekday]
/// is DateTime.monday … DateTime.sunday.
class FeelingPattern {
  const FeelingPattern.overallWorth()
    : kind = PatternKind.overallWorth,
      category = null,
      weekday = null;

  const FeelingPattern.categoryWorth(String this.category)
    : kind = PatternKind.categoryWorth,
      weekday = null;

  const FeelingPattern.categoryMixed(String this.category)
    : kind = PatternKind.categoryMixed,
      weekday = null;

  const FeelingPattern.weekdayWorth(int this.weekday)
    : kind = PatternKind.weekdayWorth,
      category = null;

  final PatternKind kind;
  final String? category;
  final int? weekday;

  @override
  bool operator ==(Object other) =>
      other is FeelingPattern &&
      other.kind == kind &&
      other.category == category &&
      other.weekday == weekday;

  @override
  int get hashCode => Object.hash(kind, category, weekday);

  @override
  String toString() => 'FeelingPattern(${kind.name}, ${category ?? weekday})';
}

enum PatternsState {
  /// Fewer than [patternsMinFelt] spends with a feeling in the window.
  notYet,

  /// Enough to go on, and nothing stands out.
  none,

  /// One to [patternsMax] patterns.
  found,
}

class FeelingPatterns {
  const FeelingPatterns(this.state, [this.patterns = const []]);

  final PatternsState state;
  final List<FeelingPattern> patterns;

  @override
  bool operator ==(Object other) =>
      other is FeelingPatterns &&
      other.state == state &&
      _sameList(other.patterns, patterns);

  @override
  int get hashCode => Object.hash(state, Object.hashAll(patterns));

  @override
  String toString() => 'FeelingPatterns(${state.name}, $patterns)';
}

bool _sameList(List<FeelingPattern> a, List<FeelingPattern> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How many spends in a group had each feeling.
class _Counts {
  int worth = 0;
  int notSure = 0;
  int notReally = 0;
  final days = <String>{};

  int get felt => worth + notSure + notReally;

  void add(String feeling, String day) {
    switch (feeling) {
      case 'worth_it':
        worth++;
      case 'not_sure':
        notSure++;
      case 'not_really':
        notReally++;
      default:
        return;
    }
    days.add(day);
  }

  /// worth ÷ felt ≥ share %.
  bool worthAtLeast(int share) => worth * 100 >= felt * share;

  /// worth ÷ felt − all.worth ÷ all.felt ≥ points %, in integers.
  bool worthAbove(_Counts all, int points) =>
      (worth * all.felt - all.worth * felt) * 100 >= points * felt * all.felt;

  bool get mixed {
    final shares = [worth, notSure, notReally];
    if (shares.any((n) => n * 100 >= felt * patternsMixedTop)) return false;
    return shares.where((n) => n * 100 >= felt * patternsMixedEach).length >= 2;
  }
}

DateTime _date(String iso) => DateTime.parse('${iso}T00:00:00Z');

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The patterns in [entries] for the 8 weeks ending [today] ("YYYY-MM-DD").
/// [categoryLabel] only breaks ties, so the order is stable.
FeelingPatterns feelingPatterns({
  required Iterable<SummaryEntry> entries,
  required String today,
  required String Function(String categoryId) categoryLabel,
}) {
  final from = _iso(
    _date(today).subtract(const Duration(days: patternsWindowDays - 1)),
  );
  final all = _Counts();
  final byCategory = <String, _Counts>{};
  final byWeekday = <int, _Counts>{};
  for (final e in entries) {
    final feeling = e.feeling;
    if (e.type != 'spent' || feeling == null) continue;
    if (e.localDate.compareTo(from) < 0 || e.localDate.compareTo(today) > 0) {
      continue;
    }
    all.add(feeling, e.localDate);
    final category = e.category;
    if (category != null) {
      byCategory.putIfAbsent(category, _Counts.new).add(feeling, e.localDate);
    }
    byWeekday
        .putIfAbsent(_date(e.localDate).weekday, _Counts.new)
        .add(feeling, e.localDate);
  }
  if (all.felt < patternsMinFelt) {
    return const FeelingPatterns(PatternsState.notYet);
  }

  bool standsOut(_Counts c) =>
      c.worthAtLeast(patternsShare) && c.worthAbove(all, patternsAboveOverall);

  final worth = <(FeelingPattern, _Counts, String)>[];
  final mixed = <(FeelingPattern, _Counts, String)>[];
  for (final MapEntry(key: id, value: c) in byCategory.entries) {
    if (c.felt < patternsMinPerCategory) continue;
    final label = categoryLabel(id).toLowerCase();
    if (standsOut(c)) {
      worth.add((FeelingPattern.categoryWorth(id), c, 'a$label'));
    } else if (c.mixed) {
      mixed.add((FeelingPattern.categoryMixed(id), c, 'a$label'));
    }
  }
  for (final MapEntry(key: day, value: c) in byWeekday.entries) {
    if (c.felt < patternsMinPerWeekday) continue;
    if (c.days.length < patternsMinWeekdayWeeks) continue;
    if (standsOut(c)) {
      worth.add((FeelingPattern.weekdayWorth(day), c, 'b$day'));
    }
  }

  // The strongest first: the larger worth-it share, then more spends, then
  // categories (by label) before weekdays (Monday first). Mixed ones after.
  int byStrength(
    (FeelingPattern, _Counts, String) a,
    (FeelingPattern, _Counts, String) b,
  ) {
    final share = (b.$2.worth * a.$2.felt).compareTo(a.$2.worth * b.$2.felt);
    if (share != 0) return share;
    final count = b.$2.felt.compareTo(a.$2.felt);
    return count != 0 ? count : a.$3.compareTo(b.$3);
  }

  worth.sort(byStrength);
  mixed.sort((a, b) {
    final count = b.$2.felt.compareTo(a.$2.felt);
    return count != 0 ? count : a.$3.compareTo(b.$3);
  });
  final found = [
    for (final (pattern, _, _) in [...worth, ...mixed]) pattern,
  ];
  if (found.isNotEmpty) {
    return FeelingPatterns(
      PatternsState.found,
      found.take(patternsMax).toList(),
    );
  }
  // Overall only when nothing more specific shows.
  if (all.worthAtLeast(patternsShare)) {
    return const FeelingPatterns(PatternsState.found, [
      FeelingPattern.overallWorth(),
    ]);
  }
  return const FeelingPatterns(PatternsState.none);
}
