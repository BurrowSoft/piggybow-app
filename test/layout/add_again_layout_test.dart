import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';
import 'stress.dart';

/// Add again today in every layout case (plan §0.3, decision 43): the
/// long-press sheet, the edit sheet's menu open, and "Added again for
/// today" with Undo.
void main() {
  setUpAll(loadAppFonts);

  Future<void> open(WidgetTester tester, LayoutCase c) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(
      () => app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: amountMax,
        currency: 'USD',
        localDate: '2026-10-01',
        category: SpendCategory.fun,
        feeling: Feeling.notSure,
        note: note80,
      ),
    );
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
  }

  for (final c in layoutCases) {
    testWidgets('R1 the long-press sheet: Add again today ($c)', (tester) async {
      await open(tester, c);
      await tester.longPress(byId('tl-row-entry-1'));
      await tester.pumpAndSettle();
      expect(byId('tl-repeat'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'R1');
    });

    testWidgets("R2 the edit sheet's menu, open ($c)", (tester) async {
      await open(tester, c);
      await tester.tapId('tl-row-entry-1');
      await tester.tapId('edit-more');
      expect(byId('edit-repeat'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'R2');
    });

    testWidgets('R3 Added again for today, with Undo ($c)', (tester) async {
      await open(tester, c);
      await tester.longPress(byId('tl-row-entry-1'));
      await tester.pumpAndSettle();
      await tester.tapId('tl-repeat');
      expect(find.text('Added again for today'), findsOneWidget);
      await expectSoundLayout(tester, reason: 'R3');
    });
  }
}
