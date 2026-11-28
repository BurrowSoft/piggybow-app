import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart';

import 'device.dart' show settingsChannel;
import 'local_prefs.dart';

/// The settings channel's method that AppDelegate.swift answers on an
/// iPhone: its argument, a folder, is kept out of every backup.
const excludeFromBackupMethod = 'excludeFromBackup';

/// iPhone (decision 72, I-1(b)): keeps [folder] and everything in it out of
/// the iPhone's backups: iCloud Backup and a Mac's. Whether a Quick Start
/// transfer skips it too is checked on two iPhones (a tester row).
/// AppDelegate.swift sets the flag (`isExcludedFromBackup`) on the folder
/// itself, so a file in it that's rewritten or replaced stays out too. True
/// once the flag is set; false when it couldn't be (no such method: Android,
/// whose backup rules do this; or an error). The journal opens either way:
/// it stays on the phone.
Future<bool> excludeFromBackup(String folder) async {
  try {
    return await const MethodChannel(
          settingsChannel,
        ).invokeMethod<bool>(excludeFromBackupMethod, folder) ??
        false;
  } on Object {
    return false;
  }
}

/// iPhone (decision 72, I-1(b)): the journal is in no backup, but the prefs
/// are. So a start with no journal file (a first start, or one after a
/// restore or a transfer) forgets whatever prefs came back with it, before
/// anything reads them. Otherwise Piggybow would open "set up already" over
/// an empty journal: onboarding skipped, and no currency, picks or plan.
/// True when it forgot them.
Future<bool> forgetPrefsWithoutJournal({
  required bool journalMissing,
  required LocalPrefs prefs,
  required TargetPlatform platform,
}) async {
  if (platform != TargetPlatform.iOS || !journalMissing) return false;
  await prefs.clear();
  return true;
}
