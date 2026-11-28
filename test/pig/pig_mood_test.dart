import 'dart:convert' show jsonDecode;
import 'dart:io' show File;
import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/pig/pig_mood.dart';

/// Every line the pig can say (plan §4.3). Nothing else may come out of pigMood.
const moodLines = {
  'pigFirstDay', 'pigCalm1', 'pigCalm2', 'pigCalm3', 'pigCalmMonday', //
  'pigHappySave', 'pigHappyPlan', 'pigHappyWorth', //
  'pigDelightedAll', 'pigDelightedBand', 'pigDelightedGoal', //
  'pigSleepy1', 'pigSleepy2', 'pigSleepy3', //
};

DateTime? _instant(Object? v) => v == null ? null : DateTime.parse(v as String);

/// An entry in another currency counts at its home amount (C37).
MoodEntry _entry(Map<String, dynamic> e) => MoodEntry(
  type: e['type'] as String,
  amountMinor: (e['home_minor'] ?? e['amount_minor']) as int,
  feeling: e['feeling'] as String?,
  localDate: e['local_date'] as String,
  createdAt: DateTime.parse(e['created_at'] as String),
  auto: e['auto'] == true,
);

GoalMarks _goal(Map<String, dynamic> g) => GoalMarks(
  name: g['name'] as String,
  bandReachedAt: [for (final t in g['band_reached_at'] as List) _instant(t)],
  reachedAt: _instant(g['reached_at']),
);

PigState _run(Map<String, dynamic> c) => pigMood(
  picks: {for (final p in c['picks'] as List) HappyPick.values.byName(p as String)},
  planMinor: c['plan_minor'] as int?,
  entries: [for (final e in c['entries'] as List) _entry(e as Map<String, dynamic>)],
  goals: [for (final g in c['goals'] as List) _goal(g as Map<String, dynamic>)],
  now: DateTime.parse(c['now'] as String),
  today: c['today'] as String,
);

void main() {
  final contract = jsonDecode(File('test/contracts/pig_mood_cases.json').readAsStringSync()) as Map<String, dynamic>;
  final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();

  test('the contract is loaded whole', () {
    expect(cases.length, 41);
    expect(cases.map((c) => c['id']).toSet().length, cases.length, reason: 'ids are unique');
  });

  group('the shared contract (test/contracts/pig_mood_cases.json)', () {
    for (final c in cases) {
      test('${c['id']}: ${c['why']}', () {
        final expected = c['expect'] as Map<String, dynamic>;
        final state = _run(c);
        expect(state.mood.name, expected['mood']);
        expect(state.lineKey, expected['line']);
        expect(state.args, (expected['args'] as Map<String, dynamic>?) ?? const <String, Object>{});
      });
    }
  });

  group('beyond the contract', () {
    final now = DateTime.utc(2026, 12, 2, 5);
    MoodEntry spend(String? feeling) => MoodEntry(
      type: 'spent',
      amountMinor: 1000,
      feeling: feeling,
      localDate: '2026-12-01',
      createdAt: DateTime.utc(2026, 12, 1, 12),
    );

    test('"Not sure" never counts against "Worth it": 1 worth_it + 2 not_sure meets worth', () {
      final state = pigMood(
        picks: {HappyPick.worth},
        planMinor: null,
        entries: [spend('worth_it'), spend('not_sure'), spend('not_sure')],
        goals: const [],
        now: now,
        today: '2026-12-02',
      );
      expect(state, const PigState(PigMood.happy, 'pigHappyWorth'));
    });

    test('a save in the week of a different year still counts (week crosses New Year)', () {
      final state = pigMood(
        picks: {HappyPick.save},
        planMinor: null,
        entries: [
          MoodEntry(type: 'saved', amountMinor: 500, localDate: '2025-12-29', createdAt: DateTime.utc(2025, 12, 29, 12)),
        ],
        goals: const [],
        now: DateTime.utc(2026, 1, 1, 5),
        today: '2026-01-01',
      );
      expect(state.lineKey, 'pigHappySave');
    });

    test('an entry dated after today is not in this week', () {
      final state = pigMood(
        picks: {HappyPick.save},
        planMinor: null,
        entries: [MoodEntry(type: 'saved', amountMinor: 500, localDate: '2026-12-03', createdAt: now)],
        goals: const [],
        now: now,
        today: '2026-12-02',
      );
      expect(state.mood, PigMood.calm);
    });
  });

  group('the line right after an Add', () {
    const band = PigState(PigMood.delighted, 'pigDelightedBand', {'band': 3});
    const goal = PigState(PigMood.delighted, 'pigDelightedGoal', {'goalName': 'Bike'});
    const calm = PigState(PigMood.calm, 'pigCalm2');

    test('no reaction: the mood line', () {
      expect(pigBubbleKey(calm, null), 'pigCalm2');
      expect(pigBubbleKey(band, null), 'pigDelightedBand');
    });

    test('each reaction has its own line', () {
      expect(pigBubbleKey(calm, PigReaction.spend), 'pigAfterSpend');
      expect(pigBubbleKey(calm, PigReaction.worth), 'pigAfterWorth');
      expect(pigBubbleKey(calm, PigReaction.notSure), 'pigAfterNotSure');
      expect(pigBubbleKey(calm, PigReaction.notReally), 'pigAfterNotReally');
      expect(pigBubbleKey(calm, PigReaction.save), 'pigAfterSave');
    });

    test('after a save, a band or the goal just reached wins over pigAfterSave (§4.7)', () {
      expect(pigBubbleKey(band, PigReaction.save), 'pigDelightedBand');
      expect(pigBubbleKey(goal, PigReaction.save), 'pigDelightedGoal');
    });

    test('after a spend, the spend reaction still shows', () {
      expect(pigBubbleKey(band, PigReaction.spend), 'pigAfterSpend');
    });
  });

  group('rotation: lines[(dayOfYear - 1) mod n]', () {
    const lines = ['a', 'b', 'c'];
    test('1 January is the first line', () => expect(rotatingLine(lines, '2026-01-01'), 'a'));
    test('2 December 2026 is day 336', () => expect(rotatingLine(lines, '2026-12-02'), 'c'));
    test('31 December in a common year is day 365', () => expect(rotatingLine(lines, '2026-12-31'), 'b'));
    test('31 December in a leap year is day 366', () => expect(rotatingLine(lines, '2028-12-31'), 'c'));
    test('a 20-line rotation (the tips)', () {
      final tips = [for (var i = 1; i <= 20; i++) 'tip${i.toString().padLeft(2, '0')}'];
      expect(rotatingLine(tips, '2026-01-20'), 'tip20');
      expect(rotatingLine(tips, '2026-01-21'), 'tip01');
    });
  });

  test('a malformed or impossible "today" throws', () {
    for (final today in ['2026-12-2', '02/12/2026', '2026-02-30', '']) {
      expect(
        () => pigMood(picks: {HappyPick.save}, planMinor: null, entries: const [], goals: const [], now: DateTime.utc(2026, 12, 2), today: today),
        throwsArgumentError,
        reason: today,
      );
    }
  });

  test('whatever the inputs, the pig only ever says one of its own lines', () {
    final r = Random(30);
    final base = DateTime.utc(2026, 12, 2, 5);
    for (var i = 0; i < 3000; i++) {
      final picks = {for (final p in HappyPick.values) if (r.nextBool()) p};
      if (picks.isEmpty) picks.add(HappyPick.save);
      final entries = [
        for (var j = r.nextInt(6); j > 0; j--)
          MoodEntry(
            type: r.nextBool() ? 'spent' : 'saved',
            amountMinor: 1 + r.nextInt(200000),
            feeling: const [null, 'worth_it', 'not_sure', 'not_really'][r.nextInt(4)],
            localDate: '2026-11-${(20 + r.nextInt(11)).toString().padLeft(2, '0')}',
            createdAt: base.subtract(Duration(hours: r.nextInt(400) - 24)),
          ),
      ];
      final goals = [
        if (r.nextBool())
          GoalMarks(
            name: 'Goal',
            bandReachedAt: [for (var b = 0; b < 5; b++) r.nextInt(4) == 0 ? base.subtract(Duration(hours: r.nextInt(60))) : null],
            reachedAt: r.nextInt(5) == 0 ? base.subtract(Duration(hours: r.nextInt(60))) : null,
          ),
      ];
      final state = pigMood(
        picks: picks,
        planMinor: r.nextBool() ? null : r.nextInt(300000),
        entries: entries,
        goals: goals,
        now: base,
        today: '2026-11-30',
      );
      expect(moodLines, contains(state.lineKey));
      if (state.mood == PigMood.delighted) {
        expect(['pigDelightedAll', 'pigDelightedBand', 'pigDelightedGoal'], contains(state.lineKey));
      }
    }
  });
}
