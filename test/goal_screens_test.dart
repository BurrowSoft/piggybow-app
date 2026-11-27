import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/router.dart';

import 'helpers.dart';

/// The goal screens (plan §3.4): create with its errors, the detail with the
/// rainbow read out, what's left, Add savings, and End goal.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart).
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');
  final t = DateTime.utc(2026, 9, 20);

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> openHome(
    WidgetTester tester, {
    Future<void> Function(TestApp)? seed,
  }) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await settle(tester, byId('home-week'));
    return app;
  }

  testWidgets(
    'create: the errors first, then a goal with what was already saved',
    (tester) async {
      final app = await openHome(tester);
      await tester.tapId('goal-create');
      await settle(tester, byId('goal-submit'));
      await tester.tapId('goal-submit');
      expect(find.text('Give your goal a name.'), findsOneWidget);
      expect(find.text('Enter a goal amount.'), findsOneWidget);

      await tester.enterId('goal-name', 'Bike');
      await tester.enterId('goal-amount', '1000');
      await tester.enterId('goal-start', '100');
      await tester.tapId('goal-submit');
      await settle(tester, byId('goal-card'));
      final goal = (await tester.runAsync(app.journal.activeGoal))!;
      expect(
        (goal.name, goal.targetMinor, goal.startMinor),
        ('Bike', 100000, 10000),
      );
      expect(find.text('${money(10000)} of ${money(100000)}'), findsOneWidget);
    },
  );

  testWidgets(
    'detail: the rainbow read out, what is left, Add savings, then End goal',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await openHome(
        tester,
        seed: (app) async {
          await app.journal.putGoal(
            Goal(
              id: 'g1',
              name: 'Bike',
              targetMinor: 100000,
              createdAt: t,
              updatedAt: t,
            ),
          );
          await app.journal.addEntry(
            type: EntryType.saved,
            amountMinor: 25000,
            currency: 'THB',
            localDate: '2026-10-01',
          );
        },
      );
      await settle(tester, byId('goal-card'));
      await tester.tapId('goal-card');
      await settle(tester, byId('goal-add-savings'));
      expect(
        find.bySemanticsLabel(
          'Rainbow 25% filled: ${money(25000)} of ${money(100000)}',
        ),
        findsOneWidget,
      );
      expect(find.text('${money(75000)} to go'), findsOneWidget);

      await tester.tapId('goal-add-savings');
      expect(find.text('Goes to Bike'), findsOneWidget);
      await tester.enterId('add-amount', '100');
      await tester.tapId('add-submit');
      await settle(tester, find.text('${money(35000)} of ${money(100000)}'));
      expect(find.text('${money(35000)} of ${money(100000)}'), findsOneWidget);

      await tester.tapId('goal-menu');
      await tester.tapId('goal-end');
      expect(find.text('End this goal?'), findsOneWidget);
      await tester.tapId('goal-end-confirm');
      await settle(tester, find.text('Start a savings goal'));
      final goal = (await tester.runAsync(() => app.journal.goal('g1')))!;
      expect(goal.status, GoalStatus.ended);
      expect(find.text('Start a savings goal'), findsOneWidget);
      expect(
        find.textContaining('Reached:'),
        findsNothing,
        reason: 'ended, not reached',
      );
      semantics.dispose();
    },
  );

  testWidgets('a 13-digit target or "Already saved" is too large', (
    tester,
  ) async {
    await openHome(tester);
    await tester.tapId('goal-create');
    await settle(tester, byId('goal-submit'));
    await tester.enterId('goal-amount', '1234567890123');
    expect(find.text('That amount is too large.'), findsOneWidget);
    await tester.enterId('goal-amount', '100');
    await tester.enterId('goal-start', '1234567890123');
    expect(find.text('That amount is too large.'), findsOneWidget);
  });

  testWidgets(
    "a reached goal's detail is read-only; the next save goes to no goal",
    (tester) async {
      final app = await openHome(
        tester,
        seed: (app) async {
          await app.journal.putGoal(
            Goal(
              id: 'g1',
              name: 'Bike',
              targetMinor: 1000,
              createdAt: t,
              updatedAt: t,
            ),
          );
          await app.journal.markCelebrated('g1');
          await app.journal.addEntry(
            type: EntryType.saved,
            amountMinor: 1000,
            currency: 'THB',
            localDate: '2026-10-01',
          );
        },
      );
      // A reached goal has no card of its own: its detail, by its route.
      unawaited(
        GoRouter.of(tester.element(byId('home-screen')))
            .push(GoalRoutes.detail('g1')),
      );
      await settle(tester, byId('goal-screen'));
      expect(byId('goal-menu'), findsNothing, reason: 'no Edit or End');
      expect(byId('goal-add-savings'), findsNothing);
      expect(find.textContaining('to go'), findsNothing);
      final next = await tester.runAsync(
        () => app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 50,
          currency: 'THB',
          localDate: '2026-10-02',
        ),
      );
      expect(next!.goalId, isNull);
    },
  );

  testWidgets('the saves name their day as Timeline does, never the ISO date', (
    tester,
  ) async {
    await openHome(
      tester,
      seed: (app) async {
        await app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 100000,
            createdAt: t,
            updatedAt: t,
          ),
        );
        for (final day in [
          '2026-10-02',
          '2026-10-01',
          '2026-09-20',
          '2025-12-31',
        ]) {
          await app.journal.addEntry(
            type: EntryType.saved,
            amountMinor: 100,
            currency: 'THB',
            localDate: day,
          );
        }
      },
    );
    await tester.tapId('goal-card');
    await settle(tester, byId('goal-screen'));
    final list = find
        .descendant(of: byId('goal-screen'), matching: find.byType(Scrollable))
        .first;
    for (final day in [
      'Today',
      'Yesterday',
      'Sun, Sep 20',
      'Wed, Dec 31, 2025',
    ]) {
      await tester.scrollUntilVisible(find.text(day), 200, scrollable: list);
      expect(find.text(day), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'[0-9]{4}-[0-9]{2}-[0-9]{2}')),
        findsNothing,
      );
    }
  });

  testWidgets(
    'a save row: its title in ink, its day muted, its amount in the accent',
    (tester) async {
      await openHome(
        tester,
        seed: (app) async {
          await app.journal.putGoal(
            Goal(
              id: 'g1',
              name: 'Bike',
              targetMinor: 100000,
              createdAt: t,
              updatedAt: t,
            ),
          );
          await app.journal.addEntry(
            type: EntryType.saved,
            amountMinor: 2000,
            currency: 'THB',
            localDate: '2026-10-01',
            note: 'Birthday money',
          );
        },
      );
      await tester.tapId('goal-card');
      await settle(tester, byId('goal-screen'));
      final theme = Theme.of(tester.element(byId('goal-screen')));
      Color? colour(Finder f) => tester.widget<Text>(f).style?.color;
      expect(colour(find.text('Birthday money')), theme.colorScheme.onSurface);
      expect(
        colour(find.text('Yesterday')),
        theme.colorScheme.onSurfaceVariant,
      );
      expect(colour(find.text('+${money(2000)}')), theme.colorScheme.primary);
    },
  );

  testWidgets(
    '"Added" from the goal detail stays there: back on Home, no SnackBar',
    (tester) async {
      await openHome(
        tester,
        seed: (app) => app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 100000,
            createdAt: t,
            updatedAt: t,
          ),
        ),
      );
      await tester.tapId('goal-card');
      await settle(tester, byId('goal-add-savings'));
      await tester.tapId('goal-add-savings');
      await tester.enterId('add-amount', '10');
      await tester.tapId('add-submit');
      expect(find.text('Added'), findsOneWidget);
      GoRouter.of(tester.element(byId('goal-screen'))).pop();
      await tester.pumpAndSettle();
      expect(byId('home-screen'), findsOneWidget);
      expect(find.text('Added'), findsNothing, reason: "not over Home's +");
    },
  );
}
