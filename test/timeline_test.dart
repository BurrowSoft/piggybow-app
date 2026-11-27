import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/money/money.dart';

import 'helpers.dart';
import 'helpers/no_error_colour.dart';

/// Timeline (plan §3.6): the empty state, the rows' colours (spends in ink,
/// saves in the accent, never an error colour or a minus), a thousand rows
/// built lazily, and a delete that keeps the scroll position.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart).
  String money(int minor) => formatMoney(minor, 'THB', 'en_US');
  // A function: the semantics finder needs the test binding, so it can't be
  // built before a test runs.
  Finder rows() => find.bySemanticsIdentifier(RegExp('^tl-row-'));

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
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> addSpend(TestApp app, int minor, {String note = ''}) =>
      app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: minor,
        currency: 'THB',
        localDate: '2026-10-02',
        category: SpendCategory.food,
        feeling: Feeling.worthIt,
        note: note,
      );

  testWidgets('empty: the calm pig and one button, no other Add', (
    tester,
  ) async {
    await openTimeline(tester);
    final pig = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      (pig.bytesLoader as SvgAssetLoader).assetName,
      'assets/pig/pig-calm.svg',
    );
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Add your first entry'), findsOneWidget);
    expect(byId('tl-empty-add'), findsOneWidget);
    expect(byId('tl-add'), findsNothing);
  });

  testWidgets('a spend in ink with no minus; a save "+amount" in the accent', (
    tester,
  ) async {
    await openTimeline(
      tester,
      seed: (app) async {
        await addSpend(app, 12050);
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 5000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      },
    );
    final theme = Theme.of(tester.element(find.text(money(12050))));
    expect(
      tester.widget<Text>(find.text(money(12050))).style?.color,
      theme.colorScheme.onSurface,
      reason: 'a spend is ink',
    );
    expect(
      tester.widget<Text>(find.text('+${money(5000)}')).style?.color,
      theme.colorScheme.primary,
      reason: 'a save is the accent',
    );
    // Wherever the amounts show (rows and the day's totals): only ink, the
    // muted ink, or the save accent; never an error colour.
    expectOnlyAllowedColours(tester, [
      money(12050),
      money(5000),
    ], extra: (t) => {t.colorScheme.primary});
    expect(find.textContaining('-${money(12050)}'), findsNothing);
    expect(find.textContaining('−'), findsNothing, reason: 'no minus sign');
    expect(byId('tl-add'), findsOneWidget);
  });

  testWidgets('a save for a goal names it', (tester) async {
    await openTimeline(
      tester,
      seed: (app) async {
        final now = DateTime.utc(2026, 10, 1);
        await app.journal.putGoal(
          Goal(
            id: 'goal-1',
            name: 'Bike',
            targetMinor: 1000000,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 5000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      },
    );
    expect(find.text('Saved for Bike'), findsOneWidget);
  });

  testWidgets(
    'a thousand entries on one day: only what is on screen is built',
    (tester) async {
      await openTimeline(
        tester,
        seed: (app) async {
          for (var i = 0; i < 1000; i++) {
            await addSpend(app, 100 + i);
          }
        },
      );
      final built = rows().evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(60), reason: 'built lazily, not all 1000');
    },
  );

  testWidgets('a delete keeps the scroll position', (tester) async {
    final app = await openTimeline(
      tester,
      seed: (app) async {
        for (var i = 0; i < 40; i++) {
          await addSpend(app, 100 + i, note: 'Item $i');
        }
      },
    );
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    // Item 9 (entry-10) is the 31st row: well down the list.
    await tester.scrollUntilVisible(
      byId('tl-row-entry-10'),
      200,
      scrollable: list,
    );
    await tester.ensureVisible(byId('tl-row-entry-10'));
    await tester.pumpAndSettle();
    // Held now: once the sheet is open, its own list is a ListView too.
    final position = tester.state<ScrollableState>(list).position;
    final before = position.pixels;
    expect(before, greaterThan(0), reason: 'scrolled down');

    await tester.tapId('tl-row-entry-10');
    await tester.tapId('edit-delete');
    await tester.tapId('delete-confirm');
    expect((await tester.runAsync(app.journal.entries))!, hasLength(39));
    await tester.pumpAndSettle();
    expect(position.pixels, before);
  });
}
