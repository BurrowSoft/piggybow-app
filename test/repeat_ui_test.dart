import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/repeat/repeat.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// Repeats on screen: the Add sheet's Repeat row, what the app adds at start
/// and on resume (and Home saying so once), Me → Repeating entries, the
/// Timeline's mark, a repeat's entry in the edit sheet, the currency lock,
/// and the app lock.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart).
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');

  /// Rent, ฿12,000 every month on the 1st, first added on [day].
  Future<Entry> rent(
    TestApp app, {
    String day = '2026-10-01',
    String? today,
    RepeatSchedule schedule = const RepeatSchedule.monthly(1),
  }) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: 1200000,
    currency: 'THB',
    localDate: day,
    category: SpendCategory.home,
    note: 'Rent',
    repeat: schedule,
    today: today ?? day,
  );

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

  Future<TestApp> open(
    WidgetTester tester, {
    TestApp? app,
    Future<void> Function(TestApp app)? seed,
    String? location,
  }) async {
    app ??= TestApp();
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app!));
    await app.pump(tester, location: location);
    await waitFor(tester, byId('home-screen'));
    return app;
  }

  Future<List<Entry>> stored(WidgetTester tester, TestApp app) async =>
      (await tester.runAsync(app.journal.entries))!;

  // The sheet's own list (Home's scrolls behind it).
  Finder sheetList() => find
      .descendant(of: find.byType(EntrySheet), matching: find.byType(Scrollable))
      .first;

  Future<void> sheetTap(WidgetTester tester, String id) async {
    await tester.scrollUntilVisible(byId(id), 100, scrollable: sheetList());
    await tester.pumpAndSettle();
    await tester.tap(byId(id));
    await tester.pumpAndSettle();
  }

  Finder textIn(String id, String text) =>
      find.descendant(of: byId(id), matching: find.text(text));

  group('the Add sheet', () {
    testWidgets('"Doesn\'t repeat" at first; Every month on the picked day starts a repeat', (tester) async {
      final app = await open(tester);
      await tester.tapId('home-add');
      await tester.enterId('add-amount', '12000');
      await sheetTap(tester, 'add-cat-home');
      await tester.scrollUntilVisible(byId('add-note'), 100, scrollable: sheetList());
      await tester.enterId('add-note', 'Rent');
      await tester.scrollUntilVisible(byId('add-repeat'), 100, scrollable: sheetList());
      expect(textIn('add-repeat', 'Repeat'), findsOneWidget);
      expect(textIn('add-repeat', "Doesn't repeat"), findsOneWidget);

      await sheetTap(tester, 'add-repeat');
      expect(textIn('repeat-choice-none', "Doesn't repeat"), findsOneWidget);
      expect(textIn('repeat-choice-monthly', 'Every month on day 2'), findsOneWidget);
      expect(textIn('repeat-choice-weekly', 'Every week on Friday'), findsOneWidget);
      expect(byId('repeat-choice-last-day'), findsNothing, reason: '2 October is no month end');
      await tester.tap(byId('repeat-choice-monthly'));
      await tester.pumpAndSettle();
      expect(textIn('add-repeat', 'Every month on day 2'), findsOneWidget);

      await tester.tapId('add-submit');
      final entries = await stored(tester, app);
      final repeats = (await tester.runAsync(app.journal.repeats))!;
      expect(repeats.single.schedule, const RepeatSchedule.monthly(2));
      expect(repeats.single.firstDate, '2026-10-02');
      expect(repeats.single.madeThrough, '2026-10-02');
      expect(repeats.single.note, 'Rent');
      expect(entries.single.repeatId, repeats.single.id);
      expect(entries.single.auto, isFalse, reason: 'the person added it');
    });

    testWidgets('the day picked after: the repeat follows it, and a month end offers "the last day"', (tester) async {
      final app = await open(tester);
      await tester.tapId('home-add');
      await tester.enterId('add-amount', '500');
      await sheetTap(tester, 'add-seg-saved');
      await sheetTap(tester, 'add-repeat');
      await tester.tap(byId('repeat-choice-monthly'));
      await tester.pumpAndSettle();

      // 30 September: the month before, its last day.
      await sheetTap(tester, 'add-date');
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(byId('add-repeat'), 100, scrollable: sheetList());
      expect(textIn('add-repeat', 'Every month on day 30'), findsOneWidget);
      expect(textIn('add-repeat', 'In shorter months, on the last day.'), findsOneWidget);

      await sheetTap(tester, 'add-repeat');
      expect(textIn('repeat-choice-last-day', 'Every month on the last day'), findsOneWidget);
      await tester.tap(byId('repeat-choice-last-day'));
      await tester.pumpAndSettle();
      expect(textIn('add-repeat', 'Every month on the last day'), findsOneWidget);

      await tester.tapId('add-submit');
      final r = (await tester.runAsync(app.journal.repeats))!.single;
      expect(r.schedule, RepeatSchedule.lastDay);
      expect(r.type, EntryType.saved);
      expect(r.firstDate, '2026-09-30');
      expect(r.madeThrough, '2026-10-02', reason: 'never a day before it existed');
    });

    testWidgets('editing an entry: no Repeat row', (tester) async {
      await open(tester, seed: (app) => rent(app));
      await tester.tapId('tab-timeline');
      await tester.tapId('tl-row-entry-2');
      await tester.scrollUntilVisible(byId('add-date'), 100, scrollable: sheetList());
      expect(byId('add-repeat'), findsNothing);
    });
  });

  group('what repeats add', () {
    testWidgets('at start, each day since; Home says so until OK', (tester) async {
      final app = await open(tester, seed: (app) => rent(app, day: '2026-08-01'));
      await waitFor(tester, byId('home-repeats'));
      expect(textIn('home-repeats', 'Added from your repeats'), findsOneWidget);
      // Newest first: 1 October (yesterday), then 1 September.
      for (final id in ['repeat-entry-1-2026-10-01', 'repeat-entry-1-2026-09-01']) {
        expect(textIn('home-repeats-$id', 'Rent'), findsOneWidget, reason: id);
      }
      expect(textIn('home-repeats-repeat-entry-1-2026-10-01', '${money(1200000)} · Yesterday'), findsOneWidget);
      expect(byId('home-repeats-more'), findsNothing);
      final added = [for (final e in await stored(tester, app)) if (e.auto) e.localDate];
      expect(added, ['2026-10-01', '2026-09-01']);

      await tester.tapId('home-repeats-ok');
      expect(byId('home-repeats'), findsNothing);
      expect(await tester.runAsync(app.journal.repeatsSeenAt), isNotNull);
    });

    testWidgets('OK puts away what was added under a clock set ahead', (tester) async {
      // The clock says 1 January 2027: the catch-up adds Nov, Dec and Jan,
      // each "added" then.
      final clock = MovableClock(DateTime.utc(2027, 1, 1, 2));
      final app = await open(
        tester,
        app: TestApp(clock: clock),
        seed: (app) => rent(app, day: '2026-10-01'),
      );
      await waitFor(tester, byId('home-repeats'));
      // Put right: 2 October 2026, before those entries were "added".
      clock.now = DateTime.utc(2026, 10, 2, 1, 30);
      await tester.tapId('home-repeats-ok');
      expect(byId('home-repeats'), findsNothing);
      expect(await tester.runAsync(app.journal.repeatsSeenAt), DateTime.utc(2027, 1, 1, 2));
    });

    testWidgets('more than 3: "and N more" opens Timeline', (tester) async {
      // Every Friday since 7 August: 8 more, up to today.
      await open(
        tester,
        seed: (app) => rent(app, day: '2026-08-07', schedule: const RepeatSchedule.weekly(5)),
      );
      await waitFor(tester, byId('home-repeats'));
      expect(textIn('home-repeats-more', 'and 5 more'), findsOneWidget);
      await tester.tapId('home-repeats-more');
      tester.expectScreen('timeline-screen');
    });

    testWidgets('on resume, the days since are added', (tester) async {
      final clock = MovableClock(DateTime.utc(2026, 10, 2, 1, 30));
      await open(
        tester,
        app: TestApp(clock: clock),
        seed: (app) => rent(app, day: '2026-10-02', schedule: const RepeatSchedule.monthly(2)),
      );
      expect(byId('home-repeats'), findsNothing);

      // A month later, 09:00 in Bangkok.
      clock.now = DateTime.utc(2026, 11, 2, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await waitFor(tester, byId('home-repeats'));
      expect(byId('home-repeats-repeat-entry-1-2026-11-02'), findsOneWidget);
    });

    testWidgets('with the app lock on: added behind it, and told after unlocking', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final lock = AppLock(
        store: MemorySecretStore(),
        biometrics: FakeBiometrics(),
        firstRun: MemoryFirstRunMarker(),
        iterations: 50,
      );
      await tester.runAsync(() => lock.setPin('2468'));
      lock.lockNow();
      final app = TestApp(appLock: lock);
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() => rent(app, day: '2026-09-01'));
      await app.pump(tester);
      await waitFor(tester, byId('lock-screen'));
      tester.expectScreen('lock-screen');
      for (var i = 0; i < 20; i++) {
        final auto = [for (final e in await stored(tester, app)) if (e.auto) e];
        if (auto.isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        [for (final e in await stored(tester, app)) if (e.auto) e.localDate],
        ['2026-10-01'],
        reason: 'added while locked',
      );

      for (final digit in '2468'.split('')) {
        await tester.tap(byId('pin-key-$digit'));
        await tester.pump();
      }
      await tester.tap(byId('pin-key-ok'));
      await waitFor(tester, byId('home-repeats'));
      expect(byId('home-repeats-repeat-entry-1-2026-10-01'), findsOneWidget);
    });
  });

  group('Me → Repeating entries', () {
    testWidgets('the list, a repeat\'s page, Save from the next one on, and Stop', (tester) async {
      final app = await open(tester, seed: (app) => rent(app));
      await tester.tapId('tab-me');
      await tester.tapId('me-repeats');
      await waitFor(tester, byId('repeat-row-entry-1'));
      expect(textIn('repeat-row-entry-1', 'Rent'), findsOneWidget);
      expect(textIn('repeat-row-entry-1', '${money(1200000)} · Every month on day 1'), findsOneWidget);

      await tester.tapId('repeat-row-entry-1');
      await waitFor(tester, byId('repeat-amount'));
      expect(textIn('repeat-schedule', 'Every month on day 1'), findsOneWidget);
      // The amount first: the page's list is lazy, and its top goes once the
      // note below is scrolled to (the typed amount stays, in the page).
      await tester.enterId('repeat-amount', '13000');
      await tester.revealId('repeat-changes');
      expect(
        textIn('repeat-changes', 'Changes apply from the next one. Entries already added stay as they are.'),
        findsOneWidget,
      );
      await tester.tapId('repeat-save');
      await waitFor(tester, byId('repeat-row-entry-1'));
      expect((await tester.runAsync(app.journal.repeats))!.single.amountMinor, 1300000);
      expect((await stored(tester, app)).single.amountMinor, 1200000, reason: 'the entry already added stays');

      await tester.tapId('repeat-row-entry-1');
      await waitFor(tester, byId('repeat-stop'));
      await tester.tapId('repeat-stop');
      expect(find.text('Stop repeating Rent?'), findsOneWidget);
      expect(find.text('Entries it already added stay in your journal.'), findsOneWidget);
      await tester.tapId('repeat-stop-confirm');
      await waitFor(tester, byId('me-repeats-empty'));
      expect(textIn('me-repeats-empty', 'None yet. Turn on Repeat when you add a spend or a save.'), findsOneWidget);
      final r = (await tester.runAsync(app.journal.repeats))!.single;
      expect(r.stoppedOn, '2026-10-02');
      expect((await stored(tester, app)).length, 1, reason: 'what it added stays');
    });

    testWidgets('none yet', (tester) async {
      await open(tester);
      await tester.tapId('tab-me');
      await tester.tapId('me-repeats');
      await waitFor(tester, byId('me-repeats-empty'));
      tester.expectScreen('me-repeats-empty');
    });

    testWidgets('the currency stays set while a repeat runs, with no entry left', (tester) async {
      await open(
        tester,
        seed: (app) async {
          final first = await rent(app);
          await app.journal.deleteEntry(first.id);
        },
      );
      await tester.tapId('tab-me');
      await tester.tapId('me-currency');
      expect(byId('currency-fixed-ok'), findsOneWidget);
    });
  });

  group('a repeat\'s entries', () {
    testWidgets('Timeline marks them, read out as "Repeats every month"', (tester) async {
      await open(
        tester,
        seed: (app) async {
          await rent(app, day: '2026-09-01');
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: 5000,
            currency: 'THB',
            localDate: '2026-10-02',
            category: SpendCategory.food,
          );
        },
      );
      await tester.tapId('tab-timeline');
      await waitFor(tester, byId('tl-row-repeat-entry-1-2026-10-01'));
      for (final id in ['tl-row-repeat-entry-1-2026-10-01', 'tl-row-entry-2']) {
        await tester.revealId(id);
        final mark = find.descendant(of: byId(id), matching: find.byIcon(Icons.repeat));
        expect(mark, findsOneWidget, reason: id);
        // What TalkBack reads for the mark, with the row.
        expect(tester.widget<Icon>(mark).semanticLabel, 'Repeats every month', reason: id);
      }
      expect(
        find.descendant(of: byId('tl-row-entry-3'), matching: find.byIcon(Icons.repeat)),
        findsNothing,
        reason: 'a plain entry',
      );
    });

    testWidgets('the edit sheet names the repeat, Manage opens it, and Delete says it still repeats', (tester) async {
      await open(tester, seed: (app) => rent(app, day: '2026-09-01'));
      await tester.tapId('tab-timeline');
      await waitFor(tester, byId('tl-row-repeat-entry-1-2026-10-01'));

      // The person's own first entry: just its schedule.
      await tester.revealId('tl-row-entry-2');
      await tester.tapId('tl-row-entry-2');
      await tester.scrollUntilVisible(byId('edit-repeat'), 100, scrollable: sheetList());
      expect(textIn('edit-repeat', 'Every month on day 1'), findsOneWidget);
      await tester.tapId('add-back');

      await tester.tapId('tl-row-repeat-entry-1-2026-10-01');
      await tester.scrollUntilVisible(byId('edit-repeat'), 100, scrollable: sheetList());
      expect(textIn('edit-repeat', 'Added by your repeat: Every month on day 1'), findsOneWidget);
      await tester.tap(byId('edit-delete'));
      await tester.pumpAndSettle();
      expect(
        textIn('delete-repeat-note', 'It will still repeat. To stop it: Me → Repeating entries.'),
        findsOneWidget,
      );
      await tester.tap(byId('delete-cancel'));
      await tester.pumpAndSettle();

      await tester.tap(byId('edit-repeat-manage'));
      await waitFor(tester, byId('repeat-amount'));
      tester.expectScreen('repeat-screen');
      expect(byId('tab-me'), findsOneWidget);
    });

    testWidgets('a stopped repeat\'s entry says so, with no Manage', (tester) async {
      final app = await open(tester, seed: (app) => rent(app, day: '2026-09-01'));
      await waitFor(tester, byId('home-repeats'));
      await tester.runAsync(() => app.journal.stopRepeat('entry-1', today: '2026-10-02'));
      await tester.tapId('tab-timeline');
      await waitFor(tester, byId('tl-row-repeat-entry-1-2026-10-01'));
      await tester.tapId('tl-row-repeat-entry-1-2026-10-01');
      await tester.scrollUntilVisible(byId('edit-repeat'), 100, scrollable: sheetList());
      expect(textIn('edit-repeat', "Added by a repeat that's stopped"), findsOneWidget);
      expect(byId('edit-repeat-manage'), findsNothing);
      await tester.tap(byId('edit-delete'));
      await tester.pumpAndSettle();
      expect(byId('delete-repeat-note'), findsNothing, reason: 'it no longer repeats');
    });
  });
}
