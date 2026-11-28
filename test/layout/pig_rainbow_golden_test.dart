// Goldens: the pig's four moods and the rainbow, each widget alone, light
// and dark (decision 44; PB Mobile Tester's PR 3 list).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/goal/rainbow.dart';
import 'package:piggybow/features/pig/pig_view.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/pig/pig_mood.dart';
import 'package:piggybow/theme/theme.dart';

import '../helpers/fonts.dart';
import '../helpers/goldens.dart';

/// The pig at 200 dp in each mood, and the rainbow at 0, 20 (arc 2 empty:
/// no cap dot), 32 and 100 %, on the app's own theme. Reduce-motion is on,
/// so Delighted doesn't hop and each PNG is one still frame.
void main() {
  setUpAll(loadAppFonts);

  /// [child] alone, centred in a square view [width] dp wide at device pixel
  /// ratio 3, on the app's [brightness] theme.
  Future<void> show(
    WidgetTester tester,
    Brightness brightness,
    int width,
    Widget child,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3.0, width * 3.0);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness, disableAnimations: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The ids PB Mobile Tester's list ticks: P1–P4 the moods, R1–R4 the fills.
  const moods = {
    PigMood.sleepy: 'P1',
    PigMood.calm: 'P2',
    PigMood.happy: 'P3',
    PigMood.delighted: 'P4',
  };
  const fills = {0: 'R1', 20: 'R2', 32: 'R3', 100: 'R4'};

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: mood, value: id) in moods.entries) {
      testWidgets('the pig, ${mood.name} (${brightness.name})', (tester) async {
        await show(tester, brightness, 200, PigView(mood: mood, size: 200));
        await expectGolden(
          tester,
          find.byType(MaterialApp),
          screen: 'pig',
          state: mood.name,
          stateId: id,
          brightness: brightness,
          width: 200,
          textScale: 1,
        );
      });
    }
    for (final MapEntry(key: percent, value: id) in fills.entries) {
      testWidgets('the rainbow at $percent % (${brightness.name})', (
        tester,
      ) async {
        await show(tester, brightness, 320, Rainbow(percent: percent));
        await expectGolden(
          tester,
          find.byType(MaterialApp),
          screen: 'rainbow',
          state: '$percent',
          stateId: id,
          brightness: brightness,
          width: 320,
          textScale: 1,
        );
      });
    }
  }
}
