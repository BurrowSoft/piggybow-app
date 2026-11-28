@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Feature 20, Patterns: Summary's card with Plus (PC1) and its teaser
/// without (PC2), each in the middle of the screen; the Patterns screen with
/// three patterns (PS1) and before there's enough (PS2). Goldens at 360 dp ×1
/// and 320 dp ×2, light and dark; PS1's layout in every case of the matrix.
void main() {
  setUpAll(loadAppFonts);

  Future<void> spend(
    TestApp app,
    Feeling feeling, {
    SpendCategory category = SpendCategory.food,
    String day = '2026-10-01',
  }) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: 500,
    currency: 'USD',
    localDate: day,
    category: category,
    feeling: feeling,
  );

  /// Food, Saturdays and Fun stand out (as in test/patterns_ui_test.dart).
  Future<void> rich(TestApp app) async {
    for (var i = 0; i < 10; i++) {
      await spend(
        app,
        Feeling.notSure,
        category: SpendCategory.other,
        day: '2026-09-30',
      );
    }
    for (var i = 0; i < 5; i++) {
      await spend(app, Feeling.worthIt);
    }
    for (var i = 0; i < 4; i++) {
      await spend(app, Feeling.worthIt, category: SpendCategory.fun);
    }
    await spend(app, Feeling.notSure, category: SpendCategory.fun);
    for (final day in [
      '2026-09-26',
      '2026-09-19',
      '2026-09-12',
      '2026-09-05',
      '2026-08-29',
    ]) {
      await spend(
        app,
        Feeling.worthIt,
        category: SpendCategory.other,
        day: day,
      );
    }
  }

  Future<void> few(TestApp app) async {
    for (var i = 0; i < 5; i++) {
      await spend(app, Feeling.worthIt);
    }
  }

  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    required Future<void> Function(TestApp) seed,
    required bool plusOn,
    String? location,
    required Finder until,
  }) async {
    setLayout(tester, c);
    final store = FakePlusStore();
    if (plusOn) {
      store.owns = const [PlusProof(token: 't1', productId: plusPlayProductId)];
    }
    final plus = PlusEntitlement(
      store: store,
      hint: MemoryPlusHint(),
      clock: testClock,
    );
    final app = TestApp(
      currency: 'USD',
      config: const AppConfig(flavor: Flavor.staging, plusEnabled: true),
      plus: plus,
    )..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() => seed(app));
    await tester.runAsync(plus.refresh);
    await app.pump(tester, location: location);
    if (location == null) await tester.tapId('tab-summary');
    for (var i = 0; i < 40 && until.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Brings Summary's card [id] to the middle of the screen.
  Future<void> centre(WidgetTester tester, String id) async {
    final list = find
        .descendant(
          of: byId('summary-screen'),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(byId(id), 200, scrollable: list);
    await Scrollable.ensureVisible(tester.element(byId(id)), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  final goldenCases = [
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0)])
      for (final brightness in Brightness.values)
        LayoutCase(width, scale, brightness),
  ];

  for (final c in goldenCases) {
    testWidgets('PC1 Summary: the Patterns card with Plus ($c)', (
      tester,
    ) async {
      await open(
        tester,
        c,
        seed: rich,
        plusOn: true,
        until: byId('sum-period-label'),
      );
      await centre(tester, 'sum-patterns');
      await expectSoundLayout(tester, reason: 'PC1');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'summary',
        state: 'patterns',
        stateId: 'PC1',
      );
    });

    testWidgets('PC2 Summary: the Patterns teaser without Plus ($c)', (
      tester,
    ) async {
      await open(
        tester,
        c,
        seed: rich,
        plusOn: false,
        until: byId('sum-period-label'),
      );
      await centre(tester, 'sum-patterns-teaser');
      await expectSoundLayout(tester, reason: 'PC2');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'summary',
        state: 'patterns-teaser',
        stateId: 'PC2',
      );
    });

    testWidgets('PS1 Patterns: three patterns ($c)', (tester) async {
      await open(
        tester,
        c,
        seed: rich,
        plusOn: true,
        location: SummaryRoutes.patterns,
        until: byId('patterns-line-0'),
      );
      await expectSoundLayout(tester, reason: 'PS1');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'patterns',
        state: 'three',
        stateId: 'PS1',
      );
    });

    testWidgets('PS2 Patterns: not enough yet ($c)', (tester) async {
      await open(
        tester,
        c,
        seed: few,
        plusOn: true,
        location: SummaryRoutes.patterns,
        until: byId('patterns-not-yet'),
      );
      await expectSoundLayout(tester, reason: 'PS2');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'patterns',
        state: 'not-yet',
        stateId: 'PS2',
      );
    });
  }

  for (final c in layoutCases) {
    testWidgets('PS1 Patterns: sound in every layout case ($c)', (
      tester,
    ) async {
      await open(
        tester,
        c,
        seed: rich,
        plusOn: true,
        location: SummaryRoutes.patterns,
        until: byId('patterns-line-0'),
      );
      final list = find
          .descendant(
            of: byId('patterns-screen'),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(list).position;
      for (var i = 0; i < 10; i++) {
        await expectSoundLayout(tester, reason: 'PS1 at ${position.pixels}');
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo(
          (position.pixels + position.viewportDimension * 0.7).clamp(
            0.0,
            position.maxScrollExtent,
          ),
        );
        await tester.pump();
      }
    });
  }
}
