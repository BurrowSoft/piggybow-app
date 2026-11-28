// Me → Your privacy in a build with Plus, which offers the home-screen widget
// (feature 16): its line, in every layout case, and as a golden (decision 44,
// 320 dp ×2, light and dark) for PB UX & PM's look.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);
  const line =
      "The widget shows today's spending and a goal on your home screen. With the app lock on, it shows only the pig.";

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  for (final c in layoutCases) {
    testWidgets("WG1 Your privacy with Plus: the widget's line ($c)", (tester) async {
      setLayout(tester, c);
      final app = TestApp(
        currency: 'USD',
        config: const AppConfig(flavor: Flavor.staging, plusEnabled: true),
      )..prefs.appearance = c.appearance;
      await app.pump(tester, location: MeRoutes.privacy);
      await tester.revealId('me-privacy-screen');
      expect(find.text(line), findsOneWidget);
      await expectSoundLayout(tester, reason: 'WG1');
      if (c.takesGolden) {
        await expectLayoutGoldens(
          tester,
          c,
          listIn('me-privacy-screen'),
          screen: 'me-privacy',
          state: 'widget-line',
          stateId: 'WG1',
        );
      }
    });
  }
}
