import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/pig/monthly_letter.dart';

import 'helpers.dart';

/// The pig's monthly letter: in a month's first 7 days, a note about the month
/// before (by the phone's dates), with the facts that apply; none for a month
/// with no entries, once "Thanks!" put it away, or with letters switched off.
void main() {
  final t = DateTime.utc(2026, 10, 1);
  var ids = 0;
  Entry entry(
    String date, {
    EntryType type = EntryType.spent,
    Feeling? feeling,
    SpendCategory category = SpendCategory.food,
    int minor = 1000,
    String currency = 'THB',
  }) =>
      Entry(
        id: 'e${++ids}',
        type: type,
        amountMinor: minor,
        currency: currency,
        localDate: date,
        createdAt: t,
        updatedAt: t,
        category: type == EntryType.spent ? category : null,
        feeling: feeling,
      );
  Goal goal(String name, DateTime? reachedAt) =>
      Goal(id: name, name: name, targetMinor: 1000, createdAt: t, updatedAt: t, reachedAt: reachedAt);
  MonthlyLetter? letter(
    DateTime today,
    List<Entry> entries, {
    List<Goal> goals = const [],
    bool on = true,
    String? dismissed,
  }) =>
      monthlyLetter(
        today: today,
        entries: entries,
        goals: goals,
        currency: 'THB',
        zone: 'Asia/Bangkok',
        on: on,
        dismissed: dismissed,
      );

  group('which month, and when', () {
    test('from the 1st to the 7th, about the month before; not from the 8th', () {
      final entries = [entry('2026-10-15')];
      expect(letter(DateTime(2026, 11, 1), entries)?.month, DateTime(2026, 10));
      expect(letter(DateTime(2026, 11, 7), entries), isNotNull);
      expect(letter(DateTime(2026, 11, 8), entries), isNull);
    });

    test('January writes about December', () {
      final l = letter(DateTime(2027, 1, 3), [entry('2026-12-31')]);
      expect(l?.month, DateTime(2026, 12));
      expect(l?.key, '2026-12');
    });

    test('none for a month with no entries, with letters off, or once put away', () {
      expect(letter(DateTime(2026, 11, 2), [entry('2026-11-01'), entry('2026-09-30')]), isNull);
      expect(letter(DateTime(2026, 11, 2), [entry('2026-10-15')], on: false), isNull);
      expect(letter(DateTime(2026, 11, 2), [entry('2026-10-15')], dismissed: '2026-10'), isNull);
      expect(letter(DateTime(2026, 11, 2), [entry('2026-10-15')], dismissed: '2026-09'), isNotNull);
    });
  });

  group('the facts', () {
    test("the days with an entry; saves in the journal's currency only", () {
      final l = letter(DateTime(2026, 11, 1), [
        entry('2026-10-03'),
        entry('2026-10-03'),
        entry('2026-10-20', type: EntryType.saved, minor: 50000),
        entry('2026-10-21', type: EntryType.saved, minor: 25000),
        entry('2026-10-22', type: EntryType.saved, minor: 999, currency: 'USD'),
      ])!;
      expect(l.days, 4);
      expect(l.savedMinor, 75000);
    });

    test('the "worth it" category only when it strictly leads, with two at least', () {
      const w = Feeling.worthIt;
      SpendCategory? worth(List<Entry> entries) => letter(DateTime(2026, 11, 1), entries)!.worthCategory;
      expect(
        worth([
          entry('2026-10-01', feeling: w, category: SpendCategory.fun),
          entry('2026-10-02', feeling: w, category: SpendCategory.fun),
          entry('2026-10-03', feeling: w),
        ]),
        SpendCategory.fun,
      );
      expect(worth([entry('2026-10-01', feeling: w, category: SpendCategory.fun)]), isNull, reason: 'only one');
      expect(
        worth([
          entry('2026-10-01', feeling: w, category: SpendCategory.fun),
          entry('2026-10-02', feeling: w, category: SpendCategory.fun),
          entry('2026-10-03', feeling: w),
          entry('2026-10-04', feeling: w),
        ]),
        isNull,
        reason: 'a tie',
      );
      expect(
        worth([
          entry('2026-10-01', feeling: Feeling.notReally, category: SpendCategory.fun),
          entry('2026-10-02', feeling: Feeling.notReally, category: SpendCategory.fun),
        ]),
        isNull,
        reason: 'only "worth it" counts',
      );
    });

    test("the goals reached that month, by the phone's date, in the order reached", () {
      final l = letter(DateTime(2026, 11, 1), [entry('2026-10-05')], goals: [
        goal('Trip', DateTime.utc(2026, 10, 20)),
        goal('Bike', DateTime.utc(2026, 10, 2)),
        // 01:00 on 1 October in Bangkok: October.
        goal('Early', DateTime.utc(2026, 9, 30, 18)),
        // 01:00 on 1 November in Bangkok: not October.
        goal('Late', DateTime.utc(2026, 10, 31, 18)),
        goal('Open', null),
      ])!;
      expect(l.goalsReached, ['Early', 'Bike', 'Trip']);
    });
  });

  group('on Home', () {
    Future<void> add(TestApp app, String date, {EntryType type = EntryType.spent, int minor = 1000}) =>
        app.journal.addEntry(
          type: type,
          amountMinor: minor,
          currency: 'THB',
          localDate: date,
          category: type == EntryType.spent ? SpendCategory.food : null,
        );

    Future<TestApp> open(WidgetTester tester, DateTime now, Future<void> Function(TestApp app) seed) async {
      final app = TestApp(clock: MovableClock(now), letters: true);
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() => seed(app));
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-week').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('on the 2nd: under the pig, its lines, and "Thanks!" puts it away', (tester) async {
      // 08:30 on 2 October in Bangkok.
      final app = await open(tester, DateTime.utc(2026, 10, 2, 1, 30), (app) async {
        await add(app, '2026-09-10');
        await add(app, '2026-09-11', type: EntryType.saved, minor: 50000);
      });
      expect(byId('home-letter'), findsOneWidget);
      expect(find.text('Your September'), findsOneWidget);
      expect(find.text("Hi! Here's a little look back at September."), findsOneWidget);
      expect(byId('home-letter-goals'), findsNothing);
      expect(find.textContaining('You saved '), findsOneWidget);
      expect(byId('home-letter-worth'), findsNothing);
      expect(find.text('You noted something on 2 days.'), findsOneWidget);
      expect(find.text('Thanks for writing it all down with me.'), findsOneWidget);
      expect(
        tester.getTopLeft(byId('home-letter')).dy,
        greaterThan(tester.getTopLeft(byId('home-pig-line')).dy),
        reason: "under the pig's bubble",
      );

      await tester.tapId('home-letter-thanks');
      expect(byId('home-letter'), findsNothing);
      expect(await tester.runAsync(app.journal.letterDismissed), '2026-09');
    });

    testWidgets("the month turns at the phone's midnight: 06:00 on 1 November in Bangkok", (tester) async {
      // Still 31 October in UTC.
      await open(tester, DateTime.utc(2026, 10, 31, 23), (app) => add(app, '2026-10-15'));
      expect(find.text('Your October'), findsOneWidget);
    });

    testWidgets('Me → Your pig switches letters off and on again (on at first)', (tester) async {
      await open(tester, DateTime.utc(2026, 10, 2, 1, 30), (app) => add(app, '2026-09-10'));
      expect(byId('home-letter'), findsOneWidget);

      await tester.tapId('tab-me');
      final toggle = find.descendant(of: byId('me-letters'), matching: find.byType(SwitchListTile));
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tapId('me-letters');
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tapId('tab-home');
      expect(byId('home-letter'), findsNothing);

      await tester.tapId('tab-me');
      await tester.tapId('me-letters');
      await tester.tapId('tab-home');
      expect(byId('home-letter'), findsOneWidget);
    });

    testWidgets('Delete everything resets the switch and "Thanks!"', (tester) async {
      final app = TestApp();
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        await app.journal.setLettersOn(false);
        await app.journal.dismissLetter('2026-09');
        await app.journal.wipe();
        expect(await app.journal.lettersOn(), isTrue);
        expect(await app.journal.letterDismissed(), isNull);
      });
    });
  });
}
