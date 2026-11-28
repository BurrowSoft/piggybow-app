import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Timeline's search in every layout case (plan §0.3, decision 43): the
/// field open with its hint whole; a search finding the 80-character note,
/// a Thai note, and a save to a goal with a 40-character name, at the
/// largest amounts; and "Nothing matches that.", whole.
void main() {
  setUpAll(loadAppFonts);
  final t = DateTime.utc(2026, 9);
  const hint = 'Search notes and categories';
  const noMatch = 'Nothing matches that.';

  /// Yesterday: half the largest amount saved for the 40-character goal
  /// (entry-1). Today: the largest spend, with the 80-character note
  /// (entry-2), and one with the Thai note (entry-3).
  Future<void> open(WidgetTester tester, LayoutCase c) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: goal40, targetMinor: amountMax, createdAt: t, updatedAt: t),
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: amountMax ~/ 2,
        currency: 'USD',
        localDate: '2026-10-01',
      );
      await app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: amountMax,
        currency: 'USD',
        localDate: '2026-10-02',
        category: SpendCategory.fun,
        feeling: Feeling.notReally,
        note: note80,
      );
      await app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 4500,
        currency: 'USD',
        localDate: '2026-10-02',
        category: SpendCategory.food,
        note: noteThai,
      );
    });
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
  }

  /// [text] is on screen once, whole: never cut at its lines' limit.
  void expectUncut(WidgetTester tester, String text, {required String reason}) {
    final paragraph = find.descendant(of: find.text(text), matching: find.byType(RichText));
    expect(paragraph, findsOneWidget, reason: reason);
    expect(
      tester.renderObject<RenderParagraph>(paragraph).didExceedMaxLines,
      isFalse,
      reason: 'cut: "$text" ($reason)',
    );
  }

  for (final c in layoutCases) {
    testWidgets('S1 the field open, its hint whole ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-search');
      expectUncut(tester, hint, reason: 'S1');
      await expectSoundLayout(tester, reason: 'S1');
    });

    testWidgets('S2 found: the 80-character note, a Thai note, the '
        '40-character goal ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-search');
      await tester.enterId('tl-search-field', 'carrot');
      expect(byId('tl-row-entry-2'), findsOneWidget);
      expect(byId('tl-row-entry-3'), findsNothing);
      await expectSoundLayout(tester, reason: 'S2 the note');
      // Its first word, "rice", with its tone mark.
      await tester.enterId('tl-search-field', noteThai.substring(0, 4));
      expect(byId('tl-row-entry-3'), findsOneWidget);
      expect(byId('tl-row-entry-2'), findsNothing);
      await expectSoundLayout(tester, reason: 'S2 Thai');
      await tester.enterId('tl-search-field', 'summer rides');
      expect(byId('tl-row-entry-1'), findsOneWidget);
      expect(byId('tl-row-entry-2'), findsNothing);
      await expectSoundLayout(tester, reason: 'S2 the goal');
    });

    testWidgets('S3 nothing matches ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-search');
      await tester.enterId('tl-search-field', 'zzz');
      expectUncut(tester, noMatch, reason: 'S3');
      await expectSoundLayout(tester, reason: 'S3');
    });
  }
}
