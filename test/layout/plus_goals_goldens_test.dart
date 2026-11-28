// Goldens: more goals with Plus (decision 44), at 320 dp ×2, light and
// dark, for PB UX & PM's look: Home with two goals and New goal, the Add
// sheet's Save toward, Me with Reached goals, and the Reached goals list.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  const owned = PlusProof(token: 't1', productId: plusPlayProductId);

  Goal goal(
    String id,
    String name, {
    int day = 1,
    int target = 1500000,
    GoalStatus status = GoalStatus.active,
    DateTime? reachedAt,
  }) => Goal(
    id: id,
    name: name,
    targetMinor: target,
    createdAt: DateTime.utc(2026, 9, day),
    updatedAt: DateTime.utc(2026, 9, day),
    status: status,
    reachedAt: reachedAt,
  );

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  Finder sheetList() => find
      .descendant(of: find.byType(EntrySheet), matching: find.byType(Scrollable))
      .first;

  /// Two goals with saves (a bike, a trip), or two reached ones.
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    String location = '/home',
    bool reached = false,
  }) async {
    setLayout(tester, c);
    final app = TestApp(
      currency: 'USD',
      config: const AppConfig(flavor: Flavor.staging, plusEnabled: true),
      plus: PlusEntitlement(
        store: FakePlusStore()..owns = const [owned],
        hint: MemoryPlusHint(),
        clock: testClock,
      ),
    )..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      if (reached) {
        for (final g in [
          goal('r1', 'Bike', status: GoalStatus.reached, reachedAt: DateTime.utc(2026, 9, 20, 12)),
          goal('r2', 'Concert tickets', day: 2, status: GoalStatus.reached, reachedAt: DateTime.utc(2026, 8, 14, 12)),
        ]) {
          await app.journal.putGoal(g, allowAnother: true);
          await app.journal.markCelebrated(g.id);
        }
        return;
      }
      await app.journal.putGoal(goal('g1', 'Bike'), allowAnother: true);
      await app.journal.putGoal(goal('g2', 'Trip to Japan', day: 5, target: 9000000), allowAnother: true);
      for (final (id, minor) in [('g1', 600000), ('g2', 1200000)]) {
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: minor,
          currency: 'USD',
          localDate: '2026-10-01',
          goalId: id,
        );
      }
    });
    await app.pump(tester, location: location);
    await settle(tester, byId(location == '/home' ? 'goal-card-2' : 'me-happy'));
  }

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('PG1 Home: two goals and New goal ($c)', (tester) async {
      await open(tester, c);
      await expectLayoutGoldens(
        tester,
        c,
        listIn('home-screen'),
        screen: 'home',
        state: 'two-goals',
        stateId: 'PG1',
      );
    });

    testWidgets('PG2 the Add sheet: Save toward ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('home-add');
      await tester.tapId('add-seg-saved');
      await tester.scrollUntilVisible(byId('add-goal-2'), 120, scrollable: sheetList());
      await tester.pumpAndSettle();
      await expectLayoutGolden(
        tester,
        c,
        screen: 'add',
        state: 'save-toward',
        stateId: 'PG2',
      );
    });

    testWidgets("PG3 Me's Reached goals row ($c)", (tester) async {
      await open(tester, c, location: '/me', reached: true);
      await tester.ensureVisible(byId('me-reached'));
      await tester.pumpAndSettle();
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'reached-row',
        stateId: 'PG3',
      );
    });

    testWidgets('PG4 the Reached goals list ($c)', (tester) async {
      await open(tester, c, location: '/me', reached: true);
      await tester.tapId('me-reached');
      await settle(tester, byId('reached-goal-2'));
      await expectLayoutGoldens(
        tester,
        c,
        listIn('reached-goals-screen'),
        screen: 'reached',
        state: 'list',
        stateId: 'PG4',
      );
    });
  }
}
