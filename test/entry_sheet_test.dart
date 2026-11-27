import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';

import 'helpers.dart';

/// The add/edit sheet and Timeline (plan §3.3, §3.6, §4.6, §4.7): integer
/// money, the day the person picked, errors only when they help, and the
/// rows grouped by day with that day's totals.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart).
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');

  // The sheet's own list, built lazily (the Timeline behind it scrolls too).
  Finder sheetList() => find
      .descendant(
        of: find.byType(EntrySheet),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<TestApp> openTimeline(
    WidgetTester tester, {
    Future<void> Function(TestApp)? seed,
  }) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    tester.expectScreen('timeline-screen');
    return app;
  }

  Future<void> addSpend(
    TestApp app,
    int minor,
    String day, {
    String note = '',
  }) => app.journal.addEntry(
    type: EntryType.spent,
    amountMinor: minor,
    currency: 'THB',
    localDate: day,
    category: SpendCategory.food,
    feeling: Feeling.worthIt,
    note: note,
  );

  Future<List<Entry>> stored(WidgetTester tester, TestApp app) async =>
      (await tester.runAsync(app.journal.entries))!;

  testWidgets(
    'the first entry: empty Timeline, Add, a spend in minor units under Today',
    (tester) async {
      final app = await openTimeline(tester);
      expect(byId('tl-empty-add'), findsOneWidget);
      expect(
        byId('tl-add'),
        findsNothing,
        reason: 'the empty state has its own button',
      );

      await tester.tapId('tl-empty-add');
      await tester.enterId('add-amount', '120.50');
      // How the amount was read, before Add.
      expect(find.text('= ${money(12050)}'), findsOneWidget);
      await tester.tapId('add-cat-food');
      await tester.tapId('add-feel-worth');
      await tester.enterId('add-note', 'Khao soi');
      await tester.tapId('add-submit');

      final entries = await stored(tester, app);
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.type, EntryType.spent);
      expect(e.amountMinor, 12050);
      expect(e.currency, 'THB');
      expect(e.category, SpendCategory.food);
      expect(e.feeling, Feeling.worthIt);
      expect(e.note, 'Khao soi');
      expect(
        e.localDate,
        '2026-10-02',
        reason: "the phone's today, in Bangkok",
      );

      expect(find.text('Added'), findsOneWidget);
      expect(byId('tl-row-${e.id}'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Spent ${money(12050)}'), findsOneWidget);
      expect(find.text('Food & drinks · Worth it'), findsOneWidget);
    },
  );

  testWidgets(
    'errors: after Add for what is missing; at once for too large or unreadable',
    (tester) async {
      final app = await openTimeline(tester);
      await tester.tapId('tl-empty-add');
      expect(
        find.text('Enter an amount.'),
        findsNothing,
        reason: 'not before Add',
      );

      await tester.tapId('add-submit');
      expect(find.text('Enter an amount.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Pick a category.'),
        100,
        scrollable: sheetList(),
      );
      expect(find.text('Pick a category.'), findsOneWidget);
      await tester.scrollUntilVisible(
        byId('add-amount'),
        -100,
        scrollable: sheetList(),
      );

      // 13 digits of baht: over the 12-digit cap in minor units.
      await tester.enterId('add-amount', '1234567890123');
      expect(find.text('That amount is too large.'), findsOneWidget);

      // A paste that isn't an amount.
      await tester.enterId('add-amount', '12a');
      expect(find.text('Enter an amount.'), findsOneWidget);
      expect(await stored(tester, app), isEmpty, reason: 'nothing was added');
    },
  );

  testWidgets(
    'typing: one decimal mark, never more decimals than the currency has',
    (tester) async {
      await openTimeline(tester);
      await tester.tapId('tl-empty-add');
      // Key by key (each a one-character change): the third decimal is refused.
      for (final text in ['1', '1,', '1,0', '1,00', '1,005']) {
        await tester.enterId('add-amount', text);
      }
      final field = tester.widget<TextField>(
        find.descendant(
          of: byId('add-amount'),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '1,00');
      expect(find.text('= ${money(100)}'), findsOneWidget);
    },
  );

  testWidgets(
    'a save: no category or feeling, no goal yet; "+amount" in the Timeline',
    (tester) async {
      final app = await openTimeline(tester);
      await tester.tapId('tl-empty-add');
      await tester.tapId('add-seg-saved');
      expect(byId('add-cat-food'), findsNothing);
      expect(byId('add-feel-worth'), findsNothing);
      expect(
        find.text('No goal yet. It still counts as saved.'),
        findsOneWidget,
      );
      await tester.enterId('add-amount', '500');
      await tester.tapId('add-submit');

      final e = (await stored(tester, app)).single;
      expect(e.type, EntryType.saved);
      expect(e.amountMinor, 50000);
      expect(e.goalId, isNull);
      expect(e.category, isNull);
      expect(find.text('+${money(50000)}'), findsOneWidget);
      expect(find.text('Saved'), findsWidgets);
    },
  );

  testWidgets('edit a row, then delete it (asked first)', (tester) async {
    final app = await openTimeline(
      tester,
      seed: (app) => addSpend(app, 8900, '2026-10-01', note: 'Coffee'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    await tester.tapId('tl-row-entry-1');
    final field = tester.widget<TextField>(
      find.descendant(of: byId('add-amount'), matching: find.byType(TextField)),
    );
    expect(field.controller!.text, '89.00', reason: 'pre-filled');
    await tester.enterId('add-amount', '95');
    await tester.tapId('edit-save');
    expect((await stored(tester, app)).single.amountMinor, 9500);
    expect(find.text('Added'), findsNothing, reason: 'an edit says nothing');

    await tester.tapId('tl-row-entry-1');
    await tester.tapId('edit-delete');
    await tester.tapId('delete-cancel');
    expect(await stored(tester, app), hasLength(1));
    await tester.tapId('edit-delete');
    await tester.tapId('delete-confirm');
    expect(await stored(tester, app), isEmpty);
    expect(byId('tl-empty-add'), findsOneWidget);
  });

  testWidgets('day headers with their totals; All, Spent and Saved', (
    tester,
  ) async {
    final app = await openTimeline(
      tester,
      seed: (app) async {
        await addSpend(app, 10000, '2026-10-02');
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 5000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
        await addSpend(app, 2000, '2026-10-01');
        await addSpend(app, 500, '2026-09-28');
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.text('Spent ${money(10000)} · Saved ${money(5000)}'),
      findsOneWidget,
    );
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Mon, Sep 28'), findsOneWidget);
    expect(byId('tl-add'), findsOneWidget);

    await tester.tapId('tl-filter-saved');
    expect(find.text('+${money(5000)}'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
    await tester.tapId('tl-filter-spent');
    expect(find.text('+${money(5000)}'), findsNothing);
    expect(find.text('Mon, Sep 28'), findsOneWidget);
    expect(await stored(tester, app), hasLength(4));
  });

  testWidgets('a feeling is optional, and a second tap clears it', (
    tester,
  ) async {
    final app = await openTimeline(tester);
    await tester.tapId('tl-empty-add');
    await tester.enterId('add-amount', '40');
    await tester.tapId('add-cat-transport');
    await tester.tapId('add-feel-not-sure');
    await tester.tapId('add-feel-not-sure');
    await tester.tapId('add-submit');
    final e = (await stored(tester, app)).single;
    expect(e.category, SpendCategory.transport);
    expect(e.feeling, isNull);
  });

  testWidgets('a save shows the active goal it goes to', (tester) async {
    await openTimeline(
      tester,
      seed: (app) => app.journal.putGoal(
        Goal(
          id: 'goal-1',
          name: 'Bike',
          targetMinor: 1000000,
          createdAt: DateTime.utc(2026, 10),
          updatedAt: DateTime.utc(2026, 10),
        ),
      ),
    );
    await tester.tapId('tl-empty-add');
    await tester.tapId('add-seg-saved');
    expect(find.text('Goes to Bike'), findsOneWidget);
    expect(find.text('No goal yet. It still counts as saved.'), findsNothing);
  });

  testWidgets(
    'the day: Today first, never a future day, Yesterday once picked',
    (tester) async {
      final app = await openTimeline(tester);
      await tester.tapId('tl-empty-add');
      Finder dateChip(String label) =>
          find.descendant(of: byId('add-date'), matching: find.text(label));
      await tester.scrollUntilVisible(
        byId('add-date'),
        100,
        scrollable: sheetList(),
      );
      expect(dateChip('Today'), findsOneWidget);

      await tester.tapId('add-date');
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(
        picker.lastDate,
        DateTime(2026, 10, 2),
        reason: 'today is the last day',
      );
      await tester.tap(find.text('1'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dateChip('Yesterday'), findsOneWidget);

      await tester.scrollUntilVisible(
        byId('add-amount'),
        -100,
        scrollable: sheetList(),
      );
      await tester.enterId('add-amount', '25');
      await tester.tapId('add-cat-food');
      await tester.tapId('add-submit');
      expect((await stored(tester, app)).single.localDate, '2026-10-01');
    },
  );

  testWidgets('an older day shows as its date', (tester) async {
    await openTimeline(tester, seed: (app) => addSpend(app, 500, '2026-09-28'));
    await tester.pumpAndSettle();
    await tester.tapId('tl-row-entry-1');
    await tester.scrollUntilVisible(
      byId('add-date'),
      100,
      scrollable: sheetList(),
    );
    expect(
      find.descendant(
        of: byId('add-date'),
        matching: find.text('Sep 28, 2026'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Added" is read out: the snack is a live region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openTimeline(tester);
    await tester.tapId('tl-empty-add');
    await tester.enterId('add-amount', '10');
    await tester.tapId('add-cat-food');
    await tester.tapId('add-submit');
    expect(find.text('Added'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Added')),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('a double tap on Add adds exactly one entry', (tester) async {
    final app = await openTimeline(tester);
    await tester.tapId('tl-empty-add');
    await tester.enterId('add-amount', '50');
    await tester.tapId('add-cat-food');
    final add = byId('add-submit');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.tap(add, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(await stored(tester, app), hasLength(1));
  });
}
