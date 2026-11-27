import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/goal/goal_progress.dart';
import 'package:piggybow/pig/pig_mood.dart';

/// PB Mobile Tester's PR 3 table (testing/check-plan-weekend.md, "Bands and percent"), target 1000.
const table = [
  // progress, percent, bands, reached
  (0, 0, 0, false),
  (199, 19, 0, false),
  (200, 20, 1, false),
  (399, 39, 1, false),
  (400, 40, 2, false),
  (999, 99, 4, false),
  (1000, 100, 5, true),
  (2500, 100, 5, true),
];

final t0 = DateTime.utc(2026, 12, 1, 10);
final t1 = DateTime.utc(2026, 12, 2, 10);
final t2 = DateTime.utc(2026, 12, 3, 10);
const none = <DateTime?>[null, null, null, null, null];

void main() {
  group('percent, bands and reached (the tester\'s table, target 1000)', () {
    for (final (progress, percent, bands, reached) in table) {
      test('progress $progress → $percent %, $bands band${bands == 1 ? '' : 's'}, ${reached ? '' : 'not '}reached', () {
        expect(goalPercent(progressMinor: progress, targetMinor: 1000), percent);
        expect(goalBands(progressMinor: progress, targetMinor: 1000), bands);
        expect(goalReached(progressMinor: progress, targetMinor: 1000), reached);
      });
    }
  });

  test('tiny target 3: progress 1 → 33 %, 1 band; progress 2 → 66 %, 3 bands', () {
    expect(goalPercent(progressMinor: 1, targetMinor: 3), 33);
    expect(goalBands(progressMinor: 1, targetMinor: 3), 1);
    expect(goalPercent(progressMinor: 2, targetMinor: 3), 66);
    expect(goalBands(progressMinor: 2, targetMinor: 3), 3);
  });

  test('huge target 999999999999, and progress far past it, never overflow', () {
    const target = 999999999999;
    expect(goalPercent(progressMinor: target, targetMinor: target), 100);
    expect(goalPercent(progressMinor: target - 1, targetMinor: target), 99);
    expect(goalPercent(progressMinor: 1, targetMinor: target), 0);
    expect(goalBands(progressMinor: target - 1, targetMinor: target), 4);
    // A progress whose × 100 would overflow a 64-bit int.
    const past = 900000000000000000;
    expect(goalPercent(progressMinor: past, targetMinor: 1000), 100);
    expect(goalBands(progressMinor: past, targetMinor: 1000), 5);
    expect(goalReached(progressMinor: past, targetMinor: 1000), isTrue);
  });

  test('bands = the spec\'s rule (progress × 5 ≥ target × i) = percent ~/ 20, for any amounts', () {
    final r = Random(41);
    for (var i = 0; i < 20000; i++) {
      final target = 1 + r.nextInt(1 << 31) * (r.nextBool() ? 1 : 1000);
      final progress = r.nextInt(3) == 0 ? target : r.nextInt(1 << 31) * (r.nextBool() ? 1 : 1000);
      final p = progress < target ? progress : target;
      final spec = [for (var band = 1; band <= 5; band++) if (p * 5 >= target * band) band].length;
      final bands = goalBands(progressMinor: progress, targetMinor: target);
      expect(bands, spec, reason: '$progress / $target');
      expect(bands, goalPercent(progressMinor: progress, targetMinor: target) ~/ 20, reason: '$progress / $target');
    }
  });

  test('a zero or negative target, or a negative progress, is refused', () {
    expect(() => goalPercent(progressMinor: 1, targetMinor: 0), throwsArgumentError);
    expect(() => goalBands(progressMinor: 1, targetMinor: -5), throwsArgumentError);
    expect(() => goalReached(progressMinor: -1, targetMinor: 10), throwsArgumentError);
  });

  group('the sticky stamps', () {
    test('a band is stamped the first time it completes, and reported once', () {
      final a = advanceGoalMarks(bandReachedAt: none, reachedAt: null, progressMinor: 250, targetMinor: 1000, nowUtc: t0);
      expect(a.bandReachedAt, [t0, null, null, null, null]);
      expect(a.bandsJustReached, [1]);
      expect(a.justReached, isFalse);
      final b = advanceGoalMarks(bandReachedAt: a.bandReachedAt, reachedAt: a.reachedAt, progressMinor: 450, targetMinor: 1000, nowUtc: t1);
      expect(b.bandReachedAt, [t0, t1, null, null, null]);
      expect(b.bandsJustReached, [2]);
    });

    test('one save across several bands stamps them all at once, lowest first', () {
      final a = advanceGoalMarks(bandReachedAt: none, reachedAt: null, progressMinor: 650, targetMinor: 1000, nowUtc: t0);
      expect(a.bandReachedAt, [t0, t0, t0, null, null]);
      expect(a.bandsJustReached, [1, 2, 3]);
    });

    test('deleting the save that completed band 2: the rainbow draws band 1 again, band 2 keeps its stamp', () {
      final marks = [t0, t1, null, null, null];
      final after = advanceGoalMarks(bandReachedAt: marks, reachedAt: null, progressMinor: 300, targetMinor: 1000, nowUtc: t2);
      expect(goalBands(progressMinor: 300, targetMinor: 1000), 1);
      expect(after.bandReachedAt, [t0, t1, null, null, null]);
      expect(after.bandsJustReached, isEmpty);
    });

    test('re-crossing band 2 sets nothing new and reports nothing', () {
      final marks = [t0, t1, null, null, null];
      final again = advanceGoalMarks(bandReachedAt: marks, reachedAt: null, progressMinor: 420, targetMinor: 1000, nowUtc: t2);
      expect(again.bandReachedAt, [t0, t1, null, null, null]);
      expect(again.bandsJustReached, isEmpty);
      expect(again.justReached, isFalse);
    });

    test('reaching the goal stamps it and every band still open, once', () {
      final marks = [t0, t1, null, null, null];
      final done = advanceGoalMarks(bandReachedAt: marks, reachedAt: null, progressMinor: 1000, targetMinor: 1000, nowUtc: t2);
      expect(done.reachedAt, t2);
      expect(done.justReached, isTrue);
      expect(done.bandReachedAt, [t0, t1, t2, t2, t2]);
      expect(done.bandsJustReached, [3, 4, 5]);
      final later = advanceGoalMarks(bandReachedAt: done.bandReachedAt, reachedAt: done.reachedAt, progressMinor: 1200, targetMinor: 1000, nowUtc: t2.add(const Duration(days: 1)));
      expect(later.reachedAt, t2);
      expect(later.justReached, isFalse);
      expect(later.bandsJustReached, isEmpty);
    });

    test('lowering the target to the progress counts as reaching it, once', () {
      final marks = [t0, t1, null, null, null];
      final lowered = advanceGoalMarks(bandReachedAt: marks, reachedAt: null, progressMinor: 500, targetMinor: 500, nowUtc: t2);
      expect(lowered.justReached, isTrue);
      expect(lowered.reachedAt, t2);
      final again = advanceGoalMarks(bandReachedAt: lowered.bandReachedAt, reachedAt: lowered.reachedAt, progressMinor: 500, targetMinor: 400, nowUtc: t2);
      expect(again.justReached, isFalse);
    });

    test('"already saved" at or above the target reaches it at creation', () {
      final created = advanceGoalMarks(bandReachedAt: none, reachedAt: null, progressMinor: 1500, targetMinor: 1000, nowUtc: t0);
      expect(created.justReached, isTrue);
      expect(created.bandsJustReached, [1, 2, 3, 4, 5]);
    });

    test('raising the target later never unsets reached_at or a band', () {
      final done = [t0, t0, t0, t0, t0];
      final raised = advanceGoalMarks(bandReachedAt: done, reachedAt: t0, progressMinor: 1000, targetMinor: 5000, nowUtc: t2);
      expect(goalReached(progressMinor: 1000, targetMinor: 5000), isFalse);
      expect(raised.reachedAt, t0);
      expect(raised.bandReachedAt, done);
      expect(raised.justReached, isFalse);
    });

    test('the input list is never changed, and the result is read-only', () {
      final marks = <DateTime?>[null, null, null, null, null];
      final a = advanceGoalMarks(bandReachedAt: marks, reachedAt: null, progressMinor: 1000, targetMinor: 1000, nowUtc: t0);
      expect(marks, none);
      expect(() => a.bandReachedAt[0] = null, throwsUnsupportedError);
      expect(() => a.bandsJustReached.add(9), throwsUnsupportedError);
    });

    test('bad input is refused: not 5 stamps, a local time, or a bad amount', () {
      expect(
        () => advanceGoalMarks(bandReachedAt: const [null], reachedAt: null, progressMinor: 1, targetMinor: 10, nowUtc: t0),
        throwsArgumentError,
      );
      expect(
        () => advanceGoalMarks(bandReachedAt: none, reachedAt: null, progressMinor: 1, targetMinor: 10, nowUtc: DateTime(2026, 12, 1)),
        throwsArgumentError,
      );
      expect(
        () => advanceGoalMarks(bandReachedAt: none, reachedAt: null, progressMinor: 1, targetMinor: 0, nowUtc: t0),
        throwsArgumentError,
      );
    });
  });

  test('the stamps go straight into the pig: a band just reached makes it delighted', () {
    final now = DateTime.utc(2026, 12, 2, 5);
    final marks = advanceGoalMarks(bandReachedAt: none, reachedAt: null, progressMinor: 450, targetMinor: 1000, nowUtc: now);
    final state = pigMood(
      picks: {HappyPick.save},
      planMinor: null,
      entries: [MoodEntry(type: 'saved', amountMinor: 450, localDate: '2026-12-02', createdAt: now)],
      goals: [GoalMarks(name: 'Bike', bandReachedAt: marks.bandReachedAt, reachedAt: marks.reachedAt)],
      now: now.add(const Duration(minutes: 1)),
      today: '2026-12-02',
    );
    expect(state, const PigState(PigMood.delighted, 'pigDelightedBand', {'band': 2}));
  });
}
