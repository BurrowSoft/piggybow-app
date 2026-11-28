import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';

import 'app_lock_test.dart' show FakeBiometrics;

/// A restore (decisions 17 and 65): the phone's backup brings the settings,
/// never the PIN. "On" with no PIN is a restore: the lock is off, and Me's
/// row says so until it's opened. A PIN alone decides the lock.
void main() {
  late MemorySecretStore store;
  late MemoryLockMirror mirror;
  AppLock make() => AppLock(
    store: store,
    biometrics: FakeBiometrics(),
    firstRun: MemoryFirstRunMarker(),
    mirror: mirror,
    iterations: 50,
  );

  setUp(() {
    store = MemorySecretStore();
    mirror = MemoryLockMirror();
  });

  test('setting a PIN turns the mirror on; clearing turns it off', () async {
    final lock = make();
    await lock.load();
    await lock.setPin('2468');
    expect(mirror.on, isTrue);
    await lock.clear();
    expect(mirror.on, isFalse);
  });

  test('"on" with no PIN is a restore: off, with the notice', () async {
    mirror.on = true;
    final lock = make();
    await lock.load();
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
    expect(lock.restoreNoticePending, isTrue);
    expect(mirror.on, isFalse, reason: 'the setting follows the lock');
    expect(mirror.notice, isTrue, reason: 'kept until the row is opened');
  });

  test('the notice stays until the row is opened', () async {
    mirror.on = true;
    await make().load();
    final again = make();
    await again.load();
    expect(again.restoreNoticePending, isTrue, reason: 'the next start');
    await again.dismissRestoreNotice();
    expect(again.restoreNoticePending, isFalse);
    expect(mirror.notice, isFalse);
    final later = make();
    await later.load();
    expect(later.restoreNoticePending, isFalse);
  });

  test('a PIN keeps the lock on, whatever the setting says', () async {
    final first = make();
    await first.load();
    await first.setPin('2468');
    mirror.on = false; // a write that failed, say
    final lock = make();
    await lock.load();
    expect(lock.enabled, isTrue);
    expect(lock.locked, isTrue);
    expect(lock.restoreNoticePending, isFalse);
    expect(mirror.on, isTrue, reason: 'set again');
  });

  test('turning the lock on again answers the notice', () async {
    mirror.on = true;
    final lock = make();
    await lock.load();
    await lock.setPin('1357');
    expect(lock.restoreNoticePending, isFalse);
    expect(mirror.notice, isFalse);
    expect(mirror.on, isTrue);
  });

  test('Delete everything resets the setting and the notice', () async {
    mirror.on = true;
    final lock = make();
    await lock.load();
    await lock.eraseAll();
    expect(mirror.on, isFalse);
    expect(mirror.notice, isFalse);
    expect(lock.restoreNoticePending, isFalse);
  });
}
