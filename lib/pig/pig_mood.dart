// The pig's mood: one pure function of what the person picked, what they noted, their goals'
// sticky "reached" times, the current instant and the phone's local date (plan §4.2).
//
// The pig never scolds. Its low state is sleepy, never sad: no rule below can make it unhappy,
// and spending more never changes its line, only whether a pick is met.

/// The pig's four moods, lowest first.
enum PigMood { sleepy, calm, happy, delighted }

/// What the person told the pig to care about (at least one is picked).
enum HappyPick { save, plan, worth }

/// What was just added, for the line shown right after an Add (plan §4.4).
enum PigReaction { spend, worth, notSure, notReally, save }

/// One entry, as the mood needs it.
class MoodEntry {
  const MoodEntry({
    required this.type,
    required this.amountMinor,
    this.feeling,
    required this.localDate,
    required this.createdAt,
    this.auto = false,
  });

  /// "spent" or "saved".
  final String type;
  final int amountMinor;

  /// "worth_it", "not_sure", "not_really" or null (spends only).
  final String? feeling;

  /// The day the person picked, "YYYY-MM-DD".
  final String localDate;

  /// When it was added (UTC).
  final DateTime createdAt;

  /// True when a repeat added it, not the person: it counts in this week's
  /// picks like any entry (it's money), but never wakes the pig.
  final bool auto;
}

/// A goal's sticky timestamps. Pass every goal, ended ones included.
class GoalMarks {
  const GoalMarks({required this.name, required this.bandReachedAt, this.reachedAt});

  final String name;

  /// When bands 1 to 5 were first completed (UTC); null for bands not reached. Length 5.
  final List<DateTime?> bandReachedAt;

  /// When the goal was reached (UTC), or null.
  final DateTime? reachedAt;
}

/// The mood, the line's ARB key, and the values for the line's placeholders.
class PigState {
  const PigState(this.mood, this.lineKey, [this.args = const {}]);

  final PigMood mood;
  final String lineKey;

  /// {'band': 2} for pigDelightedBand, {'goalName': 'Bike'} for pigDelightedGoal, else empty.
  final Map<String, Object> args;

  /// True when the line comes from a band or the goal reached in the last 24 hours (rule 1).
  bool get isMilestone => lineKey == 'pigDelightedBand' || lineKey == 'pigDelightedGoal';

  @override
  bool operator ==(Object other) =>
      other is PigState &&
      other.mood == mood &&
      other.lineKey == lineKey &&
      other.args.length == args.length &&
      args.entries.every((e) => other.args[e.key] == e.value);

  @override
  int get hashCode => Object.hash(mood, lineKey, Object.hashAllUnordered(args.entries.map((e) => '${e.key}=${e.value}')));

  @override
  String toString() => 'PigState(${mood.name}, $lineKey${args.isEmpty ? '' : ', $args'})';
}

const _milestoneWindow = Duration(hours: 24);
const _recentWindow = Duration(hours: 72);
const _calmLines = ['pigCalm1', 'pigCalm2', 'pigCalm3'];
const _sleepyLines = ['pigSleepy1', 'pigSleepy2', 'pigSleepy3'];
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime _dateOf(String iso) {
  final m = _isoDate.firstMatch(iso);
  if (m == null) throw ArgumentError.value(iso, 'date', 'must be YYYY-MM-DD');
  final date = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (date.month != int.parse(m[2]!) || date.day != int.parse(m[3]!)) {
    throw ArgumentError.value(iso, 'date', 'not a real date');
  }
  return date;
}

String _isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// How long ago [t] was; a time after [now] (the clock moved back) counts as 0.
Duration _age(DateTime now, DateTime t) {
  final age = now.difference(t);
  return age.isNegative ? Duration.zero : age;
}

/// 1-based day of the year of a local date.
int _dayOfYear(DateTime date) => date.difference(DateTime.utc(date.year)).inDays + 1;

/// The rotating line for [today]: lines[(dayOfYear - 1) mod n].
String rotatingLine(List<String> lines, String today) => lines[(_dayOfYear(_dateOf(today)) - 1) % lines.length];

/// Rule 1's line, if a band or a goal was reached strictly less than 24 hours before [now].
/// A goal beats any band; among bands, the highest one wins.
PigState? _milestone(List<GoalMarks> goals, DateTime now) {
  GoalMarks? reachedGoal;
  DateTime? reachedGoalAt;
  var band = 0;
  for (final g in goals) {
    final r = g.reachedAt;
    if (r != null && _age(now, r) < _milestoneWindow && (reachedGoalAt == null || r.isAfter(reachedGoalAt))) {
      reachedGoal = g;
      reachedGoalAt = r;
    }
    for (var i = 0; i < g.bandReachedAt.length && i < 5; i++) {
      final t = g.bandReachedAt[i];
      if (t != null && _age(now, t) < _milestoneWindow && i + 1 > band) band = i + 1;
    }
  }
  if (reachedGoal != null) return PigState(PigMood.delighted, 'pigDelightedGoal', {'goalName': reachedGoal.name});
  if (band > 0) return PigState(PigMood.delighted, 'pigDelightedBand', {'band': band});
  return null;
}

/// The pig's mood and line (plan §4.2). [now] is the current instant (UTC); [today] is the
/// phone's local date ("YYYY-MM-DD"), read live. The first matching rule wins.
PigState pigMood({
  required Set<HappyPick> picks,
  required int? planMinor,
  required List<MoodEntry> entries,
  required List<GoalMarks> goals,
  required DateTime now,
  required String today,
}) {
  final todayDate = _dateOf(today);
  final monday = _isoOf(todayDate.subtract(Duration(days: todayDate.weekday - DateTime.monday)));

  // 1. A band or the goal, reached in the last 24 hours.
  final milestone = _milestone(goals, now);
  if (milestone != null) return milestone;

  // This week: Monday to today, by the day the person picked.
  final week = [
    for (final e in entries)
      if (e.localDate.compareTo(monday) >= 0 && e.localDate.compareTo(today) <= 0) e,
  ];
  final weekSpends = week.where((e) => e.type == 'spent');
  var spent = 0;
  var worthIt = 0;
  var notReally = 0;
  for (final e in weekSpends) {
    spent += e.amountMinor;
    if (e.feeling == 'worth_it') worthIt++;
    if (e.feeling == 'not_really') notReally++;
  }

  final met = <HappyPick>{
    if (week.any((e) => e.type == 'saved')) HappyPick.save,
    if (planMinor != null && week.isNotEmpty && spent <= planMinor) HappyPick.plan,
    if (worthIt >= 1 && worthIt >= notReally) HappyPick.worth,
  }.intersection(picks);

  // 2. Everything they picked (two or more picks).
  if (picks.length >= 2 && met.length == picks.length) {
    return const PigState(PigMood.delighted, 'pigDelightedAll');
  }

  // 3. Something they picked: the first in the order save, plan, worth.
  for (final pick in HappyPick.values) {
    if (met.contains(pick)) {
      return PigState(PigMood.happy, switch (pick) {
        HappyPick.save => 'pigHappySave',
        HappyPick.plan => 'pigHappyPlan',
        HappyPick.worth => 'pigHappyWorth',
      });
    }
  }

  // 4. Nothing noted yet.
  if (entries.isEmpty) return const PigState(PigMood.calm, 'pigFirstDay');

  // 5. Something the person added in the last 72 hours (by when it was added, not the day it's
  // dated); an entry a repeat added isn't the person's.
  if (entries.any((e) => !e.auto && _age(now, e.createdAt) < _recentWindow)) {
    final line = todayDate.weekday == DateTime.monday ? 'pigCalmMonday' : rotatingLine(_calmLines, today);
    return PigState(PigMood.calm, line);
  }

  // 6. Resting.
  return PigState(PigMood.sleepy, rotatingLine(_sleepyLines, today));
}

/// The line to show in the bubble: the reaction to what was just added, if any (plan §4.4),
/// except that after a save, a band or the goal reached (rule 1) is shown instead (§4.7).
/// The mood itself never changes with a reaction.
String pigBubbleKey(PigState state, PigReaction? lastAdd) {
  if (lastAdd == null) return state.lineKey;
  if (lastAdd == PigReaction.save && state.isMilestone) return state.lineKey;
  return switch (lastAdd) {
    PigReaction.spend => 'pigAfterSpend',
    PigReaction.worth => 'pigAfterWorth',
    PigReaction.notSure => 'pigAfterNotSure',
    PigReaction.notReally => 'pigAfterNotReally',
    PigReaction.save => 'pigAfterSave',
  };
}
