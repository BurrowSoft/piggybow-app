import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:piggybow/features/currency/currency_picker.dart';
import 'package:piggybow/features/onboarding/onboarding_screens.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;
import 'package:piggybow/router.dart';
import 'package:piggybow/session/app_session.dart' show Routes;

import 'helpers.dart';

/// Onboarding (plan §3.1): on the first open only, O1 Welcome → O2 "What
/// makes your pig happy?" → O3 the optional first goal → Home. The picks
/// and the plan are saved; Continue says what's missing; both O3 buttons
/// end onboarding; nothing asks for notifications; it never shows again.
void main() {
  Future<TestApp> openFresh(
    WidgetTester tester, {
    Future<void> Function(TestApp)? seed,
    String? location,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp(onboarded: false);
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> toHappy(WidgetTester tester) async {
    await tester.tapId('onb-start');
    await tester.pumpAndSettle();
    tester.expectScreen('onb-happy');
  }

  Future<void> toGoal(WidgetTester tester) async {
    await toHappy(tester);
    await tester.tapId('onb-pick-save');
    await tester.tapId('onb-continue');
    await tester.pumpAndSettle();
    tester.expectScreen('onb-goal');
  }

  test('the gate: onboarding until it is done, and never after', () {
    expect(onboardingGate(Routes.home, done: false), OnboardingRoutes.welcome);
    expect(onboardingGate('/timeline', done: false), OnboardingRoutes.welcome);
    expect(
      onboardingGate(OnboardingRoutes.happy, done: false),
      OnboardingRoutes.happy,
    );
    expect(onboardingGate(OnboardingRoutes.welcome, done: true), Routes.home);
    expect(onboardingGate(OnboardingRoutes.goal, done: true), Routes.home);
    expect(onboardingGate('/timeline', done: true), '/timeline');
  });

  testWidgets('a first open starts on O1, wherever it was opened', (
    tester,
  ) async {
    await openFresh(tester, location: '/timeline');
    tester.expectScreen('onb-welcome');
    expect(find.text('Meet your money pig'), findsOneWidget);
    expect(
      find.text('No bank login and no account. Your entries stay with you.'),
      findsOneWidget,
    );
    expect(
      find.text('Amounts in Thai baht (${currencySymbolOf('THB', 'en_US')})'),
      findsOneWidget,
    );
  });

  testWidgets('O2: Continue says what is missing, then saves the picks and '
      'the plan', (tester) async {
    final app = await openFresh(tester);
    await toHappy(tester);
    expect(byId('onb-plan'), findsNothing, reason: 'none picked first');
    await tester.tapId('onb-continue');
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one.'), findsOneWidget);

    await tester.tapId('onb-pick-plan');
    expect(byId('onb-plan'), findsOneWidget, reason: 'the plan shows its field');
    await tester.tapId('onb-continue');
    await tester.pumpAndSettle();
    expect(find.text('Enter your weekly plan.'), findsOneWidget);

    await tester.enterId('onb-plan', '1500');
    await tester.tapId('onb-pick-worth');
    await tester.tapId('onb-continue');
    await tester.pumpAndSettle();
    tester.expectScreen('onb-goal');
    expect(await tester.runAsync(app.journal.picks), {
      HappyPick.plan,
      HappyPick.worth,
    });
    expect(await tester.runAsync(app.journal.planMinor), 150000);
  });

  testWidgets('O2: a plan over 12 digits is too large', (tester) async {
    await openFresh(tester);
    await toHappy(tester);
    await tester.tapId('onb-pick-plan');
    await tester.enterId('onb-plan', '1234567890123');
    await tester.tapId('onb-continue');
    await tester.pumpAndSettle();
    expect(find.text('That amount is too large.'), findsOneWidget);
    tester.expectScreen('onb-happy');
  });

  testWidgets('O3 "Maybe later": Home, no goal, and onboarding never again', (
    tester,
  ) async {
    final app = await openFresh(tester);
    await toGoal(tester);
    expect(find.text('Saving for something?'), findsOneWidget);
    await tester.tapId('onb-goal-later');
    await tester.pumpAndSettle();
    tester.expectScreen('home-screen');
    expect(await tester.runAsync(app.journal.onboarded), isTrue);
    expect(await tester.runAsync(app.journal.goals), isEmpty);

    GoRouter.of(
      tester.element(byId('home-screen')),
    ).go(OnboardingRoutes.welcome);
    await tester.pumpAndSettle();
    tester.expectScreen('home-screen');
  });

  testWidgets('O3 "Start my rainbow": the goal, then Home', (tester) async {
    final app = await openFresh(tester);
    await toGoal(tester);
    await tester.tapId('onb-goal-start');
    await tester.pumpAndSettle();
    expect(find.text('Give your goal a name.'), findsOneWidget);
    tester.expectScreen('onb-goal');
    expect(await tester.runAsync(app.journal.onboarded), isFalse);

    await tester.enterId('goal-name', 'Bike');
    await tester.enterId('goal-amount', '1000');
    await tester.tapId('onb-goal-start');
    await tester.pumpAndSettle();
    tester.expectScreen('home-screen');
    final goal = (await tester.runAsync(app.journal.activeGoal))!;
    expect((goal.name, goal.targetMinor), ('Bike', 100000));
    expect(await tester.runAsync(app.journal.onboarded), isTrue);
  });

  testWidgets('nothing in onboarding asks for notifications', (tester) async {
    final app = await openFresh(tester);
    await toGoal(tester);
    await tester.tapId('onb-goal-later');
    await tester.pumpAndSettle();
    expect(app.notifications.requests, 0);
  });

  testWidgets("O1 Change: the phone's currency first, and a pick changes the "
      'line', (tester) async {
    final app = await openFresh(tester);
    await tester.tapId('onb-currency-change');
    await tester.pumpAndSettle();
    tester.expectScreen('currency-screen');
    final first = find
        .descendant(of: byId('currency-screen'), matching: find.byType(ListTile))
        .first;
    expect(
      find.descendant(of: first, matching: find.textContaining('US dollar')),
      findsOneWidget,
      reason: "en_US's own currency on top",
    );
    await tester.tapId('currency-JPY');
    await tester.pumpAndSettle();
    tester.expectScreen('onb-welcome');
    expect(await tester.runAsync(app.journal.currency), 'JPY');
    expect(
      find.text(
        'Amounts in Japanese yen (${currencySymbolOf('JPY', 'en_US')})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('once anything is stored the currency is set, and says so', (
    tester,
  ) async {
    final app = await openFresh(
      tester,
      seed: (app) => app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 100,
        currency: 'THB',
        localDate: '2026-10-02',
        category: SpendCategory.food,
      ),
    );
    await tester.tapId('onb-currency-change');
    await tester.pumpAndSettle();
    expect(find.text('Currency is set'), findsOneWidget);
    await tester.tapId('currency-fixed-ok');
    await tester.pumpAndSettle();
    expect(byId('currency-screen'), findsNothing);
    expect(await tester.runAsync(app.journal.currency), 'THB');
  });

  test('onboarding shows only over a blank journal', () async {
    Future<JournalStore> open() async {
      final store = await JournalStore.inMemory(clock: testClock);
      addTearDown(store.close);
      return store;
    }

    final blank = await open();
    await blank.setCurrency('THB');
    expect(await onboardedAtStart(blank), isFalse, reason: 'a first open');

    final done = await open();
    await done.setOnboarded();
    expect(await onboardedAtStart(done), isTrue);

    // A phone from before onboarding: its notes stay as they are.
    final upgraded = await open();
    await upgraded.addEntry(
      type: EntryType.spent,
      amountMinor: 100,
      currency: 'THB',
      localDate: '2026-10-02',
      category: SpendCategory.food,
    );
    expect(await onboardedAtStart(upgraded), isTrue);
    expect(await upgraded.onboarded(), isTrue, reason: 'and from then on');

    // Stopped in O3, after O2 saved the picks.
    final picked = await open();
    await picked.setPicks({HappyPick.save});
    expect(await onboardedAtStart(picked), isTrue);
  });
}
