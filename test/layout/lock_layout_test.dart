@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/core/button_pair.dart';

import '../app_lock_test.dart' show FakeBiometrics;
import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// The lock screen and Forgot PIN's dialogs in every layout case (plan
/// §3.11, decision 70): the PIN pad (L1), Forgot PIN with the phone's screen
/// lock (L2) and without one (L3), the erase confirm (L4), and the new PIN
/// after the screen lock (L5). Goldens at 320 dp ×2, light and dark.
void main() {
  setUpAll(loadAppFonts);

  /// The app locked with a PIN, in case [c].
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    bool screenLock = true,
  }) async {
    setLayout(tester, c);
    final bio = FakeBiometrics()
      ..has = false
      ..screenLock = screenLock;
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: bio,
      firstRun: MemoryFirstRunMarker(),
      iterations: 50,
    );
    await tester.runAsync(() => lock.setPin('2468'));
    lock.lockNow();
    final app = TestApp(appLock: lock)..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    for (var i = 0; i < 40 && byId('lock-screen').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    tester.expectScreen('lock-screen');
  }

  Future<void> golden(
    WidgetTester tester,
    LayoutCase c,
    String state,
    String stateId,
  ) async {
    await expectSoundLayout(tester, reason: stateId);
    if (c.takesGolden) {
      await expectLayoutGolden(
        tester,
        c,
        screen: 'lock',
        state: state,
        stateId: stateId,
      );
    }
  }

  for (final c in layoutCases) {
    testWidgets('L1 the lock screen ($c)', (tester) async {
      await open(tester, c);
      await golden(tester, c, 'pin', 'L1');
    });

    testWidgets('L2 Forgot PIN, with a phone screen lock ($c)', (
      tester,
    ) async {
      await open(tester, c);
      await tester.tapId('lock-forgot');
      tester.expectScreen('lock-forgot-device');
      // On one line, or full width with the main way back on top
      // (decision 71).
      final row = tester.renderObject<RenderButtonRow>(find.byType(ButtonRow));
      final main = tester.getRect(byId('lock-forgot-device'));
      final erase = tester.getRect(byId('lock-forgot-erase'));
      final cancel = tester.getRect(byId('lock-forgot-cancel'));
      if (row.stacked) {
        expect(main.bottom, lessThanOrEqualTo(erase.top), reason: 'L2 order');
        expect(erase.bottom, lessThanOrEqualTo(cancel.top));
        expect(erase.width, moreOrLessEquals(main.width));
        expect(cancel.width, moreOrLessEquals(main.width));
      } else {
        expect(erase.right, lessThanOrEqualTo(main.left), reason: 'L2 row');
        expect(cancel.right, lessThanOrEqualTo(erase.left));
      }
      if (c.width == 320 && c.textScale == 2) {
        expect(row.stacked, isTrue, reason: 'L2 at 320 ×2: no room');
      }
      await golden(tester, c, 'forgot', 'L2');
    });

    testWidgets('L3 Forgot PIN, no phone screen lock ($c)', (tester) async {
      await open(tester, c, screenLock: false);
      await tester.tapId('lock-forgot');
      tester.expectScreen('lock-forgot-erase');
      await golden(tester, c, 'forgot-erase-only', 'L3');
    });

    testWidgets('L4 the erase confirm ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('lock-forgot');
      await tester.tapId('lock-forgot-erase');
      tester.expectScreen('lock-erase-confirm');
      await golden(tester, c, 'erase-confirm', 'L4');
    });

    testWidgets('L5 a new PIN, after the phone screen lock ($c)', (
      tester,
    ) async {
      await open(tester, c);
      await tester.tapId('lock-forgot');
      await tester.tapId('lock-forgot-device');
      tester.expectScreen('lock-new-pin-cancel');
      await golden(tester, c, 'new-pin', 'L5');
    });
  }
}
