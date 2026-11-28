// Feature 21's screens in every layout case: Back up to a file, empty (BK1)
// and with its too-short line (BK2); Restore from a file, choosing (RS1), a
// wrong password (RS2), "Replace everything?" over a journal with notes
// (RS3), and done (RS4). Goldens at 320 dp ×2 and 360 dp ×1, light and dark.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fake_backup.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);
  late FakeBackup backup;
  setUp(() => (backup = FakeBackup()).install());

  Finder listIn(String screenId) => find
      .descendant(of: byId(screenId), matching: find.byType(Scrollable))
      .first;

  /// The plan's golden cases: 320 dp ×2, and 360 dp ×1.
  bool takes(LayoutCase c) =>
      c.takesGolden || (c.width == 360 && c.textScale == 1);

  Future<void> open(
    WidgetTester tester,
    LayoutCase c,
    String location, {
    bool withNotes = false,
  }) async {
    setLayout(tester, c);
    final app = TestApp()..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (withNotes) {
      await tester.runAsync(
        () => app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 4500,
          currency: 'THB',
          localDate: '2026-10-01',
          category: SpendCategory.food,
        ),
      );
    }
    await app.pump(tester, location: location);
  }

  /// Sound in every case; goldens in [takes]'s (a screen's top and end).
  Future<void> check(
    WidgetTester tester,
    LayoutCase c, {
    required String screen,
    required String state,
    required String stateId,
    Finder? scrollable,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectSoundLayout(tester, reason: stateId);
    if (!takes(c)) return;
    if (scrollable == null) {
      await expectLayoutGolden(
        tester,
        c,
        screen: screen,
        state: state,
        stateId: stateId,
      );
    } else {
      await expectLayoutGoldens(
        tester,
        c,
        scrollable,
        screen: screen,
        state: state,
        stateId: stateId,
      );
    }
  }

  Future<void> chooseFile(WidgetTester tester, String password) async {
    backup.picked = (
      name: 'piggybow-backup-2026-09-30.piggybow',
      text: await backup.file(tester),
    );
    await tester.tapId('restore-choose');
    await tester.enterId('restore-password', password);
    await tester.tapId('restore-go');
  }

  for (final c in layoutCases) {
    testWidgets('BK1 Back up to a file ($c)', (tester) async {
      await open(tester, c, MeRoutes.backup);
      // That Piggybow can't recover the password: on screen before any
      // scrolling, at every text size.
      expect(
        tester.getRect(byId('backup-no-recovery')).bottom,
        lessThanOrEqualTo(780),
        reason: 'BK1: the no-recovery line is in view',
      );
      await check(
        tester,
        c,
        screen: 'backup',
        state: 'empty',
        stateId: 'BK1',
        scrollable: listIn('backup-screen'),
      );
    });

    testWidgets('BK2 Back up: too short ($c)', (tester) async {
      await open(tester, c, MeRoutes.backup);
      await tester.enterId('backup-password', 'short');
      await tester.enterId('backup-again', 'short');
      await tester.tapId('backup-go');
      tester.expectScreen('backup-screen');
      expect(byId('backup-error'), findsOneWidget);
      await check(
        tester,
        c,
        screen: 'backup',
        state: 'too-short',
        stateId: 'BK2',
        scrollable: listIn('backup-screen'),
      );
    });

    testWidgets('RS1 Restore: choose a file ($c)', (tester) async {
      await open(tester, c, MeRoutes.restore);
      await check(
        tester,
        c,
        screen: 'restore',
        state: 'choose',
        stateId: 'RS1',
        scrollable: listIn('restore-screen'),
      );
    });

    testWidgets('RS2 Restore: a wrong password ($c)', (tester) async {
      await open(tester, c, MeRoutes.restore);
      await chooseFile(tester, 'wrong horse');
      expect(byId('restore-error'), findsOneWidget);
      await check(
        tester,
        c,
        screen: 'restore',
        state: 'wrong-password',
        stateId: 'RS2',
        scrollable: listIn('restore-screen'),
      );
    });

    testWidgets('RS3 Restore: Replace everything? ($c)', (tester) async {
      await open(tester, c, MeRoutes.restore, withNotes: true);
      await chooseFile(tester, 'correct horse');
      expect(byId('restore-replace-body'), findsOneWidget);
      await check(
        tester,
        c,
        screen: 'restore',
        state: 'replace',
        stateId: 'RS3',
      );
    });

    testWidgets('RS4 Restore: done ($c)', (tester) async {
      await open(tester, c, MeRoutes.restore);
      await chooseFile(tester, 'correct horse');
      expect(byId('restore-done'), findsOneWidget);
      await check(
        tester,
        c,
        screen: 'restore',
        state: 'done',
        stateId: 'RS4',
        scrollable: listIn('restore-screen'),
      );
    });
  }
}
