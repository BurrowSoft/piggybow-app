// Goldens: repeating entries, RP1–RP9 at 320 dp ×2 (decision 44), and their
// layout in every case.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/repeat/repeat.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/goldens.dart';
import 'layout_matrix.dart';

/// RP1 the Add sheet with Repeat on a month end (the hint), RP2 its choices,
/// RP3 Me's list, RP4 empty, RP5 a repeat's page, RP6 its stop dialog, RP7
/// Home's card (and the card alone), RP8 Timeline's mark, RP9 the edit
/// sheet of an entry a repeat added.
void main() {
  setUpAll(loadAppFonts);

  /// A monthly or weekly repeat, its first entry on [day].
  Future<Entry> repeating(
    TestApp app, {
    String day = '2026-09-01',
    RepeatSchedule schedule = const RepeatSchedule.monthly(1),
    String note = 'Rent',
    SpendCategory category = SpendCategory.home,
    int minor = 1200000,
  }) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: minor,
    currency: 'THB',
    localDate: day,
    category: category,
    note: note,
    repeat: schedule,
    today: day,
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
    WidgetTester tester,
    LayoutCase c, {
    MovableClock? clock,
    Future<void> Function(TestApp app)? seed,
  }) async {
    setLayout(tester, c);
    final app = TestApp(clock: clock)..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await waitFor(tester, byId('home-screen'));
    return app;
  }

  Finder sheetList() => find
      .descendant(of: find.byType(EntrySheet), matching: find.byType(Scrollable))
      .first;

  Finder listOf(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  Future<void> reveal(WidgetTester tester, Finder list, String id) async {
    await tester.scrollUntilVisible(byId(id), 120, scrollable: list);
    await tester.pumpAndSettle();
  }

  /// The checks on every part of [list], scrolled through top to bottom.
  Future<void> checkScrolled(WidgetTester tester, Finder list, String state) async {
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(tester, reason: '$state at ${position.pixels.round()}');
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pump();
    }
  }

  // 08:30 in Bangkok on 30 September 2026, a month's last day.
  MovableClock monthEnd() => MovableClock(DateTime.utc(2026, 9, 30, 1, 30));

  for (final c in layoutCases) {
    testWidgets('RP1 the Add sheet: rent every month on day 30, and the hint ($c)', (tester) async {
      await open(tester, c, clock: monthEnd());
      await tester.tapId('home-add');
      await tester.enterId('add-amount', '12000');
      await reveal(tester, sheetList(), 'add-cat-home');
      await tester.tap(byId('add-cat-home'));
      await tester.pump();
      await reveal(tester, sheetList(), 'add-note');
      await tester.enterId('add-note', 'Rent');
      await reveal(tester, sheetList(), 'add-repeat');
      await tester.tap(byId('add-repeat'));
      await tester.pumpAndSettle();
      await tester.tap(byId('repeat-choice-monthly'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: byId('add-repeat'), matching: find.text('In shorter months, on the last day.')),
        findsOneWidget,
      );
      await checkScrolled(tester, sheetList(), 'RP1');
      if (c.takesGolden) {
        await expectLayoutGoldens(tester, c, sheetList(), screen: 'add-sheet', state: 'repeat', stateId: 'RP1');
      }
    });

    testWidgets('RP2 the Repeat choices on a month end ($c)', (tester) async {
      await open(tester, c, clock: monthEnd());
      await tester.tapId('home-add');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await reveal(tester, sheetList(), 'add-repeat');
      await tester.tap(byId('add-repeat'));
      await tester.pumpAndSettle();
      for (final id in ['none', 'monthly', 'last-day', 'weekly']) {
        expect(byId('repeat-choice-$id'), findsOneWidget, reason: id);
      }
      await expectSoundLayout(tester, reason: 'RP2');
      if (c.takesGolden) {
        await expectLayoutGolden(tester, c, screen: 'add-sheet', state: 'repeat-choices', stateId: 'RP2');
      }
    });

    testWidgets('RP3 Me → Repeating entries: a monthly one and a weekly one ($c)', (tester) async {
      await open(
        tester,
        c,
        seed: (app) async {
          await repeating(app, day: '2026-10-01');
          // Monday 28 September.
          await repeating(
            app,
            day: '2026-09-28',
            schedule: const RepeatSchedule.weekly(1),
            note: 'Gym membership',
            category: SpendCategory.health,
            minor: 50000,
          );
        },
      );
      await tester.tapId('tab-me');
      await tester.tapId('me-repeats');
      await waitFor(tester, byId('repeat-row-entry-3'));
      expect(byId('repeat-row-entry-1'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'RP3');
      if (c.takesGolden) {
        await expectLayoutGolden(tester, c, screen: 'me-repeats', state: 'list', stateId: 'RP3');
      }
    });

    testWidgets('RP4 Me → Repeating entries: none yet ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tab-me');
      await tester.tapId('me-repeats');
      await waitFor(tester, byId('me-repeats-empty'));
      await expectSoundLayout(tester, reason: 'RP4');
      if (c.takesGolden) {
        await expectLayoutGolden(tester, c, screen: 'me-repeats', state: 'empty', stateId: 'RP4');
      }
    });

    testWidgets('RP5 a repeat\'s page, and RP6 its stop dialog ($c)', (tester) async {
      await open(tester, c, seed: (app) => repeating(app, day: '2026-10-01'));
      await tester.tapId('tab-me');
      await tester.tapId('me-repeats');
      await waitFor(tester, byId('repeat-row-entry-1'));
      await tester.tapId('repeat-row-entry-1');
      await waitFor(tester, byId('repeat-amount'));
      final page = listOf('repeat-screen');
      await checkScrolled(tester, page, 'RP5');
      if (c.takesGolden) {
        await expectLayoutGoldens(tester, c, page, screen: 'repeat', state: 'page', stateId: 'RP5');
      }

      await reveal(tester, page, 'repeat-stop');
      await tester.tap(byId('repeat-stop'));
      await tester.pumpAndSettle();
      expect(byId('repeat-stop-confirm'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'RP6');
      if (c.takesGolden) {
        await expectLayoutGolden(tester, c, screen: 'repeat', state: 'stop', stateId: 'RP6');
      }
    });

    testWidgets('RP7 Home: what repeats added, 3 and "and 1 more" ($c)', (tester) async {
      // Every Friday from 4 September: four more by today.
      await open(
        tester,
        c,
        seed: (app) => repeating(
          app,
          day: '2026-09-04',
          schedule: const RepeatSchedule.weekly(5),
          note: 'Gym',
          category: SpendCategory.health,
          minor: 50000,
        ),
      );
      await waitFor(tester, byId('home-repeats-more'));
      final home = listOf('home-screen');
      await reveal(tester, home, 'home-repeats-ok');
      await checkScrolled(tester, home, 'RP7');
      if (c.takesGolden) {
        await expectLayoutGoldens(tester, c, home, screen: 'home', state: 'repeats', stateId: 'RP7');
        // The card alone, whole: at text ×2 it falls between those two.
        await settleForGolden(tester, home, end: false);
        await tester.ensureVisible(byId('home-repeats'));
        await tester.pumpAndSettle();
        await expectGolden(
          tester,
          byId('home-repeats'),
          screen: 'home',
          state: 'repeats-card',
          stateId: 'RP7',
          brightness: c.brightness,
          width: c.width.toInt(),
          textScale: c.textScale.toInt(),
        );
      }
    });

    testWidgets('RP8 Timeline: a repeat\'s entries marked ($c)', (tester) async {
      await open(tester, c, seed: (app) => repeating(app));
      await tester.tapId('tab-timeline');
      await waitFor(tester, byId('tl-row-repeat-entry-1-2026-10-01'));
      final timeline = listOf('timeline-screen');
      await checkScrolled(tester, timeline, 'RP8');
      if (c.takesGolden) {
        await expectLayoutGoldens(tester, c, timeline, screen: 'timeline', state: 'repeat-mark', stateId: 'RP8');
      }
    });

    testWidgets('RP9 the edit sheet of an entry a repeat added ($c)', (tester) async {
      await open(tester, c, seed: (app) => repeating(app));
      await tester.tapId('tab-timeline');
      await waitFor(tester, byId('tl-row-repeat-entry-1-2026-10-01'));
      await tester.tapId('tl-row-repeat-entry-1-2026-10-01');
      await reveal(tester, sheetList(), 'edit-repeat');
      expect(byId('edit-repeat-manage'), findsOneWidget);
      await checkScrolled(tester, sheetList(), 'RP9');
      if (c.takesGolden) {
        await expectLayoutGoldens(tester, c, sheetList(), screen: 'edit-sheet', state: 'repeat', stateId: 'RP9');
      }
    });
  }
}
