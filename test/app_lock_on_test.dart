import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/app_lock.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// The app lock is in v0.1 (plan P12, decision 70): on in every build,
/// staging and prod, debug and release, so Me always offers it.
void main() {
  test('every env file leaves the app lock on', () {
    final files = Directory('env')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(3), reason: 'dev, staging, prod');
    for (final file in files) {
      final env = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final value = env['APP_LOCK_ENABLED'];
      expect(
        value == null || value == 'true',
        isTrue,
        reason: '${file.path}: APP_LOCK_ENABLED is $value',
      );
    }
  });

  test('a build that sets nothing has the lock: the default is on', () {
    // These tests run with no --dart-define, as a build without the key.
    expect(AppConfig.fromEnvironment().appLockEnabled, isTrue);
    expect(const AppConfig(flavor: Flavor.prod).appLockEnabled, isTrue);
  });

  for (final on in [false, true]) {
    testWidgets("a prod build's Me: the App lock row, ${on ? 'On' : 'Off'}", (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final lock = AppLock(
        store: MemorySecretStore(),
        biometrics: FakeBiometrics(),
        firstRun: MemoryFirstRunMarker(),
        iterations: 50,
      );
      if (on) await tester.runAsync(() => lock.setPin('2468'));
      final app = TestApp(
        config: const AppConfig(flavor: Flavor.prod),
        appLock: lock,
      );
      await tester.runAsync(app.openJournal);
      await app.pump(tester, location: '/me');
      for (var i = 0; i < 40 && byId('me-lock').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(byId('me-lock'), findsOneWidget);
      expect(
        find.descendant(of: byId('me-lock'), matching: find.text('App lock')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byId('me-lock'),
          matching: find.text(on ? 'On' : 'Off'),
        ),
        findsOneWidget,
      );
    });
  }
}
