@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/fixtures/launch_fixture.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/goldens.dart';

/// Feature 2, the sleepy pig at night: Home at 23:00 on the phone's clock,
/// on the store screenshots' journal (STORE1), light and dark.
void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    final appearance = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('Home at 23:00, $appearance', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 780 * 3);
      addTearDown(tester.view.reset);
      final fixture = LaunchFixture.byId('STORE1', '{"cases": []}');
      final app = TestApp(currency: 'USD', clock: fixture.clock)
        ..prefs.appearance = appearance;
      await tester.runAsync(app.openJournal);
      expect(await tester.runAsync(() => fixture.write(app.journal)), isNull);
      // The fixture's day (18 November, Bangkok) at 23:00 there.
      fixture.clock.now = DateTime.utc(2026, 11, 18, 16);
      await app.pump(tester);
      final pigLine = byId('home-pig-line');
      for (var k = 0; k < 40 && pigLine.evaluate().isEmpty; k++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(
        find.text("It's getting late. I'll be here tomorrow."),
        findsOneWidget,
      );
      await expectGolden(
        tester,
        find.byType(MaterialApp),
        screen: 'home',
        state: 'night',
        stateId: 'N1',
        brightness: brightness,
        width: 360,
        textScale: 1,
      );
    });
  }
}
