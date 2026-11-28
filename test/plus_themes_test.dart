import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_store.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:piggybow/theme/theme.dart';

import 'helpers.dart';

/// Piggybow Plus's themes (plus-spec §1): Me → Appearance → Theme offers
/// Strawberry and the Plus themes. A Plus theme needs Plus (the paywall when
/// it isn't on). What's shown follows Plus as it is now: Strawberry the
/// moment Plus ends, the chosen theme again when it comes back. A build
/// without Plus has no Theme row and always shows Strawberry.
void main() {
  const owned = PlusProof(token: 't1', productId: plusPlayProductId);
  final strawberry = paletteColours(null, Brightness.light).accent;
  final plum = paletteColours(PlusPalette.plum, Brightness.light).accent;

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

  /// Me, light; [stored] is a choice already on the phone (a backup).
  Future<({TestApp app, FakePlusStore store, PlusEntitlement? plus})> open(
    WidgetTester tester, {
    bool plusBuild = true,
    bool plusOn = false,
    String? stored,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final store = FakePlusStore()..owns = plusOn ? const [owned] : const [];
    final plus = plusBuild
        ? PlusEntitlement(
            store: store,
            hint: MemoryPlusHint(),
            clock: testClock,
          )
        : null;
    final app = TestApp(
      config: AppConfig(flavor: Flavor.staging, plusEnabled: plusBuild),
      plus: plus,
    )..prefs.appearance = 'light';
    if (stored != null) app.prefs.palette = stored;
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-screen'));
    return (app: app, store: store, plus: plus);
  }

  /// The accent the app shows now.
  Color shown(WidgetTester tester) => Theme.of(
    tester.element(byId('me-screen')),
  ).extension<PiggybowPalette>()!.accent;

  Finder rowSays(String text) =>
      find.descendant(of: byId('me-theme'), matching: find.text(text));

  testWidgets('a build without Plus: no Theme row, Strawberry even with a '
      'choice on the phone', (tester) async {
    await open(tester, plusBuild: false, stored: 'plum');
    expect(byId('me-theme'), findsNothing);
    expect(shown(tester), strawberry);
  });

  testWidgets('Plus off: Strawberry; picking Plum opens the paywall, and '
      'closing it changes nothing', (tester) async {
    final o = await open(tester);
    expect(shown(tester), strawberry);
    expect(rowSays('Strawberry'), findsOneWidget);
    await tester.tapId('me-theme');
    tester.expectScreen('theme-sheet');
    expect(
      find.descendant(of: byId('theme-sheet'), matching: find.text('Plus')),
      findsNWidgets(3),
      reason: 'on each Plus theme, not on Strawberry',
    );
    await tester.tapId('theme-plum');
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(o.app.prefs.palette, isNull);
    expect(shown(tester), strawberry);
    expect(rowSays('Strawberry'), findsOneWidget);
  });

  testWidgets('Plus on: Plum shows at once, and the row says so', (
    tester,
  ) async {
    final o = await open(tester, plusOn: true);
    await tester.tapId('me-theme');
    await tester.tapId('theme-plum');
    expect(byId('plus-screen'), findsNothing, reason: 'no paywall with Plus');
    expect(o.app.prefs.palette, 'plum');
    expect(shown(tester), plum);
    expect(rowSays('Plum'), findsOneWidget);
  });

  testWidgets('Plus ends: Strawberry, Plum kept and said to come back; Plus '
      'back: Plum again', (tester) async {
    final o = await open(tester, plusOn: true, stored: 'plum');
    expect(shown(tester), plum);
    o.store.owns = const [];
    await tester.runAsync(o.plus!.refresh);
    await tester.pumpAndSettle();
    expect(shown(tester), strawberry);
    expect(o.app.prefs.palette, 'plum', reason: 'the choice is kept');
    expect(
      rowSays('Strawberry for now · Plum comes back with Plus'),
      findsOneWidget,
    );
    o.store.owns = const [owned];
    await tester.runAsync(o.plus!.refresh);
    await tester.pumpAndSettle();
    expect(shown(tester), plum);
    expect(rowSays('Plum'), findsOneWidget);
  });

  testWidgets('a restored phone: a backed-up Plum without Plus shows '
      'Strawberry', (tester) async {
    await open(tester, stored: 'plum');
    expect(shown(tester), strawberry);
    expect(
      rowSays('Strawberry for now · Plum comes back with Plus'),
      findsOneWidget,
    );
  });

  testWidgets('picking Strawberry clears the choice', (tester) async {
    final o = await open(tester, plusOn: true, stored: 'plum');
    await tester.tapId('me-theme');
    await tester.tapId('theme-strawberry');
    expect(o.app.prefs.palette, isNull);
    expect(shown(tester), strawberry);
    expect(rowSays('Strawberry'), findsOneWidget);
  });
}
