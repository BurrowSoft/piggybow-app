import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/router.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Taking money out of savings in every layout case (plan §0.3, decision
/// 43), with a 40-character goal name and the largest amounts: the sheet
/// with "more than you've saved", the goal with Take out and a taken-out
/// row, Timeline's row, Summary's line, and the locks: a save the goal
/// needs, edited, and the goal's Already saved, each saying why, whole.
void main() {
  setUpAll(loadAppFonts);
  final t = DateTime.utc(2026, 9);
  const saved = 600000000000;
  const out = 99999999999;
  const saveLocked = 'Some of this money was taken out of $goal40. Change or remove that first.';
  const startLocked = 'Some of this money was taken out of this goal. Change or remove that first.';

  Future<TestApp> open(
    WidgetTester tester,
    LayoutCase c, {
    String location = '/home',
    Future<void> Function(TestApp app)? more,
  }) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: goal40, targetMinor: amountMax, createdAt: t, updatedAt: t),
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: saved,
        currency: 'USD',
        localDate: '2026-10-01',
      );
      await app.journal.takeOut(
        goalId: 'goal-1',
        amountMinor: out,
        currency: 'USD',
        localDate: '2026-10-02',
        note: note80,
      );
      await more?.call(app);
    });
    await app.pump(tester, location: location);
    await tester.pumpAndSettle();
    return app;
  }

  /// Pumps until [done], at most 2 s: a screen reads the store before it
  /// shows its fields.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// The entry sheet's amount, as typed ('' until the sheet has loaded).
  String amountText(WidgetTester tester) {
    final field = find.descendant(of: byId('add-amount'), matching: find.byType(TextField));
    if (field.evaluate().isEmpty) return '';
    return tester.widget<TextField>(field).controller!.text;
  }

  /// Taps a Timeline row near its top: a tall row's middle can sit under
  /// the tab bar.
  Future<void> openRow(WidgetTester tester, String id) async {
    await tester.revealId(id);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(byId(id)).topLeft + const Offset(24, 16));
    await tester.pumpAndSettle();
  }

  /// Each [text] on screen shows whole: never cut at its lines' limit.
  void expectUncut(WidgetTester tester, String text, int count, {required String reason}) {
    final paragraphs = find.descendant(of: find.text(text), matching: find.byType(RichText));
    expect(paragraphs, findsNWidgets(count), reason: reason);
    for (final e in paragraphs.evaluate()) {
      final p = e.renderObject! as RenderParagraph;
      expect(p.didExceedMaxLines, isFalse, reason: 'cut: "$text" ($reason)');
    }
  }

  for (final c in layoutCases) {
    testWidgets("T1 the take-out sheet: more than you've saved ($c)", (tester) async {
      await open(tester, c, location: GoalRoutes.detail('goal-1'));
      await tester.tapId('goal-take-out');
      await tester.enterId('takeout-amount', '9999999999');
      expect(find.text("That's more than you've saved for this goal"), findsOneWidget);
      await expectSoundLayout(tester, reason: 'T1');
    });

    testWidgets('T2 the goal: Take out, and a taken-out row ($c)', (tester) async {
      await open(tester, c, location: GoalRoutes.detail('goal-1'));
      await tester.revealId('goal-save-entry-2');
      await tester.pumpAndSettle();
      expect(byId('goal-take-out'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'T2');
    });

    testWidgets("T3 Timeline: the taken-out row ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tab-timeline');
      expect(byId('tl-row-entry-2'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'T3');
    });

    testWidgets("T4 Summary: Taken out, its own line ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tab-summary');
      await tester.revealId('sum-taken-out');
      await tester.pumpAndSettle();
      await expectSoundLayout(tester, reason: 'T4');
    });

    testWidgets('T5 a save the goal needs, edited: lowered, then Delete, each '
        'saying why ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tab-timeline');
      await openRow(tester, 'tl-row-entry-1');
      await settleUntil(tester, () => amountText(tester).isNotEmpty);
      expect(amountText(tester), isNotEmpty, reason: 'T5: the save, loaded');
      await tester.enterId('add-amount', '1');
      expectUncut(tester, saveLocked, 1, reason: 'T5 the amount');
      await tester.tapId('edit-delete');
      expect(byId('delete-confirm'), findsNothing);
      // The amount's line, and the sheet's line above the buttons.
      expectUncut(tester, saveLocked, 2, reason: 'T5 the sheet');
      await expectSoundLayout(tester, reason: 'T5');
    });

    testWidgets("T6 the goal's editor: Already saved below what was taken "
        'out beyond its saves ($c)', (tester) async {
      await open(
        tester,
        c,
        location: GoalRoutes.edit('goal-1'),
        more: (app) async {
          // Already saved 3,000,000,000.00, then everything taken out: the
          // saves cover only part of it, so Already saved can't go lower.
          final goal = (await app.journal.goal('goal-1'))!;
          await app.journal.putGoal(goal.copyWith(startMinor: 300000000000));
          await app.journal.takeOut(
            goalId: 'goal-1',
            amountMinor: 300000000000 + saved - out,
            currency: 'USD',
            localDate: '2026-10-02',
          );
        },
      );
      await settleUntil(tester, () => byId('goal-start').evaluate().isNotEmpty);
      await tester.revealId('goal-start');
      await tester.enterId('goal-start', '1');
      expectUncut(tester, startLocked, 1, reason: 'T6');
      await expectSoundLayout(tester, reason: 'T6');
    });
  }
}
