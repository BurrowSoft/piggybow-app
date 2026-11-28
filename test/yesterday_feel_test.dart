import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/summary/unfelt_yesterday.dart';

import 'helpers.dart';

/// "How did yesterday feel?" on Home: yesterday's spends (the phone's own
/// day) with no feeling yet, three at most, in the order they were added. An
/// answer is that spend's feeling; "Not now" hides the card until tomorrow;
/// Me → Your pig can switch it off; Delete everything resets both.
void main() {
  test("a repeat's spends aren't asked about: the person didn't note them", () {
    final t = DateTime.utc(2026, 10, 1, 2);
    Entry spend(String id, int minute, {bool auto = false, Feeling? feeling}) => Entry(
      id: id,
      type: EntryType.spent,
      amountMinor: 1250,
      currency: 'THB',
      localDate: '2026-10-01',
      createdAt: t.add(Duration(minutes: minute)),
      updatedAt: t,
      category: SpendCategory.food,
      feeling: feeling,
      repeatId: auto ? 'r1' : null,
      auto: auto,
    );
    final entries = [
      spend('rent', 0, auto: true),
      spend('lunch', 1),
      spend('felt', 2, feeling: Feeling.worthIt),
    ];
    expect([for (final e in unfeltYesterday(entries, '2026-10-01')) e.id], ['lunch']);
    expect(unfeltYesterday(entries, '2026-10-02'), isEmpty);
  });

  /// A spend (or a save) on [date], a minute after the last one added.
  Future<Entry> add(
    TestApp app,
    MovableClock clock,
    String date, {
    EntryType type = EntryType.spent,
    Feeling? feeling,
    String note = '',
  }) {
    clock.now = clock.now.add(const Duration(minutes: 1));
    return app.journal.addEntry(
      type: type,
      amountMinor: 1250,
      currency: 'THB',
      localDate: date,
      category: type == EntryType.spent ? SpendCategory.food : null,
      feeling: feeling,
      note: note,
    );
  }

  Future<void> openHome(WidgetTester tester, TestApp app) async {
    await app.pump(tester);
    for (var i = 0; i < 40 && byId('home-week').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// A journal change made in runAsync reloads Home on real time: frames with
  /// real time between them, until [f] shows or a while has passed.
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Home's list scrolled to Today's idea, right under the card's place: the
  /// card is built there if it's shown at all.
  Future<void> expectNoCard(WidgetTester tester) async {
    await tester.revealId('home-idea');
    expect(byId('home-yesterday'), findsNothing);
  }

  testWidgets("yesterday's spends with no feeling: three at most, in the order added", (tester) async {
    // 09:00 on 1 October in Bangkok.
    final clock = MovableClock(DateTime.utc(2026, 10, 1, 2));
    final app = TestApp(clock: clock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      for (var i = 1; i <= 4; i++) {
        await add(app, clock, '2026-10-01', note: 'Spend $i'); // entry-1 to entry-4
      }
      await add(app, clock, '2026-10-01', feeling: Feeling.worthIt); // entry-5
      await add(app, clock, '2026-10-01', type: EntryType.saved); // entry-6
      await add(app, clock, '2026-09-30'); // entry-7
      clock.now = DateTime.utc(2026, 10, 2, 1, 30); // 08:30 on 2 October
      await add(app, clock, '2026-10-02'); // entry-8
    });
    await openHome(tester, app);

    await tester.revealId('home-yesterday');
    expect(find.text('How did yesterday feel?'), findsOneWidget);
    expect(find.text('A quick look back, if you like.'), findsOneWidget);
    for (final id in ['entry-1', 'entry-2', 'entry-3']) {
      expect(byId('home-yesterday-$id'), findsOneWidget, reason: id);
    }
    for (final id in ['entry-4', 'entry-5', 'entry-6', 'entry-7', 'entry-8']) {
      expect(byId('home-yesterday-$id'), findsNothing, reason: id);
    }
    expect(find.text('Spend 1'), findsOneWidget);
    expect(find.text('Spend 4'), findsNothing, reason: 'no fourth row, and no count of it');
  });

  testWidgets('a spend in your own category, with no note, is named by it', (tester) async {
    // 09:00 on 1 October in Bangkok.
    final clock = MovableClock(DateTime.utc(2026, 10, 1, 2));
    final app = TestApp(clock: clock);
    const tea = '${CustomCategory.idPrefix}tea';
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putCustomCategory(
        CustomCategory(
          id: tea,
          name: 'Bubble tea',
          icon: CategoryIcon.coffee,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      );
      clock.now = clock.now.add(const Duration(minutes: 1));
      await app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 1250,
        currency: 'THB',
        localDate: '2026-10-01',
        customCategory: tea,
      ); // entry-1
      clock.now = DateTime.utc(2026, 10, 2, 1, 30); // 08:30 on 2 October
    });
    await openHome(tester, app);

    await tester.revealId('home-yesterday');
    expect(
      find.descendant(of: byId('home-yesterday-entry-1'), matching: find.text('Bubble tea')),
      findsOneWidget,
    );
  });

  testWidgets("an answer is that spend's feeling: its row goes, then the card", (tester) async {
    final clock = MovableClock(DateTime.utc(2026, 10, 1, 2));
    final app = TestApp(clock: clock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await add(app, clock, '2026-10-01'); // entry-1
      await add(app, clock, '2026-10-01'); // entry-2
      clock.now = DateTime.utc(2026, 10, 2, 1, 30);
    });
    await openHome(tester, app);

    await tester.tapId('home-yesterday-entry-1-worth_it');
    final entries = await tester.runAsync(app.journal.entries);
    expect(entries!.singleWhere((e) => e.id == 'entry-1').feeling, Feeling.worthIt);
    expect(byId('home-yesterday-entry-1'), findsNothing);
    expect(byId('home-yesterday-entry-2'), findsOneWidget);

    await tester.tapId('home-yesterday-entry-2-not_really');
    final after = await tester.runAsync(app.journal.entries);
    expect(after!.singleWhere((e) => e.id == 'entry-2').feeling, Feeling.notReally);
    await expectNoCard(tester);
    expect(app.services.lastAdd.value, isNull, reason: "the pig doesn't react");
  });

  testWidgets('"Not now" hides it until tomorrow', (tester) async {
    final clock = MovableClock(DateTime.utc(2026, 10, 1, 2));
    final app = TestApp(clock: clock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await add(app, clock, '2026-10-01'); // entry-1
      clock.now = DateTime.utc(2026, 10, 2, 1, 30);
      await add(app, clock, '2026-10-02'); // entry-2
    });
    await openHome(tester, app);

    await tester.tapId('home-yesterday-later');
    await expectNoCard(tester);
    // Still hidden when Home reads again later that day (given the time to
    // show it, were it not hidden).
    await tester.runAsync(() => add(app, clock, '2026-10-02', type: EntryType.saved));
    await waitFor(tester, byId('home-yesterday'));
    await expectNoCard(tester);

    // The next day, 2 October is yesterday, and its spend is asked about.
    clock.now = DateTime.utc(2026, 10, 3, 1, 30);
    await tester.runAsync(() => add(app, clock, '2026-10-03', type: EntryType.saved));
    await waitFor(tester, byId('home-yesterday'));
    await tester.revealId('home-yesterday');
    expect(byId('home-yesterday-entry-2'), findsOneWidget);
    expect(byId('home-yesterday-entry-1'), findsNothing);
  });

  testWidgets("yesterday is the phone's: at 06:00 on 2 October in Bangkok, UTC is still on the 1st", (tester) async {
    final clock = MovableClock(DateTime.utc(2026, 9, 30, 2));
    final app = TestApp(clock: clock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await add(app, clock, '2026-09-30'); // entry-1
      await add(app, clock, '2026-10-01'); // entry-2
      clock.now = DateTime.utc(2026, 10, 1, 23);
    });
    await openHome(tester, app);

    await tester.revealId('home-yesterday');
    expect(byId('home-yesterday-entry-2'), findsOneWidget);
    expect(byId('home-yesterday-entry-1'), findsNothing);
  });

  testWidgets('Me → Your pig switches it off and on again (on at first)', (tester) async {
    final clock = MovableClock(DateTime.utc(2026, 10, 1, 2));
    final app = TestApp(clock: clock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await add(app, clock, '2026-10-01'); // entry-1
      clock.now = DateTime.utc(2026, 10, 2, 1, 30);
    });
    await openHome(tester, app);
    await tester.revealId('home-yesterday');

    await tester.tapId('tab-me');
    final toggle = find.descendant(of: byId('me-yesterday-feel'), matching: find.byType(SwitchListTile));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tapId('me-yesterday-feel');
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tapId('tab-home');
    await expectNoCard(tester);

    await tester.tapId('tab-me');
    await tester.tapId('me-yesterday-feel');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tapId('tab-home');
    await tester.revealId('home-yesterday');
    expect(byId('home-yesterday-entry-1'), findsOneWidget);
  });

  testWidgets('Delete everything resets the switch and "Not now"', (tester) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.setYesterdayFeelOn(false);
      await app.journal.hideYesterdayFeel('2026-10-02');
      expect(await app.journal.yesterdayFeelOn(), isFalse);
      expect(await app.journal.yesterdayFeelHiddenOn(), '2026-10-02');
      await app.journal.wipe();
      expect(await app.journal.yesterdayFeelOn(), isTrue);
      expect(await app.journal.yesterdayFeelHiddenOn(), isNull);
    });
  });
}
