import 'package:flutter/services.dart';

import 'device.dart' show settingsChannel;

/// The settings channel's method that AppDelegate.swift answers on an
/// iPhone: its argument, a folder, is kept out of every backup.
const excludeFromBackupMethod = 'excludeFromBackup';

/// iPhone (decision 72, I-1(b)): keeps [folder] and everything in it out of
/// every backup the iPhone makes: iCloud Backup, a Mac's backup and, as far as
/// Apple documents, a Quick Start transfer. AppDelegate.swift sets the flag
/// (`isExcludedFromBackup`) on the folder itself, so a file in it that's
/// rewritten or replaced stays out too. True once the flag is set; false when
/// it couldn't be (no such method: Android, whose backup rules do this; or an
/// error). The journal opens either way: it stays on the phone.
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
