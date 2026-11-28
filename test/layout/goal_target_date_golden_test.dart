@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Feature 11, a goal's target date: the goal form with a date and its ×
/// (TD1); the goal with "About 12 weeks to go at this pace" (TD2) and with
/// "Target: Dec 31, 2026" (TD3), the line in the middle of the screen. 360 dp
/// at text ×1 and 320 dp at ×2, light and dark.
void main() {
  setUpAll(loadAppFonts);
  final t = DateTime.utc(2026, 9, 20);
  final bike = Goal(
    id: 'g1',
    name: 'Bike',
    targetMinor: 100000,
    startMinor: 10000,
    createdAt: t,
    updatedAt: t,
    targetDate: '2026-12-31',
  );

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    required String location,
    required Finder until,
    required String saveDay,
  }) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(bike);
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 22500,
        currency: 'USD',
        localDate: saveDay,
      );
    });
    await app.pump(tester, location: location);
    await settle(tester, until);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  /// Brings [target] to the middle of the goal screen's list.
  Future<void> centre(WidgetTester tester, Finder target) async {
    final list = find
        .descendant(of: byId('goal-screen'), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(target, 200, scrollable: list);
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  final cases = [
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0)])
      for (final brightness in Brightness.values)
        LayoutCase(width, scale, brightness),
  ];

  for (final c in cases) {
    testWidgets('TD1 the goal form with a target date ($c)', (tester) async {
      await open(
        tester,
        c,
        location: GoalRoutes.edit('g1'),
        until: byId('goal-submit'),
        saveDay: '2026-09-28',
      );
      expect(find.text('Dec 31, 2026'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'TD1');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'goal-edit',
        state: 'target-date',
        stateId: 'TD1',
      );
    });

    testWidgets('TD2 the goal with its pace ($c)', (tester) async {
      // 1,000 − (100 + 225) = 675 left at 225 in 4 weeks: 12 weeks.
      await open(
        tester,
        c,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        saveDay: '2026-09-28',
      );
      await centre(tester, byId('goal-outlook'));
      expect(find.text('About 12 weeks to go at this pace'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'TD2');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'goal-detail',
        state: 'pace',
        stateId: 'TD2',
      );
    });

    testWidgets('TD3 the goal with its target date ($c)', (tester) async {
      // The only save is over 4 weeks old: no pace, so the date shows.
      await open(
        tester,
        c,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        saveDay: '2026-09-01',
      );
      await centre(tester, byId('goal-outlook'));
      expect(find.text('Target: Dec 31, 2026'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'TD3');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'goal-detail',
        state: 'target',
        stateId: 'TD3',
      );
    });
  }
}
