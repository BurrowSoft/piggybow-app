// Goldens: SW1, SW9, SW0 and SM1 at 360 dp ×1 (light, dark) and 320 dp ×2
// (light), decision 44.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/no_error_colour.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Summary in every layout case (plan §0.3, decision 43; PB Mobile Tester's
/// PR 4 list): fixture S1's week (every card), all nine categories at the
/// largest amount, an empty week; S1's December, an empty month; the week
/// label that crosses a year. Every amount on one line, in allowed colours.
void main() {
  setUpAll(loadAppFonts);
  String usd(int minor) => formatMoney(minor, 'USD', 'en_US');
  final s1Now = DateTime.parse('2026-12-02T05:00:00Z');

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    DateTime? now,
    Future<void> Function(TestApp)? seed,
  }) async {
    setLayout(tester, c);
    final app = TestApp(
      currency: 'USD',
      clock: Clock(fixed: now ?? s1Now),
    )..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-summary');
    await settle(tester, byId('sum-period-label'));
  }

  Future<void> spend(
    TestApp app,
    int minor,
    SpendCategory category,
    Feeling? feeling,
    String day,
  ) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: minor,
    currency: 'USD',
    localDate: day,
    category: category,
    feeling: feeling,
  );

  Future<void> s1(TestApp app) async {
    await app.journal.setPicks({HappyPick.save, HappyPick.plan});
    await app.journal.setPlanMinor(15000);
    await spend(app, 10000, SpendCategory.home, null, '2026-11-30');
    await spend(app, 1250, SpendCategory.food, Feeling.worthIt, '2026-12-01');
    await spend(
      app,
      320,
      SpendCategory.transport,
      Feeling.notSure,
      '2026-12-02',
    );
    await app.journal.addEntry(
      type: EntryType.saved,
      amountMinor: 5000,
      currency: 'USD',
      localDate: '2026-12-01',
    );
    await spend(app, 4500, SpendCategory.fun, Feeling.notReally, '2026-11-24');
  }

  /// Every category this week at the largest amount, each with a feeling,
  /// and a plan far below them (the bar simply full).
  Future<void> nineAtMax(TestApp app) async {
    await app.journal.setPicks({HappyPick.plan});
    await app.journal.setPlanMinor(100);
    for (final (i, c) in SpendCategory.values.indexed) {
      await spend(app, amountMax, c, Feeling.values[i % 3], '2026-12-01');
    }
  }

  /// Every amount on screen on one line and in an allowed colour, and the
  /// layout sound, at each scroll position from the top to the end.
  Future<void> checkScrolled(
    WidgetTester tester,
    String state,
    List<String> amounts,
  ) async {
    final list = find
        .descendant(
          of: byId('summary-screen'),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final at = '$state at ${position.pixels.round()}';
      await expectSoundLayout(tester, reason: at);
      final shown = [
        for (final a in amounts)
          if (find.textContaining(a).evaluate().isNotEmpty) a,
      ];
      for (final a in shown) {
        if (find.text(a).evaluate().isNotEmpty) {
          expectOneLine(tester, a, reason: at);
        }
      }
      if (shown.isNotEmpty) {
        expectOnlyAllowedColours(
          tester,
          shown,
          extra: (t) => {t.colorScheme.primary},
          reason: at,
        );
      }
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
  }

  /// The cases Summary's goldens are taken in (PB UX & PM's look): 360 dp at
  /// text ×1, light and dark, and 320 dp at ×2, light.
  bool summaryGolden(LayoutCase c) =>
      (c.width == 360 && c.textScale == 1) ||
      (c.width == 320 && c.textScale == 2 && c.brightness == Brightness.light);

  /// The whole Summary as a golden (decision 44), named by PB Mobile
  /// Tester's ids: top, and its end if it scrolls.
  Future<void> golden(
    WidgetTester tester,
    LayoutCase c,
    String state,
    String stateId,
  ) async {
    if (!summaryGolden(c)) return;
    await expectLayoutGoldens(
      tester,
      c,
      find
          .descendant(
            of: byId('summary-screen'),
            matching: find.byType(Scrollable),
          )
          .first,
      screen: 'summary',
      state: state,
      stateId: stateId,
    );
  }

  for (final c in layoutCases) {
    testWidgets('S1 this week: every card ($c)', (tester) async {
      await open(tester, c, seed: s1);
      expect(byId('sum-plan-bar'), findsOneWidget);
      await checkScrolled(tester, 'S1 week', [
        usd(11570),
        usd(5000),
        usd(15000),
        usd(10000),
        usd(1250),
        usd(320),
      ]);
      await golden(tester, c, 's1-week', 'SW1');
    });

    testWidgets('nine categories at the largest amount ($c)', (tester) async {
      await open(tester, c, seed: nineAtMax);
      await checkScrolled(tester, 'nine at max', [
        usd(amountMax * SpendCategory.values.length),
        usd(amountMax),
        usd(100),
      ]);
      expect(
        find.textContaining(longestCategory),
        findsWidgets,
        reason: 'the longest label, whole',
      );
      await golden(tester, c, 'nine-at-max', 'SW9');
    });

    testWidgets('an empty week ($c)', (tester) async {
      await open(tester, c);
      expect(find.text('Nothing noted for this week.'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'empty week');
      await golden(tester, c, 'empty-week', 'SW0');
    });

    testWidgets('S1 December ($c)', (tester) async {
      await open(tester, c, seed: s1);
      await tester.tapId('sum-month');
      expect(find.text('December 2026'), findsOneWidget);
      await checkScrolled(tester, 'S1 December', [
        usd(1570),
        usd(5000),
        usd(1250),
        usd(320),
      ]);
      await golden(tester, c, 's1-december', 'SM1');
    });

    testWidgets('an empty month ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('sum-month');
      expect(find.text('Nothing noted for this month.'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'empty month');
    });

    testWidgets('the week that crosses a year: its label, whole ($c)', (
      tester,
    ) async {
      // Wednesday 6 January 2027; a spend in the week before.
      await open(
        tester,
        c,
        now: DateTime.parse('2027-01-06T05:00:00Z'),
        seed: (app) => spend(app, 4500, SpendCategory.food, null, '2026-12-29'),
      );
      expect(find.text('Jan 4 – Jan 10'), findsOneWidget);
      await tester.tapId('sum-prev');
      expect(find.text('Dec 28, 2026 – Jan 3, 2027'), findsOneWidget);
      await checkScrolled(tester, 'year-crossing week', [usd(4500)]);
    });
  }
}
