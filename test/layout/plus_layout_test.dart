import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Piggybow Plus in every layout case (plan §0.3, decision 43): the paywall
/// at its fullest (both plans at long store prices, the free week, a note,
/// Terms and Privacy), the paywall with Plus on, Me's Plus rows, and Delete
/// everything with its Plus line.
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

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

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

  /// Long store prices, with the spaces some stores put in them.
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    bool on = false,
    String location = '/plus',
  }) async {
    setLayout(tester, c);
    final store =
        FakePlusStore(yearly: 'IDR 899.000,00')
          ..nextOutcome = const PlusPending()
          ..owns = on ? const [owned] : const [];
    final app = TestApp(
      currency: 'USD',
      config: const AppConfig(
        flavor: Flavor.staging,
        plusEnabled: true,
        termsUrl: 'https://example.invalid/terms',
        privacyUrl: 'https://example.invalid/privacy',
      ),
      plus: PlusEntitlement(store: store, hint: MemoryPlusHint(), clock: testClock),
    )..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: location);
    await settle(
      tester,
      byId(location == '/plus' ? (on ? 'plus-on' : 'plus-restore') : 'me-happy'),
    );
  }

  for (final c in layoutCases) {
    testWidgets('P1 the paywall, fullest ($c)', (tester) async {
      await open(tester, c);
      // A pending payment: the note under the plans.
      await tester.tapId('plus-plan-yearly-start');
      await settle(tester, byId('plus-note'));
      await checkScrolled(tester, 'plus-screen', 'P1');
    });

    testWidgets('P2 the paywall with Plus on ($c)', (tester) async {
      await open(tester, c, on: true);
      await checkScrolled(tester, 'plus-screen', 'P2');
    });

    testWidgets("P3 Me's Plus rows, with Plus on ($c)", (tester) async {
      await open(tester, c, on: true, location: '/me');
      expect(byId('me-plus-manage'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'P3');
    });

    testWidgets('P4 Delete everything with its Plus line ($c)', (tester) async {
      await open(tester, c, on: true, location: '/me');
      await tester.tapId('me-delete');
      expect(byId('me-delete-plus-line'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'P4');
    });
  }
}
