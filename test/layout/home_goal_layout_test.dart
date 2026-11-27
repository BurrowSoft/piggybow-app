import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/pig/pig_mood.dart' show PigReaction;
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/no_error_colour.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Home and the goal screens in every layout case (plan §0.3, decision 43):
/// Home on the first day and full (a plan, the reminder offer, a goal with a
/// 40-character name and the largest target), Home after a goal was reached
/// (the longest bubble), the longest after-Add reaction, the plan bar over
/// the plan; the goal form with its errors and with the keyboard up, the
/// goal detail, a reached goal's read-only detail, the End goal dialog, and
/// the celebration.
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
    await settle(tester, byId('home-pig-line'));
    return app;
  }

  /// The checks on the whole of [list]'s screen, scrolled top to bottom;
  /// the colour check on each of [amounts] wherever it's on screen.
  Future<void> checkScrolled(
    WidgetTester tester,
    Finder list,
    String state, {
    List<String> amounts = const [],
  }) async {
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      final at = '$state at ${position.pixels.round()}';
      await expectSoundLayout(tester, reason: at);
      final shown = [
        for (final a in amounts)
          if (find.textContaining(a).evaluate().isNotEmpty) a,
      ];
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

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  Goal longGoal({int target = amountMax, int start = 0}) => Goal(
    id: 'g1',
    name: goal40,
    targetMinor: target,
    startMinor: start,
    createdAt: t,
    updatedAt: t,
  );

  Future<void> fullWeek(TestApp app) async {
    await app.journal.putGoal(longGoal(start: 250000));
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

  /// A goal reached today and already celebrated: Home shows "Reached: …"
  /// and the pig's longest line, "You reached …!".
  Future<void> reachedToday(TestApp app) async {
    await app.journal.putGoal(longGoal(target: 1000));
    await app.journal.markCelebrated('g1');
    await app.journal.addEntry(
      type: EntryType.saved,
      amountMinor: 1000,
      currency: 'USD',
      localDate: '2026-10-02',
    );
  }

  final fullAmounts = [usd(123456 + 4550), usd(99999 + 250000), usd(amountMax)];

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
        expect(byId('home-reminder-yes'), findsOneWidget);
        await checkScrolled(
          tester,
          listIn('home-screen'),
          'H2',
          amounts: fullAmounts,
        );
      },
    );

    testWidgets(
      'H4/H5 Home after a goal was reached: "Reached:" and the longest line ($c)',
      (tester) async {
        await open(tester, c, seed: reachedToday);
        expect(find.text('You reached $goal40!'), findsOneWidget);
        await checkScrolled(tester, listIn('home-screen'), 'H4');
        expect(find.text('Reached: $goal40'), findsOneWidget);
      },
    );

    testWidgets('H6 the longest after-Add reaction ($c)', (tester) async {
      final app = await open(tester, c);
      app.services.lastAdd.value = PigReaction.notSure;
      await tester.pumpAndSettle();
      expect(
        find.text('Noted. You can change how it felt anytime.'),
        findsOneWidget,
      );
      await checkScrolled(tester, listIn('home-screen'), 'H6');
    });

    testWidgets('H7 the plan bar at 150 %: simply full ($c)', (tester) async {
      await open(
        tester,
        c,
        seed: (app) async {
          await app.journal.setPlanMinor(1000);
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: 1500,
            currency: 'USD',
            localDate: '2026-10-01',
            category: SpendCategory.food,
          );
        },
      );
      await checkScrolled(tester, listIn('home-screen'), 'H7');
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
      expect(
        bar.color,
        Theme.of(tester.element(find.byType(LinearProgressIndicator)))
            .colorScheme
            .primary,
      );
    });

    testWidgets('G1 the goal form with its errors ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('goal-create');
      await settle(tester, byId('goal-submit'));
      await tester.tapId('goal-submit');
      expect(find.text('Give your goal a name.'), findsOneWidget);
      await checkScrolled(tester, listIn('goal-edit-screen'), 'G1');
    });

    testWidgets(
      'G1b the goal form with the keyboard up: the field and the button in reach ($c)',
      (tester) async {
        await open(tester, c);
        await tester.tapId('goal-create');
        await settle(tester, byId('goal-submit'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
        await tester.pumpAndSettle();
        await checkScrolled(tester, listIn('goal-edit-screen'), 'G1b');
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        await tester.ensureVisible(byId('goal-submit'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(byId('goal-submit')).bottom,
          lessThanOrEqualTo(screen.height - 300 + 0.5),
        );
      },
    );

    testWidgets('G2 the goal detail with its saves ($c)', (tester) async {
      await open(tester, c, seed: fullWeek);
      await tester.tapId('goal-card');
      await settle(tester, byId('goal-add-savings'));
      await checkScrolled(
        tester,
        listIn('goal-screen'),
        'G2',
        amounts: [usd(amountMax)],
      );
    });

    testWidgets("G4 a reached goal's detail is read-only ($c)", (tester) async {
      await open(tester, c, seed: reachedToday);
      // A reached goal has no card of its own (Home shows "Reached: …"):
      // its detail, by its route.
      unawaited(
        GoRouter.of(tester.element(byId('home-screen')))
            .push(GoalRoutes.detail('g1')),
      );
      await settle(tester, byId('goal-screen'));
      expect(byId('goal-menu'), findsNothing, reason: 'no Edit or End');
      expect(byId('goal-add-savings'), findsNothing);
      await checkScrolled(tester, listIn('goal-screen'), 'G4');
    });

    testWidgets('G5 the End goal dialog ($c)', (tester) async {
      await open(tester, c, seed: fullWeek);
      await tester.tapId('goal-card');
      await settle(tester, byId('goal-menu'));
      await tester.tapId('goal-menu');
      await tester.tapId('goal-end');
      expect(find.text('End this goal?'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'G5');
    });

    testWidgets('G3 the celebration ($c)', (tester) async {
      await open(
        tester,
        c,
        seed: (app) async {
          await app.journal.putGoal(longGoal());
          await app.journal.addEntry(
            type: EntryType.saved,
            amountMinor: amountMax,
            currency: 'USD',
            localDate: '2026-10-01',
          );
        },
      );
      await settle(tester, byId('goal-done-screen'));
      await checkScrolled(
        tester,
        listIn('goal-done-screen'),
        'G3',
        amounts: [usd(amountMax)],
      );
    });
  }
}
