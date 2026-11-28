import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/pig/pig_mood.dart';

/// Money taken out of savings never moves the pig (feature 5): the mood is
/// the same with or without a withdrawal, whatever else the week holds.
void main() {
  // Friday 2 October 2026, 08:30 in Bangkok.
  final now = DateTime.utc(2026, 10, 2, 1, 30);
  const today = '2026-10-02';

  MoodEntry withdrawal({String day = today, DateTime? at}) => MoodEntry(
    type: 'withdraw',
    amountMinor: 20000,
    localDate: day,
    createdAt: at ?? now,
  );

  PigState mood(List<MoodEntry> entries, {Set<HappyPick> picks = const {HappyPick.plan}}) => pigMood(
    picks: picks,
    planMinor: 100000,
    entries: entries,
    goals: const [],
    now: now,
    today: today,
  );

  test('a withdrawal alone: still the first day, not a plan kept', () {
    expect(mood([withdrawal()]), mood(const []));
    expect(mood([withdrawal()]).lineKey, 'pigFirstDay');
  });

  test('a withdrawal never counts as something added lately', () {
    final old = MoodEntry(
      type: 'spent',
      amountMinor: 500,
      localDate: '2026-09-20',
      createdAt: DateTime.utc(2026, 9, 20),
    );
    expect(mood([old, withdrawal()]), mood([old]));
  });

  test('beside a save and spends, it changes nothing', () {
    final week = [
      MoodEntry(type: 'saved', amountMinor: 3000, localDate: '2026-09-29', createdAt: DateTime.utc(2026, 9, 29)),
      MoodEntry(type: 'spent', amountMinor: 120000, feeling: 'not_really', localDate: '2026-09-30', createdAt: DateTime.utc(2026, 9, 30)),
    ];
    for (final picks in [{HappyPick.save}, {HappyPick.plan}, {HappyPick.worth}, HappyPick.values.toSet()]) {
      expect(mood([...week, withdrawal()], picks: picks), mood(week, picks: picks), reason: '$picks');
    }
  });
}
