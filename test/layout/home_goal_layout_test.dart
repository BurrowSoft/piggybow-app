import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/no_error_colour.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Home and the goal screens in every layout case (plan §0.3, decision 43):
/// Home on the first day and full (a plan, the reminder offer, a goal with a
/// 40-character name and the largest target), the goal form with its
/// errors, the goal detail, and the celebration.
void main() {
  setUpAll(loadAppFonts);
  String usd(int minor) => formatMoney(minor, 'USD', 'en_US');
  final t = DateTime.utc(2026, 9, 20);

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> open(
    WidgetTester tester,
    LayoutCase c, {
    Future<void> Function(TestApp)? seed,
  }) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await settle(tester, byId('home-week'));
    return app;
  }

  /// The checks on the whole of [list]'s screen, scrolled top to bottom.
  Future<void> checkScrolled(
    WidgetTester tester,
    Finder list,
    String state,
  ) async {
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(
        tester,
        reason: '$state at ${position.pixels.round()}',
      );
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

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  Future<void> fullWeek(TestApp app) async {
    await app.journal.putGoal(
      Goal(
        id: 'g1',
        name: goal40,
        targetMinor: amountMax,
        startMinor: 250000,
        createdAt: t,
        updatedAt: t,
      ),
    );
    await app.journal.setPlanMinor(200000);
    await app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: 123456,
      currency: 'USD',
      localDate: '2026-09-29',
      category: SpendCategory.fun,
      feeling: Feeling.worthIt,
      note: note80,
    );
    await app.journal.addEntry(
      type: EntryType.spent,
      amountMinor: 4550,
      currency: 'USD',
      localDate: '2026-10-01',
      category: SpendCategory.food,
      feeling: Feeling.worthIt,
    );
    await app.journal.addEntry(
      type: EntryType.saved,
      amountMinor: 99999,
      currency: 'USD',
      localDate: '2026-10-02',
    );
  }

  for (final c in layoutCases) {
    testWidgets('H1 Home on the first day ($c)', (tester) async {
      await open(tester, c);
      expect(find.text('Start a savings goal'), findsOneWidget);
      await checkScrolled(tester, listIn('home-screen'), 'H1');
    });

    testWidgets(
      'H2 Home full: a plan, the offer, a long goal, large amounts ($c)',
      (tester) async {
        await open(tester, c, seed: fullWeek);
        await settle(tester, byId('goal-card'));
        expect(byId('home-reminder-yes'), findsOneWidget);
        expectOnlyAllowedColours(
          tester,
          [usd(123456 + 4550), usd(99999 + 250000)],
          extra: (t) => {t.colorScheme.primary},
          reason: 'H2 amounts',
        );
        await checkScrolled(tester, listIn('home-screen'), 'H2');
      },
    );

    testWidgets('G1 the goal form with its errors ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('goal-create');
      await settle(tester, byId('goal-submit'));
      await tester.tapId('goal-submit');
      expect(find.text('Give your goal a name.'), findsOneWidget);
      await checkScrolled(tester, listIn('goal-edit-screen'), 'G1');
    });

    testWidgets('G2 the goal detail with its saves ($c)', (tester) async {
      await open(tester, c, seed: fullWeek);
      await settle(tester, byId('goal-card'));
      await tester.tapId('goal-card');
      await settle(tester, byId('goal-add-savings'));
      await checkScrolled(tester, listIn('goal-screen'), 'G2');
    });

    testWidgets('G3 the celebration ($c)', (tester) async {
      await open(
        tester,
        c,
        seed: (app) async {
          await app.journal.putGoal(
            Goal(
              id: 'g1',
              name: goal40,
              targetMinor: amountMax,
              createdAt: t,
              updatedAt: t,
            ),
          );
          await app.journal.addEntry(
            type: EntryType.saved,
            amountMinor: amountMax,
            currency: 'USD',
            localDate: '2026-10-01',
          );
        },
      );
      await settle(tester, byId('goal-done-screen'));
      await checkScrolled(tester, listIn('goal-done-screen'), 'G3');
    });
  }
}
