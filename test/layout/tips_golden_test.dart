// Goldens: pig tips on screen (A3, decision 90), at 320 dp ×2, light and
// dark, for PB UX & PM's look: the consent sheet, Home with a written tip,
// the Report sheet, and Me with tips on.
@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/tips/pig_tips.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);

  const written = WrittenTip(
    day: '2026-10-02',
    text: 'Try a slow Saturday: one small treat, planned ahead.',
    model: 'claude-sonnet-5-5',
    sig: 'sig-1',
  );

  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    required PigTips tips,
    String? location,
  }) async {
    setLayout(tester, c);
    final app = TestApp(pigTips: tips)..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: location);
    for (var i = 0; i < 60 && byId(location == null ? 'home-idea' : 'me-screen').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// [id]'s row in the middle of its screen.
  Future<void> centre(WidgetTester tester, String id) async {
    await tester.revealId(id);
    await Scrollable.ensureVisible(tester.element(byId(id)), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('TP1 the consent sheet ($c)', (tester) async {
      await open(tester, c, tips: FakePigTips(), location: '/me');
      await tester.tapId('me-pig-tips');
      await expectSoundLayout(tester, reason: 'TP1');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'tips-sheet',
        stateId: 'TP1',
      );
    });

    testWidgets('TP2 Home with a written tip ($c)', (tester) async {
      await open(tester, c, tips: FakePigTips(on: true, tip: written));
      await centre(tester, 'home-idea');
      await expectSoundLayout(tester, reason: 'TP2');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'home',
        state: 'written-tip',
        stateId: 'TP2',
      );
    });

    testWidgets('TP3 the Report sheet ($c)', (tester) async {
      await open(tester, c, tips: FakePigTips(on: true, tip: written));
      await centre(tester, 'home-idea');
      await tester.tapId('home-idea-report');
      await expectSoundLayout(tester, reason: 'TP3');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'home',
        state: 'tip-report',
        stateId: 'TP3',
      );
    });

    testWidgets('TP4 Me with pig tips on ($c)', (tester) async {
      await open(tester, c, tips: FakePigTips(on: true), location: '/me');
      await centre(tester, 'me-pig-tips');
      await expectSoundLayout(tester, reason: 'TP4');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'pig-tips-on',
        stateId: 'TP4',
      );
    });
  }
}
