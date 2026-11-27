// A savings goal's progress (plan §2, §3.4, §3.5): the percent, the five rainbow bands, whether
// it's reached, and the sticky "first reached" stamps. Integers only.
//
// Progress is "already saved" plus the goal's saves, in minor units. Everything is computed on
// min(progress, target), so a progress far past the target can't overflow and the percent caps
// at 100.

/// The number of rainbow bands; band i (1-5) is one fifth of the goal.
const int goalBandCount = 5;

void _check(int progressMinor, int targetMinor) {
  if (targetMinor <= 0) throw ArgumentError.value(targetMinor, 'targetMinor', 'must be positive');
  if (progressMinor < 0) throw ArgumentError.value(progressMinor, 'progressMinor', 'must not be negative');
}

int _capped(int progressMinor, int targetMinor) => progressMinor < targetMinor ? progressMinor : targetMinor;

/// floor(progress × 100 / target), from 0 to 100.
int goalPercent({required int progressMinor, required int targetMinor}) {
  _check(progressMinor, targetMinor);
  return _capped(progressMinor, targetMinor) * 100 ~/ targetMinor;
}

/// How many bands are complete, 0 to 5: band i is complete when progress × 5 ≥ target × i.
/// (The same as goalPercent ~/ 20.)
int goalBands({required int progressMinor, required int targetMinor}) {
  _check(progressMinor, targetMinor);
  final p = _capped(progressMinor, targetMinor);
  var bands = 0;
  while (bands < goalBandCount && p * goalBandCount >= targetMinor * (bands + 1)) {
    bands++;
  }
  return bands;
}

/// Whether the goal is reached: progress ≥ target.
bool goalReached({required int progressMinor, required int targetMinor}) {
  _check(progressMinor, targetMinor);
  return progressMinor >= targetMinor;
}

/// The goal's stamps after a change (a save added, edited or deleted, or the target edited).
///
/// The stamps are sticky. A band's time is set the first time that band is complete and is never
/// unset; [reachedAt] likewise (lowering the target to or below the progress counts as reaching
/// it, once). Progress dropping back below a stamped band changes no stamp; the rainbow draws from
/// the progress, and the stamps only drive the one-time celebrations. [bandsJustReached] (ascending)
/// and [justReached] report what this change completed for the first time.
///
/// [bandReachedAt] has 5 entries, index 0 = band 1. The result can go straight into the pig's
/// GoalMarks (bandReachedAt, reachedAt).
({List<DateTime?> bandReachedAt, DateTime? reachedAt, List<int> bandsJustReached, bool justReached}) advanceGoalMarks({
  required List<DateTime?> bandReachedAt,
  required DateTime? reachedAt,
  required int progressMinor,
  required int targetMinor,
  required DateTime nowUtc,
}) {
  if (bandReachedAt.length != goalBandCount) {
    throw ArgumentError.value(bandReachedAt.length, 'bandReachedAt', 'must have $goalBandCount entries');
  }
  if (!nowUtc.isUtc) throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
  final bands = goalBands(progressMinor: progressMinor, targetMinor: targetMinor);
  final marks = List<DateTime?>.of(bandReachedAt);
  final just = <int>[];
  for (var band = 1; band <= bands; band++) {
    if (marks[band - 1] == null) {
      marks[band - 1] = nowUtc;
      just.add(band);
    }
  }
  final firstReach = reachedAt == null && goalReached(progressMinor: progressMinor, targetMinor: targetMinor);
  return (
    bandReachedAt: List<DateTime?>.unmodifiable(marks),
    reachedAt: firstReach ? nowUtc : reachedAt,
    bandsJustReached: List<int>.unmodifiable(just),
    justReached: firstReach,
  );
}
