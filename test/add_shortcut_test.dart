import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/core/device.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/entry.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// The home-screen shortcut, "Add a spend" (Android): the app opens on Home
/// with the Add sheet on Spent, once per use; with the lock on, the lock
/// screen comes first. And the Android side: each flavour's shortcut opens its
/// own app, with the action and the names MainActivity and Flutter share.
void main() {
  EntryType sheetStart(WidgetTester tester) => tester.widget<EntrySheet>(find.byType(EntrySheet)).start;

  group('the shortcut, used', () {
    testWidgets('from another tab: Home, with the Add sheet on Spent', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      await tester.tapId('tab-me');
      tester.expectScreen('me-screen');
      app.launchActions.use();
      await tester.pumpAndSettle();
      expect(find.byType(EntrySheet), findsOneWidget);
      expect(sheetStart(tester), EntryType.spent);
      tester.expectScreen('home-screen');
    });

    testWidgets('to start the app: the sheet once the tabs are up', (tester) async {
      final app = TestApp();
      app.launchActions.use();
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(find.byType(EntrySheet), findsOneWidget);
      expect(sheetStart(tester), EntryType.spent);
    });

    testWidgets('once per use, and none over a sheet already up', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.launchActions.use();
      await tester.pumpAndSettle();
      app.launchActions.use();
      await tester.pumpAndSettle();
      expect(find.byType(EntrySheet), findsOneWidget);
      expect(app.launchActions.addSpendPending.value, isFalse, reason: 'answered');
    });

    testWidgets('with the lock on: the lock screen first, then the sheet', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final lock = AppLock(
        store: MemorySecretStore(),
        biometrics: FakeBiometrics()..has = false,
        firstRun: MemoryFirstRunMarker(),
        iterations: 50,
      );
      await tester.runAsync(() => lock.setPin('2468'));
      lock.lockNow();
      final app = TestApp(appLock: lock);
      app.launchActions.use();
      await app.pump(tester);
      for (var i = 0; i < 100 && byId('lock-screen').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      tester.expectScreen('lock-screen');

      for (final digit in '2468'.split('')) {
        await tester.tap(byId('pin-key-$digit'));
        await tester.pump();
      }
      await tester.tap(byId('pin-key-ok'));
      await tester.pumpAndSettle();

      expect(byId('lock-screen'), findsNothing);
      expect(find.byType(EntrySheet), findsOneWidget);
      expect(sheetStart(tester), EntryType.spent);
    });
  });

  group('Android: the static shortcut', () {
    final kotlin = File('android/app/src/main/kotlin/com/burrowsoft/piggybow/MainActivity.kt').readAsStringSync();

    test('MainActivity and Flutter use the same names', () {
      expect(kotlin, contains('TAKE_LAUNCH_ACTION = "$takeLaunchActionMethod"'));
      expect(kotlin, contains('LAUNCH_ACTION = "$launchActionMethod"'));
      expect(kotlin, contains('ADD_SPEND = "$addSpendAction"'));
    });

    test("each flavour's shortcut opens its own app, with MainActivity's action", () {
      final action = RegExp(r'ACTION_ADD_SPEND = "([^"]+)"').firstMatch(kotlin)![1]!;
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.burrowsoft.piggybow"'));
      expect(gradle, contains('applicationIdSuffix = ".dev"'));
      expect(gradle, contains('applicationIdSuffix = ".staging"'));
      const packages = {
        'main': 'com.burrowsoft.piggybow',
        'dev': 'com.burrowsoft.piggybow.dev',
        'staging': 'com.burrowsoft.piggybow.staging',
      };
      packages.forEach((set, package) {
        final xml = File('android/app/src/$set/res/xml/shortcuts.xml').readAsStringSync();
        expect(xml, contains('android:targetPackage="$package"'), reason: set);
        expect(xml, contains('android:targetClass="com.burrowsoft.piggybow.MainActivity"'), reason: set);
        expect(xml, contains('android:action="$action"'), reason: set);
        expect(xml, contains('android:icon="@drawable/ic_shortcut_add"'), reason: set);
        expect(xml, contains('android:shortcutShortLabel="@string/shortcut_add_short"'), reason: set);
        expect(xml, contains('android:shortcutLongLabel="@string/shortcut_add_long"'), reason: set);
      });
      expect(Directory('android/app/src/prod').existsSync(), isFalse, reason: "prod uses main's copy");
    });

    test('the launcher activity lists them, and they say "Add a spend"', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('<meta-data android:name="android.app.shortcuts" android:resource="@xml/shortcuts"/>'));
      final strings = File('android/app/src/main/res/values/strings.xml').readAsStringSync();
      expect(strings, contains('<string name="shortcut_add_long">Add a spend</string>'));
      expect(strings, contains('<string name="shortcut_add_short">Add</string>'));
      for (final icon in [
        'drawable/ic_shortcut_add.xml',
        'drawable-v26/ic_shortcut_add.xml',
        'drawable/ic_shortcut_add_foreground.xml',
      ]) {
        expect(File('android/app/src/main/res/$icon').existsSync(), isTrue, reason: icon);
      }
    });
  });
}
