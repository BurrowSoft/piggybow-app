// iOS plan S11, Apple price parity: the app shows the introductory offer
// StoreKit reports for this Apple ID (the free week, the Christmas year, or
// neither), and the Christmas price in the style of StoreKit's own yearly
// price for the storefront.
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:piggybow/features/plus/iap_plus_store.dart';

SKProductDiscountWrapper intro({
  required SKProductDiscountPaymentMode mode,
  required SKSubscriptionPeriodUnit unit,
  int units = 1,
  int periods = 1,
  String price = '29.99',
  String symbol = r'$',
}) => SKProductDiscountWrapper(
  price: price,
  priceLocale: SKPriceLocaleWrapper(currencySymbol: symbol, currencyCode: 'USD', countryCode: 'US'),
  numberOfPeriods: periods,
  paymentMode: mode,
  subscriptionPeriod: SKProductSubscriptionPeriodWrapper(numberOfUnits: units, unit: unit),
  identifier: null,
  type: SKProductDiscountType.introductory,
);

void main() {
  group("appleIntro: StoreKit's word for this Apple ID", () {
    ({bool trial, String? offerPrice}) read(SKProductDiscountWrapper? i, {bool eligible = true}) =>
        appleIntro(eligible: eligible, intro: i, yearly: r'$59.99', yearlyRaw: 59.99);

    final freeWeek = intro(mode: SKProductDiscountPaymentMode.freeTrail, unit: SKSubscriptionPeriodUnit.week, price: '0');
    final christmas = intro(mode: SKProductDiscountPaymentMode.payUpFront, unit: SKSubscriptionPeriodUnit.year);

    test('the free week: the trial, no offer price (7 days counts as a week)', () {
      expect(read(freeWeek), (trial: true, offerPrice: null));
      final sevenDays = intro(
        mode: SKProductDiscountPaymentMode.freeTrail,
        unit: SKSubscriptionPeriodUnit.day,
        units: 7,
        price: '0',
      );
      expect(read(sevenDays), (trial: true, offerPrice: null));
    });

    test('the Christmas year: its price, no trial', () {
      expect(read(christmas), (trial: false, offerPrice: r'$29.99'));
    });

    test('ineligible: neither, whatever the intro is', () {
      expect(read(freeWeek, eligible: false), (trial: false, offerPrice: null));
      expect(read(christmas, eligible: false), (trial: false, offerPrice: null));
    });

    test('none (no intro configured, or it could not be read): neither', () {
      expect(read(null), (trial: false, offerPrice: null));
    });

    test('anything else: neither (a free month is not "7-day free trial"; '
        'pay as you go; two paid years; an empty price)', () {
      expect(read(intro(mode: SKProductDiscountPaymentMode.freeTrail, unit: SKSubscriptionPeriodUnit.month, price: '0')),
          (trial: false, offerPrice: null));
      expect(read(intro(mode: SKProductDiscountPaymentMode.payAsYouGo, unit: SKSubscriptionPeriodUnit.month, periods: 12)),
          (trial: false, offerPrice: null));
      expect(read(intro(mode: SKProductDiscountPaymentMode.payUpFront, unit: SKSubscriptionPeriodUnit.year, units: 2)),
          (trial: false, offerPrice: null));
      expect(read(intro(mode: SKProductDiscountPaymentMode.payUpFront, unit: SKSubscriptionPeriodUnit.year, price: '')),
          (trial: false, offerPrice: null));
    });
  });

  group("storeStylePrice: the yearly price's own style", () {
    String style(String yearly, double raw, String amount, {String symbol = '?'}) =>
        storeStylePrice(yearly: yearly, yearlyRaw: raw, amount: amount, symbol: symbol);

    test('US, UK, euro area, Brazil, Switzerland', () {
      expect(style(r'$59.99', 59.99, '29.99'), r'$29.99');
      expect(style('£49.99', 49.99, '24.99'), '£24.99');
      expect(style('59,99 €', 59.99, '29.99'), '29,99 €');
      expect(style('R\$ 299,90', 299.9, '149.9'), 'R\$ 149,90');
      expect(style('CHF 59.00', 59, '29'), 'CHF 29.00');
    });

    test('grouping and no decimals: Japan, India, a space-grouped rouble', () {
      expect(style('¥6,000', 6000, '3000'), '¥3,000');
      expect(style('₹4,999.00', 4999, '2499'), '₹2,499.00');
      expect(style('1\u00A0234,56\u00A0₽', 1234.56, '617.28'), '617,28\u00A0₽');
      expect(style('12\u00A0000\u00A0₽', 12000, '6000'), '6\u00A0000\u00A0₽');
    });

    test("can't read it that way: the plugin's SK1 form, symbol + amount", () {
      expect(style('Free', 0, '29.99', symbol: r'$'), r'$29.99');
      expect(style(r'$59.99', 49.99, '29.99', symbol: r'$'), r'$29.99');
      expect(style(r'$59.99', 59.99, 'n/a', symbol: r'$'), r'$n/a');
    });
  });
}
