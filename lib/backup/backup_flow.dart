// Feature 21, the backup file's two flows without their screens
// (backup_screens.dart): back up (the journal sealed into a file, handed to
// the share sheet alone) and restore (a file read and checked whole, then
// the journal replaced in one go and the settings that travel applied).
//
// Sealing and opening run off the UI's isolate: Argon2id takes a moment on a
// phone, and the screen keeps moving meanwhile. They use the cryptography
// package's own Dart code there, the same on every phone.

import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart' as picker;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/services.dart';
import '../data/models.dart' show ReminderTime;
import '../journal/journal_store.dart';
import '../session/app_session.dart';
import '../theme/palettes.dart';
import 'backup_file.dart';
import 'backup_snapshot.dart';

/// The shortest password a backup takes: length only, no rules about what
/// it holds, pasting allowed (NIST 800-63B).
const backupMinPassword = 8;

/// piggybow-backup-2026-11-28.piggybow, on the phone's own day.
String backupFileName(DateTime localToday) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'piggybow-backup-${localToday.year.toString().padLeft(4, '0')}-'
      '${two(localToday.month)}-${two(localToday.day)}.piggybow';
}

/// What the backup flows reach outside the app: the crypto, the file picker,
/// the share sheet and the cache folder. Tests swap them ([current]).
class BackupHooks {
  const BackupHooks({
    this.seal = _sealInIsolate,
    this.open = _openInIsolate,
    this.pickFile = _pickFile,
    this.share = _shareSheet,
    this.cache = getTemporaryDirectory,
  });

  /// What the screens use; a test sets its own and puts this back.
  @visibleForTesting
  static BackupHooks current = const BackupHooks();

  final Future<String> Function(Object? data, String password) seal;
  final Future<Object?> Function(String file, String password) open;

  /// The file the person picks, its name and its text, or null if they
  /// picked none. [NotABackup] for one too large to be a backup.
  final Future<({String name, String text})?> Function() pickFile;

  final Future<void> Function(XFile file) share;
  final Future<Directory> Function() cache;
}

Future<String> _sealInIsolate(Object? data, String password) =>
    Isolate.run(() => sealBackup(data, password));

Future<Object?> _openInIsolate(String file, String password) =>
    Isolate.run(() => openBackup(file, password));

/// Android's own document picker: no storage permission. Any file, since a
/// .piggybow file has no registered type; a wrong one says so after.
Future<({String name, String text})?> _pickFile() async {
  final file = await picker.openFile();
  if (file == null) return null;
  if (await file.length() > backupMaxBytes) throw const NotABackup();
  try {
    return (name: file.name, text: await file.readAsString());
  } on FormatException {
    throw const NotABackup();
  }
}

Future<void> _shareSheet(XFile file) =>
    SharePlus.instance.share(ShareParams(files: [file]));

/// Me → Back up to a file: the journal and the settings that travel, sealed
/// with [password], as piggybow-backup-YYYY-MM-DD.piggybow through the share
/// sheet with nothing else in the share. The file is deleted once the sheet
/// returns (and swept at each start, with the CSV's: me_actions.dart).
Future<void> backUpToFile(
  AppServices services,
  AppSession session,
  String password, {
  BackupHooks? hooks,
}) async {
  final use = hooks ?? BackupHooks.current;
  final account = session.accountState;
  final backup = BackupSnapshot(
    journal: await services.journal.snapshot(),
    prefs: PrefsSnapshot.take(
      session.prefs,
      reminderOn: account?.reminderOn ?? false,
      reminderTime: account?.reminderTime ?? ReminderTime.defaultTime,
    ),
  );
  final sealed = await use.seal(backup.toJson(), password);
  final root = await use.cache();
  final folder = Directory('${root.path}/export');
  await folder.create(recursive: true);
  final file = File(
    '${folder.path}/${backupFileName(services.localDay.today)}',
  );
  await file.writeAsString(sealed);
  try {
    await use.share(XFile(file.path, mimeType: 'application/octet-stream'));
  } finally {
    if (await file.exists()) await file.delete();
  }
}

/// A backup file's [text], opened with [password] and checked whole: what a
/// restore would write, before anything is touched. A [BackupException]
/// otherwise: [BackupWontOpen], [NotABackup] (content the journal would
/// refuse included) or [BackupTooNew].
Future<BackupSnapshot> readBackup(
  String text,
  String password, {
  BackupHooks? hooks,
}) async {
  final use = hooks ?? BackupHooks.current;
  final backup = BackupSnapshot.fromJson(await use.open(text, password));
  try {
    return BackupSnapshot(
      journal: JournalStore.checkSnapshot(backup.journal),
      prefs: backup.prefs,
    );
  } on FormatException {
    throw const NotABackup();
  }
}

/// Replaces the journal with [backup]'s (one transaction: all of it or none)
/// and applies the settings that travel: a language this build offers, a
/// known appearance and theme, and the reminder's time, with the reminder
/// off. The app lock stays as it is. Onboarding is the screen's to settle.
Future<void> restoreBackup(
  AppServices services,
  AppSession session,
  BackupSnapshot backup,
) async {
  await services.journal.replaceWith(backup.journal);
  final prefs = backup.prefs;

  // The rest is the person's setup, not their journal: a step that fails
  // keeps this phone's setting and never undoes the restore.
  Future<void> step(Future<void> Function() run) async {
    try {
      await run();
    } on Object {
      // Kept as it was on this phone.
    }
  }

  final locale = prefs.localeCode;
  if (locale != null && session.shippedLocales.contains(locale)) {
    await step(() => session.updateRegion(locale: locale));
  }
  final mode = switch (prefs.appearance) {
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => null,
  };
  if (mode != null) await step(() => session.setThemeMode(mode));
  final stored = prefs.palette;
  final palette = storedPaletteName(stored);
  final at = stored?.indexOf('@') ?? -1;
  final until = at < 0 ? null : DateTime.tryParse(stored!.substring(at + 1));
  if (palette != null && until != null) {
    await step(() => session.setPalette(palette, until));
  }
  final reminder = prefs.restoredReminder;
  await step(
    () => session.updateReminder(on: reminder.on, time: reminder.time),
  );
}
