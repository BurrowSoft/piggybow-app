import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/money/rate.dart';

import 'helpers.dart';

/// Money in another currency, on screen (feature 19): the Add sheet starts
/// in the home currency; its currency chip picks another; the rate is
/// filled in from the last one, typed either way, and read with the phone's
/// decimal separator only; the amount at home shows before Add; an edit
/// converts again; and Timeline shows both amounts.
///
/// Finders see only what's on screen, so each step first scrolls the sheet
/// to what it uses ([show]).
void main() {
  // Tests run on Friday 2 October 2026 in Bangkok; the journal is in baht.
  Rate rate(String text, [RateDirection d = RateDirection.toHome]) =>
      parseRate(text, d, mark: '.').rate!;
  String thb(int minor, [String locale = 'en_US']) =>
      formatMoney(minor, 'THB', locale);
  String eur(int minor, [String locale = 'en_US']) =>
      formatMoney(minor, 'EUR', locale);

  Future<void> euroSpend(TestApp app, {int minor = 1234, Rate? at}) =>
      app.journal.addEntry(
        type: EntryType.spent,
        amountMinor: minor,
        currency: 'EUR',
        localDate: '2026-10-02',
        category: SpendCategory.food,
        rate: at ?? rate('39.12'),
      );

  Finder sheetList() => find
      .descendant(
        of: find.byType(EntrySheet),
        matching: find.byType(Scrollable),
      )
      .first;

  /// [finder] in the sheet (Timeline behind it may show the same text).
  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(EntrySheet), matching: finder);

  /// The sheet from its top, scrolled down until [id] is on screen.
  Future<void> show(WidgetTester tester, String id) async {
    tester.state<ScrollableState>(sheetList()).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(byId(id), 120, scrollable: sheetList());
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String id, String text) async {
    await show(tester, id);
    await tester.enterId(id, text);
  }

  Future<void> tapIn(WidgetTester tester, String id) async {
    await show(tester, id);
    await tester.tap(byId(id));
    await tester.pumpAndSettle();
  }

  /// What the rate field shows.
  Future<String> rateText(WidgetTester tester) async {
    await show(tester, 'add-rate');
    return tester
        .widget<TextField>(
          find.descendant(
            of: byId('add-rate'),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
  }

  Future<TestApp> openTimeline(
    WidgetTester tester, {
    String localeName = 'en_US',
    Future<void> Function(TestApp)? seed,
  }) async {
    final app = TestApp(deviceLocaleName: localeName);
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester);
    await tester.tapId('tab-timeline');
    tester.expectScreen('timeline-screen');
    return app;
  }

  Future<TestApp> openAdd(
    WidgetTester tester, {
    String localeName = 'en_US',
    Future<void> Function(TestApp)? seed,
  }) async {
    final app = await openTimeline(tester, localeName: localeName, seed: seed);
    await tester.tapId(
      byId('tl-empty-add').evaluate().isEmpty ? 'tl-add' : 'tl-empty-add',
    );
    return app;
  }

  Future<void> pickCurrency(WidgetTester tester, String code) async {
    await tapIn(tester, 'add-currency');
    tester.expectScreen('currency-screen');
    await tester.tapId('currency-$code');
    expect(byId('currency-screen'), findsNothing);
  }

  Future<List<Entry>> stored(WidgetTester tester, TestApp app) async =>
      (await tester.runAsync(app.journal.entries))!;

  /// The lines under the amount: how it was read ([asTyped]), and, in
  /// another currency, the amount at home ([atHome], formatted) in its
  /// sentence.
  Future<void> expectLines(
    WidgetTester tester, {
    required String asTyped,
    String? atHome,
  }) async {
    await show(tester, 'add-amount');
    expect(inSheet(find.text(asTyped)), findsOneWidget);
    if (atHome == null) {
      expect(byId('add-converted'), findsNothing);
    } else {
      expect(
        inSheet(find.text("That's $atHome at this rate.")),
        findsOneWidget,
      );
    }
  }

  // Wiring item 21 (E's repeats with #76): a repeat stays in the home
  // currency for now. In another one the Repeat row says so and can't be
  // tapped, and Add makes no repeat; back in the home currency it's on.
  testWidgets(
    'in another currency, Repeat is off and says why, and Add makes no repeat',
    (tester) async {
      const why = 'Repeats work in your home currency for now.';
      ListTile row() => tester.widget<ListTile>(
        find.descendant(of: byId('add-repeat'), matching: find.byType(ListTile)),
      );
      final app = await openAdd(tester);
      await pickCurrency(tester, 'EUR');
      await show(tester, 'add-repeat');
      expect(
        find.descendant(of: byId('add-repeat'), matching: find.text(why)),
        findsOneWidget,
      );
      expect(row().onTap, isNull);

      await pickCurrency(tester, 'THB');
      await show(tester, 'add-repeat');
      expect(find.text(why), findsNothing);
      expect(row().onTap, isNotNull);

      await pickCurrency(tester, 'EUR');
      await enter(tester, 'add-amount', '12.34');
      await enter(tester, 'add-rate', '39.12');
      await tapIn(tester, 'add-cat-food');
      await tester.tapId('add-submit');
      final entry = (await stored(tester, app)).single;
      expect((entry.currency, entry.convertedMinor, entry.repeatId), ('EUR', 48274, null));
      expect(await tester.runAsync(app.journal.repeats), isEmpty);
    },
  );

  testWidgets('a new entry starts in the home currency, with no rate', (
    tester,
  ) async {
    await openAdd(tester);
    await show(tester, 'add-currency');
    expect(
      find.descendant(of: byId('add-currency'), matching: find.text('THB')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(byId('add-currency')).getSemanticsData().label,
      contains('Currency: Thai baht'),
    );
    // A rate row would be right under the chip, on screen.
    expect(inSheet(find.text('Rate')), findsNothing);
    expect(byId('add-rate'), findsNothing);
  });

  testWidgets(
    'a spend in euros: the rate, the amount at home before Add, then both kept',
    (tester) async {
      final app = await openAdd(tester);
      await pickCurrency(tester, 'EUR');
      await show(tester, 'add-currency');
      expect(
        find.descendant(of: byId('add-currency'), matching: find.text('EUR')),
        findsOneWidget,
      );
      expect(await rateText(tester), '', reason: 'no rate for euros yet');
      expect(inSheet(find.text('1 EUR =')), findsOneWidget);
      expect(inSheet(find.text('THB')), findsOneWidget, reason: 'after it');

      await enter(tester, 'add-amount', '12.34');
      await expectLines(tester, asTyped: '= ${eur(1234)}');
      await tapIn(tester, 'add-cat-food');
      await tester.tapId('add-submit');
      await show(tester, 'add-rate');
      expect(find.text('Enter the rate'), findsOneWidget);
      expect(await stored(tester, app), isEmpty);

      await enter(tester, 'add-rate', '39.12');
      expect(find.text('Enter the rate'), findsNothing);
      await expectLines(
        tester,
        asTyped: '= ${eur(1234)}',
        atHome: thb(48274),
      );
      await tester.tapId('add-submit');

      final e = (await stored(tester, app)).single;
      expect(
        (e.currency, e.amountMinor, e.rate, e.convertedMinor),
        ('EUR', 1234, rate('39.12'), 48274),
      );
      expect(
        await tester.runAsync(() => app.journal.lastRate('EUR')),
        rate('39.12'),
      );

      // Timeline: the amount as spent, and under it the amount at home; the
      // day's total in baht.
      final row = byId('tl-row-${e.id}');
      expect(
        find.descendant(of: row, matching: find.text(eur(1234))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('= ${thb(48274)}')),
        findsOneWidget,
      );
      expect(find.text('Spent ${thb(48274)}'), findsOneWidget);
    },
  );

  testWidgets(
    'the last rate for that currency is filled in; ⇄ types it the other way and keeps both',
    (tester) async {
      final app = await openAdd(tester, seed: euroSpend);
      await pickCurrency(tester, 'EUR');
      expect(await rateText(tester), '39.12');
      await enter(tester, 'add-amount', '12.34');
      await expectLines(
        tester,
        asTyped: '= ${eur(1234)}',
        atHome: thb(48274),
      );

      await tapIn(tester, 'add-rate-flip');
      expect(inSheet(find.text('1 THB =')), findsOneWidget);
      expect(await rateText(tester), '');
      await enter(tester, 'add-rate', '0.0256');
      await expectLines(
        tester,
        asTyped: '= ${eur(1234)}',
        atHome: thb(48203),
      );

      await tapIn(tester, 'add-rate-flip');
      expect(inSheet(find.text('1 EUR =')), findsOneWidget);
      expect(await rateText(tester), '39.12', reason: 'kept');
      await tapIn(tester, 'add-rate-flip');
      expect(await rateText(tester), '0.0256', reason: 'kept too');

      await tapIn(tester, 'add-cat-food');
      await tester.tapId('add-submit');
      final added = (await stored(
        tester,
        app,
      )).firstWhere((e) => e.id != 'entry-1');
      expect(
        (added.rate, added.convertedMinor),
        (rate('0.0256', RateDirection.fromHome), 48203),
      );
    },
  );

  testWidgets(
    'errors: a grouping mark at once; no rate or 0 after Add; too small or too large at once',
    (tester) async {
      final app = await openAdd(tester);
      await pickCurrency(tester, 'EUR');
      await enter(tester, 'add-amount', '12.34');
      await enter(tester, 'add-rate', '1,400');
      expect(
        find.text('Type the rate with digits and one . only, like 36.5.'),
        findsOneWidget,
      );
      await expectLines(tester, asTyped: '= ${eur(1234)}');

      await enter(tester, 'add-rate', '0');
      expect(
        find.text('Enter a rate above 0'),
        findsNothing,
        reason: 'not before Add',
      );
      await tapIn(tester, 'add-cat-food');
      await tester.tapId('add-submit');
      await show(tester, 'add-rate');
      expect(find.text('Enter a rate above 0'), findsOneWidget);

      // ¥1 at "1 JPY = 0.0001 THB" is under a satang.
      await pickCurrency(tester, 'JPY');
      await enter(tester, 'add-amount', '1');
      await enter(tester, 'add-rate', '0.0001');
      expect(
        find.text("At this rate, that's less than ${thb(1)}."),
        findsOneWidget,
      );
      // ¥999,999,999 at "1 JPY = 99999 THB" is over the 12-digit cap.
      await enter(tester, 'add-amount', '999999999');
      await enter(tester, 'add-rate', '99999');
      expect(find.text('That amount is too large.'), findsOneWidget);
      await tester.tapId('add-submit');
      expect(await stored(tester, app), isEmpty);
    },
  );

  testWidgets(
    'where "," is the decimal separator (de), the rate takes "," and refuses "."',
    (tester) async {
      final app = await openAdd(tester, localeName: 'de_DE');
      await pickCurrency(tester, 'EUR');
      await enter(tester, 'add-amount', '12,34');
      await enter(tester, 'add-rate', '39.12');
      expect(
        find.text('Type the rate with digits and one , only, like 36,5.'),
        findsOneWidget,
      );
      await enter(tester, 'add-rate', '39,12');
      await expectLines(
        tester,
        asTyped: '= ${eur(1234, 'de_DE')}',
        atHome: thb(48274, 'de_DE'),
      );
      await tapIn(tester, 'add-cat-food');
      await tester.tapId('add-submit');
      expect((await stored(tester, app)).single.rate, rate('39.12'));
    },
  );

  testWidgets(
    'an edit in euros: its rate filled in, a new amount converted again; back in baht, no rate',
    (tester) async {
      final app = await openTimeline(tester, seed: euroSpend);
      await tester.tapId('tl-row-entry-1');
      await show(tester, 'add-currency');
      expect(
        find.descendant(of: byId('add-currency'), matching: find.text('EUR')),
        findsOneWidget,
      );
      expect(await rateText(tester), '39.12');
      await expectLines(
        tester,
        asTyped: '= ${eur(1234)}',
        atHome: thb(48274),
      );

      await enter(tester, 'add-amount', '20');
      await expectLines(
        tester,
        asTyped: '= ${eur(2000)}',
        atHome: thb(78240),
      );
      await tester.tapId('edit-save');
      var e = (await stored(tester, app)).single;
      expect((e.amountMinor, e.convertedMinor), (2000, 78240));

      await tester.tapId('tl-row-entry-1');
      await pickCurrency(tester, 'THB');
      await show(tester, 'add-currency');
      expect(byId('add-rate'), findsNothing, reason: 'no rate in baht');
      expect(inSheet(find.text('Rate')), findsNothing);
      await enter(tester, 'add-amount', '782.40');
      await expectLines(tester, asTyped: '= ${thb(78240)}');
      await tester.tapId('edit-save');
      e = (await stored(tester, app)).single;
      expect(
        (e.currency, e.amountMinor, e.rate, e.convertedMinor),
        ('THB', 78240, null, null),
      );
    },
  );

  testWidgets('Me: the row is the home currency', (tester) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    await tester.tapId('tab-me');
    await tester.revealId('me-currency');
    expect(
      find.descendant(
        of: byId('me-currency'),
        matching: find.text('Home currency'),
      ),
      findsOneWidget,
    );
  });
}
