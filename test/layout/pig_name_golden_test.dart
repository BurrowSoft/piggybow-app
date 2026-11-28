@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/fixtures/launch_fixture.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/goldens.dart';

/// Feature 1, name your pig: Home with the pig named "Mochi" on the store
/// screenshots' journal (STORE1), and the name dialog over Me; light and
/// dark.
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

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    addTearDown(tester.view.reset);
  }

  Future<void> waitFor(WidgetTester tester, String id) async {
    for (var k = 0; k < 40 && byId(id).evaluate().isEmpty; k++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    final appearance = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Home, the pig named Mochi, $appearance', (tester) async {
      phone(tester);
      final fixture = LaunchFixture.byId('STORE1', '{"cases": []}');
      final app = TestApp(currency: 'USD', clock: fixture.clock)
        ..prefs.appearance = appearance
        ..prefs.pigName = 'Mochi';
      await tester.runAsync(app.openJournal);
      expect(await tester.runAsync(() => fixture.write(app.journal)), isNull);
      await app.pump(tester);
      await waitFor(tester, 'home-pig-line');
      expect(byId('home-pig-name'), findsOneWidget);
      await expectGolden(
        tester,
        find.byType(MaterialApp),
        screen: 'home',
        state: 'pig-named',
        stateId: 'PN1',
        brightness: brightness,
        width: 360,
        textScale: 1,
      );
    });

    testWidgets('Me → Your pig → Name, the dialog, $appearance', (
      tester,
    ) async {
      phone(tester);
      final app = TestApp()
        ..prefs.appearance = appearance
        ..prefs.pigName = 'Mochi';
      await tester.runAsync(app.openJournal);
      await app.pump(tester, location: '/me');
      await waitFor(tester, 'me-pig-name');
      await tester.tapId('me-pig-name');
      expect(byId('me-pig-name-field'), findsOneWidget);
      await expectGolden(
        tester,
        find.byType(MaterialApp),
        screen: 'me',
        state: 'pig-name',
        stateId: 'PN2',
        brightness: brightness,
        width: 360,
        textScale: 1,
      );
    });
  }
}
