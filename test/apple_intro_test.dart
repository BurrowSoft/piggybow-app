// The iPhone's free week: the app shows the introductory offer StoreKit
// reports for this Apple ID, and only the free week counts as a trial.
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
  group("appleFreeWeek: StoreKit's word for this Apple ID", () {
    final freeWeek = intro(mode: SKProductDiscountPaymentMode.freeTrail, unit: SKSubscriptionPeriodUnit.week, price: '0');

    test('the free week is the trial (7 days counts as a week)', () {
      expect(appleFreeWeek(eligible: true, intro: freeWeek), isTrue);
      final sevenDays = intro(
        mode: SKProductDiscountPaymentMode.freeTrail,
        unit: SKSubscriptionPeriodUnit.day,
        units: 7,
        price: '0',
      );
      expect(appleFreeWeek(eligible: true, intro: sevenDays), isTrue);
    });

    test('ineligible: no free week, whatever the intro is', () {
      expect(appleFreeWeek(eligible: false, intro: freeWeek), isFalse);
    });

    test('none (no intro configured, or it could not be read): no free week', () {
      expect(appleFreeWeek(eligible: true, intro: null), isFalse);
    });

    test('anything else: no free week (a free month, two free weeks, pay as '
        'you go, a paid first year)', () {
      for (final other in [
        intro(mode: SKProductDiscountPaymentMode.freeTrail, unit: SKSubscriptionPeriodUnit.month, price: '0'),
        intro(mode: SKProductDiscountPaymentMode.freeTrail, unit: SKSubscriptionPeriodUnit.week, periods: 2, price: '0'),
        intro(mode: SKProductDiscountPaymentMode.payAsYouGo, unit: SKSubscriptionPeriodUnit.month, periods: 12),
        intro(mode: SKProductDiscountPaymentMode.payUpFront, unit: SKSubscriptionPeriodUnit.year),
      ]) {
        expect(appleFreeWeek(eligible: true, intro: other), isFalse, reason: '${other.paymentMode} ${other.subscriptionPeriod.unit}');
      }
    });
  });
}
