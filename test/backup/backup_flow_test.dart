import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';
import 'package:piggybow/backup/backup_flow.dart';
import 'package:piggybow/backup/backup_snapshot.dart';
import 'package:piggybow/data/models.dart' show ReminderTime;
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/theme/palettes.dart';
import 'package:share_plus/share_plus.dart' show XFile;

import '../helpers.dart';

/// Feature 21's two flows without their screens: a backup goes to the share
/// sheet alone, sealed, and is deleted after; a restore replaces the journal
/// and applies only the settings this build knows, with the reminder off; a
/// file that can't restore says why before anything is touched.
void main() {
  const fast = BackupKdf(memoryKiB: 64, iterations: 1, parallelism: 1);
  final direct = BackupHooks(
    seal: (data, password) => sealBackup(data, password, kdf: fast),
    open: openBackup,
  );
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('pb_backup'));
  tearDown(() => cache.deleteSync(recursive: true));

  /// This phone: one spend with a Thai note, in English, Thai offered too.
  Future<TestApp> start(WidgetTester tester) async {
    final app = TestApp(shippedLocales: const ['en', 'th'], chosenLocale: 'en');
    await tester.runAsync(app.openJournal);
    await tester.runAsync(
      () => app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 4500,
        currency: 'THB',
        localDate: '2026-10-01',
        category: SpendCategory.food,
        note: 'ข้าวมันไก่',
      ),
    );
    await app.pump(tester);
    return app;
  }

  /// A backup from another phone: one euro spend, Thai, dark, a theme, and
  /// the reminder on at 21:30.
  Future<BackupSnapshot> fromAnotherPhone(
    WidgetTester tester, {
    String? locale = 'th',
    String? appearance = 'dark',
    String? palette = 'sea@2099-01-01T00:00:00.000Z',
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
    return BackupSnapshot(
      journal: journal,
      prefs: PrefsSnapshot(
        localeCode: locale,
        appearance: appearance,
        palette: palette,
        reminderTime: const ReminderTime(21, 30),
        reminderWasOn: true,
      ),
    );
  }

  testWidgets('a backup goes to the share sheet alone, sealed, and is deleted '
      'after', (tester) async {
    final app = await start(tester);
    String? name;
    String? path;
    String? text;
    await tester.runAsync(
      () => backUpToFile(
        app.services,
        app.session,
        'correct horse',
        hooks: BackupHooks(
          seal: direct.seal,
          cache: () async => cache,
          share: (XFile file) async {
            name = file.name;
            path = file.path;
            text = await File(file.path).readAsString();
          },
        ),
      ),
    );
    // The phone's own day (tests run on Friday 2 October 2026 in Bangkok).
    expect(name, 'piggybow-backup-2026-10-02.piggybow');
    expect(backupFileName(DateTime(2026, 1, 5)), 'piggybow-backup-2026-01-05.piggybow');
    expect(File(path!).existsSync(), isFalse, reason: 'deleted after the sheet');
    expect(text, isNot(contains('ข้าวมันไก่')), reason: 'nothing in the clear');

    final back = (await tester.runAsync(
      () => readBackup(text!, 'correct horse', hooks: direct),
    ))!;
    expect(back.journal.entries.values.single['note'], 'ข้าวมันไก่');
    expect(back.journal.settings['currency'], 'THB');
    expect(back.prefs.localeCode, 'en');
  });

  testWidgets('a restore replaces the journal and applies the settings that '
      'travel, with the reminder off', (tester) async {
    final app = await start(tester);
    await tester.runAsync(
      () => app.session.updateReminder(on: true, time: const ReminderTime(8, 0)),
    );
    final backup = await fromAnotherPhone(tester);
    await tester.runAsync(
      () => restoreBackup(app.services, app.session, backup),
    );
    final entries = (await tester.runAsync(app.journal.entries))!;
    expect([for (final e in entries) e.note], ['Bus']);
    expect(await tester.runAsync(app.journal.currency), 'EUR');
    expect(app.session.locale.languageCode, 'th');
    expect(app.session.themeMode, ThemeMode.dark);
    expect(app.session.chosenPalette, PlusPalette.sea);
    expect(app.session.accountState!.reminderOn, isFalse);
    expect(app.session.accountState!.reminderTime.wire, '21:30');
  });

  testWidgets('a language this build doesn\'t offer, or a look it doesn\'t '
      'know, is left as it is', (tester) async {
    final app = await start(tester);
    final backup = await fromAnotherPhone(
      tester,
      locale: 'xx',
      appearance: 'purple',
      palette: 'plaid@2099-01-01T00:00:00.000Z',
    );
    await tester.runAsync(
      () => restoreBackup(app.services, app.session, backup),
    );
    expect(app.session.locale.languageCode, 'en');
    expect(app.session.themeMode, ThemeMode.system);
    expect(app.session.chosenPalette, isNull);
  });

  testWidgets('a file that can\'t restore says why, before anything is '
      'touched', (tester) async {
    final app = await start(tester);
    final good = (await fromAnotherPhone(tester)).toJson();

    Future<String> sealed(Map<String, Object?> json) async =>
        (await tester.runAsync(
          () => sealBackup(json, 'correct horse', kdf: fast),
        ))!;

    Future<Object?> outcome(String text, String password) =>
        tester.runAsync<Object?>(() async {
          try {
            await readBackup(text, password, hooks: direct);
            return null;
          } on Object catch (error) {
            return error;
          }
        });

    Map<String, Object?> edited(void Function(Map<String, dynamic>) change) {
      final copy = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
      change(copy);
      return copy;
    }

    final file = await sealed(good);
    expect(await outcome(file, 'correct horse'), isNull);
    expect(await outcome(file, 'wrong horse'), isA<BackupWontOpen>());
    expect(await outcome('hello', 'correct horse'), isA<NotABackup>());
    // Content the journal would refuse: a currency this build doesn't list.
    final unlisted = await sealed(
      edited((m) {
        final entries = m['journal']['entries'] as Map<String, dynamic>;
        (entries.values.first as Map<String, dynamic>)['currency'] = 'XYZ';
      }),
    );
    expect(await outcome(unlisted, 'correct horse'), isA<NotABackup>());
    final newer = await sealed(
      edited((m) => m['schema'] = backupSchema + 1),
    );
    expect(await outcome(newer, 'correct horse'), isA<BackupTooNew>());

    final entries = (await tester.runAsync(app.journal.entries))!;
    expect([for (final e in entries) e.note], ['ข้าวมันไก่']);
  });
}
