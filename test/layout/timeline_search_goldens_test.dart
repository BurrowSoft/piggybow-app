// Goldens: Timeline's search (decision 44), at 320 dp ×2, light and dark,
// for PB UX & PM's look: the field open on "coffee" (today keeps only
// Coffee, and its total), nothing matching, and the icon before it opens.
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

void main() {
  setUpAll(loadAppFonts);
  final t = DateTime.utc(2026, 9);

  /// Today: Coffee 3.50 (worth it) and Lunch 12.00, both Food & drinks.
  /// Yesterday: 100.00 saved for Bike.
  Future<void> open(WidgetTester tester, LayoutCase c) async {
    setLayout(tester, c);
    final app = TestApp(currency: 'USD')..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, createdAt: t, updatedAt: t),
      );
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 10000,
        currency: 'USD',
        localDate: '2026-10-01',
      );
      await app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 350,
        currency: 'USD',
        localDate: '2026-10-02',
        category: SpendCategory.food,
        feeling: Feeling.worthIt,
        note: 'Coffee',
      );
      await app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: 1200,
        currency: 'USD',
        localDate: '2026-10-02',
        category: SpendCategory.food,
        note: 'Lunch',
      );
    });
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
  }

  for (final c in layoutCases.where((c) => c.takesGolden)) {
    testWidgets('TS1 the field open on "coffee" ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-search');
      await tester.enterId('tl-search-field', 'coffee');
      expect(byId('tl-row-entry-2'), findsOneWidget);
      expect(byId('tl-row-entry-3'), findsNothing);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'timeline',
        state: 'search-coffee',
        stateId: 'TS1',
      );
    });

    testWidgets('TS2 nothing matches ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('tl-search');
      await tester.enterId('tl-search-field', 'zzz');
      expect(find.text('Nothing matches that.'), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'timeline',
        state: 'search-no-match',
        stateId: 'TS2',
      );
    });

    testWidgets('TS3 the icon, before the search opens ($c)', (tester) async {
      await open(tester, c);
      expect(byId('tl-search'), findsOneWidget);
      await expectLayoutGolden(
        tester,
        c,
        screen: 'timeline',
        state: 'search-closed',
        stateId: 'TS3',
      );
    });
  }
}
