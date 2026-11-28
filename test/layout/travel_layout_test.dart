// Goldens: MC1, MC2 and MC3 at 320 dp ×2 (decision 44).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/money/rate.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Money in another currency in every layout case (feature 19): the Add
/// sheet with a spend in euros, its rate and the amount at home (MC1); a
/// rate that can't be read, and its line (MC2); Timeline's row with both
/// amounts, next to one in baht (MC3). Goldens at 320 dp ×2, light and dark.
void main() {
  setUpAll(loadAppFonts);
  String thb(int minor) => formatMoney(minor, 'THB', 'en_US');
  String eur(int minor) => formatMoney(minor, 'EUR', 'en_US');

  /// Timeline of a journal in baht, in case [c].
  Future<void> open(
    WidgetTester tester,
    LayoutCase c, {
    Future<void> Function(TestApp)? seed,
  }) async {
    setLayout(tester, c);
    final app = TestApp()..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
  }

  Finder sheetList() => find
      .descendant(
        of: find.byType(EntrySheet),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the sheet until [id] is on screen, then lets the frame settle.
  Future<void> reveal(WidgetTester tester, String id) async {
    await tester.scrollUntilVisible(byId(id), 120, scrollable: sheetList());
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

  /// The Add sheet with €12.34, in euros, and [rate] typed.
  Future<void> travelSpend(WidgetTester tester, String rate) async {
    await tester.tapId('tl-empty-add');
    await tester.enterId('add-amount', '12.34');
    await tester.tapId('add-currency');
    await tester.tapId('currency-EUR');
    await reveal(tester, 'add-rate');
    await tester.enterId('add-rate', rate);
  }

  for (final c in layoutCases) {
    testWidgets('MC1 a spend in euros: its rate and the amount at home ($c)', (
      tester,
    ) async {
      await open(tester, c);
      await travelSpend(tester, '39.12');
      expectOneLine(tester, '= ${eur(1234)}', reason: 'MC1 as spent');
      expectOneLine(tester, '= ${thb(48274)}', reason: 'MC1 at home');
      expect(find.text('1 EUR ='), findsOneWidget);
      await reveal(tester, 'add-cat-food');
      await tester.tap(byId('add-cat-food'));
      await tester.pumpAndSettle();
      await checkSheet(tester, 'MC1');
      if (c.takesGolden) {
        // The top (the amount, both lines, the currency and the rate), and
        // the end when the sheet scrolls.
        await expectLayoutGoldens(
          tester,
          c,
          sheetList(),
          screen: 'add-sheet',
          state: 'travel',
          stateId: 'MC1',
        );
      }
    });

    testWidgets('MC2 a rate with a grouping mark: its line at once ($c)', (
      tester,
    ) async {
      await open(tester, c);
      await travelSpend(tester, '1,400');
      expect(
        find.text('Type the rate with digits and one . only, like 36.5.'),
        findsOneWidget,
      );
      expect(byId('add-converted'), findsNothing);
      await checkSheet(tester, 'MC2');
      if (c.takesGolden) {
        // The rate field and its line on screen, with no caret.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(byId('add-rate'));
        await tester.pumpAndSettle();
        await expectLayoutGolden(
          tester,
          c,
          screen: 'add-sheet',
          state: 'travel-rate-error',
          stateId: 'MC2',
        );
      }
    });

    testWidgets('MC3 Timeline: a spend in euros, both amounts ($c)', (
      tester,
    ) async {
      await open(
        tester,
        c,
        seed: (app) async {
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: 12050,
            currency: 'THB',
            localDate: '2026-10-02',
            category: SpendCategory.food,
            feeling: Feeling.worthIt,
            note: 'Khao soi',
          );
          await app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: 1234,
            currency: 'EUR',
            localDate: '2026-10-02',
            category: SpendCategory.food,
            feeling: Feeling.worthIt,
            note: 'Croissants',
            rate: parseRate('39.12', RateDirection.toHome, mark: '.').rate,
          );
        },
      );
      expect(find.text(eur(1234)), findsOneWidget);
      expect(find.text('= ${thb(48274)}'), findsOneWidget);
      expect(find.text(thb(12050)), findsOneWidget);
      expect(find.text('Spent ${thb(60324)}'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'MC3');
      if (c.takesGolden) {
        await expectLayoutGolden(
          tester,
          c,
          screen: 'timeline',
          state: 'travel',
          stateId: 'MC3',
        );
      }
    });
  }
}
