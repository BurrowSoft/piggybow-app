import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services.dart';
import '../../data/models.dart' show ReminderTime;
import '../../export/csv_export.dart';
import '../../session/app_session.dart';

/// The folders in the app's own cache that hold export files: ours, and the
/// one share_plus copies a file into for the share sheet.
const _exportFolders = ['export', 'share_plus'];

/// Removes every export file left in the cache (at each start, and as part
/// of Delete everything): an export lives only while it's being shared.
Future<void> sweepExports({Future<Directory> Function()? cache}) async {
  final root = await (cache ?? getTemporaryDirectory)();
  for (final name in _exportFolders) {
    final folder = Directory('${root.path}/$name');
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}

/// The journal as a CSV (plan §3.8, csv_export.dart): oldest first, a save
/// to a goal names it.
Future<String> journalCsv(AppServices services) async {
  final store = services.journal;
  final goals = {for (final g in await store.goals()) g.id: g.name};
  final entries = await store.entries();
  return buildCsv([
    for (final e in entries.reversed)
      CsvRow(
        localDate: e.localDate,
        type: e.type.id,
        amountMinor: e.amountMinor,
        currency: e.currency,
        category: e.category?.id,
        feeling: e.feeling?.id,
        note: e.note,
        goalName: e.goalId == null ? null : goals[e.goalId],
      ),
  ]);
}

/// Me → Export my data: the file piggybow-YYYY-MM-DD.csv (UTF-8 with a BOM)
/// goes through the share sheet, with nothing else in the share (no subject,
/// no text), and is deleted once the sheet returns. On an iPad the sheet will
/// need an origin rect (sharePositionOrigin) when iOS ships.
Future<void> exportJournal(
  AppServices services, {
  Future<Directory> Function()? cache,
  Future<void> Function(XFile file)? share,
}) async {
  final root = await (cache ?? getTemporaryDirectory)();
  final folder = Directory('${root.path}/export');
  await folder.create(recursive: true);
  final file = File(
    '${folder.path}/${csvFileName(services.localDay.today)}',
  );
  await file.writeAsString(await journalCsv(services));
  try {
    final xfile = XFile(file.path, mimeType: 'text/csv');
    await (share ?? _shareSheet)(xfile);
  } finally {
    if (await file.exists()) await file.delete();
  }
}

Future<void> _shareSheet(XFile file) =>
    SharePlus.instance.share(ShareParams(files: [file]));

/// Me → Delete all my data (plan §3.8, the §4.7 wipe list): the journal
/// (entries, goals, picks, plan, currency and the onboarding flag), the
/// scheduled reminders and the reminder setting, the app lock's PIN (only
/// after the journal is gone), the appearance, and every export file. Then
/// onboarding shows again, from O1. Crash reports keep no cache while the
/// build has no Sentry DSN (v0.1).
Future<void> deleteEverything(
  AppServices services,
  AppSession session, {
  Future<Directory> Function()? cache,
}) async {
  await services.journal.wipe();
  await services.reminders.cancelAll();
  await session.updateReminder(on: false, time: ReminderTime.defaultTime);
  final lock = services.appLock;
  final userId = session.user?.id;
  if (lock != null && userId != null) await lock.forget(userId);
  await session.setThemeMode(ThemeMode.system);
  try {
    await sweepExports(cache: cache);
  } on Object {
    // No cache to sweep (no file was ever exported): the wipe goes on.
  }
  services.onboarded.value = false;
}
