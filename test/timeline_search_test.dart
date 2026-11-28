import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/timeline/timeline_search.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';

import 'helpers.dart';

/// Timeline's search (feature 15): the icon opens a field under the app
/// bar; every word typed must be in a row's note or its name (a spend's
/// category, a save's goal), any case, any Latin accent, Thai as typed; it
/// works with All / Spent / Saved, and a day's header and totals count only
/// what matches; "Nothing matches that." is read out; ✕ or back clears and
/// closes it; it stays through an edit and a tab switch.
void main() {
  group('the words', () {
    test('case and Latin accents fold; Thai stays as typed', () {
      expect(foldForSearch('Crème Brûlée'), 'creme brulee');
      expect(foldForSearch('ÑANDÚ'), 'nandu');
      expect(
        foldForSearch('Straße Øre Ærø Œuvre Łódź Ağaç İstanbul Phở'),
        'strasse ore aero oeuvre lodz agac istanbul pho',
      );
      // An accent typed as its own mark after the letter.
      expect(foldForSearch(String.fromCharCodes([0x63, 0x61, 0x66, 0x65, 0x301])), 'cafe');
      // Thai "rice" (with its tone mark) and "white" (without): two words.
      final rice = String.fromCharCodes([0x0e02, 0x0e49, 0x0e32, 0x0e27]);
      final white = String.fromCharCodes([0x0e02, 0x0e32, 0x0e27]);
      expect(foldForSearch(rice), rice);
      expect(matchesSearch(searchWords(rice), [rice]), isTrue);
      expect(matchesSearch(searchWords(white), [rice]), isFalse);
    });

    test('a search is its words, trimmed; a blank one has none', () {
      expect(searchWords('  food   LUNCH '), ['food', 'lunch']);
      expect(searchWords('   '), isEmpty);
    });

    test('every word must match, each within the note or the name', () {
      expect(matchesSearch(['food', 'lunch'], ['Lunch', 'Food & drinks']), isTrue);
      expect(matchesSearch(['food', 'dinner'], ['Lunch', 'Food & drinks']), isFalse);
      expect(matchesSearch(['cof'], ['COFFEE']), isTrue);
      expect(matchesSearch(['lunchfood'], ['Lunch', 'Food']), isFalse);
      expect(matchesSearch(const [], ['anything']), isTrue);
    });
  });

  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart).
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');
  final t = DateTime.utc(2026, 9, 20);

  /// Today: Coffee 3.50 and Lunch 12.00 (Food & drinks). Yesterday: Crème
  /// brûlée 50.00 (Groceries) and 100.00 saved for Bike. 30 September: bike
  /// repair 3.00 (Transport).
  Future<TestApp> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await tester.runAsync(() async {
      await app.journal.putGoal(
        Goal(id: 'goal-1', name: 'Bike', targetMinor: 100000, createdAt: t, updatedAt: t),
      );
      Future<void> spend(int minor, SpendCategory c, String note, String date, {Feeling? feeling}) =>
          app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: minor,
            currency: 'THB',
            localDate: date,
            category: c,
            feeling: feeling,
            note: note,
          );
      await spend(350, SpendCategory.food, 'Coffee', '2026-10-02', feeling: Feeling.worthIt);
      await spend(1200, SpendCategory.food, 'Lunch', '2026-10-02');
      await spend(5000, SpendCategory.groceries, 'Crème brûlée', '2026-10-01');
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 10000,
        currency: 'THB',
        localDate: '2026-10-01',
      );
      await spend(300, SpendCategory.transport, 'bike repair', '2026-09-30');
    });
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    tester.expectScreen('timeline-screen');
    await tester.pumpAndSettle();
    return app;
  }

  /// Which of the five rows are on Timeline now, by id.
  List<String> rows() => [
    for (var i = 1; i <= 5; i++)
      if (byId('tl-row-entry-$i').evaluate().isNotEmpty) 'entry-$i',
  ];

  Future<void> search(WidgetTester tester, String text) => tester.enterId('tl-search-field', text);

  testWidgets('the icon opens the field under the app bar; a word finds a '
      'note in any case and with or without its accents', (tester) async {
    await open(tester);
    expect(rows(), hasLength(5));
    expect(byId('tl-search-field'), findsNothing);
    await tester.tapId('tl-search');
    expect(byId('tl-search-field'), findsOneWidget);
    expect(byId('tl-search'), findsNothing, reason: 'no icon while it is open');
    expect(find.text('Search notes and categories'), findsOneWidget);
    expect(rows(), hasLength(5), reason: 'nothing typed: everything');
    await search(tester, 'COF');
    expect(rows(), ['entry-1']);
    await search(tester, 'creme');
    expect(rows(), ['entry-3']);
    await search(tester, 'BRÛLÉE');
    expect(rows(), ['entry-3']);
  });

  testWidgets("a category finds its spends, a goal its saves; every word must "
      'match; a feeling or an amount finds nothing', (tester) async {
    await open(tester);
    await tester.tapId('tl-search');
    await search(tester, 'food');
    expect(rows(), ['entry-1', 'entry-2']);
    await search(tester, 'groceries');
    expect(rows(), ['entry-3']);
    // The save for Bike, and the spend noted "bike repair".
    await search(tester, 'bike');
    expect(rows(), ['entry-4', 'entry-5']);
    await search(tester, 'food lunch');
    expect(rows(), ['entry-2']);
    await search(tester, 'worth');
    expect(rows(), isEmpty);
    await search(tester, '3.50');
    expect(rows(), isEmpty);
  });

  testWidgets('it works with All / Spent / Saved', (tester) async {
    await open(tester);
    await tester.tapId('tl-search');
    await search(tester, 'bike');
    await tester.tapId('tl-filter-spent');
    expect(rows(), ['entry-5']);
    await tester.tapId('tl-filter-saved');
    expect(rows(), ['entry-4']);
    await tester.tapId('tl-filter-all');
    expect(rows(), ['entry-4', 'entry-5']);
  });

  testWidgets("a day's header and totals count only what matches", (tester) async {
    await open(tester);
    expect(find.text('Spent ${money(1550)}'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    await tester.tapId('tl-search');
    await search(tester, 'coffee');
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Spent ${money(350)}'), findsOneWidget);
    expect(find.text('Spent ${money(1550)}'), findsNothing);
    expect(find.text('Yesterday'), findsNothing, reason: 'no day without a match');
  });

  testWidgets('"Nothing matches that." is read out; with nothing typed, a '
      'filter that leaves nothing says nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tapId('tl-search');
    await search(tester, 'coffee');
    await tester.tapId('tl-filter-saved');
    expect(rows(), isEmpty);
    expect(find.text('Nothing matches that.'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Nothing matches that.')),
      isSemantics(isLiveRegion: true),
    );
    await search(tester, '');
    expect(find.text('Nothing matches that.'), findsNothing);
    expect(rows(), ['entry-4']);
    semantics.dispose();
  });

  testWidgets('✕ clears it and closes the field; so does back, which stays '
      'on Timeline', (tester) async {
    await open(tester);
    await tester.tapId('tl-search');
    await search(tester, 'coffee');
    await tester.tapId('tl-search-close');
    expect(byId('tl-search-field'), findsNothing);
    expect(byId('tl-search'), findsOneWidget);
    expect(rows(), hasLength(5));
    // Opened again, it starts empty.
    await tester.tapId('tl-search');
    expect(rows(), hasLength(5));
    await search(tester, 'coffee');
    expect(rows(), ['entry-1']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(byId('tl-search-field'), findsNothing);
    expect(byId('timeline-screen'), findsOneWidget);
    expect(rows(), hasLength(5));
  });

  testWidgets('it stays through an edit and a tab switch', (tester) async {
    await open(tester);
    await tester.tapId('tl-search');
    await search(tester, 'coffee');
    await tester.tapId('tl-row-entry-1');
    expect(byId('add-back'), findsOneWidget);
    await tester.tapId('add-back');
    expect(rows(), ['entry-1']);
    await tester.tapId('tab-home');
    await tester.tapId('tab-timeline');
    expect(
      find.descendant(of: byId('tl-search-field'), matching: find.text('coffee')),
      findsOneWidget,
    );
    expect(rows(), ['entry-1']);
  });

  testWidgets('no search on an empty Timeline', (tester) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(byId('tl-search'), findsNothing);
  });
}
