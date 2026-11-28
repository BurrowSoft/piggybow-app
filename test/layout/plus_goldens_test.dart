// Goldens: Piggybow Plus (decision 44), at 320 dp ×2, light and dark, for
// PB UX & PM's look: the paywall's offer, a pending payment's note, the
// paywall with Plus on, Me's Plus rows with Plus on, and "Delete
// everything?" with its Plus line.
@Tags(['golden'])
library;

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

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  /// The open dialog's words: they scroll at the largest text sizes.
  Finder dialogWords() => find
      .descendant(of: find.byType(AlertDialog), matching: find.byType(Scrollable))
      .first;

  /// US prices as the store formats them.
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    bool on = false,
    String location = '/plus',
    PlusBuyOutcome? next,
  }) async {
    setLayout(tester, c);
    final store = FakePlusStore(yearly: r'$59.99')
      ..nextOutcome = next
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

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('PL1 the paywall, the offer ($c)', (tester) async {
      await open(tester, c);
      await expectLayoutGoldens(
        tester,
        c,
        listIn('plus-screen'),
        screen: 'plus',
        state: 'offer',
        stateId: 'PL1',
      );
    });

    testWidgets("PL2 a pending payment's note ($c)", (tester) async {
      await open(tester, c, next: const PlusPending());
      await tester.tapId('plus-plan-yearly-start');
      await settle(tester, byId('plus-note'));
      await tester.ensureVisible(byId('plus-note'));
      await tester.pumpAndSettle();
      await expectLayoutGolden(
        tester,
        c,
        screen: 'plus',
        state: 'pending',
        stateId: 'PL2',
      );
    });

    testWidgets('PL3 the paywall with Plus on ($c)', (tester) async {
      await open(tester, c, on: true);
      await expectLayoutGoldens(
        tester,
        c,
        listIn('plus-screen'),
        screen: 'plus',
        state: 'on',
        stateId: 'PL3',
      );
    });

    testWidgets("PL4 Me's Plus rows, with Plus on ($c)", (tester) async {
      await open(tester, c, on: true, location: '/me');
      await settleForGolden(tester, listIn('me-screen'), end: false);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'plus-on',
        stateId: 'PL4',
      );
    });

    testWidgets('PL5 "Delete everything?" with its Plus line ($c)', (tester) async {
      await open(tester, c, on: true, location: '/me');
      await tester.tapId('me-delete');
      expect(byId('me-delete-plus-line'), findsOneWidget);
      await expectLayoutGoldens(
        tester,
        c,
        dialogWords(),
        screen: 'me',
        state: 'delete-plus',
        stateId: 'PL5',
      );
    });
  }
}
