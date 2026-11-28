// Feature 11, a goal's pace and its target date: what the goal's detail says
// under "{x} to go". Integers only; days are "YYYY-MM-DD" in the phone's zone.
//
// The pace is what was saved to the goal in the last 4 weeks; the line is
// "About N weeks to go at this pace". With no pace, a target date that hasn't
// passed shows as "Target: {date}". The two are never compared: nothing here
// can say "behind".

import '../core/clock.dart';
import '../journal/entry.dart';

/// The pace looks back this many days, today included: 4 weeks.
const goalPaceDays = 28;

/// Beyond this many weeks the pace line isn't shown.
const goalPaceMaxWeeks = 52;

/// What went into a goal from [today] − 27 days to [today], by each entry's
/// own day: its saves less what was taken out of it (#61), so a take-out
/// slows the pace. Zero or less: no pace ([goalPaceWeeks]). "Already saved"
/// at the start isn't in [entries].
int recentSavesMinor(Iterable<Entry> entries, DateTime today) {
  final from = wireDate(addDays(today, 1 - goalPaceDays));
  final to = wireDate(today);
  var sum = 0;
  for (final e in entries) {
    final sign = switch (e.type) {
      EntryType.saved => 1,
      EntryType.withdraw => -1,
      EntryType.spent => 0,
    };
    if (sign == 0) continue;
    if (e.localDate.compareTo(from) < 0 || e.localDate.compareTo(to) > 0) {
      continue;
    }
    sum += sign * e.amountMinor;
  }
  return sum;
}

/// Weeks to go at the pace of the last 4 weeks: ceil(remaining × 4 ÷ saved
/// in them). Null when nothing remains, nothing was saved in them, or it would
/// take more than [goalPaceMaxWeeks].
int? goalPaceWeeks({required int remainingMinor, required int recentMinor}) {
  if (remainingMinor <= 0 || recentMinor <= 0) return null;
  const weeks = goalPaceDays ~/ 7;
  final n = (remainingMinor * weeks + recentMinor - 1) ~/ recentMinor;
  return n > goalPaceMaxWeeks ? null : n;
}

/// The line under "{x} to go": the pace when there is one ([paceWeeks]), else
/// the target date while it hasn't passed ([targetDate], "YYYY-MM-DD"), else
/// nothing (both null). Nothing once reached.
({int? paceWeeks, String? targetDate}) goalOutlook({
  required int remainingMinor,
  required int recentMinor,
  required String? targetDate,
  required String today,
}) {
  if (remainingMinor <= 0) return (paceWeeks: null, targetDate: null);
  final weeks = goalPaceWeeks(
    remainingMinor: remainingMinor,
    recentMinor: recentMinor,
  );
  if (weeks != null) return (paceWeeks: weeks, targetDate: null);
  final showDate = targetDate != null && targetDate.compareTo(today) >= 0;
  return (paceWeeks: null, targetDate: showDate ? targetDate : null);
}
