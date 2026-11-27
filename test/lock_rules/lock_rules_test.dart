import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/lock_rules/lock_rules.dart';

void main() {
  group('the lock is on only when a PIN exists (§0.8)', () {
    test('every combination', () {
      expect(lockState(prefsLockOn: true, pinExists: true), LockState.on);
      expect(lockState(prefsLockOn: true, pinExists: false), LockState.offAfterRestore);
      expect(lockState(prefsLockOn: false, pinExists: false), LockState.off);
      expect(lockState(prefsLockOn: false, pinExists: true), LockState.off);
    });

    test('a restored phone (settings say on, secure storage empty) is never locked out', () {
      expect(lockState(prefsLockOn: true, pinExists: false), isNot(LockState.on));
    });
  });

  test('Me\'s App lock subtitle: On, Off, or the after-restore line until it\'s seen', () {
    expect(lockRowKey(lockOn: true, restoreNoticePending: false), 'meStateOn');
    expect(lockRowKey(lockOn: false, restoreNoticePending: false), 'meStateOff');
    expect(lockRowKey(lockOn: false, restoreNoticePending: true), 'lockOffAfterRestore');
    expect(lockRowKey(lockOn: true, restoreNoticePending: true), 'meStateOn', reason: 'once set again, it is simply on');
  });

  group('Forgot PIN (decision 19)', () {
    test('with a phone screen lock: that path first, erase second; without: erase only', () {
      expect(forgotPinPaths(deviceHasScreenLock: true), ForgotPinPaths.deviceThenErase);
      expect(forgotPinPaths(deviceHasScreenLock: false), ForgotPinPaths.eraseOnly);
    });

    test('the screen-lock path proves the owner, then sets a new PIN, and erases nothing', () {
      expect(deviceLockSteps, [ForgotPinStep.askDeviceLock, ForgotPinStep.setNewPin]);
      expect(deviceLockSteps, isNot(contains(ForgotPinStep.eraseJournal)));
      expect(deviceLockSteps, isNot(contains(ForgotPinStep.clearPin)));
    });

    test('the erase path confirms, erases the journal, and only then clears the PIN', () {
      expect(eraseSteps, [ForgotPinStep.confirmErase, ForgotPinStep.eraseJournal, ForgotPinStep.clearPin]);
      expect(eraseSteps.indexOf(ForgotPinStep.eraseJournal), lessThan(eraseSteps.indexOf(ForgotPinStep.clearPin)),
          reason: 'clearing the PIN before the journal is erased would be a way in');
      expect(eraseSteps.first, ForgotPinStep.confirmErase);
    });

    test('no path clears the PIN without erasing first, and none skips proving the owner to set a new one', () {
      for (final steps in [deviceLockSteps, eraseSteps]) {
        final clear = steps.indexOf(ForgotPinStep.clearPin);
        if (clear >= 0) expect(steps.sublist(0, clear), contains(ForgotPinStep.eraseJournal));
        final set = steps.indexOf(ForgotPinStep.setNewPin);
        if (set >= 0) expect(steps.sublist(0, set), contains(ForgotPinStep.askDeviceLock));
      }
    });
  });
}
