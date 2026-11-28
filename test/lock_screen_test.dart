import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/journal/entry.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// The lock screen (plan §3.11; decisions 19, 67, 70, 71): the PIN, and
/// Forgot PIN's two ways back. The phone's own screen lock, then a new PIN;
/// or erase and start over behind a second confirm, with Delete everything's
/// own wipe: the journal first, and the PIN only after it.
void main() {
  late MemorySecretStore secrets;
  late FakeBiometrics bio;
  late AppLock lock;

  setUp(() {
    secrets = MemorySecretStore();
    // No fingerprint asked for as the lock shows.
    bio = FakeBiometrics()..has = false;
    lock = AppLock(
      store: secrets,
      biometrics: bio,
      firstRun: MemoryFirstRunMarker(),
      iterations: 50,
    );
  });

  /// Frames with real time between them: the wipe sweeps the cache with real
  /// file calls.
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// The app with one entry, locked with the PIN 2468.
  Future<TestApp> openLocked(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    await tester.runAsync(() => lock.setPin('2468'));
    lock.lockNow();
    final app = TestApp(appLock: lock);
    await tester.runAsync(app.openJournal);
    await tester.runAsync(
      () => app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 1000,
        currency: 'THB',
        localDate: '2026-10-01',
      ),
    );
    await app.pump(tester);
    await waitFor(tester, byId('lock-screen'));
    tester.expectScreen('lock-screen');
    return app;
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(byId('pin-key-$digit'));
      await tester.pump();
    }
    await tester.tap(byId('pin-key-ok'));
    await tester.pumpAndSettle();
  }

  testWidgets('the right PIN opens the app; a wrong one says so', (
    tester,
  ) async {
    await openLocked(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
    await typePin(tester, '1111');
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    await typePin(tester, '2468');
    expect(byId('lock-screen'), findsNothing);
  });

  group('Forgot PIN, with a phone screen lock', () {
    testWidgets('the dialog: the screen lock first, erase second', (
      tester,
    ) async {
      await openLocked(tester);
      await tester.tapId('lock-forgot');
      expect(find.text('Forgot your PIN?'), findsOneWidget);
      expect(
        find.text(
          "Use your phone's own screen lock to get in, then choose a new PIN.",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "If that's not possible, the only way back in is to erase "
          "Piggybow's data on this phone and start over.",
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byId('lock-forgot-device'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
        reason: 'the main way back',
      );
      expect(
        find.descendant(
          of: byId('lock-forgot-erase'),
          matching: find.byType(TextButton),
        ),
        findsOneWidget,
        reason: 'the secondary text button',
      );
      await tester.tapId('lock-forgot-cancel');
      expect(find.text('Forgot your PIN?'), findsNothing);
      expect(find.text('Enter your PIN'), findsOneWidget);
    });

    testWidgets('the screen lock, then a new PIN twice: open, old PIN gone', (
      tester,
    ) async {
      await openLocked(tester);
      await tester.tapId('lock-forgot');
      await tester.tapId('lock-forgot-device');
      expect(bio.screenLockAsked, 1);
      expect(find.text('Choose a 4–6 digit PIN'), findsOneWidget);
      // A mismatch starts over.
      await typePin(tester, '1357');
      expect(find.text('Enter it again'), findsOneWidget);
      await typePin(tester, '9999');
      expect(find.text("The PINs don't match"), findsOneWidget);
      await typePin(tester, '1357');
      await typePin(tester, '1357');
      expect(byId('lock-screen'), findsNothing);
      expect(lock.locked, isFalse);
      // Locked again: only the new PIN opens it.
      lock.lockNow();
      await tester.pumpAndSettle();
      await typePin(tester, '2468');
      expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
      await typePin(tester, '1357');
      expect(byId('lock-screen'), findsNothing);
    });

    testWidgets('the screen lock cancelled or failed: still the PIN pad', (
      tester,
    ) async {
      bio.screenLockPass = false;
      await openLocked(tester);
      await tester.tapId('lock-forgot');
      await tester.tapId('lock-forgot-device');
      expect(bio.screenLockAsked, 1);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.text('Choose a 4–6 digit PIN'), findsNothing);
      expect(lock.locked, isTrue);
    });

    testWidgets('Cancel on the new PIN: back to the PIN pad, nothing set', (
      tester,
    ) async {
      await openLocked(tester);
      await tester.tapId('lock-forgot');
      await tester.tapId('lock-forgot-device');
      await tester.tapId('lock-new-pin-cancel');
      expect(find.text('Enter your PIN'), findsOneWidget);
      await typePin(tester, '2468');
      expect(byId('lock-screen'), findsNothing, reason: 'the old PIN still');
    });
  });

  testWidgets('no phone screen lock: erase only, and the dialog says why', (
    tester,
  ) async {
    bio.screenLock = false;
    await openLocked(tester);
    await tester.tapId('lock-forgot');
    expect(find.text('Forgot your PIN?'), findsOneWidget);
    expect(
      find.text(
        "Your phone has no screen lock, so the only way back in is to erase "
        "Piggybow's data on this phone and start over.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('own screen lock'), findsNothing);
    expect(find.textContaining("If that's not possible"), findsNothing);
    expect(byId('lock-forgot-device'), findsNothing);
    expect(byId('lock-forgot-erase'), findsOneWidget);
  });

  testWidgets('erase asks once more; Cancel keeps everything', (tester) async {
    final app = await openLocked(tester);
    await tester.tapId('lock-forgot');
    await tester.tapId('lock-forgot-erase');
    expect(find.text('Delete everything?'), findsOneWidget);
    expect(
      find.text(
        'This erases all your entries, goals and settings from Piggybow on '
        "this phone. It can't be undone.",
      ),
      findsOneWidget,
    );
    await tester.tapId('lock-erase-cancel');
    expect(find.text('Delete everything?'), findsNothing);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(await tester.runAsync(app.journal.isBlank), isFalse);
    expect(secrets.values['app_lock.pin_hash'], isNotNull);
    expect(lock.locked, isTrue);
  });

  testWidgets('erase confirmed: everything goes, then onboarding from O1', (
    tester,
  ) async {
    final app = await openLocked(tester);
    await tester.tapId('lock-forgot');
    await tester.tapId('lock-forgot-erase');
    await tester.tapId('lock-erase-confirm');
    await waitFor(tester, byId('onb-welcome'));
    tester.expectScreen('onb-welcome');
    expect(byId('lock-screen'), findsNothing);
    expect(lock.enabled, isFalse);
    expect(secrets.values, isEmpty, reason: 'the PIN and its settings');
    expect(await tester.runAsync(app.journal.isBlank), isTrue);
  });

  testWidgets(
    'a journal that cannot be erased keeps its lock: said, never skipped',
    (tester) async {
      final app = await openLocked(tester);
      await tester.tapId('lock-forgot');
      await tester.tapId('lock-forgot-erase');
      // A journal that can't be wiped: its store is closed.
      await tester.runAsync(app.journal.close);
      await tester.tapId('lock-erase-confirm');
      await waitFor(tester, find.text('Not everything was erased'));
      expect(find.text('Not everything was erased'), findsOneWidget);
      // Decision 67: the PIN goes only after the journal did.
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);
      expect(secrets.values['app_lock.pin_hash'], isNotNull);
      expect(app.services.onboarded.value, isTrue);
      // Try again runs every step again; it still fails here.
      await tester.tapId('lock-erase-retry');
      await waitFor(tester, find.text('Not everything was erased'));
      expect(find.text('Not everything was erased'), findsOneWidget);
      expect(lock.locked, isTrue);
      await tester.tapId('lock-erase-failed-ok');
      expect(find.text('Not everything was erased'), findsNothing);
      tester.expectScreen('lock-screen');
      expect(find.text('Enter your PIN'), findsOneWidget);
    },
  );
}
