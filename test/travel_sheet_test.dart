import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.tapId('add-currency');
    tester.expectScreen('currency-screen');
    await tester.tapId('currency-$code');
    expect(byId('currency-screen'), findsNothing);
  }

  Future<List<Entry>> stored(WidgetTester tester, TestApp app) async =>
      (await tester.runAsync(app.journal.entries))!;

  /// What the rate field shows.
  String rateText(WidgetTester tester) => tester
      .widget<TextField>(
        find.descendant(of: byId('add-rate'), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  testWidgets('a new entry starts in the home currency, with no rate', (
    tester,
  ) async {
    await openAdd(tester);
    expect(
      find.descendant(of: byId('add-currency'), matching: find.text('THB')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(byId('add-currency')).label,
      contains('Currency: Thai baht'),
    );
    expect(byId('add-rate'), findsNothing);
    expect(byId('add-converted'), findsNothing);
  });

  testWidgets(
    'a spend in euros: the rate, the amount at home before Add, then both kept',
    (tester) async {
      final app = await openAdd(tester);
      await pickCurrency(tester, 'EUR');
      expect(
        find.descendant(of: byId('add-currency'), matching: find.text('EUR')),
        findsOneWidget,
      );
      expect(byId('add-rate'), findsOneWidget);
      expect(find.text('1 EUR ='), findsOneWidget);
      expect(find.text('THB'), findsOneWidget, reason: 'after the rate');
      expect(rateText(tester), '', reason: 'no rate for euros yet');

      await tester.enterId('add-amount', '12.34');
      expect(find.text('= ${eur(1234)}'), findsOneWidget);
      expect(byId('add-converted'), findsNothing, reason: 'no rate yet');
      await tester.tapId('add-cat-food');
      await tester.tapId('add-submit');
      await tester.revealId('add-rate');
      expect(find.text('Enter the rate'), findsOneWidget);
      expect(await stored(tester, app), isEmpty);

      await tester.enterId('add-rate', '39.12');
      expect(find.text('Enter the rate'), findsNothing);
      expect(find.text('= ${thb(48274)}'), findsOneWidget);
      await tester.tapId('add-submit');

      final e = (await stored(tester, app)).single;
      expect(
        (e.currency, e.amountMinor, e.rate, e.convertedMinor),
        ('EUR', 1234, rate('39.12'), 48274),
      );
      expect(await tester.runAsync(() => app.journal.lastRate('EUR')), rate('39.12'));

      // Timeline: the amount as spent, and under it the amount at home; the
      // day's total in baht.
      final row = byId('tl-row-${e.id}');
      expect(find.descendant(of: row, matching: find.text(eur(1234))), findsOneWidget);
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
      expect(rateText(tester), '39.12');
      await tester.enterId('add-amount', '12.34');
      expect(find.text('= ${thb(48274)}'), findsOneWidget);

      await tester.tapId('add-rate-flip');
      expect(find.text('1 THB ='), findsOneWidget);
      expect(rateText(tester), '');
      await tester.enterId('add-rate', '0.0256');
      expect(find.text('= ${thb(48203)}'), findsOneWidget);

      await tester.tapId('add-rate-flip');
      expect(find.text('1 EUR ='), findsOneWidget);
      expect(rateText(tester), '39.12', reason: 'kept');
      await tester.tapId('add-rate-flip');
      expect(rateText(tester), '0.0256', reason: 'kept too');

      await tester.tapId('add-cat-food');
      await tester.tapId('add-submit');
      final added = (await stored(tester, app)).firstWhere((e) => e.id != 'entry-1');
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
      await tester.enterId('add-amount', '12.34');
      await tester.enterId('add-rate', '1,400');
      expect(
        find.text('Type the rate with digits and one . only, like 36.5.'),
        findsOneWidget,
      );
      expect(byId('add-converted'), findsNothing);

      await tester.enterId('add-rate', '0');
      expect(find.text('Enter a rate above 0'), findsNothing, reason: 'not before Add');
      await tester.tapId('add-cat-food');
      await tester.tapId('add-submit');
      await tester.revealId('add-rate');
      expect(find.text('Enter a rate above 0'), findsOneWidget);

      // ¥1 at "1 JPY = 0.0001 THB" is under a satang.
      await pickCurrency(tester, 'JPY');
      await tester.enterId('add-amount', '1');
      await tester.enterId('add-rate', '0.0001');
      expect(
        find.text("At this rate, that's less than ${thb(1)}."),
        findsOneWidget,
      );
      // ¥999,999,999 at "1 JPY = 99999 THB" is over the 12-digit cap.
      await tester.enterId('add-amount', '999999999');
      await tester.enterId('add-rate', '99999');
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
      await tester.enterId('add-amount', '12,34');
      await tester.enterId('add-rate', '39.12');
      expect(
        find.text('Type the rate with digits and one , only, like 36,5.'),
        findsOneWidget,
      );
      await tester.enterId('add-rate', '39,12');
      expect(find.text('= ${thb(48274, 'de_DE')}'), findsOneWidget);
      await tester.tapId('add-cat-food');
      await tester.tapId('add-submit');
      expect((await stored(tester, app)).single.rate, rate('39.12'));
    },
  );

  testWidgets(
    'an edit in euros: its rate filled in, a new amount converted again; back in baht, no rate',
    (tester) async {
      final app = await openTimeline(tester, seed: euroSpend);
      await tester.tapId('tl-row-entry-1');
      expect(
        find.descendant(of: byId('add-currency'), matching: find.text('EUR')),
        findsOneWidget,
      );
      expect(rateText(tester), '39.12');
      expect(find.text('= ${thb(48274)}'), findsOneWidget);

      await tester.enterId('add-amount', '20');
      expect(find.text('= ${thb(78240)}'), findsOneWidget);
      await tester.tapId('edit-save');
      var e = (await stored(tester, app)).single;
      expect((e.amountMinor, e.convertedMinor), (2000, 78240));

      await tester.tapId('tl-row-entry-1');
      await pickCurrency(tester, 'THB');
      expect(byId('add-rate'), findsNothing);
      expect(byId('add-converted'), findsNothing);
      await tester.enterId('add-amount', '782.40');
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
      find.descendant(of: byId('me-currency'), matching: find.text('Home currency')),
      findsOneWidget,
    );
  });
}
