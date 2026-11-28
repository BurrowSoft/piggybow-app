import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/core/backup.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/core/device.dart';
import 'package:piggybow/core/local_prefs.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// On an iPhone the journal is never in a backup (decision 72, I-1(b)): its
/// folder is flagged out of every backup at each start, before the journal
/// file opens, through AppDelegate.swift on the settings channel. That the
/// flag is really set on a device is a VITOR_TEST row (iCloud's backup size
/// for Piggybow), and a Quick Start transfer is a two-iPhone row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(settingsChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  late List<MethodCall> calls;
  bool? fileThere;

  File journalFile() => File('${dir.path}/${JournalStore.fileName}');

  /// The iPhone's side of the channel, as AppDelegate.swift answers it.
  void iPhoneAnswers({bool fail = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case excludeFromBackupMethod:
          fileThere = journalFile().existsSync();
          if (fail) throw PlatformException(code: 'not-excluded');
          return true;
        case openNotificationSettingsMethod:
          return null;
        default:
          // FlutterMethodNotImplemented.
          throw MissingPluginException();
      }
    });
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pb_iphone_backup');
    calls = [];
    fileThere = null;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  Future<JournalStore> openOn(TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return await JournalStore.openIn(dir, clock: Clock());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  test(
    "an iPhone: the journal's folder is out of backups before the file opens",
    () async {
      iPhoneAnswers();
      final store = await openOn(TargetPlatform.iOS);
      addTearDown(store.close);
      expect(
        [for (final c in calls) (c.method, c.arguments)],
        [(excludeFromBackupMethod, dir.path)],
      );
      expect(fileThere, isFalse, reason: 'flagged before the journal exists');
      expect(journalFile().existsSync(), isTrue, reason: 'then it opens');
    },
  );

  test('every start asks again (the flag is cheap; a restore loses it)', () async {
    iPhoneAnswers();
    final first = await openOn(TargetPlatform.iOS);
    await first.close();
    final second = await openOn(TargetPlatform.iOS);
    addTearDown(second.close);
    expect(calls.where((c) => c.method == excludeFromBackupMethod), hasLength(2));
    expect(fileThere, isTrue, reason: 'the second start: the file exists');
  });

  test('Android: nothing is asked (its backup rules decide)', () async {
    iPhoneAnswers();
    final store = await openOn(TargetPlatform.android);
    addTearDown(store.close);
    expect(calls, isEmpty);
  });

  test("the flag can't be set: the journal still opens (it stays on the phone)", () async {
    iPhoneAnswers(fail: true);
    final store = await openOn(TargetPlatform.iOS);
    addTearDown(store.close);
    expect(journalFile().existsSync(), isTrue);
  });

  test('excludeFromBackup: true once set; false with no such method', () async {
    iPhoneAnswers();
    expect(await excludeFromBackup(dir.path), isTrue);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await excludeFromBackup(dir.path), isFalse);
  });

  test('the journal file: missing before the first open, there after', () async {
    expect(await JournalStore.missingIn(dir), isTrue);
    final store = await openOn(TargetPlatform.android);
    await store.close();
    expect(await JournalStore.missingIn(dir), isFalse);
  });

  group('prefs a backup brought back, with no journal (the Reviewer, #79)', () {
    MemoryLocalPrefs restored() => MemoryLocalPrefs(
      localeCode: 'en',
      welcomeSeen: true,
      accountOnDevice: true,
      deviceAccount: '{"id":"device-1"}',
    );

    test('an iPhone with no journal file forgets them', () async {
      final prefs = restored();
      expect(
        await forgetPrefsWithoutJournal(
          journalMissing: true,
          prefs: prefs,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        (prefs.welcomeSeen, prefs.accountOnDevice, prefs.deviceAccount),
        (false, false, null),
      );
    });

    test('with its journal, or on Android, they stay', () async {
      for (final (missing, platform) in [
        (false, TargetPlatform.iOS),
        (true, TargetPlatform.android),
      ]) {
        final prefs = restored();
        expect(
          await forgetPrefsWithoutJournal(
            journalMissing: missing,
            prefs: prefs,
            platform: platform,
          ),
          isFalse,
        );
        expect(prefs.welcomeSeen, isTrue, reason: '$platform');
        expect(prefs.deviceAccount, isNotNull, reason: '$platform');
      }
    });

    testWidgets('a restored iPhone with no journal opens on the first-run screens', (
      tester,
    ) async {
      // What a backup restores: the device's prefs, never the journal.
      final app = TestApp(onboarded: false);
      app.prefs
        ..welcomeSeen = true
        ..accountOnDevice = true;
      // main.dart, before anything reads the prefs.
      await tester.runAsync(
        () => forgetPrefsWithoutJournal(
          journalMissing: true,
          prefs: app.prefs,
          platform: TargetPlatform.iOS,
        ),
      );
      await tester.runAsync(app.openJournal);
      await app.pump(tester);
      await tester.pumpAndSettle();
      tester.expectScreen('onb-welcome');
      expect(app.prefs.welcomeSeen, isFalse);
    });

    testWidgets(
      'a same-iPhone restore brings the PIN back too (ThisDeviceOnly): with no '
      'journal, the lock is off and the first-run screens open',
      (tester) async {
        // The restored prefs, in the real store: the lock's first-run
        // marker among them.
        SharedPreferences.setMockInitialValues({
          'app_lock.installed': true,
          'device.welcome_seen': true,
          'device.account_on_device': true,
        });
        // The keychain, as a restore to the same iPhone brings it back.
        final keychain = MemorySecretStore();
        final before = AppLock(
          store: keychain,
          biometrics: FakeBiometrics(),
          firstRun: const PrefsFirstRunMarker(),
          iterations: 50,
        );
        await tester.runAsync(() => before.setPin('2468'));
        expect(before.enabled, isTrue);

        // main.dart's order: the prefs, forgotten with no journal; then the
        // lock loads.
        final prefs = (await tester.runAsync(SharedLocalPrefs.load))!;
        await tester.runAsync(
          () => forgetPrefsWithoutJournal(
            journalMissing: true,
            prefs: prefs,
            platform: TargetPlatform.iOS,
          ),
        );
        final lock = AppLock(
          store: keychain,
          biometrics: FakeBiometrics(),
          firstRun: const PrefsFirstRunMarker(),
          iterations: 50,
        );
        await tester.runAsync(lock.load);
        expect(
          lock.enabled,
          isFalse,
          reason: 'its first-run marker went with the prefs: the old PIN is cleared',
        );

        final app = TestApp(onboarded: false, appLock: lock);
        await tester.runAsync(app.openJournal);
        await app.pump(tester);
        await tester.pumpAndSettle();
        tester.expectScreen('onb-welcome');
        expect(byId('lock-screen'), findsNothing);
      },
    );
  });

  test(
    "readAndroidSdk() is still null on an iPhone (the method isn't there)",
    () async {
      iPhoneAnswers();
      expect(await readAndroidSdk(), isNull);
      expect(calls.single.method, androidSdkMethod);
    },
  );

  test(
    'AppDelegate.swift: the same names, the flag on the folder, the iOS 16 '
    'settings URL, and nothing else answered',
    () {
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(swift, contains('settingsChannel = "$settingsChannel"'));
      expect(
        swift,
        contains('openNotificationSettings = "$openNotificationSettingsMethod"'),
      );
      expect(swift, contains('excludeFromBackup = "$excludeFromBackupMethod"'));
      expect(swift, contains('URL(fileURLWithPath: path, isDirectory: true)'));
      expect(swift, contains('values.isExcludedFromBackup = true'));
      expect(swift, contains('try url.setResourceValues(values)'));
      expect(swift, contains('if #available(iOS 16, *)'));
      expect(swift, contains('UIApplication.openNotificationSettingsURLString'));
      expect(swift, contains('UIApplication.openSettingsURLString'));
      // androidSdk, updateWidget and the rest: not implemented on an iPhone.
      expect(RegExp(r'case AppDelegate\.').allMatches(swift), hasLength(2));
      expect(swift, contains('result(FlutterMethodNotImplemented)'));
    },
  );
}
