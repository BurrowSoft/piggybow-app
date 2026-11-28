import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';
import 'package:piggybow/backup/backup_flow.dart';
import 'package:piggybow/backup/backup_snapshot.dart';
import 'package:piggybow/data/models.dart' show ReminderTime;
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/journal_store.dart';

import '../helpers.dart';

/// The backup screens' outside world for a widget test (BackupHooks): a
/// stand-in "sealed" file (the password beside the data, checked on opening
/// as the real tag is), a picker that returns [picked] or throws
/// [pickError], a share sheet that records each file's name, and a real
/// cache folder. The real crypto is backup_flow_test's.
class FakeBackup {
  FakeBackup() : cache = Directory.systemTemp.createTempSync('pb_backup');

  final Directory cache;
  final shared = <String>[];
  ({String name, String text})? picked;
  Object? pickError;

  void install() {
    BackupHooks.current = BackupHooks(
      seal: (data, password) async =>
          jsonEncode({'password': password, 'data': data}),
      open: (text, password) async {
        final Object? file;
        try {
          file = jsonDecode(text);
        } on FormatException {
          throw const NotABackup();
        }
        if (file is! Map || file['password'] == null) throw const NotABackup();
        if (file['password'] != password) throw const BackupWontOpen();
        return file['data'];
      },
      pickFile: () async {
        if (pickError case final error?) throw error;
        return picked;
      },
      share: (file) async => shared.add(file.name),
      cache: () async => cache,
    );
    addTearDown(() {
      BackupHooks.current = const BackupHooks();
      cache.deleteSync(recursive: true);
    });
  }

  /// A file from another phone, sealed with "correct horse": one bus ride in
  /// euros, the reminder at 21:30, on unless [reminderOn] says otherwise.
  Future<String> file(
    WidgetTester tester, {
    int schema = backupSchema,
    bool reminderOn = true,
  }) async {
    final journal = (await tester.runAsync(() async {
      final other = await JournalStore.inMemory(clock: testClock);
      await other.setCurrency('EUR');
      await other.setOnboarded();
      await other.addEntry(
        type: EntryType.spent,
        amountMinor: 1234,
        currency: 'EUR',
        localDate: '2026-09-30',
        category: SpendCategory.transport,
        note: 'Bus',
      );
      final snapshot = await other.snapshot();
      await other.close();
      return snapshot;
    }))!;
    final data = BackupSnapshot(
      journal: journal,
      prefs: PrefsSnapshot(
        localeCode: null,
        appearance: null,
        palette: null,
        reminderTime: const ReminderTime(21, 30),
        reminderWasOn: reminderOn,
      ),
    ).toJson();
    return jsonEncode({
      'password': 'correct horse',
      'data': {...data, 'schema': schema},
    });
  }
}
