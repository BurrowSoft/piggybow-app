import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/money/money.dart';
import 'package:piggybow/money/rate.dart';

/// Money in another currency (feature 19): a typed rate, read the way it was
/// typed, and one conversion into the home currency, with integers only and
/// one rounding, halves up.
void main() {
  const toHome = RateDirection.toHome;
  const fromHome = RateDirection.fromHome;

  Rate rate(String text, [RateDirection direction = toHome]) => parseRate(text, direction).rate!;

  int? convert(int minor, String currency, String home, Rate r) =>
      toHomeMinor(amountMinor: minor, currency: currency, home: home, rate: r);

  group('a typed rate', () {
    test('"." or "," as the mark; kept as its digits and their scale', () {
      expect(rate('39.12'), const Rate(units: 3912, scale: 2, direction: toHome));
      expect(rate('39,12'), const Rate(units: 3912, scale: 2, direction: toHome));
      expect(rate('0.0256', fromHome), const Rate(units: 256, scale: 4, direction: fromHome));
      expect(rate('.5'), const Rate(units: 5, scale: 1, direction: toHome));
      expect(rate('25400'), const Rate(units: 25400, scale: 0, direction: toHome));
      expect(rate(' 7. '), const Rate(units: 7, scale: 0, direction: toHome));
    });

    test('written back with "." and its own digits', () {
      expect(rate('39,12').plain, '39.12');
      expect(rate('0.0256').plain, '0.0256');
      expect(rate('39.10').plain, '39.10');
      expect(rate('25400').plain, '25400');
    });

    test('empty, unreadable, zero, over 6 decimals or over 9 digits: refused', () {
      expect(parseRate('', toHome).problem, RateProblem.empty);
      expect(parseRate('  ', toHome).problem, RateProblem.empty);
      for (final bad in ['abc', '1.2.3', '1,000.5', '-3', '+3', '1e3', '.', '1.1234567', '1234567890']) {
        expect(parseRate(bad, toHome).problem, RateProblem.invalid, reason: bad);
      }
      for (final zero in ['0', '0.0', '000', '.000']) {
        expect(parseRate(zero, toHome).problem, RateProblem.zero, reason: zero);
      }
      // Leading zeros don't count toward the 9 digits.
      expect(rate('000123456789').units, 123456789);
    });

    test('as stored, and read back; anything odd is not a rate', () {
      final r = rate('0.0256', fromHome);
      expect(Rate.fromMap(r.toMap()), r);
      expect(r.toMap(), {'units': 256, 'scale': 4, 'dir': 'from_home'});
      for (final bad in [
        null,
        'x',
        {'units': 0, 'scale': 2, 'dir': 'to_home'},
        {'units': 12, 'scale': 7, 'dir': 'to_home'},
        {'units': 12, 'scale': 2, 'dir': 'sideways'},
        {'units': '12', 'scale': 2, 'dir': 'to_home'},
      ]) {
        expect(Rate.fromMap(bad), isNull, reason: '$bad');
      }
    });

    test('the CSV form, with codes, from the digits', () {
      expect(rateText(rate('39,12'), currency: 'EUR', home: 'THB'), '1 EUR = 39.12 THB');
      expect(rateText(rate('0.0256', fromHome), currency: 'EUR', home: 'THB'), '1 THB = 0.0256 EUR');
    });
  });

  group('one conversion into the home currency', () {
    test('€12.34 at "1 EUR = 39.12 THB" is ฿482.74 (482.7408)', () {
      expect(convert(1234, 'EUR', 'THB', rate('39.12')), 48274);
    });

    test('the other way: €12.34 at "1 THB = 0.0256 EUR" is ฿482.03 (482.03125)', () {
      expect(convert(1234, 'EUR', 'THB', rate('0.0256', fromHome)), 48203);
    });

    test('0-digit currencies, both ways', () {
      // ¥1,000 at "1 JPY = 0.2301 THB": ฿230.10.
      expect(convert(1000, 'JPY', 'THB', rate('0.2301')), 23010);
      // ฿100.00 in a yen journal at "1 THB = 4.35 JPY": ¥435.
      expect(convert(10000, 'THB', 'JPY', rate('4.35')), 435);
      // ₫250,000 at "1 USD = 25400 VND", into dollars: $9.84 (9.8425…).
      expect(convert(250000, 'VND', 'USD', rate('25400', fromHome)), 984);
      // Rp100,000 at "1 IDR = 0.0021 THB": ฿210.00.
      expect(convert(100000, 'IDR', 'THB', rate('0.0021')), 21000);
      // 10,000 Ft into won at "1 HUF = 3.9 KRW": ₩39,000.
      expect(convert(10000, 'HUF', 'KRW', rate('3.9')), 39000);
    });

    test('halves go up; anything under a half goes down', () {
      // $0.01 at "1 USD = 0.5 EUR": 0.5 of a cent, up to 1.
      expect(convert(1, 'USD', 'EUR', rate('0.5')), 1);
      // $0.03 at "1 USD = 0.5 EUR": 1.5, up to 2.
      expect(convert(3, 'USD', 'EUR', rate('0.5')), 2);
      // $0.01 at "1 USD = 1.49 EUR": 1.49, down to 1.
      expect(convert(1, 'USD', 'EUR', rate('1.49')), 1);
      // $0.01 at "1 USD = 1.5 EUR": 1.5, up to 2.
      expect(convert(1, 'USD', 'EUR', rate('1.5')), 2);
    });

    test('under one minor unit, or over the 12-digit cap: no amount', () {
      // $0.01 at "1 USD = 0.4 EUR": 0.4 of a cent.
      expect(convert(1, 'USD', 'EUR', rate('0.4')), isNull);
      // The largest amount at a rate over 1.
      expect(convert(maxAmountMinor, 'USD', 'THB', rate('1.01')), isNull);
      // The largest amount at 1 still fits.
      expect(convert(maxAmountMinor, 'USD', 'EUR', rate('1')), maxAmountMinor);
    });

    test('never from nothing', () {
      expect(() => convert(0, 'USD', 'EUR', rate('1')), throwsArgumentError);
    });
  });
}
