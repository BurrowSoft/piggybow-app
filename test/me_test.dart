import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/core/device.dart';
import 'package:piggybow/features/me/me_actions.dart';
import 'package:piggybow/features/me/me_screen.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/lock_rules/lock_rules.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/pig/pig_mood.dart' show HappyPick;

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// Me (plan §3.8, decision 63): the rows and what they change, the plan
/// dialog, Remove plan, the reminder and its notice, appearance, Delete
/// everything (the §4.7 wipe list), Export, privacy, help and the version.
void main() {
  String thb(int minor) => formatMoney(minor, 'THB', 'en_US');

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // Delete everything sweeps the export cache: a real folder where the app
  // asks for its temporary directory.
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('pb_me');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => temp.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    temp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> openMe(
    WidgetTester tester, {
    Future<void> Function(TestApp)? seed,
    AppConfig config = const AppConfig(flavor: Flavor.staging),
    double width = 360,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = Size(width * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp(config: config);
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-happy'));
    return app;
  }

  testWidgets('the picks, named in the row', (tester) async {
    await openMe(
      tester,
      seed: (app) => app.journal.setPicks({HappyPick.worth, HappyPick.save}),
    );
    expect(
      find.text('Saving something each week · Spends that feel worth it'),
      findsOneWidget,
    );
    expect(find.text('Not set'), findsOneWidget, reason: 'no plan yet');
  });

  testWidgets('the plan: set in the dialog, shown, then removed', (
    tester,
  ) async {
    final app = await openMe(tester);
    await tester.tapId('me-plan');
    await tester.enterId('me-plan-amount', '1500');
    await tester.tapId('me-plan-save');
    await settle(tester, find.text(thb(150000)));
    expect(await tester.runAsync(app.journal.planMinor), 150000);
    expect(find.text(thb(150000)), findsOneWidget);

    await tester.tapId('me-plan');
    await tester.tapId('me-plan-remove');
    await settle(tester, find.text('Not set'));
    expect(await tester.runAsync(app.journal.planMinor), isNull);
  });

  testWidgets('a plan over 12 digits is too large', (tester) async {
    await openMe(tester);
    await tester.tapId('me-plan');
    await tester.enterId('me-plan-amount', '1234567890123');
    await tester.tapId('me-plan-save');
    expect(find.text('That amount is too large.'), findsOneWidget);
  });

  testWidgets('Remove plan with only the plan picked: another pick first', (
    tester,
  ) async {
    final app = await openMe(
      tester,
      seed: (app) async {
        await app.journal.setPicks({HappyPick.plan});
        await app.journal.setPlanMinor(100000);
      },
    );
    await tester.tapId('me-plan');
    await tester.tapId('me-plan-remove');
    await settle(tester, byId('me-happy-done'));
    tester.expectScreen('me-happy');
    await tester.tapId('me-happy-done');
    expect(find.text('Pick at least one.'), findsOneWidget);
    await tester.tapId('onb-pick-save');
    await tester.tapId('me-happy-done');
    await settle(tester, byId('me-screen'));
    expect(await tester.runAsync(app.journal.picks), {HappyPick.save});
    expect(await tester.runAsync(app.journal.planMinor), isNull);
  });

  testWidgets('the reminder: on asks for notifications and shows its time', (
    tester,
  ) async {
    final app = await openMe(tester);
    expect(byId('me-reminder-time'), findsNothing);
    await tester.tapId('me-reminder');
    await settle(tester, byId('me-reminder-time'));
    expect(app.notifications.requests, 1);
    expect(find.text('8:00 PM'), findsOneWidget, reason: 'plan §3.10: 20:00');
  });

  testWidgets("notifications off: the notice, and the phone's settings", (
    tester,
  ) async {
    final app = await openMe(tester);
    app.notifications.grant = false;
    await tester.tapId('me-reminder');
    await settle(tester, byId('me-open-settings'));
    expect(
      find.text(
        "Notifications are off for Piggybow. Turn them on in your phone's settings.",
      ),
      findsOneWidget,
    );
    await tester.tapId('me-open-settings');
    expect(app.notifications.settingsOpened, 1);
  });

  testWidgets('appearance: a tap sets it, on this phone', (tester) async {
    final app = await openMe(tester);
    await tester.tapId('me-theme-dark');
    expect(app.prefs.appearance, 'dark');
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

  testWidgets('Delete everything: the wipe list, then O1 on a new account', (
    tester,
  ) async {
    final app = await openMe(
      tester,
      seed: (app) async {
        await app.journal.setPicks({HappyPick.save});
        await app.journal.setPlanMinor(50000);
        await app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 100000,
            createdAt: DateTime.utc(2026, 9),
            updatedAt: DateTime.utc(2026, 9),
          ),
        );
        await app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 1200,
          currency: 'THB',
          localDate: '2026-10-02',
          category: SpendCategory.food,
        );
      },
    );
    final oldId = app.session.user!.id;
    await tester.tapId('me-reminder');
    await tester.tapId('me-theme-dark');
    await app.prefs.setLocaleCode('en');
    await app.prefs.setWelcomeSeen();
    await tester.tapId('me-delete');
    expect(find.text('Delete everything?'), findsOneWidget);
    await tester.tapId('me-delete-confirm');
    await waitFor(tester, byId('onb-welcome'));

    tester.expectScreen('onb-welcome');
    // The journal, the reminders, every pref: gone.
    expect(await tester.runAsync(app.journal.isBlank), isTrue);
    expect(await tester.runAsync(app.journal.onboarded), isFalse);
    expect(app.services.onboarded.value, isFalse);
    expect(app.reminders.cancels, greaterThan(0));
    expect(app.reminders.scheduled, isEmpty);
    expect(app.prefs.appearance, isNull);
    expect(app.prefs.localeCode, isNull);
    expect(app.prefs.palette, isNull);
    expect(app.prefs.welcomeSeen, isFalse);
    expect(app.prefs.sessionEndedNoEmail, isFalse);
    // A new device account: a new id, nothing of the old one.
    final newId = app.session.user!.id;
    expect(newId, isNot(oldId));
    expect(app.prefs.deviceAccount, isNot(contains(oldId)));
    expect(app.session.accountState?.reminderOn, isFalse);

    // Onboarding again, then Home, on the new account.
    await tester.tapId('onb-start');
    await tester.tapId('onb-pick-save');
    await tester.tapId('onb-continue');
    await settle(tester, byId('onb-goal-later'));
    await tester.tapId('onb-goal-later');
    await settle(tester, byId('home-screen'));
    tester.expectScreen('home-screen');
    expect(app.session.user!.id, newId);
  });

  testWidgets('a step that fails: Me says so, and Try again finishes it', (
    tester,
  ) async {
    final app = await openMe(
      tester,
      seed: (app) => app.journal.setPicks({HappyPick.save}),
    );
    app.reminders.failCancel = true;
    await tester.tapId('me-delete');
    await tester.tapId('me-delete-confirm');
    await waitFor(tester, find.text('Not everything was erased'));
    expect(find.text('Not everything was erased'), findsOneWidget);
    expect(
      await tester.runAsync(app.journal.isBlank),
      isTrue,
      reason: 'the other steps still ran',
    );
    expect(app.services.onboarded.value, isTrue, reason: 'only full success');
    app.reminders.failCancel = false;
    await tester.tapId('me-delete-retry');
    await waitFor(tester, byId('onb-welcome'));
    tester.expectScreen('onb-welcome');
  });

  testWidgets('a failed journal wipe keeps the PIN, the prefs, the account', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final secrets = MemorySecretStore();
    final lock = AppLock(
      store: secrets,
      biometrics: FakeBiometrics(),
      firstRun: MemoryFirstRunMarker()..wasSeen = true,
      iterations: 50,
    );
    final app = TestApp(appLock: lock);
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-happy'));
    final id = app.session.user!.id;
    // The lock on, with a PIN (the phone's, not the account's).
    await tester.runAsync(() => lock.setPin('2468'));
    await tester.pumpAndSettle();
    expect(lock.enabled, isTrue);
    await tester.tapId('me-theme-dark');
    // A journal that can't be wiped: its store is closed.
    await tester.runAsync(app.journal.close);
    await tester.tapId('me-delete');
    await tester.tapId('me-delete-confirm');
    await waitFor(tester, find.text('Not everything was erased'));
    expect(find.text('Not everything was erased'), findsOneWidget);
    expect(lock.enabled, isTrue, reason: 'the lock still on');
    expect(
      secrets.values['app_lock.pin_hash'],
      isNotNull,
      reason: 'its PIN',
    );
    expect(app.prefs.appearance, 'dark', reason: 'the prefs');
    expect(app.session.user!.id, id, reason: 'the account');
    expect(app.services.onboarded.value, isTrue);
  });

  testWidgets('a wide phone: every dialog opens without an error', (
    tester,
  ) async {
    // Wider than 360 dp a dialog isn't at its narrowest, so it asks its
    // title how wide it would be: WholeWordsText answers (a LayoutBuilder
    // alone asserts in debug builds).
    final app = await openMe(tester, width: 411);
    await tester.tapId('me-plan');
    await tester.tapId('me-plan-cancel');
    await tester.tapId('me-delete');
    expect(find.text('Delete everything?'), findsOneWidget);
    // A journal that can't be wiped: "Not everything was erased".
    await tester.runAsync(app.journal.close);
    await tester.tapId('me-delete-confirm');
    await waitFor(tester, find.text('Not everything was erased'));
    expect(find.text('Not everything was erased'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('after a restore, the lock row says so until opened', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    // The settings said "on"; the PIN didn't come with the backup.
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: FakeBiometrics(),
      mirror: MemoryLockMirror(on: true),
      iterations: 50,
    );
    await tester.runAsync(lock.load);
    final app = TestApp(appLock: lock);
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-happy'));
    final notice = find.text('Off after a restore. Turn it on again.');
    expect(notice, findsOneWidget);
    await tester.tapId('me-lock');
    expect(lock.restoreNoticePending, isFalse);
  });

  testWidgets('the App lock row follows the lock as it turns on and off', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: FakeBiometrics(),
      iterations: 50,
    );
    final app = TestApp(appLock: lock);
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: '/me');
    await settle(tester, byId('me-happy'));
    Finder row(String state) {
      return find.descendant(of: byId('me-lock'), matching: find.text(state));
    }

    expect(row('Off'), findsOneWidget);
    // Turned on and off while Me stays open: the row follows each time.
    await tester.runAsync(() => lock.setPin('2468'));
    await tester.pumpAndSettle();
    expect(row('On'), findsOneWidget);
    await tester.runAsync(lock.clear);
    await tester.pumpAndSettle();
    expect(row('Off'), findsOneWidget);
  });

  testWidgets('Delete everything, cancelled: nothing changes', (tester) async {
    final app = await openMe(
      tester,
      seed: (app) => app.journal.setPicks({HappyPick.save}),
    );
    await tester.tapId('me-delete');
    await tester.tapId('me-delete-cancel');
    expect(await tester.runAsync(app.journal.isBlank), isFalse);
    tester.expectScreen('me-screen');
  });

  testWidgets('privacy: no crash-report line without a Sentry DSN', (
    tester,
  ) async {
    await openMe(tester);
    await tester.tapId('me-privacy');
    await settle(tester, byId('me-privacy-screen'));
    expect(find.textContaining('No ads, no tracking.'), findsOneWidget);
    expect(find.textContaining('crash report'), findsNothing);
  });

  testWidgets('privacy: the crash-report line with a Sentry DSN', (
    tester,
  ) async {
    await openMe(
      tester,
      config: const AppConfig(
        flavor: Flavor.staging,
        sentryDsn: 'https://key@example.invalid/1',
      ),
    );
    await tester.tapId('me-privacy');
    await settle(tester, byId('me-privacy-screen'));
    expect(find.textContaining('crash report'), findsOneWidget);
  });

  testWidgets('help only with SUPPORT_URL; the version always', (
    tester,
  ) async {
    await openMe(tester);
    expect(byId('me-help'), findsNothing);
    await tester.scrollUntilVisible(
      byId('me-version'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Version 0.1.0 (1)'), findsOneWidget);
  });

  testWidgets('help with SUPPORT_URL', (tester) async {
    await openMe(
      tester,
      config: const AppConfig(
        flavor: Flavor.staging,
        supportUrl: 'https://example.invalid/support',
      ),
    );
    await tester.scrollUntilVisible(
      byId('me-help'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(byId('me-help'), findsOneWidget);
  });

  test("every App lock subtitle lock_rules can ask for is in the ARB", () {
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    for (final lockOn in [true, false]) {
      for (final pending in [true, false]) {
        final key = lockRowKey(lockOn: lockOn, restoreNoticePending: pending);
        expect(arb.containsKey(key), isTrue, reason: key);
      }
    }
  });

  testWidgets('the App lock subtitles read as the ARB says', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(lockRowText(l10n, 'meStateOn'), 'On');
    expect(lockRowText(l10n, 'meStateOff'), 'Off');
    expect(
      lockRowText(l10n, 'lockOffAfterRestore'),
      'Off after a restore. Turn it on again.',
    );
  });

  test('the settings channel: the same names in Dart and in MainActivity', () {
    final kotlin = File(
      'android/app/src/main/kotlin/com/burrowsoft/piggybow/MainActivity.kt',
    ).readAsStringSync();
    expect(kotlin, contains('SETTINGS_CHANNEL = "$settingsChannel"'));
    expect(
      kotlin,
      contains('OPEN_NOTIFICATION_SETTINGS = "$openNotificationSettingsMethod"'),
    );
    // If those settings can't open: the app's details, then nothing.
    expect(kotlin, contains('ACTION_APPLICATION_DETAILS_SETTINGS'));
    expect(kotlin, contains('catch (e: Exception)'));
  });

  group('export', () {
    late Directory cache;
    setUp(() => cache = Directory.systemTemp.createTempSync('pb_export'));
    tearDown(() => cache.deleteSync(recursive: true));

    testWidgets('the CSV goes to the share sheet alone, then is deleted', (
      tester,
    ) async {
      final app = TestApp();
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        await app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 100000,
            createdAt: DateTime.utc(2026, 9),
            updatedAt: DateTime.utc(2026, 9),
          ),
        );
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 120050,
          currency: 'THB',
          localDate: '2026-10-01',
        );
      });
      await app.pump(tester);
      String? name;
      String? text;
      String? path;
      List<int>? bytes;
      await tester.runAsync(
        () => exportJournal(
          app.services,
          cache: () async => cache,
          share: (file) async {
            name = file.name;
            path = file.path;
            bytes = await file.readAsBytes();
            text = utf8.decode(bytes!);
          },
        ),
      );
      expect(name, 'piggybow-2026-10-02.csv');
      // UTF-8 with a BOM (EF BB BF), so spreadsheets read Thai text right.
      expect(bytes!.take(3), [0xEF, 0xBB, 0xBF]);
      expect(text, contains('2026-10-01,saved,1200.50,THB'));
      expect(text, contains('Bike'));
      expect(File(path!).existsSync(), isFalse, reason: 'deleted after');
    });

    test('nothing is left from before: the sweep at each start', () async {
      Directory('${cache.path}/export').createSync();
      File('${cache.path}/export/old.csv').writeAsStringSync('x');
      Directory('${cache.path}/share_plus').createSync();
      File('${cache.path}/share_plus/old.csv').writeAsStringSync('x');
      await sweepExports(cache: () async => cache);
      expect(Directory('${cache.path}/export').existsSync(), isFalse);
      expect(Directory('${cache.path}/share_plus').existsSync(), isFalse);
    });
  });
}
