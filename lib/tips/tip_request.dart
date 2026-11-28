// What a written pig tip is asked from (decision 79): the only journal data
// that leaves the phone when pig tips are on (each request also carries the
// anonymous id and, as every connection does, the IP address). Shares and
// counts of this week so far: never a note, a goal's or a category's name,
// an amount, a date or the currency. supabase/contracts/pig-tip-request.json
// is its shape, read by the app's tests and the server's.

import '../journal/entry.dart';
import '../pig/pig_mood.dart' show HappyPick;
import '../summary/summary.dart';

/// Your own categories travel as one bucket: their names are typed by you.
const tipYoursBucket = 'yours';

/// How many built-in categories a request names, the largest first.
const tipTopCategories = 3;

/// A written tip's request, as sent.
class TipRequest {
  const TipRequest({
    required this.language,
    required this.weekday,
    required this.categoryShares,
    required this.feelings,
    required this.saves,
    this.planPercent,
    this.goalPercent,
    required this.activeGoals,
    required this.picks,
  });

  /// The language the tip is written in ("en").
  final String language;

  /// Today, 1 (Monday) to 7 (Sunday): how far into the week.
  final int weekday;

  /// This week's spending, in whole percent of it: the [tipTopCategories]
  /// largest built-ins by id, and [tipYoursBucket] for your own.
  final Map<String, int> categoryShares;

  /// This week's spends by how they felt: worth_it, not_sure, not_really,
  /// and none (not answered).
  final Map<String, int> feelings;

  /// How many saves this week.
  final int saves;

  /// This week's spending in whole percent of the plan, at most 100 (as
  /// Summary shows it); null without a plan.
  final int? planPercent;

  /// The goal saves go to, in whole percent reached; null without one.
  final int? goalPercent;

  final int activeGoals;

  /// What makes your pig happy, in the app's order.
  final List<String> picks;

  Map<String, Object> toJson() => {
    'language': language,
    'weekday': weekday,
    'category_shares': categoryShares,
    'feelings': feelings,
    'saves': saves,
    'plan_percent': ?planPercent,
    'goal_percent': ?goalPercent,
    'active_goals': activeGoals,
    'picks': picks,
  };
}

/// The request for [todayWire] (the phone's local date, "YYYY-MM-DD"), from
/// the journal's [entries], the weekly [planMinor], the default goal's
/// [goalPercent], how many goals are active, and the person's [picks].
TipRequest buildTipRequest({
  required String language,
  required String todayWire,
  required List<Entry> entries,
  required int? planMinor,
  required int? goalPercent,
  required int activeGoals,
  required Set<HappyPick> picks,
}) {
  final week = periodContaining(PeriodKind.week, todayWire);
  var spent = 0;
  var saves = 0;
  final byCategory = <String, int>{};
  final feelings = {'worth_it': 0, 'not_sure': 0, 'not_really': 0, 'none': 0};
  for (final e in entries) {
    // This week so far: never a later day.
    if (!week.contains(e.localDate) || e.localDate.compareTo(todayWire) > 0) {
      continue;
    }
    if (e.type == EntryType.saved) {
      saves++;
      continue;
    }
    spent += e.amountMinor;
    final key =
        e.category?.id ?? (e.customCategory == null ? null : tipYoursBucket);
    if (key != null) byCategory[key] = (byCategory[key] ?? 0) + e.amountMinor;
    final feeling = e.feeling?.id ?? 'none';
    feelings[feeling] = (feelings[feeling] ?? 0) + 1;
  }

  // The largest built-ins first; on a tie, by id, so a request is the same
  // for the same week.
  final builtIns =
      byCategory.entries.where((c) => c.key != tipYoursBucket).toList()
        ..sort((a, b) {
          final byAmount = b.value.compareTo(a.value);
          return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
        });
  final yours = byCategory[tipYoursBucket];
  final plan = planMinor;
  final ofPlan = plan == null || plan <= 0 ? null : _floorPercent(spent, plan);
  return TipRequest(
    language: language,
    weekday: DateTime.parse(todayWire).weekday,
    categoryShares: {
      for (final c in builtIns.take(tipTopCategories))
        c.key: _floorPercent(c.value, spent),
      if (yours != null) tipYoursBucket: _floorPercent(yours, spent),
    },
    feelings: feelings,
    saves: saves,
    planPercent: ofPlan == null || ofPlan <= 100 ? ofPlan : 100,
    goalPercent: goalPercent,
    activeGoals: activeGoals,
    picks: [
      for (final p in HappyPick.values)
        if (picks.contains(p)) p.name,
    ],
  );
}

/// floor(part × 100 / whole), exact for any size of amounts (as Summary).
int _floorPercent(int part, int whole) =>
    (BigInt.from(part) * BigInt.from(100) ~/ BigInt.from(whole)).toInt();
