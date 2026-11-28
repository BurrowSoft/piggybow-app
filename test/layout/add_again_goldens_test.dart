// Goldens: Add again today (decision 44), at 320 dp ×2, light and dark, for
// PB UX & PM's look: the long-press sheet, the edit sheet's menu open, and
// "Added again for today" with Undo.
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> open(WidgetTester tester, LayoutCase c) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(
      () => app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 1250,
        currency: 'USD',
        localDate: '2026-10-01',
        category: SpendCategory.food,
        feeling: Feeling.worthIt,
        note: 'Lunch with Mai',
      ),
    );
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
  }

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('RG1 the long-press sheet ($c)', (tester) async {
      await open(tester, c);
      await tester.longPress(byId('tl-row-entry-1'));
      await tester.pumpAndSettle();
      await expectLayoutGolden(
        tester,
        c,
        screen: 'timeline',
        state: 'add-again-sheet',
        stateId: 'RG1',
      );
    });

    testWidgets("RG2 the edit sheet's menu, open ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tl-row-entry-1');
      await tester.tapId('edit-more');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'edit-sheet',
        state: 'menu',
        stateId: 'RG2',
      );
    });

    testWidgets('RG3 Added again for today, with Undo ($c)', (tester) async {
      await open(tester, c);
      await tester.longPress(byId('tl-row-entry-1'));
      await tester.pumpAndSettle();
      await tester.tapId('tl-repeat');
      await expectLayoutGolden(
        tester,
        c,
        screen: 'timeline',
        state: 'added-again',
        stateId: 'RG3',
      );
    });
  }
}
