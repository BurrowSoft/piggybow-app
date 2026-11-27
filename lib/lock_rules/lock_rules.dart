// The app lock's rules (plan §0.8, §3.11, decision 19): when the lock is on, what a restore does to
// it, what Me's lock row says, and the Forgot PIN paths as ordered steps.

/// The lock is on only when a PIN exists in secure storage. Secure storage isn't backed up, so on a
/// restored phone the settings can say "on" with no PIN: that's [offAfterRestore]. The app then
/// turns the setting off and shows lockOffAfterRestore on the Me row until the row is opened.
enum LockState { off, on, offAfterRestore }

LockState lockState({required bool prefsLockOn, required bool pinExists}) {
  if (!prefsLockOn) return LockState.off;
  return pinExists ? LockState.on : LockState.offAfterRestore;
}

/// The ARB key for Me's App lock subtitle: "On", "Off", or the after-restore line while its notice
/// hasn't been seen.
String lockRowKey({required bool lockOn, required bool restoreNoticePending}) {
  if (lockOn) return 'meStateOn';
  return restoreNoticePending ? 'lockOffAfterRestore' : 'meStateOff';
}

/// What Forgot PIN offers. With a phone screen lock: that first, and erase as the secondary text
/// button. Without one: erase only.
enum ForgotPinPaths { deviceThenErase, eraseOnly }

ForgotPinPaths forgotPinPaths({required bool deviceHasScreenLock}) =>
    deviceHasScreenLock ? ForgotPinPaths.deviceThenErase : ForgotPinPaths.eraseOnly;

/// One step of a Forgot PIN path, run in order; the next step runs only if this one succeeds.
enum ForgotPinStep {
  /// The phone's own screen lock (fingerprint, face, or the phone's PIN or pattern).
  askDeviceLock,

  /// Choose a new Piggybow PIN, replacing the old one.
  setNewPin,

  /// The erase dialog, then its second confirmation (deleteAllTitle / deleteAllConfirm).
  confirmErase,

  /// The same wipe as Delete everything: the store, prefs, reminders, export files, caches.
  eraseJournal,

  /// Remove the PIN. Only ever after [eraseJournal]: clearing the lock without erasing the journal
  /// would let anyone in.
  clearPin,
}

/// The phone-screen-lock path: prove it's the phone's owner, then set a new PIN. Nothing is erased.
const List<ForgotPinStep> deviceLockSteps = [ForgotPinStep.askDeviceLock, ForgotPinStep.setNewPin];

/// The erase path: confirm twice, erase the journal, and only then clear the PIN.
const List<ForgotPinStep> eraseSteps = [
  ForgotPinStep.confirmErase,
  ForgotPinStep.eraseJournal,
  ForgotPinStep.clearPin,
];
