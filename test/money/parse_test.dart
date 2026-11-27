import 'dart:math' show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/money/currency.dart';
import 'package:piggybow/money/money.dart';

import 'matrix.dart' show locales;

void expectMinor(String text, String currency, int minor, {bool allowZero = false}) {
  final r = parseAmount(text, currency, allowZero: allowZero);
  expect(r.problem, isNull, reason: '"$text" $currency');
  expect(r.minor, minor, reason: '"$text" $currency');
}

void expectProblem(String text, String currency, AmountProblem problem, {bool allowZero = false}) {
  final r = parseAmount(text, currency, allowZero: allowZero);
  expect(r.minor, isNull, reason: '"$text" $currency');
  expect(r.problem, problem, reason: '"$text" $currency');
}

/// A random single amount from 1 to the cap, spread over every length (1 to 12 digits).
int randomAmount(Random r) {
  final length = 1 + r.nextInt(12);
  var n = 1 + r.nextInt(9);
  for (var i = 1; i < length; i++) {
    n = n * 10 + r.nextInt(10);
  }
  return n;
}

void main() {
  group('parseAmount, USD', () {
    test('accepts digits with "." or "," as the mark', () {
      expectMinor('12', 'USD', 1200);
      expectMinor('12.5', 'USD', 1250);
      expectMinor('12,5', 'USD', 1250);
      expectMinor('12.50', 'USD', 1250);
      expectMinor('12,50', 'USD', 1250);
      expectMinor('0.05', 'USD', 5);
      expectMinor('.5', 'USD', 50);
      expectMinor('12.', 'USD', 1200);
      expectMinor('007', 'USD', 700);
      expectMinor('9999999999.99', 'USD', 999999999999);
    });

    test('surrounding spaces are ignored', () {
      expectMinor(' 12.50 ', 'USD', 1250);
      expectMinor('\t12\n', 'USD', 1200);
    });

    test('empty', () {
      expectProblem('', 'USD', AmountProblem.empty);
      expectProblem('   ', 'USD', AmountProblem.empty);
    });

    test('zero', () {
      for (final t in ['0', '00', '0.00', '0,0', '.0', '0.']) {
        expectProblem(t, 'USD', AmountProblem.zero);
      }
    });

    test('zero is allowed only where asked ("Already saved")', () {
      expectMinor('0', 'USD', 0, allowZero: true);
      expectMinor('0.00', 'USD', 0, allowZero: true);
      expectProblem('', 'USD', AmountProblem.empty, allowZero: true);
    });

    test('more than 12 digits is too big', () {
      expectProblem('10000000000.00', 'USD', AmountProblem.tooBig);
      expectProblem('10000000000', 'USD', AmountProblem.tooBig);
      expectProblem('99999999999999999999999999', 'USD', AmountProblem.tooBig);
    });

    test('anything else is invalid', () {
      for (final t in [
        '12.345', // more decimals than USD has
        '1.234,56', // two marks
        '12,345,678',
        '12.3.4',
        '-5',
        '+5',
        '1e3',
        r'$12.50',
        '12 USD',
        '1 200',
        '.',
        ',',
        '๑๒', // Thai digits
        '１２', // full-width digits
        '١٢', // Arabic-Indic digits
        '12\u00A0000',
      ]) {
        expectProblem(t, 'USD', AmountProblem.invalid);
      }
    });
  });

  group('parseAmount, JPY (no minor digits)', () {
    test('whole units', () {
      expectMinor('1200', 'JPY', 1200);
      expectMinor('999999999999', 'JPY', 999999999999);
    });
    test('any decimal mark is invalid', () {
      expectProblem('12.5', 'JPY', AmountProblem.invalid);
      expectProblem('12.', 'JPY', AmountProblem.invalid);
      expectProblem('12,0', 'JPY', AmountProblem.invalid);
    });
    test('13 digits is too big', () {
      expectProblem('1234567890123', 'JPY', AmountProblem.tooBig);
    });
  });

  test('an unlisted currency throws', () {
    expect(() => parseAmount('12', 'XYZ'), throwsArgumentError);
  });

  test('never throws on any text, and anything accepted is in range', () {
    final r = Random(28);
    const alphabet = '0123456789.,-+ e\$\u00A0๑';
    for (var i = 0; i < 20000; i++) {
      final text = String.fromCharCodes([
        for (var j = r.nextInt(20); j > 0; j--) alphabet.codeUnitAt(r.nextInt(alphabet.length)),
      ]);
      for (final code in const ['USD', 'JPY']) {
        final p = parseAmount(text, code);
        expect((p.minor == null) != (p.problem == null), isTrue, reason: '"$text"');
        if (p.minor != null) {
          expect(p.minor! >= 1 && p.minor! <= maxAmountMinor, isTrue, reason: '"$text"');
        }
      }
    }
  });

  group('the edit field round trip', () {
    test('inputAmount: plain digits and the locale\'s mark, no grouping or symbol', () {
      expect(inputAmount(120050, 'USD', 'en_US'), '1200.50');
      expect(inputAmount(120050, 'USD', 'de_DE'), '1200,50');
      expect(inputAmount(120050, 'EUR', 'fr_FR'), '1200,50');
      expect(inputAmount(5, 'USD', 'en_US'), '0.05');
      expect(inputAmount(1200, 'JPY', 'de_DE'), '1200');
      expect(inputAmount(999999999999, 'USD', 'en_US'), '9999999999.99');
    });

    test('parse(inputAmount(x)) == x for every currency × locale', () {
      final r = Random(28);
      for (final code in supportedCurrencies) {
        for (final locale in locales) {
          for (final minor in [1, 5, 100, maxAmountMinor, for (var i = 0; i < 40; i++) randomAmount(r)]) {
            final text = inputAmount(minor, code, locale);
            expect(parseAmount(text, code).minor, minor, reason: '$minor $code $locale "$text"');
          }
        }
      }
    });

    test('the display form never parses (so a symbol or grouping is never misread)', () {
      final r = Random(28);
      for (final code in supportedCurrencies) {
        for (final locale in locales) {
          for (final minor in [1, 1234, 123456, for (var i = 0; i < 10; i++) randomAmount(r)]) {
            final shown = formatMoney(minor, code, locale);
            expect(parseAmount(shown, code).problem, isNotNull, reason: '$code $locale "$shown"');
          }
        }
      }
    });

    test('inputAmount refuses amounts a field can\'t hold', () {
      expect(() => inputAmount(-1, 'USD', 'en_US'), throwsArgumentError);
      expect(() => inputAmount(maxAmountMinor + 1, 'USD', 'en_US'), throwsArgumentError);
    });
  });

  group('plainAmount (files)', () {
    test('"." and no grouping, whatever the locale', () {
      expect(plainAmount(120050, 'USD'), '1200.50');
      expect(plainAmount(120050, 'THB'), '1200.50');
      expect(plainAmount(5, 'USD'), '0.05');
      expect(plainAmount(0, 'USD'), '0.00');
      expect(plainAmount(1200, 'JPY'), '1200');
      expect(plainAmount(999999999999, 'USD'), '9999999999.99');
    });
    test('a negative amount throws', () {
      expect(() => plainAmount(-5, 'USD'), throwsArgumentError);
    });
  });
}
