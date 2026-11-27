import 'dart:ui' show Tristate;

import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/router.dart';

import 'helpers.dart';

void main() {
  testWidgets('a first start opens on Home: the device account, no sign-in', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester);
    tester.expectScreen('home-screen');
    expect(app.session.user?.id, 'device-1');
    expect(app.session.user?.isAnonymous, isTrue);
    // The device account is stored on the phone, never anywhere else.
    expect(app.prefs.deviceAccount, contains('"id":"device-1"'));
  });

  testWidgets('every tab has its Maestro id and opens its screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await TestApp().pump(tester);

    tester.expectScreen('home-screen');
    for (final tab in AppTab.values) {
      await tester.tapId('tab-${tab.id}');
      tester.expectScreen('${tab.id}-screen');
      expect(
        tester.getSemantics(byId('tab-${tab.id}')).flagsCollection.isSelected ==
            Tristate.isTrue,
        isTrue,
        reason: 'tab-${tab.id} exposes selected',
      );
    }
    semantics.dispose();
  });

  testWidgets('English labels: Home, Timeline, Summary, Me', (tester) async {
    await TestApp().pump(tester);
    for (final label in ['Home', 'Timeline', 'Summary', 'Me']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('unknown routes land on Home', (tester) async {
    await TestApp().pump(tester);
    await tester.tapId('tab-me');
    GoRouter.of(tester.element(byId('me-screen'))).go('/homex');
    await tester.pumpAndSettle();
    tester.expectScreen('home-screen');
  });
}
