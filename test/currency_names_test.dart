import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/money/currency.dart';

/// The picker's currency names (plan §4.6's table, word for word): every
/// supported currency has its own, and none falls back to its code.
void main() {
  const names = {
    'THB': 'Thai baht',
    'USD': 'US dollar',
    'EUR': 'Euro',
    'GBP': 'British pound',
    'JPY': 'Japanese yen',
    'CNY': 'Chinese yuan',
    'HKD': 'Hong Kong dollar',
    'TWD': 'New Taiwan dollar',
    'SGD': 'Singapore dollar',
    'MYR': 'Malaysian ringgit',
    'IDR': 'Indonesian rupiah',
    'PHP': 'Philippine peso',
    'VND': 'Vietnamese dong',
    'KRW': 'South Korean won',
    'INR': 'Indian rupee',
    'AUD': 'Australian dollar',
    'NZD': 'New Zealand dollar',
    'CAD': 'Canadian dollar',
    'BRL': 'Brazilian real',
    'MXN': 'Mexican peso',
    'ARS': 'Argentine peso',
    'CLP': 'Chilean peso',
    'COP': 'Colombian peso',
    'CHF': 'Swiss franc',
    'SEK': 'Swedish krona',
    'NOK': 'Norwegian krone',
    'DKK': 'Danish krone',
    'PLN': 'Polish zloty',
    'CZK': 'Czech koruna',
    'HUF': 'Hungarian forint',
    'TRY': 'Turkish lira',
    'ZAR': 'South African rand',
    'ILS': 'Israeli new shekel',
  };

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('every supported currency, named as in the plan', () {
    expect(supportedCurrencies.toSet(), names.keys.toSet());
    for (final code in supportedCurrencies) {
      expect(l10n.currencyName(code), names[code], reason: code);
    }
  });

  test('a row reads "{name} ({symbol})"', () {
    expect(l10n.currencyRow('Thai baht', 'B'), 'Thai baht (B)');
  });
}
