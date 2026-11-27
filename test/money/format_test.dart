// formatMoney against intl as the oracle. Floating point appears only here, in the oracle:
// the formatter itself builds the string from integers.

import 'dart:math' show pow;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:piggybow/money/currency.dart';
import 'package:piggybow/money/money.dart';

import 'matrix.dart';


/// intl's own output for the same value, the way the app would format it without our code.
String oracle(int minor, String code, String locale) => NumberFormat.simpleCurrency(
  locale: locale,
  name: code,
).format(minor / pow(10, minorDigitsOf(code)));

void main() {
  group('formatMoney equals intl', () {
    for (final locale in locales) {
      // The locale intl actually formats with, so a fallback (es_AR → es) is visible.
      final used = NumberFormat.simpleCurrency(locale: locale, name: 'USD').locale;
      group('$locale (intl uses $used)', () {
        for (final code in supportedCurrencies) {
          test('$code × ${amounts.length} amounts', () {
            for (final minor in amounts) {
              expect(formatMoney(minor, code, locale), oracle(minor, code, locale), reason: '$minor');
            }
          });
        }
      });
    }
  });

  group('spot checks (readable cases from the same matrix)', () {
    test('interface example: (123456, THB, en_US) → ฿1,234.56', () {
      expect(formatMoney(123456, 'THB', 'en_US'), '฿1,234.56');
    });
    test('en_IN uses Indian grouping', () {
      expect(formatMoney(12345678, 'INR', 'en_IN'), '₹1,23,456.78');
    });
    test('de_DE puts the symbol after the decimals, never "1.234 €,56"', () {
      expect(formatMoney(123456, 'EUR', 'de_DE'), '1.234,56\u00A0€');
    });
    test('fr_FR groups with a narrow no-break space', () {
      expect(formatMoney(123456, 'EUR', 'fr_FR'), '1\u202F234,56\u00A0€');
    });
    test("de_CH: CHF first, apostrophe grouping (intl 0.20.3's data)", () {
      expect(formatMoney(123456, 'CHF', 'de_CH'), "CHF\u00A01'234.56");
    });
    test('he_IL keeps its right-to-left marks', () {
      expect(formatMoney(123456, 'ILS', 'he_IL'), '\u200F1,234.56\u00A0\u200F₪');
    });
    test('0-digit currencies show whole units', () {
      expect(formatMoney(1200, 'JPY', 'ja_JP'), '¥1,200');
      expect(formatMoney(1200, 'VND', 'vi_VN'), '1.200\u00A0₫');
    });
    test('small amounts keep their leading zeros', () {
      expect(formatMoney(5, 'USD', 'en_US'), r'$0.05');
      expect(formatMoney(0, 'USD', 'en_US'), r'$0.00');
    });
    test('the largest single amount', () {
      expect(formatMoney(999999999999, 'USD', 'en_US'), r'$9,999,999,999.99');
    });
  });

  test('no plain space anywhere, so a number and its symbol never wrap apart', () {
    for (final locale in locales) {
      for (final code in supportedCurrencies) {
        for (final minor in amounts) {
          expect(formatMoney(minor, code, locale).contains(' '), isFalse, reason: '$minor $code $locale');
        }
      }
    }
  });

  test('totals past the 12-digit cap format exactly (beyond what floating point can hold)', () {
    const total = 12345678901234567; // more than 2^53
    expect(formatMoney(total, 'USD', 'en_US'), r'$123,456,789,012,345.67');
    expect(formatMoney(total, 'JPY', 'en_US'), '¥12,345,678,901,234,567');
  });

  test('device locale shapes format like their plain form', () {
    expect(formatMoney(123456, 'THB', 'th_TH_#u-nu-thai'), formatMoney(123456, 'THB', 'th_TH'));
    expect(formatMoney(123456, 'EUR', 'de-DE'), formatMoney(123456, 'EUR', 'de_DE'));
    expect(formatMoney(123456, 'TWD', 'zh_Hant_TW'), formatMoney(123456, 'TWD', 'zh_TW'));
  });

  test('an unknown locale formats as English instead of failing', () {
    expect(formatMoney(123456, 'USD', 'xx_YY'), formatMoney(123456, 'USD', 'en'));
    expect(formatMoney(123456, 'USD', ''), formatMoney(123456, 'USD', 'en'));
  });

  test('a negative amount or an unlisted currency throws', () {
    expect(() => formatMoney(-1, 'USD', 'en_US'), throwsArgumentError);
    expect(() => formatMoney(100, 'XYZ', 'en_US'), throwsArgumentError);
  });
}
