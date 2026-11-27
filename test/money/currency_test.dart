import 'package:flutter_test/flutter_test.dart';
import 'package:intl/number_symbols_data.dart' show currencyFractionDigits;
import 'package:piggybow/money/currency.dart';

/// PINNED. This table decides how every stored amount is read: changing a value after a release
/// would reinterpret amounts already saved in that currency, so any change here is BLOCKING.
///
/// Taken from intl 0.20.3 (CLDR). Deliberate differences from ISO 4217 (decision 28): IDR, COP
/// and HUF are 0 here (ISO lists 2). intl formats them without decimals and they aren't used
/// with cents day to day.
const Map<String, int> pinnedMinorDigits = {
  'THB': 2, 'USD': 2, 'EUR': 2, 'GBP': 2, 'JPY': 0, 'CNY': 2, 'HKD': 2, 'TWD': 2, //
  'SGD': 2, 'MYR': 2, 'IDR': 0, 'PHP': 2, 'VND': 0, 'KRW': 0, 'INR': 2, 'AUD': 2, //
  'NZD': 2, 'CAD': 2, 'BRL': 2, 'MXN': 2, 'ARS': 2, 'CLP': 0, 'COP': 0, 'CHF': 2, //
  'SEK': 2, 'NOK': 2, 'DKK': 2, 'PLN': 2, 'CZK': 2, 'HUF': 0, 'TRY': 2, 'ZAR': 2, //
  'ILS': 2, //
};

/// The plan's English names (§4.6), standing in for the ARB lookup.
const Map<String, String> englishNames = {
  'THB': 'Thai baht', 'USD': 'US dollar', 'EUR': 'Euro', 'GBP': 'British pound',
  'JPY': 'Japanese yen', 'CNY': 'Chinese yuan', 'HKD': 'Hong Kong dollar',
  'TWD': 'New Taiwan dollar', 'SGD': 'Singapore dollar', 'MYR': 'Malaysian ringgit',
  'IDR': 'Indonesian rupiah', 'PHP': 'Philippine peso', 'VND': 'Vietnamese dong',
  'KRW': 'South Korean won', 'INR': 'Indian rupee', 'AUD': 'Australian dollar',
  'NZD': 'New Zealand dollar', 'CAD': 'Canadian dollar', 'BRL': 'Brazilian real',
  'MXN': 'Mexican peso', 'ARS': 'Argentine peso', 'CLP': 'Chilean peso',
  'COP': 'Colombian peso', 'CHF': 'Swiss franc', 'SEK': 'Swedish krona',
  'NOK': 'Norwegian krone', 'DKK': 'Danish krone', 'PLN': 'Polish zloty',
  'CZK': 'Czech koruna', 'HUF': 'Hungarian forint', 'TRY': 'Turkish lira',
  'ZAR': 'South African rand', 'ILS': 'Israeli new shekel',
};

void main() {
  group('the currency table', () {
    test("the list is the plan's 33 codes, each once, in the plan's order", () {
      expect(supportedCurrencies, [
        'THB', 'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'HKD', 'TWD', 'SGD', 'MYR', 'IDR', //
        'PHP', 'VND', 'KRW', 'INR', 'AUD', 'NZD', 'CAD', 'BRL', 'MXN', 'ARS', 'CLP', //
        'COP', 'CHF', 'SEK', 'NOK', 'DKK', 'PLN', 'CZK', 'HUF', 'TRY', 'ZAR', 'ILS', //
      ]);
      expect(supportedCurrencies.toSet(), pinnedMinorDigits.keys.toSet());
    });

    test('minor digits are pinned for all 33', () {
      for (final code in supportedCurrencies) {
        expect(minorDigitsOf(code), pinnedMinorDigits[code], reason: code);
      }
    });

    test('the 0-digit currencies are exactly CLP, COP, HUF, IDR, JPY, KRW, VND', () {
      final zero = [for (final c in supportedCurrencies) if (minorDigitsOf(c) == 0) c]..sort();
      expect(zero, ['CLP', 'COP', 'HUF', 'IDR', 'JPY', 'KRW', 'VND']);
    });

    test("the pinned digits equal intl's, so what's shown matches what's stored", () {
      for (final code in supportedCurrencies) {
        expect(
          minorDigitsOf(code),
          currencyFractionDigits[code] ?? currencyFractionDigits['DEFAULT'],
          reason: code,
        );
      }
    });

    test('an unlisted or badly written code throws instead of guessing a scale', () {
      for (final code in ['XYZ', 'usd', 'US', '', 'BTC', 'BGN']) {
        expect(() => minorDigitsOf(code), throwsArgumentError, reason: code);
      }
    });
  });

  group('defaultCurrency', () {
    const cases = <String, String>{
      'th_TH': 'THB',
      'en_US': 'USD',
      'en_GB': 'GBP',
      'en-GB': 'GBP',
      'de_DE': 'EUR',
      'fr_FR': 'EUR',
      'pt_PT': 'EUR',
      'nl_BE': 'EUR',
      'ja_JP': 'JPY',
      'ko_KR': 'KRW',
      'vi_VN': 'VND',
      'id_ID': 'IDR',
      'ms_MY': 'MYR',
      'zh_Hans_CN': 'CNY',
      'zh_Hant_TW': 'TWD',
      'zh_Hant_HK': 'HKD',
      'de_CH': 'CHF',
      'fr_CH': 'CHF',
      'he_IL': 'ILS',
      'pt_BR': 'BRL',
      'sv_SE': 'SEK',
      'nb_NO': 'NOK',
      'da_DK': 'DKK',
      'en_IN': 'INR',
      'en_AU': 'AUD',
      'en_NZ': 'NZD',
      'en_CA': 'CAD',
      'fr_CA': 'CAD',
      'en_SG': 'SGD',
      'en_PH': 'PHP',
      'es_AR': 'ARS',
      'es_MX': 'MXN',
      'es_CL': 'CLP',
      'es_CO': 'COP',
      'pl_PL': 'PLN',
      'cs_CZ': 'CZK',
      'hu_HU': 'HUF',
      'tr_TR': 'TRY',
      'en_ZA': 'ZAR',
      // A region whose currency isn't listed, or a numeric region: USD.
      'ur_PK': 'USD',
      'ar_EG': 'USD',
      'es_419': 'USD',
      // Device shapes: Android's extension, POSIX encodings.
      'th_TH_#u-nu-thai': 'THB',
      'de_DE.UTF-8': 'EUR',
      'de_DE@euro': 'EUR',
      // No region: the language's default in intl, if listed.
      'th': 'THB',
      'de': 'EUR',
      'ja': 'JPY',
      'en': 'USD',
      // Nothing usable: USD.
      '': 'USD',
      'C': 'USD',
      'POSIX': 'USD',
      'xx_YY': 'USD',
    };
    for (final entry in cases.entries) {
      test('"${entry.key}" → ${entry.value}', () {
        expect(defaultCurrency(entry.key), entry.value);
      });
    }

    test('no locale → USD', () => expect(defaultCurrency(null), 'USD'));

    test('the answer is always a listed currency', () {
      for (final l in [...cases.keys, 'en_US_POSIX', 'sr_Latn_RS', 'yue_Hant_HK', 'en_001']) {
        expect(supportedCurrencies, contains(defaultCurrency(l)), reason: l);
      }
    });
  });

  group('currencyOrder', () {
    String name(String code) => englishNames[code]!;

    test("the device's currency first, then every other one by name", () {
      final order = currencyOrder('THB', name);
      expect(order.first, 'THB');
      expect(order.length, 33);
      expect(order.toSet(), supportedCurrencies.toSet());
      final rest = order.skip(1).map(name).toList();
      final sorted = [...rest]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(rest, sorted);
      expect(order.sublist(1, 4), ['ARS', 'AUD', 'BRL']); // Argentine, Australian, Brazilian
    });

    test('names that compare equal fall back to the code', () {
      final order = currencyOrder('USD', (_) => 'same');
      expect(order.first, 'USD');
      expect(order.skip(1), [...supportedCurrencies.where((c) => c != 'USD')]..sort());
    });

    test('an unlisted first currency throws', () {
      expect(() => currencyOrder('XYZ', name), throwsArgumentError);
    });
  });
}
