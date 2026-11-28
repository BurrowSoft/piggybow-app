// The Summary's numbers for one week (Monday to Sunday) or one calendar month (plan §3.7,
// decision 29): totals, the category rows with floored whole percents, the worth counts, the
// plan bar (current week only), the period's label and whether the arrows can move.
//
// All maths is integers. Local dates are "YYYY-MM-DD" strings, so they compare as text.
// DateFormat needs the locale's date symbols loaded first (initializeDateFormatting); the app
// gets that from flutter_localizations.

import 'package:intl/intl.dart' show DateFormat, Intl;

import '../journal/entry.dart' show Entry;
import '../money/locale.dart' show parseLocale;

enum PeriodKind { week, month }

/// A week (Monday to Sunday) or a calendar month, by local dates.
class Period {
  const Period(this.kind, this.start, this.end);

  final PeriodKind kind;

  /// First and last day, "YYYY-MM-DD", both included.
  final String start;
  final String end;

  bool contains(String date) => date.compareTo(start) >= 0 && date.compareTo(end) <= 0;

  @override
  bool operator ==(Object other) => other is Period && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'Period(${kind.name}, $start – $end)';
}

/// One entry, as the Summary needs it.
class SummaryEntry {
  const SummaryEntry({
    required this.type,
    required this.amountMinor,
    this.category,
    this.feeling,
    required this.localDate,
  });

  /// [e] as Summary, Home and Patterns all read it: by its category's id,
  /// built-in or your own, so every view counts the same spends. Notes are
  /// never read.
  SummaryEntry.of(Entry e)
    : this(
        type: e.type.id,
        amountMinor: e.amountMinor,
        category: e.categoryId,
        feeling: e.feeling?.id,
        localDate: e.localDate,
      );

  /// "spent", "saved" or "withdraw".
  final String type;
  final int amountMinor;

  /// A category id; spends only.
  final String? category;

  /// "worth_it", "not_sure", "not_really" or null; spends only.
  final String? feeling;

  /// "YYYY-MM-DD".
  final String localDate;
}

/// A "By category" row: the category's spends in the period and its floored whole percent.
class CategoryRow {
  const CategoryRow(this.id, this.amountMinor, this.percent);

  final String id;
  final int amountMinor;
  final int percent;

  @override
  bool operator ==(Object other) =>
      other is CategoryRow && other.id == id && other.amountMinor == amountMinor && other.percent == percent;

  @override
  int get hashCode => Object.hash(id, amountMinor, percent);

  @override
  String toString() => 'CategoryRow($id, $amountMinor, $percent%)';
}

class Summary {
  const Summary({
    required this.period,
    required this.label,
    required this.spentMinor,
    required this.savedMinor,
    required this.takenOutMinor,
    required this.categories,
    required this.worth,
    required this.notSure,
    required this.notReally,
    required this.showWorth,
    required this.planPercent,
    required this.hasPrev,
    required this.hasNext,
    required this.isEmpty,
  });

  final Period period;
  final String label;
  final int spentMinor;
  final int savedMinor;

  /// What was taken out of savings in the period: its own line, never netted
  /// against Saved (0 when nothing was).
  final int takenOutMinor;

  /// Spend categories only, largest first; equal amounts by label.
  final List<CategoryRow> categories;

  final int worth;
  final int notSure;
  final int notReally;

  /// The "Worth it?" card shows only when a spend in the period has a feeling.
  final bool showWorth;

  /// The plan bar: floor(spent × 100 / plan), capped at 100. Null means no bar: only the
  /// current week, in the week view, with a plan set, has one.
  final int? planPercent;

  /// Whether the arrows are enabled. They're disabled (not hidden) at the oldest entry's period
  /// and at the current one, and both are disabled when there are no entries at all.
  final bool hasPrev;
  final bool hasNext;

  /// Nothing noted in this period (sumEmptyWeek / sumEmptyMonth).
  final bool isEmpty;
}

final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime _dateOf(String iso) {
  final m = _isoDate.firstMatch(iso);
  if (m == null) throw ArgumentError.value(iso, 'date', 'must be YYYY-MM-DD');
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final date = DateTime.utc(y, mo, d);
  if (date.month != mo || date.day != d) throw ArgumentError.value(iso, 'date', 'not a real date');
  return date;
}

String _isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The week (Monday start, in every locale) or the month that contains [date].
Period periodContaining(PeriodKind kind, String date) {
  final d = _dateOf(date);
  switch (kind) {
    case PeriodKind.week:
      final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
      return Period(kind, _isoOf(monday), _isoOf(monday.add(const Duration(days: 6))));
    case PeriodKind.month:
      return Period(kind, _isoOf(DateTime.utc(d.year, d.month)), _isoOf(DateTime.utc(d.year, d.month + 1, 0)));
  }
}

/// The period [by] steps away (−1 = the previous one).
Period periodShift(Period p, int by) {
  final start = _dateOf(p.start);
  return switch (p.kind) {
    PeriodKind.week => periodContaining(PeriodKind.week, _isoOf(start.add(Duration(days: 7 * by)))),
    PeriodKind.month => periodContaining(PeriodKind.month, _isoOf(DateTime.utc(start.year, start.month + by))),
  };
}

/// The locale intl formats dates with for a device locale string ("en_GB", "de-DE"…).
String intlDateLocale(String? raw) {
  final p = parseLocale(raw);
  if (p == null) return 'en_US';
  final candidate = p.region == null ? p.language : '${p.language}_${p.region}';
  return Intl.verifiedLocale(candidate, DateFormat.localeExists, onFailure: (_) => 'en_US')!;
}

/// "Nov 23 – Nov 29" (each end in the locale's MMMd), with the year on both ends when the week
/// crosses a year or isn't in today's year; a month is the locale's "MMMM y" ("November 2026").
String periodLabel(Period p, String today, String locale) {
  final l = intlDateLocale(locale);
  final start = _dateOf(p.start);
  if (p.kind == PeriodKind.month) return DateFormat.yMMMM(l).format(start);
  final end = _dateOf(p.end);
  final withYear = start.year != end.year || start.year != _dateOf(today).year;
  final f = withYear ? DateFormat.yMMMd(l) : DateFormat.MMMd(l);
  return '${f.format(start)} – ${f.format(end)}';
}

/// floor(part × 100 / whole), exact for any size of amounts.
int _floorPercent(int part, int whole) =>
    (BigInt.from(part) * BigInt.from(100) ~/ BigInt.from(whole)).toInt();

/// Everything the Summary shows for [period]. [today] is the phone's local date, read live.
Summary summarize({
  required Period period,
  required String today,
  required List<SummaryEntry> entries,
  required int? planMinor,
  required String locale,
  required String Function(String categoryId) categoryLabel,
}) {
  var spent = 0;
  var saved = 0;
  var takenOut = 0;
  var worth = 0;
  var notSure = 0;
  var notReally = 0;
  var any = false;
  final byCategory = <String, int>{};
  String? oldest;

  for (final e in entries) {
    if (oldest == null || e.localDate.compareTo(oldest) < 0) oldest = e.localDate;
    // Every entry is checked, in the period or not: an unknown type is a
    // bug, said loudly.
    if (e.type != 'spent' && e.type != 'saved' && e.type != 'withdraw') {
      throw ArgumentError.value(
        e.type,
        'type',
        'must be "spent", "saved" or "withdraw"',
      );
    }
    if (!period.contains(e.localDate)) continue;
    any = true;
    // Taken out of savings: its own total; never a spend, never less saved.
    if (e.type == 'withdraw') {
      takenOut += e.amountMinor;
      continue;
    }
    if (e.type == 'saved') {
      saved += e.amountMinor;
      continue;
    }
    spent += e.amountMinor;
    final c = e.category;
    if (c != null) byCategory[c] = (byCategory[c] ?? 0) + e.amountMinor;
    switch (e.feeling) {
      case 'worth_it':
        worth++;
      case 'not_sure':
        notSure++;
      case 'not_really':
        notReally++;
    }
  }

  final rows = [
    for (final MapEntry(:key, :value) in byCategory.entries)
      CategoryRow(key, value, spent == 0 ? 0 : _floorPercent(value, spent)),
  ]..sort((a, b) {
      final byAmount = b.amountMinor.compareTo(a.amountMinor);
      if (byAmount != 0) return byAmount;
      final byLabel = categoryLabel(a.id).toLowerCase().compareTo(categoryLabel(b.id).toLowerCase());
      return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
    });

  final current = periodContaining(period.kind, today);
  final plan = planMinor;
  final planPercent = period.kind == PeriodKind.week && period == current && plan != null && plan > 0
      ? (_floorPercent(spent, plan) > 100 ? 100 : _floorPercent(spent, plan))
      : null;

  return Summary(
    period: period,
    label: periodLabel(period, today, locale),
    spentMinor: spent,
    savedMinor: saved,
    takenOutMinor: takenOut,
    categories: rows,
    worth: worth,
    notSure: notSure,
    notReally: notReally,
    showWorth: worth + notSure + notReally > 0,
    planPercent: planPercent,
    hasPrev: oldest != null && period.start.compareTo(periodContaining(period.kind, oldest).start) > 0,
    hasNext: oldest != null && period.start.compareTo(current.start) < 0,
    isEmpty: !any,
  );
}
