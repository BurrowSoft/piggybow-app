import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services.dart';
import '../../data/device_backend.dart';
import '../../export/csv_export.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
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
/// to a goal names it, a spend's category has its name beside its id (a
/// built-in's in [l10n]'s language, the app's; English when none is given).
Future<String> journalCsv(
  AppServices services, {
  AppLocalizations? l10n,
}) async {
  final store = services.journal;
  final words = l10n ?? lookupAppLocalizations(const Locale('en'));
  final goals = {for (final g in await store.goals()) g.id: g.name};
  final customs = {for (final c in await store.customCategories()) c.id: c};
  final entries = await store.entries();
  return buildCsv([
    for (final e in entries.reversed)
      CsvRow(
        localDate: e.localDate,
        type: e.type.id,
        amountMinor: e.amountMinor,
        currency: e.currency,
        category: e.categoryId,
        categoryName: switch (e.categoryId) {
          final id? => categoryName(words, id, customs),
          null => null,
        },
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
  AppLocalizations? l10n,
  Future<Directory> Function()? cache,
  Future<void> Function(XFile file)? share,
}) async {
  final root = await (cache ?? getTemporaryDirectory)();
  final folder = Directory('${root.path}/export');
  await folder.create(recursive: true);
  final file = File(
    '${folder.path}/${csvFileName(services.localDay.today)}',
  );
  await file.writeAsString(await journalCsv(services, l10n: l10n));
  try {
    final xfile = XFile(file.path, mimeType: 'text/csv');
    await (share ?? _shareSheet)(xfile);
  } finally {
    if (await file.exists()) await file.delete();
  }
}

Future<void> _shareSheet(XFile file) =>
    SharePlus.instance.share(ShareParams(files: [file]));

/// Me → Delete all my data (plan §3.8, the §4.7 wipe list, decision 67):
/// the journal; the scheduled reminders; the app lock's secure storage,
/// every id (only after the journal is gone); every pref (the device
/// account, its reminder, language, appearance and the rest); every export
/// file; Plus's launch hint (the store's own record of a subscription stays:
/// erasing the app never cancels it); pig tips' anonymous id, deleted on the
/// server now or, with no connection, at a later start. Then a fresh device
/// account, and
/// onboarding from O1. The lock, the
/// prefs and the account go only after the journal did; the other steps run
/// even if one fails; false when any did (Me says so and offers Try again).
/// Crash reports keep no cache while the build has no Sentry DSN (v0.1).
Future<bool> deleteEverything(
  AppServices services,
  AppSession session, {
  Future<Directory> Function()? cache,
}) async {
  var done = true;
  Future<bool> step(Future<void> Function() run) async {
    try {
      await run();
      return true;
    } on Object catch (error, stack) {
      done = false;
      // The person sees "Not everything was erased"; a debug build or a
      // test also says which step and why (never a release build).
      assert(() {
        debugPrint('Delete everything: a step failed: $error\n$stack');
        return true;
      }());
      return false;
    }
  }

  // The journal first. Only once it is gone do the lock, the prefs and the
  // account go: a journal still on the phone keeps its PIN and its account,
  // so this wipe (which Forgot PIN's erase reuses) is never a way past the
  // lock (decision 67, amended).
  // Pig tips first: off, and the anonymous id deleted on the server (its
  // reports first). With no connection, that delete is kept through the
  // erase below and sent at a later start.
  String? tipsDelete;
  await step(() async => tipsDelete = await services.pigTips?.eraseBegin());
  final journalGone = await step(services.journal.wipe);
  await step(services.reminders.cancelAll);
  await step(() => sweepExports(cache: cache));
  await step(() async => services.plus?.forget());
  if (!journalGone) return false;
  await step(() async => services.appLock?.eraseAll());
  await step(() async => services.pigTips?.eraseEnd(tipsDelete));
  await step(session.prefs.clear);
  await step(() async {
    final backend = session.account;
    if (backend is DeviceBackend) {
      await backend.startOver(
        timeZone: services.localDay.zone,
        country: session.device.countryCode,
      );
    }
    await session.reloadAccount();
  });
  if (done) services.onboarded.value = false;
  return done;
}
