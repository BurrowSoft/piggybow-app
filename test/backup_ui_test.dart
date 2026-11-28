import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/backup/backup_file.dart';
import 'package:piggybow/backup/backup_flow.dart';
import 'package:piggybow/backup/backup_snapshot.dart';
import 'package:piggybow/core/app_config.dart';
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
    // Real time for the file calls (a busy CI runner is slow), frames
    // between; up to 6 s.
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done(), isTrue, reason: 'the file work finished in time');
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
    // The section's title, over its rows: revealing them may have
    // scrolled it away.
    await tester.ensureVisible(find.text(l10n.meSecData, skipOffstage: false));
    await tester.pumpAndSettle();
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

  testWidgets('the share sheet dismissed: the screen stays, the password '
      'kept, nothing said, and the file gone', (tester) async {
    final app = TestApp();
    await app.pump(tester, location: MeRoutes.backup);
    backup.shareGoes = false;
    await tester.enterId('backup-password', 'correct horse');
    await tester.enterId('backup-again', 'correct horse');
    await tester.tap(byId('backup-go'));
    await tester.pump();
    // Done once the sheet was shown, the file deleted after it, and the
    // button no longer busy.
    final export = Directory('${backup.cache.path}/export');
    await settleIo(
      tester,
      () =>
          backup.shared.isNotEmpty &&
          export.existsSync() &&
          export.listSync().isEmpty &&
          find.text(l10n.backupAction).evaluate().isNotEmpty,
    );
    tester.expectScreen('backup-screen');
    expect(byId('backup-error'), findsNothing);
    expect(fieldText(tester, 'backup-password'), 'correct horse');
    expect(backup.shared, hasLength(1));
  });

  testWidgets('with the backup file off (BACKUP_FILE=false): no backup rows '
      'in Me, no "Moving from another phone?" on the first screen', (tester) async {
    const off = AppConfig(flavor: Flavor.prod, backupFileEnabled: false);
    final me = TestApp(config: off);
    await me.pump(tester, location: '/me');
    await tester.revealId('me-export');
    expect(byId('me-export'), findsOneWidget);
    expect(byId('me-backup'), findsNothing);
    expect(byId('me-restore'), findsNothing);

    final fresh = TestApp(config: off, onboarded: false);
    await fresh.pump(tester);
    tester.expectScreen('onb-welcome');
    expect(byId('onb-restore'), findsNothing);
  });

  // TalkBack: the eye is a node of its own, a focusable button that says
  // what it does, and acting on it shows the password. The field's own
  // node doesn't swallow it.
  testWidgets('the password eye is its own TalkBack node: "Show password", '
      'then "Hide password"', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = TestApp();
    await app.pump(tester, location: MeRoutes.backup);
    final eye = find.descendant(of: byId('backup-show'), matching: find.byType(IconButton));
    final field = find.descendant(of: byId('backup-password'), matching: find.byType(EditableText));
    expect(tester.getSemantics(eye).id, isNot(tester.getSemantics(field).id), reason: 'not folded into the field');
    expect(
      tester.getSemantics(eye),
      containsSemantics(tooltip: l10n.backupShowPassword, isButton: true, isFocusable: true, hasTapAction: true),
    );
    expect(tester.getSemantics(field).label, isNot(contains(l10n.backupShowPassword)));
    // What TalkBack's double tap does.
    tester.semantics.tap(find.semantics.byPredicate((n) => n.tooltip == l10n.backupShowPassword));
    await tester.pump();
    expect(
      tester.getSemantics(eye),
      containsSemantics(tooltip: l10n.backupHidePassword, isButton: true, isFocusable: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  test('backupTooShort is a plural: one character, or characters', () {
    expect(l10n.backupTooShort(1), 'Use at least 1 character.');
    expect(l10n.backupTooShort(8), 'Use at least 8 characters.');
  });

  // The store build has it: on unless BACKUP_FILE=false, which no env file
  // says (the release build takes env/prod.json and no other define,
  // release_pipeline_test).
  test('the store build has the backup file: on by default, and no env file '
      'turns it off', () {
    final source = File('lib/core/app_config.dart').readAsStringSync();
    expect(
      source,
      contains("backupFileEnabled: const bool.fromEnvironment('BACKUP_FILE', defaultValue: true),"),
    );
    expect(RegExp(r'backupFileEnabled:[^,]*kReleaseMode').hasMatch(source), isFalse);
    for (final name in ['dev', 'staging', 'prod']) {
      final env = jsonDecode(File('env/$name.json').readAsStringSync()) as Map<String, dynamic>;
      expect(env['BACKUP_FILE'] ?? 'true', 'true', reason: 'env/$name.json');
    }
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
    // The name as picked (it may break after its - and . on a narrow line).
    final shown = tester
        .widget<Text>(
          find.descendant(of: byId('restore-file'), matching: find.byType(Text)),
        )
        .data!
        .replaceAll(String.fromCharCode(0x200B), '');
    expect(shown, 'piggybow-backup-2026-09-30.piggybow');
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

  testWidgets('a backup with the reminder off: no reminder line', (
    tester,
  ) async {
    final app = TestApp(onboarded: false);
    await app.pump(tester);
    backup.picked = (
      name: 'b.piggybow',
      text: await backup.file(tester, reminderOn: false),
    );
    await tester.tapId('onb-restore');
    await tester.tapId('restore-choose');
    await tester.enterId('restore-password', 'correct horse');
    await tester.tapId('restore-go');
    expect(byId('restore-done'), findsOneWidget);
    expect(byId('restore-reminder'), findsNothing);
    expect(find.text(l10n.restoreReminder), findsNothing);
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
