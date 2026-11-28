import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/fixtures/launch_fixture.dart';
import 'package:piggybow/goal/goal_progress.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/pig/pig_mood.dart';
import 'package:piggybow/summary/summary.dart';
import 'package:piggybow/tips/tips.dart';

/// The store screenshots' fixtures STORE1 and STORE2 (decision 34;
/// testing/play-screenshots-plan.md §3, moved to Wednesday 18 November 2026
/// so Home's idea is tip02): the numbers Home, Summary and Timeline show,
/// worked out here from the journal they write.
void main() {
  Future<JournalStore> written(String id) async {
    // The contract's cases aren't read for a store fixture.
    final f = LaunchFixture.byId(id, '{"cases": []}');
    expect(f.error, isNull, reason: id);
    expect(f.check('2026-11-18'), isNull, reason: id);
    expect(f.check('2026-11-19'), contains('2026-11-18'), reason: id);
    var ids = 0;
    final store = await JournalStore.inMemory(
      clock: f.clock,
      newId: () => 'id${++ids}',
    );
    addTearDown(store.close);
    expect(await f.write(store), isNull, reason: id);
    return store;
  }

  test('the day: Wednesday 18 November, noon in UTC+7, and tip02 on Home', () {
    expect(storeNow, DateTime.utc(2026, 11, 18, 5));
    expect(DateTime(2026, 11, 18).weekday, DateTime.wednesday);
    expect(tipForDay(DateTime(2026, 11, 18)), 2);
  });

  test("STORE1: the plan's week, in US dollars, brand-free", () async {
    final store = await written('STORE1');
    expect(await store.currency(), 'USD');
    expect(await store.picks(), {HappyPick.save});
    expect(await store.planMinor(), 25000);
    expect(
      await store.reminderOfferAnswered(),
      isTrue,
      reason: 'no "A gentle nudge?" on Home in the shots',
    );
    final entries = await store.entries();
    expect(entries, hasLength(8));
    expect({for (final e in entries) e.currency}, {'USD'});
    expect([for (final e in entries.reversed) e.note], [
      'Birthday money',
      'Internet bill',
      'Concert tickets',
      'Coffee and a pastry',
      'Groceries for the week',
      'Sold an old jacket',
      'Bus to work',
      'Lunch with a friend',
    ]);

    // Summary's week: Monday 16 to Sunday 22 November.
    final s = summarize(
      period: periodContaining(PeriodKind.week, '2026-11-18'),
      today: '2026-11-18',
      entries: [
        for (final e in entries)
          SummaryEntry(
            type: e.type.id,
            amountMinor: e.amountMinor,
            category: e.category?.id,
            feeling: e.feeling?.id,
            localDate: e.localDate,
          ),
      ],
      planMinor: 25000,
      locale: 'en_US',
      categoryLabel: (id) => id,
    );
    expect(s.spentMinor, 16290);
    expect(s.savedMinor, 6000);
    expect(s.planPercent, 65);
    expect(
      [for (final c in s.categories) (c.id, c.amountMinor, c.percent)],
      [
        ('groceries', 6240, 38),
        ('home', 4500, 27),
        ('fun', 3200, 19),
        ('food', 2075, 12),
        ('transport', 275, 1),
      ],
    );
    expect((s.worth, s.notSure, s.notReally), (3, 1, 1));

    // The goal: "Trip to Japan", $480.00 of $1,500.00, 32 %.
    final goal = (await store.activeGoal())!;
    expect(goal.name, 'Trip to Japan');
    expect(goal.targetMinor, 150000);
    final progress = await store.goalProgress(goal);
    expect(progress, 48000);
    expect(goalPercent(progressMinor: progress, targetMinor: 150000), 32);

    // Happy, for this week's save: no band stamped in the last 24 hours.
    final mood = pigMood(
      picks: {HappyPick.save},
      planMinor: 25000,
      entries: [
        for (final e in entries)
          MoodEntry(
            type: e.type.id,
            amountMinor: e.amountMinor,
            feeling: e.feeling?.id,
            localDate: e.localDate,
            createdAt: e.createdAt,
          ),
      ],
      goals: [
        GoalMarks(
          name: goal.name,
          bandReachedAt: goal.bandReachedAt,
          reachedAt: goal.reachedAt,
        ),
      ],
      now: storeNow,
      today: '2026-11-18',
    );
    expect(mood.mood, PigMood.happy);
    expect(mood.lineKey, 'pigHappySave');
  });

  test('STORE2: the same journal, the goal one 50-dollar save from reached', () async {
    final store = await written('STORE2');
    expect(await store.entries(), hasLength(8));
    expect(await store.reminderOfferAnswered(), isTrue);
    final goal = (await store.activeGoal())!;
    expect(goal.status, GoalStatus.active);
    expect(await store.goalProgress(goal), 145000);
    expect(goal.reachedAt, isNull);
    // Its bands came with what was already saved, on 1 November: none in
    // the 24 hours before the screenshot.
    for (final at in goal.bandReachedAt.nonNulls) {
      expect(storeNow.difference(at), greaterThan(const Duration(hours: 24)));
    }
  });

  test('a store fixture goes only into a blank journal, like the others', () async {
    final f = LaunchFixture.byId('STORE1', '{"cases": []}');
    final store = await JournalStore.inMemory(clock: f.clock);
    addTearDown(store.close);
    await store.addEntry(
      type: EntryType.saved,
      amountMinor: 100,
      currency: 'USD',
      localDate: '2026-11-18',
    );
    expect(await f.write(store), contains('empty journal'));
    expect(await store.entries(), hasLength(1));
  });
}
