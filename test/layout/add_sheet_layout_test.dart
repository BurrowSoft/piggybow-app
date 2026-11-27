// Goldens: A2, A5 and B1 at 320 dp ×2 (decision 44).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import '../helpers/no_error_colour.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// The add/edit sheet and the delete dialog in every layout case (plan
/// §0.3, decision 43): keyboard open, full with the largest amount, the
/// errors, a save with a long goal name, an edit on an older day.
void main() {
  setUpAll(loadAppFonts);
  String usd(int minor) => formatMoney(minor, 'USD', 'en_US');

  Future<TestApp> open(
    WidgetTester tester,
    LayoutCase c, {
    double keyboard = 0,
    Future<void> Function(TestApp)? seed,
  }) async {
    setLayout(tester, c, keyboard: keyboard);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
    return app;
  }

  Finder sheetList() => find
      .descendant(
        of: find.byType(EntrySheet),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the sheet until [id] is on screen, then lets the frame settle:
  /// a tap right after a scroll would use the old layout (and could land on
  /// Add in the bar below).
  Future<void> reveal(WidgetTester tester, String id) async {
    await tester.scrollUntilVisible(byId(id), 120, scrollable: sheetList());
    await tester.pumpAndSettle();
  }

  /// Taps a Timeline row near its top: a tall row's middle can sit under
  /// the tab bar.
  Future<void> openRow(WidgetTester tester, String id) async {
    await tester.ensureVisible(byId(id));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(byId(id)).topLeft + const Offset(24, 16));
    await tester.pumpAndSettle();
  }

  /// The checks on every part of the sheet, scrolled through top to bottom.
  Future<void> checkSheet(WidgetTester tester, String state) async {
    final position = tester.state<ScrollableState>(sheetList()).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(
        tester,
        reason: '$state at ${position.pixels.round()}',
      );
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
  }

  Future<void> seedFullSpend(TestApp app) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: amountMax,
    currency: 'USD',
    localDate: '2026-09-28',
    category: SpendCategory.fun,
    feeling: Feeling.notReally,
    note: note80,
  );

  for (final c in layoutCases) {
    testWidgets(
      'A1 just opened, keyboard open: the amount and Add in reach ($c)',
      (tester) async {
        await open(tester, c);
        await tester.tapId('tl-empty-add');
        // The keyboard comes up once the sheet is open (the amount is
        // focused); before that, the tab bar is in reach.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
        await tester.pumpAndSettle();
        await expectSoundLayout(tester, reason: 'A1');
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final add = tester.getRect(byId('add-submit'));
        expect(
          add.bottom,
          lessThanOrEqualTo(screen.height - 300 + 0.5),
          reason: 'Add above the keyboard',
        );
        final amount = tester.getRect(byId('add-amount'));
        expect(amount.top, greaterThanOrEqualTo(0));
        expect(
          amount.bottom,
          lessThanOrEqualTo(screen.height - 300 + 0.5),
          reason: 'the amount above the keyboard',
        );
      },
    );

    testWidgets(
      'A2 a full spend: the largest amount, the longest category, 80 characters ($c)',
      (tester) async {
        await open(tester, c);
        await tester.tapId('tl-empty-add');
        await tester.enterId('add-amount', '9999999999.99');
        final preview = '= ${usd(amountMax)}';
        expectOneLine(tester, preview, reason: 'A2 preview');
        expectOnlyAllowedColours(tester, [preview], reason: 'A2 preview');
        await reveal(tester, 'add-cat-fun');
        await tester.tap(byId('add-cat-fun'));
        await tester.pump();
        expect(find.text(longestCategory), findsWidgets);
        await reveal(tester, 'add-feel-not-really');
        await tester.tap(byId('add-feel-not-really'));
        await reveal(tester, 'add-note');
        await tester.enterId('add-note', note80);
        await tester.pumpAndSettle();
        await checkSheet(tester, 'A2');
        if (c.takesGolden) {
          // The top (amount, preview, categories) and the end (the feeling,
          // the 80-character note, Add).
          await expectLayoutGoldens(
            tester,
            c,
            sheetList(),
            screen: 'add-sheet',
            state: 'spent-full',
            stateId: 'A2',
          );
        }
      },
    );

    testWidgets('A3 the errors after Add ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-empty-add');
      await tester.tap(byId('add-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount.'), findsOneWidget);
      await checkSheet(tester, 'A3');
      expect(find.text('Pick a category.'), findsOneWidget);
    });

    testWidgets('A4 a 13-digit amount: too large ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-empty-add');
      await tester.enterId('add-amount', '1234567890123');
      expect(find.text('That amount is too large.'), findsOneWidget);
      await checkSheet(tester, 'A4');
    });

    testWidgets('A5 a save, to a goal with a 40-character name ($c)', (
      tester,
    ) async {
      await open(
        tester,
        c,
        seed: (app) => app.journal.putGoal(
          Goal(
            id: 'goal-1',
            name: goal40,
            targetMinor: 100000,
            createdAt: DateTime.utc(2026, 9),
            updatedAt: DateTime.utc(2026, 9),
          ),
        ),
      );
      await tester.tapId('tl-empty-add');
      await tester.tapId('add-seg-saved');
      expect(find.text('Goes to $goal40'), findsOneWidget);
      await tester.enterId('add-amount', '9999999999.99');
      await checkSheet(tester, 'A5');
      if (c.takesGolden) {
        // The end too, only if the sheet scrolls at all.
        await expectLayoutGoldens(
          tester,
          c,
          sheetList(),
          screen: 'add-sheet',
          state: 'saved-goal',
          stateId: 'A5',
        );
      }
    });

    testWidgets('A6 a save with no goal ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-empty-add');
      await tester.tapId('add-seg-saved');
      expect(
        find.text('No goal yet. It still counts as saved.'),
        findsOneWidget,
      );
      await checkSheet(tester, 'A6');
    });

    testWidgets('A7 edit, on an older day; B1 the delete dialog ($c)', (
      tester,
    ) async {
      await open(tester, c, seed: seedFullSpend);
      await openRow(tester, 'tl-row-entry-1');
      await checkSheet(tester, 'A7');
      expect(find.text('Sep 28, 2026'), findsOneWidget);
      await tester.tap(byId('edit-delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'B1');
      if (c.takesGolden) {
        await expectLayoutGolden(
          tester,
          c,
          screen: 'delete-dialog',
          state: 'confirm',
          stateId: 'B1',
        );
      }
    });
  }
}
