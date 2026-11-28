import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';
import 'package:piggybow/backup/backup_flow.dart';
import 'package:piggybow/backup/backup_snapshot.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/router.dart';

import 'helpers.dart';
import 'helpers/fake_backup.dart';

/// Feature 21's screens: Me's Your data, Back up (at least 8 characters,
/// typed twice, then the share sheet), and Restore from Me or the first
/// screen (empty: straight in; with notes: Replace or Cancel; each reason a
/// file can't restore, the password kept). The crypto is the flows' own
/// test's; here a stand-in "sealed" file keeps the screens fast.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late FakeBackup backup;

  setUp(() => (backup = FakeBackup()).install());

  Future<List<String>> notes(WidgetTester tester, TestApp app) async => [
    for (final e in (await tester.runAsync(app.journal.entries))!) e.note,
  ];

  /// Lets real file work finish (the cache folder runs on real time),
  /// pumping between, until [done].
  Future<void> settleIo(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String id) => tester
      .widget<TextField>(
        find.descendant(of: byId(id), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  testWidgets('Me: Your data holds the backup, its restore and the export', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester, location: '/me');
    for (final id in ['me-backup', 'me-restore', 'me-export']) {
      await tester.revealId(id);
      expect(byId(id), findsOneWidget, reason: id);
    }
    expect(find.text(l10n.meSecData), findsOneWidget);
    await tester.tapId('me-backup');
    tester.expectScreen('backup-screen');
  });

  testWidgets('a backup: at least 8 characters, typed twice, then the share '
      'sheet; the file is gone after', (tester) async {
    final app = TestApp();
    await app.pump(tester, location: MeRoutes.backup);
    tester.expectScreen('backup-screen');
    expect(byId('backup-no-recovery'), findsOneWidget);

    await tester.enterId('backup-password', 'short');
    await tester.enterId('backup-again', 'short');
    await tester.tapId('backup-go');
    expect(find.text(l10n.backupTooShort(backupMinPassword)), findsOneWidget);

    await tester.enterId('backup-password', 'correct horse');
    await tester.enterId('backup-again', 'correct horsf');
    await tester.tapId('backup-go');
    expect(find.text(l10n.backupMismatch), findsOneWidget);
    expect(backup.shared, isEmpty);

    await tester.enterId('backup-again', 'correct horse');
    await tester.tap(byId('backup-go'));
    await tester.pump();
    // Done once the screen closes: after the share sheet and the delete.
    await settleIo(tester, () => byId('backup-screen').evaluate().isEmpty);
    expect(backup.shared, ['piggybow-backup-2026-10-02.piggybow']);
    tester.expectScreen('me-screen');
    expect(
      Directory('${backup.cache.path}/export').listSync(),
      isEmpty,
      reason: 'deleted once the share sheet returned',
    );
  });

  testWidgets('on a new phone, from the first screen: straight in, then Home', (
    tester,
  ) async {
    final app = TestApp(onboarded: false);
    await app.pump(tester);
    tester.expectScreen('onb-welcome');
    backup.picked = (
      name: 'piggybow-backup-2026-09-30.piggybow',
      text: await backup.file(tester),
    );
    await tester.tapId('onb-restore');
    tester.expectScreen('restore-screen');
    await tester.tapId('restore-choose');
    expect(find.text('piggybow-backup-2026-09-30.piggybow'), findsOneWidget);
    await tester.enterId('restore-password', 'correct horse');
    await tester.tapId('restore-go');
    expect(
      byId('restore-replace-body'),
      findsNothing,
      reason: 'nothing to replace',
    );
    expect(byId('restore-done'), findsOneWidget);
    expect(find.text(l10n.restoreReminder), findsOneWidget);
    await tester.tapId('restore-finish');
    tester.expectScreen('home-screen');
    expect(app.services.onboarded.value, isTrue);
    expect(await notes(tester, app), ['Bus']);
  });

  testWidgets('over a journal with notes: Cancel keeps it, Replace replaces '
      'it', (tester) async {
    final app = TestApp();
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
    await app.pump(tester, location: MeRoutes.restore);
    backup.picked = (name: 'b.piggybow', text: await backup.file(tester));
    await tester.tapId('restore-choose');
    await tester.enterId('restore-password', 'correct horse');

    await tester.tapId('restore-go');
    expect(byId('restore-replace-body'), findsOneWidget);
    await tester.tapId('restore-replace-cancel');
    tester.expectScreen('restore-screen');
    expect(byId('restore-done'), findsNothing);
    expect(await notes(tester, app), ['ข้าวมันไก่']);

    await tester.tapId('restore-go');
    await tester.tapId('restore-replace');
    expect(byId('restore-done'), findsOneWidget);
    expect(await notes(tester, app), ['Bus']);
  });

  testWidgets('each reason a file can\'t restore, said kindly; the password '
      'stays', (tester) async {
    final app = TestApp();
    await app.pump(tester, location: MeRoutes.restore);

    // Nothing picked: still choosing.
    await tester.tapId('restore-choose');
    expect(byId('restore-file'), findsNothing);

    // Too large to be a backup: said before any password.
    backup.pickError = const NotABackup();
    await tester.tapId('restore-choose');
    expect(find.text(l10n.restoreNotBackup), findsOneWidget);
    backup.pickError = null;

    backup.picked = (name: 'b.piggybow', text: await backup.file(tester));
    await tester.tapId('restore-choose');
    await tester.enterId('restore-password', 'wrong horse');
    await tester.tapId('restore-go');
    expect(find.text(l10n.restoreWrongPassword), findsOneWidget);
    expect(fieldText(tester, 'restore-password'), 'wrong horse');

    backup.picked = (name: 'notes.txt', text: 'hello');
    await tester.tapId('restore-other');
    await tester.enterId('restore-password', 'correct horse');
    await tester.tapId('restore-go');
    expect(find.text(l10n.restoreNotBackup), findsOneWidget);

    backup.picked = (
      name: 'b.piggybow',
      text: await backup.file(tester, schema: backupSchema + 1),
    );
    await tester.tapId('restore-other');
    await tester.enterId('restore-password', 'correct horse');
    await tester.tapId('restore-go');
    expect(find.text(l10n.restoreTooNew), findsOneWidget);
    expect(byId('restore-done'), findsNothing);
    expect(await notes(tester, app), isEmpty, reason: 'nothing was touched');
  });
}
