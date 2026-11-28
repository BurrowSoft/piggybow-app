import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/data/models.dart' show ReminderTime;
import 'package:piggybow/features/me/me_actions.dart';
import 'package:piggybow/features/pig/pig_view.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/pig/pig_mood.dart';
import 'package:piggybow/repeat/repeat.dart';

import 'helpers.dart';

/// An entry a repeat added is money, not something the person wrote: it
/// counts in this week's picks and in the export (with its repeat's kind),
/// but it doesn't silence today's reminder or wake the pig.
void main() {
  /// Frames, with real time between them, until [f] shows.
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// The app on Friday 2 October 2026, 08:30 in Bangkok, after [seed] ran
  /// on [seededAt]: the person's own entries are from then, and the app's
  /// catch-up at start adds what the repeats owe since.
  Future<TestApp> open(
    WidgetTester tester, {
    required DateTime seededAt,
    required Future<void> Function(TestApp app) seed,
  }) async {
    final clock = MovableClock(seededAt);
    final app = TestApp(clock: clock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() => seed(app));
    clock.now = DateTime.utc(2026, 10, 2, 1, 30);
    await app.pump(tester);
    await waitFor(tester, byId('home-repeats'));
    return app;
  }

  Future<Entry> repeating(
    TestApp app, {
    required String day,
    required RepeatSchedule schedule,
    EntryType type = EntryType.spent,
  }) => app.journal.addEntry(
    type: type,
    amountMinor: type == EntryType.spent ? 1200000 : 50000,
    currency: 'THB',
    localDate: day,
    category: type == EntryType.spent ? SpendCategory.home : null,
    note: type == EntryType.spent ? 'Rent' : '',
    repeat: schedule,
    today: day,
  );

  PigMood pigMoodOnHome(WidgetTester tester) =>
      tester.widget<PigView>(find.byType(PigView)).mood;

  testWidgets("an entry a repeat added today keeps today's reminder", (
    tester,
  ) async {
    // Rent on the 2nd, first added on 2 September.
    final app = await open(
      tester,
      seededAt: DateTime.utc(2026, 9, 2, 1, 30),
      seed: (app) => repeating(
        app,
        day: '2026-09-02',
        schedule: const RepeatSchedule.monthly(2),
      ),
    );
    expect(byId('home-repeats-repeat-entry-1-2026-10-02'), findsOneWidget);
    await app.session.updateReminder(on: true, time: const ReminderTime(21, 0));
    await tester.pumpAndSettle();
    expect(
      app.reminders.scheduled.first.id,
      20261002,
      reason: "the person hasn't written anything today",
    );
  });

  testWidgets("an entry a repeat added doesn't wake the pig, nor make it answer", (
    tester,
  ) async {
    // The person's own last entry was added on 20 September (12 days ago).
    final app = await open(
      tester,
      seededAt: DateTime.utc(2026, 9, 20, 1, 30),
      seed: (app) => repeating(
        app,
        day: '2026-09-01',
        schedule: const RepeatSchedule.monthly(1),
      ),
    );
    // Added at start, just now: 1 October's rent.
    expect(byId('home-repeats-repeat-entry-1-2026-10-01'), findsOneWidget);
    expect(pigMoodOnHome(tester), PigMood.sleepy);
    expect(app.services.lastAdd.value, isNull, reason: 'no "you added" line');
  });

  testWidgets('a save a repeat added this week meets "saving something each week"', (
    tester,
  ) async {
    // Every Thursday, from 24 September; this week's comes on 1 October.
    await open(
      tester,
      seededAt: DateTime.utc(2026, 9, 24, 1, 30),
      seed: (app) async {
        await app.journal.setPicks({HappyPick.save});
        await repeating(
          app,
          day: '2026-09-24',
          schedule: const RepeatSchedule.weekly(4),
          type: EntryType.saved,
        );
      },
    );
    expect(byId('home-repeats-repeat-entry-1-2026-10-01'), findsOneWidget);
    expect(pigMoodOnHome(tester), PigMood.happy);
  });

  testWidgets("the export: a repeat's entries say its kind, the first one too", (
    tester,
  ) async {
    final app = await open(
      tester,
      seededAt: DateTime.utc(2026, 9, 1, 1, 30),
      seed: (app) async {
        await repeating(
          app,
          day: '2026-09-01',
          schedule: const RepeatSchedule.monthly(1),
        );
        await app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 5000,
          currency: 'THB',
          localDate: '2026-09-05',
          category: SpendCategory.food,
        );
      },
    );
    final csv = (await tester.runAsync(() => journalCsv(app.services)))!;
    final lines = csv.split('\r\n');
    expect(lines.first, endsWith(',goal,repeat'));
    expect(lines, contains('2026-09-01,spent,12000.00,THB,home,,Rent,,monthly'));
    expect(lines, contains('2026-09-05,spent,50.00,THB,food,,,,'));
    expect(lines, contains('2026-10-01,spent,12000.00,THB,home,,Rent,,monthly'));
  });
}
