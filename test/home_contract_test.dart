import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/pig/pig_view.dart';
import 'package:piggybow/fixtures/launch_fixture.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/pig/pig_mood.dart';

import 'helpers.dart';

/// Every case of the mood contract (test/contracts/pig_mood_cases.json),
/// written into the journal by the launch-fixture writer the on-device flows
/// use, and read off Home: the pig's mood (its TalkBack label) and its line
/// are what the pure function gives. This pins Home to the contract, ended
/// goals included (decision 53). Each case's now is the app's clock; its
/// today is that instant's day in Bangkok (helpers.dart).
void main() {
  final casesJson = File(fixtureCasesAsset).readAsStringSync();
  final contract = jsonDecode(casesJson) as Map<String, dynamic>;
  final cases = (contract['cases'] as List).cast<Map<String, dynamic>>();

  for (final c in cases) {
    final expected = c['expect'] as Map<String, dynamic>;
    testWidgets('${c['id']} on Home: ${c['why']}', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final fixture = LaunchFixture.byId(c['id'] as String, casesJson);
      final app = TestApp(
        currency: contract['currency'] as String,
        clock: fixture.clock,
      );
      await tester.runAsync(app.openJournal);
      expect(
        fixture.check(app.localDay.todayWire),
        isNull,
        reason: "the case's today is the app's",
      );
      await tester.runAsync(() => fixture.write(app.journal));
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-pig-line').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(byId('goal-done-screen'), findsNothing);

      final l10n = AppLocalizations.of(tester.element(byId('home-screen')));
      final mood = PigMood.values.byName(expected['mood'] as String);
      expect(
        tester.getSemantics(byId('home-pig')),
        isSemantics(label: pigA11yLabel(l10n, mood)),
      );
      final line = pigLineText(
        l10n,
        expected['line'] as String,
        Map<String, Object>.from(expected['args'] as Map? ?? const {}),
      );
      expect(
        find.descendant(of: byId('home-pig-line'), matching: find.text(line)),
        findsOneWidget,
        reason: expected['line'] as String,
      );
    });
  }
}
