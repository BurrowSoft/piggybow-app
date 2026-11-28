import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/goal.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// More goals in every layout case (plan §0.3, decision 43): Home with two
/// goals of the longest names and New goal, the Add sheet's Save toward
/// chips, Me's Reached goals row, and the Reached goals list.
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
  const other = 'Holiday by the sea with my two sisters';

  Goal goal(
    String id,
    String name, {
    int day = 1,
    GoalStatus status = GoalStatus.active,
    DateTime? reachedAt,
  }) => Goal(
    id: id,
    name: name,
    targetMinor: 999999999999,
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

  // The sheet's own list (Home scrolls behind it too).
  Finder sheetList() => find
      .descendant(of: find.byType(EntrySheet), matching: find.byType(Scrollable))
      .first;

  /// The checks on the whole of [screenId]'s list, scrolled top to bottom.
  Future<void> checkScrolled(
    WidgetTester tester,
    String screenId,
    String state,
  ) async {
    final list = find
        .descendant(of: byId(screenId), matching: find.byType(Scrollable))
        .first;
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
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }

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
      final goals = reached
          ? [
              goal('r1', goal40, status: GoalStatus.reached, reachedAt: DateTime.utc(2026, 9, 3, 12)),
              goal('r2', other, day: 2, status: GoalStatus.reached, reachedAt: DateTime.utc(2025, 12, 31, 12)),
            ]
          : [goal('g1', goal40), goal('g2', other, day: 5)];
      for (final g in goals) {
        await app.journal.putGoal(g, allowAnother: true);
        if (reached) await app.journal.markCelebrated(g.id);
      }
    });
    await app.pump(tester, location: location);
    await settle(tester, byId(location == '/home' ? 'goal-card-2' : 'me-happy'));
  }

  for (final c in layoutCases) {
    testWidgets('G1 Home: two goals of the longest names, and New goal ($c)', (tester) async {
      await open(tester, c);
      expect(byId('home-new-goal'), findsOneWidget);
      await checkScrolled(tester, 'home-screen', 'G1');
    });

    testWidgets('G2 the Add sheet: Save toward, both goals ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('home-add');
      await tester.tapId('add-seg-saved');
      await tester.scrollUntilVisible(byId('add-goal-2'), 120, scrollable: sheetList());
      await tester.pumpAndSettle();
      await expectSoundLayout(tester, reason: 'G2');
    });

    testWidgets("G3 Me's Reached goals row, then the list ($c)", (tester) async {
      await open(tester, c, location: '/me', reached: true);
      expect(byId('me-reached'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'G3 Me');
      await tester.tapId('me-reached');
      await settle(tester, byId('reached-goal-2'));
      await checkScrolled(tester, 'reached-goals-screen', 'G3');
    });
  }
}
