import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import 'helpers.dart';

/// More goals with Plus (decision 79): one goal always works without Plus;
/// with Plus, New goal adds a card (oldest first), the Add sheet asks which
/// goal a save is for, a goal's own Add savings starts on it; after Plus
/// ends the goals stay and take saves but New goal asks for Plus; Me's
/// Reached goals, for everyone; and a pending payment holds every Start.
void main() {
  const owned = PlusProof(token: 't1', productId: plusPlayProductId);

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Goal goal(
    String id,
    String name, {
    int day = 1,
    GoalStatus status = GoalStatus.active,
    DateTime? reachedAt,
  }) => Goal(
    id: id,
    name: name,
    targetMinor: 10000000,
    createdAt: DateTime.utc(2026, 9, day),
    updatedAt: DateTime.utc(2026, 9, day),
    status: status,
    reachedAt: reachedAt,
  );

  /// The app with [goals]; [plusBuild] false is a build without Plus.
  Future<({TestApp app, FakePlusStore store})> open(
    WidgetTester tester, {
    bool plusBuild = true,
    bool plusOn = false,
    List<Goal> goals = const [],
    Future<void> Function(TestApp app)? seed,
    String location = '/home',
    PlusBuyOutcome? next,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final store = FakePlusStore()
      ..owns = plusOn ? const [owned] : const []
      ..nextOutcome = next;
    final app = TestApp(
      config: AppConfig(flavor: Flavor.staging, plusEnabled: plusBuild),
      plus: plusBuild
          ? PlusEntitlement(store: store, hint: MemoryPlusHint(), clock: testClock)
          : null,
    );
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      for (final g in goals) {
        await app.journal.putGoal(g, allowAnother: true);
        if (g.status == GoalStatus.reached) await app.journal.markCelebrated(g.id);
      }
      if (seed != null) await seed(app);
    });
    await app.pump(tester, location: location);
    await settle(
      tester,
      byId(switch (location) {
        '/home' => 'home-screen',
        '/plus' => 'plus-restore',
        _ => 'me-happy',
      }),
    );
    return (app: app, store: store);
  }

  Future<List<Entry>> saves(WidgetTester tester, TestApp app) async => [
    for (final e in (await tester.runAsync(app.journal.entries))!)
      if (e.type == EntryType.saved) e,
  ];

  /// Home's + → Saved → [amount] → Add, choosing [goalChip] first if given.
  Future<void> addSave(WidgetTester tester, String amount, {String? goalChip}) async {
    await tester.tapId('home-add');
    await tester.tapId('add-seg-saved');
    await tester.enterId('add-amount', amount);
    if (goalChip != null) await tester.tapId(goalChip);
    await tester.tapId('add-submit');
  }

  // The release gate (the Reviewer's): one goal always works without Plus.
  testWidgets('a build without Plus: one goal, its card, and saves go to it', (tester) async {
    final o = await open(tester, plusBuild: false, goals: [goal('g1', 'Bike')]);
    expect(byId('goal-card'), findsOneWidget);
    expect(byId('goal-card-2'), findsNothing);
    expect(byId('home-new-goal'), findsNothing);
    await tester.tapId('home-add');
    await tester.tapId('add-seg-saved');
    expect(find.text('Goes to Bike'), findsOneWidget);
    expect(byId('add-goal-1'), findsNothing);
    await tester.enterId('add-amount', '25');
    await tester.tapId('add-submit');
    expect((await saves(tester, o.app)).single.goalId, 'g1');
  });

  testWidgets('without Plus on: the one goal works, and New goal opens the paywall', (tester) async {
    final o = await open(tester, goals: [goal('g1', 'Bike')]);
    await addSave(tester, '25');
    expect((await saves(tester, o.app)).single.goalId, 'g1');
    await tester.tapId('home-new-goal');
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(byId('goal-edit-screen'), findsNothing);
    expect(byId('goal-card-2'), findsNothing);
  });

  testWidgets('with Plus: New goal makes a second goal; its card comes after the first', (tester) async {
    final o = await open(tester, plusOn: true, goals: [goal('g1', 'Bike')]);
    await tester.tapId('home-new-goal');
    tester.expectScreen('goal-edit-screen');
    await tester.enterId('goal-name', 'Trip');
    await tester.enterId('goal-amount', '900');
    await tester.tapId('goal-submit');
    await settle(tester, byId('goal-card-2'));
    final active = (await tester.runAsync(o.app.journal.activeGoals))!;
    expect(active.map((g) => g.name), ['Bike', 'Trip']);
    expect(
      find.descendant(of: byId('goal-card'), matching: find.text('Bike')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: byId('goal-card-2'), matching: find.text('Trip')),
      findsOneWidget,
    );
  });

  testWidgets('two goals: the sheet asks which, starting on the goal last saved to', (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      goals: [goal('g1', 'Bike'), goal('g2', 'Trip', day: 5)],
      seed: (app) => app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 100,
        currency: 'THB',
        localDate: '2026-10-01',
        goalId: 'g2',
      ),
    );
    await tester.tapId('home-add');
    await tester.tapId('add-seg-saved');
    expect(find.text('Save toward'), findsOneWidget);
    expect(find.textContaining('Goes to'), findsNothing);
    expect(byId('add-goal-1'), findsOneWidget);
    expect(byId('add-goal-2'), findsOneWidget);
    await tester.enterId('add-amount', '30');
    await tester.tapId('add-submit');
    expect((await saves(tester, o.app)).map((e) => e.goalId).toList(), ['g2', 'g2']);
    // Another goal chosen: the save goes there.
    await addSave(tester, '40', goalChip: 'add-goal-1');
    final all = await saves(tester, o.app);
    expect(all.where((e) => e.goalId == 'g1').single.amountMinor, 4000);
  });

  testWidgets("a goal's own Add savings starts the sheet on that goal", (tester) async {
    final o = await open(
      tester,
      plusOn: true,
      goals: [goal('g1', 'Bike'), goal('g2', 'Trip', day: 5)],
    );
    await tester.tapId('goal-card-2');
    tester.expectScreen('goal-screen');
    await tester.tapId('goal-add-savings');
    await tester.enterId('add-amount', '15');
    await tester.tapId('add-submit');
    expect((await saves(tester, o.app)).single.goalId, 'g2');
  });

  testWidgets('after Plus ends: both goals stay and take saves; New goal asks for Plus', (tester) async {
    final o = await open(tester, goals: [goal('g1', 'Bike'), goal('g2', 'Trip', day: 5)]);
    expect(byId('goal-card'), findsOneWidget);
    expect(byId('goal-card-2'), findsOneWidget);
    await addSave(tester, '20', goalChip: 'add-goal-2');
    expect((await saves(tester, o.app)).single.goalId, 'g2');
    await tester.tapId('home-new-goal');
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
  });

  testWidgets('Reached goals in Me: none, no row', (tester) async {
    await open(tester, plusBuild: false, location: '/me');
    expect(byId('me-reached'), findsNothing);
  });

  testWidgets('Reached goals in Me, for everyone: the count, the latest first, each read-only', (
    tester,
  ) async {
    await open(
      tester,
      plusBuild: false,
      location: '/me',
      goals: [
        goal('g1', 'Bike', status: GoalStatus.reached, reachedAt: DateTime.utc(2026, 9, 3, 12)),
        goal('g2', 'Trip', day: 2, status: GoalStatus.reached, reachedAt: DateTime.utc(2026, 9, 20, 12)),
        goal('g3', 'Sofa', day: 3),
      ],
    );
    expect(find.text('2 goals reached'), findsOneWidget);
    await tester.tapId('me-reached');
    tester.expectScreen('reached-goals-screen');
    expect(
      find.descendant(of: byId('reached-goal-1'), matching: find.text('Trip')),
      findsOneWidget,
    );
    expect(find.text('Reached Sun, Sep 20'), findsOneWidget);
    expect(find.text('Reached Thu, Sep 3'), findsOneWidget);
    expect(byId('reached-goal-3'), findsNothing, reason: 'an active goal is not reached');
    await tester.tapId('reached-goal-1');
    tester.expectScreen('goal-screen');
    expect(byId('goal-add-savings'), findsNothing, reason: 'read-only');
    expect(byId('goal-menu'), findsNothing);
  });

  testWidgets('a pending payment holds every Start; Restore and the links stay; '
      "Restore's answer ends the wait", (tester) async {
    await open(
      tester,
      location: '/plus',
      next: const PlusPending(),
      goals: [goal('g1', 'Bike')],
    );
    FilledButton start(String id) => tester.widget<FilledButton>(
      find.descendant(of: byId(id), matching: find.byType(FilledButton)),
    );
    await tester.tapId('plus-plan-yearly-start');
    expect(byId('plus-note'), findsOneWidget);
    expect(start('plus-plan-yearly-start').onPressed, isNull);
    final restore = tester.widget<TextButton>(
      find.descendant(of: byId('plus-restore'), matching: find.byType(TextButton)),
    );
    expect(restore.onPressed, isNotNull);
    await tester.tapId('plus-restore');
    expect(find.text('No Plus subscription was found for this store account.'), findsOneWidget);
    expect(start('plus-plan-yearly-start').onPressed, isNotNull);
  });
}
