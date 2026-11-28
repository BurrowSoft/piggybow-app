// Goldens: Me (decision 44), at 320 dp ×2, light and dark, for PB UX & PM's
// look at PR 4b: Me with no plan and with one, the notifications-off notice,
// the plan dialog empty and with a plan, the picker, "Delete everything?",
// Your privacy in a build without a Sentry DSN, "Not everything was
// erased", and the App lock row after a restore (5c).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;

import '../app_lock_test.dart' show FakeBiometrics;
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

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  Future<TestApp> open(
    WidgetTester tester,
    LayoutCase c, {
    int? plan,
    bool notificationsOff = false,
    AppLock? lock,
  }) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD', appLock: lock)
      ..prefs.appearance = c.appearance;
    if (notificationsOff) app.notifications.grant = false;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.setPicks({HappyPick.save, HappyPick.worth});
      if (plan != null) await app.journal.setPlanMinor(plan);
    });
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-happy'));
    return app;
  }

  /// A dialog as a golden: no caret in its field.
  Future<void> unfocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  /// The open dialog's words: they scroll at the largest text sizes.
  Finder dialogWords() {
    final scrollables = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    );
    return scrollables.first;
  }

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('M1 Me, no plan ($c)', (tester) async {
      await open(tester, c);
      await expectLayoutGoldens(
        tester,
        c,
        listIn('me-screen'),
        screen: 'me',
        state: 'no-plan',
        stateId: 'M1',
      );
    });

    testWidgets('M2 Me, a plan set ($c)', (tester) async {
      await open(tester, c, plan: 150000);
      await settleForGolden(tester, listIn('me-screen'), end: false);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'plan-set',
        stateId: 'M2',
      );
    });

    testWidgets('M3 notifications off: the notice and Open settings ($c)', (
      tester,
    ) async {
      await open(tester, c, notificationsOff: true);
      await tester.tapId('me-reminder');
      await settle(tester, byId('me-open-settings'));
      await tester.ensureVisible(byId('me-open-settings'));
      await tester.pumpAndSettle();
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'notifications-off',
        stateId: 'M3',
      );
    });

    testWidgets('M4 the plan dialog, empty ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-plan');
      await unfocus(tester);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'plan-dialog-empty',
        stateId: 'M4',
      );
    });

    testWidgets('M5 the plan dialog with a plan: Remove plan ($c)', (
      tester,
    ) async {
      await open(tester, c, plan: 150000);
      await tester.tapId('me-plan');
      await unfocus(tester);
      expect(byId('me-plan-remove'), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'plan-dialog-set',
        stateId: 'M5',
      );
    });

    testWidgets('M6 the picker in Me ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-happy');
      await settle(tester, byId('me-happy-done'));
      await expectLayoutGoldens(
        tester,
        c,
        listIn('me-happy'),
        screen: 'me-picker',
        state: 'picks',
        stateId: 'M6',
      );
    });

    testWidgets('M7 "Delete everything?" ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-delete');
      expect(find.text('Delete everything?'), findsOneWidget);
      await expectLayoutGoldens(
        tester,
        c,
        dialogWords(),
        screen: 'me',
        state: 'delete-all',
        stateId: 'M7',
      );
    });

    testWidgets('M8 Your privacy, no Sentry DSN ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('me-privacy');
      await settle(tester, byId('me-privacy-screen'));
      expect(find.textContaining('crash report'), findsNothing);
      await expectLayoutGoldens(
        tester,
        c,
        listIn('me-privacy-screen'),
        screen: 'me-privacy',
        state: 'lines',
        stateId: 'M8',
      );
    });

    testWidgets('M9 "Not everything was erased" ($c)', (tester) async {
      final app = await open(tester, c);
      // A journal that can't be wiped (its store closed): nothing else is
      // erased, so the dialog shows in the appearance chosen.
      await tester.runAsync(app.journal.close);
      await tester.tapId('me-delete');
      await tester.tapId('me-delete-confirm');
      // Real time between frames, for any real file calls of the wipe.
      final title = find.text('Not everything was erased');
      for (var i = 0; i < 40 && title.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      await expectLayoutGoldens(
        tester,
        c,
        dialogWords(),
        screen: 'me',
        state: 'delete-failed',
        stateId: 'M9',
      );
    });

    testWidgets('M10 the App lock row after a restore ($c)', (tester) async {
      // The settings said "on"; the PIN didn't come with the backup.
      final lock = AppLock(
        store: MemorySecretStore(),
        biometrics: FakeBiometrics(),
        mirror: MemoryLockMirror(on: true),
        iterations: 50,
      );
      await tester.runAsync(lock.load);
      await open(tester, c, lock: lock);
      // Me scrolled to Privacy & security: its header at the top.
      await Scrollable.ensureVisible(
        tester.element(find.text('Privacy & security')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Off after a restore. Turn it on again.'),
        findsOneWidget,
      );
      await expectLayoutGolden(
        tester,
        c,
        screen: 'me',
        state: 'lock-after-restore',
        stateId: 'M10',
      );
    });
  }
}
