// The currencies Piggybow v0.1 offers, their minor digits, and the default for a device locale.
//
// Money is stored as integer minor units plus a currency code. The minor-digits table below
// decides how a stored amount is read, so it is pinned by a test: changing an entry after a
// release would reinterpret every amount already saved in that currency.

import 'package:intl/number_symbols_data.dart' show numberFormatSymbols;

import 'locale.dart';

/// The v0.1 list, in the plan's order.
const List<String> supportedCurrencies = [
  'THB', 'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'HKD', 'TWD', 'SGD', 'MYR', 'IDR', //
  'PHP', 'VND', 'KRW', 'INR', 'AUD', 'NZD', 'CAD', 'BRL', 'MXN', 'ARS', 'CLP', //
  'COP', 'CHF', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF', 'TRY', 'ZAR', 'ILS', //
];

/// Minor digits per currency, as intl formats them (CLDR). Pinned; never change after release.
///
/// IDR, COP and HUF are 0 here (intl and everyday use), where ISO 4217 lists 2.
const Map<String, int> _minorDigits = {
  'THB': 2, 'USD': 2, 'EUR': 2, 'GBP': 2, 'JPY': 0, 'CNY': 2, 'HKD': 2, 'TWD': 2, //
  'SGD': 2, 'MYR': 2, 'IDR': 0, 'PHP': 2, 'VND': 0, 'KRW': 0, 'INR': 2, 'AUD': 2, //
  'NZD': 2, 'CAD': 2, 'BRL': 2, 'MXN': 2, 'ARS': 2, 'CLP': 0, 'COP': 0, 'CHF': 2, //
  'SEK': 2, 'NOK': 2, 'DKK': 2, 'PLN': 2, 'CZK': 2, 'HUF': 0, 'TRY': 2, 'ZAR': 2, //
  'ILS': 2, //
};

/// How many minor digits [code] has (THB 2, JPY 0). Throws [ArgumentError] for a code that
/// isn't in [supportedCurrencies], so an unknown code can never be read with a guessed scale.
int minorDigitsOf(String code) {
  final digits = _minorDigits[code];
  if (digits == null) throw ArgumentError.value(code, 'code', 'not a supported currency');
  return digits;
}

/// The currency of each region (ISO 3166-1 alpha-2) whose currency is in the list.
///
/// intl has region data for only a few locales, so "es_AR" would otherwise fall back to "es"
/// and get the euro. Regions not listed here (with a region code) default to USD.
const Map<String, String> _regionCurrency = {
  'TH': 'THB',
  // USD
  'US': 'USD', 'PR': 'USD', 'GU': 'USD', 'VI': 'USD', 'AS': 'USD', 'MP': 'USD', 'UM': 'USD',
  'EC': 'USD', 'SV': 'USD', 'TL': 'USD', 'FM': 'USD', 'MH': 'USD', 'PW': 'USD', 'BQ': 'USD',
  'TC': 'USD', 'VG': 'USD', 'IO': 'USD',
  // EUR
  'AT': 'EUR', 'BE': 'EUR', 'BG': 'EUR', 'CY': 'EUR', 'DE': 'EUR', 'EE': 'EUR', 'ES': 'EUR',
  'FI': 'EUR', 'FR': 'EUR', 'GR': 'EUR', 'HR': 'EUR', 'IE': 'EUR', 'IT': 'EUR', 'LT': 'EUR',
  'LU': 'EUR', 'LV': 'EUR', 'MT': 'EUR', 'NL': 'EUR', 'PT': 'EUR', 'SI': 'EUR', 'SK': 'EUR',
  'AD': 'EUR', 'MC': 'EUR', 'SM': 'EUR', 'VA': 'EUR', 'ME': 'EUR', 'XK': 'EUR', 'GF': 'EUR',
  'GP': 'EUR', 'MQ': 'EUR', 'RE': 'EUR', 'YT': 'EUR', 'PM': 'EUR', 'BL': 'EUR', 'MF': 'EUR',
  'AX': 'EUR',
  // GBP
  'GB': 'GBP', 'IM': 'GBP', 'JE': 'GBP', 'GG': 'GBP',
  'JP': 'JPY', 'CN': 'CNY', 'HK': 'HKD', 'TW': 'TWD', 'SG': 'SGD', 'MY': 'MYR', 'ID': 'IDR',
  'PH': 'PHP', 'VN': 'VND', 'KR': 'KRW', 'IN': 'INR',
  // AUD, NZD
  'AU': 'AUD', 'CX': 'AUD', 'CC': 'AUD', 'NF': 'AUD', 'NR': 'AUD', 'KI': 'AUD', 'TV': 'AUD',
  'HM': 'AUD',
  'NZ': 'NZD', 'CK': 'NZD', 'NU': 'NZD', 'PN': 'NZD', 'TK': 'NZD',
  'CA': 'CAD', 'BR': 'BRL', 'MX': 'MXN', 'AR': 'ARS', 'CL': 'CLP', 'CO': 'COP',
  'CH': 'CHF', 'LI': 'CHF',
  'SE': 'SEK',
  'NO': 'NOK', 'SJ': 'NOK', 'BV': 'NOK',
  'DK': 'DKK', 'FO': 'DKK', 'GL': 'DKK',
  'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF', 'TR': 'TRY', 'ZA': 'ZAR', 'IL': 'ILS',
};

/// The currency to offer first for a device locale ("th_TH" → THB, "es_AR" → ARS, "de" → EUR).
///
/// With a region: that region's currency if it's in the list, else USD. Without one: the
/// language's default currency in intl's data if it's in the list, else USD. Never throws.
String defaultCurrency(String? deviceLocale) {
  final parts = parseLocale(deviceLocale);
  if (parts == null) return 'USD';
  final region = parts.region;
  if (region != null) return _regionCurrency[region] ?? 'USD';
  final symbols = numberFormatSymbols[parts.language];
  final code = symbols == null ? null : (symbols as dynamic).DEF_CURRENCY_CODE as String?;
  return code != null && _minorDigits.containsKey(code) ? code : 'USD';
}

/// The picker's order: [first] (the device's currency) at the top, then every other supported
/// currency sorted by its localized [name] (case-insensitive; the code breaks ties).
List<String> currencyOrder(String first, String Function(String code) name) {
  if (!_minorDigits.containsKey(first)) {
    throw ArgumentError.value(first, 'first', 'not a supported currency');
  }
  final rest = supportedCurrencies.where((c) => c != first).toList()
    ..sort((a, b) {
      final byName = name(a).toLowerCase().compareTo(name(b).toLowerCase());
      return byName != 0 ? byName : a.compareTo(b);
    });
  return [first, ...rest];
}
