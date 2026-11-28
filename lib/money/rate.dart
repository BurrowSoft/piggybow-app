// Money in another currency (feature 19): the rate a person types, and the
// one conversion of an amount into the journal's home currency.
//
// No floating point anywhere. A rate is [Rate.units] × 10^-[Rate.scale],
// read the way it was typed ([RateDirection]). An amount is converted once,
// when it's saved, with BigInt and a single rounding: halves go up (amounts
// are never negative).

import 'package:intl/intl.dart' show NumberFormat;

import 'currency.dart';
import 'locale.dart';
import 'money.dart';

/// Which way a rate was typed.
enum RateDirection {
  /// "1 EUR = 39.12 THB": how much home money one unit of the other buys.
  toHome('to_home'),

  /// "1 THB = 0.0256 EUR": how much of the other one unit of home money buys.
  fromHome('from_home');

  const RateDirection(this.id);

  /// The stored value.
  final String id;

  static RateDirection? fromId(Object? id) =>
      values.where((d) => d.id == id).firstOrNull;
}

/// At most this many decimals in a rate ("0.025641").
const int maxRateDecimals = 6;

/// At most this many digits in a rate, leading zeros aside.
const int maxRateDigits = 9;

/// A rate as typed: [units] × 10^-[scale], read in [direction].
class Rate {
  const Rate({required this.units, required this.scale, required this.direction})
    : assert(units > 0),
      assert(scale >= 0 && scale <= maxRateDecimals);

  /// The digits as typed, without the mark: "39.12" is 3912.
  final int units;

  /// How many of them come after the mark: "39.12" is 2.
  final int scale;
  final RateDirection direction;

  /// The rate as it was typed, with "." as the mark: "39.12", "0.0256".
  String get plain {
    if (scale == 0) return '$units';
    final digits = '$units'.padLeft(scale + 1, '0');
    final at = digits.length - scale;
    return '${digits.substring(0, at)}.${digits.substring(at)}';
  }

  Map<String, Object> toMap() => {'units': units, 'scale': scale, 'dir': direction.id};

  /// Null for a rate this build can't read.
  static Rate? fromMap(Object? m) {
    if (m is! Map) return null;
    final units = m['units'];
    final scale = m['scale'];
    final direction = RateDirection.fromId(m['dir']);
    if (units is! int || units <= 0) return null;
    if (scale is! int || scale < 0 || scale > maxRateDecimals) return null;
    if (direction == null) return null;
    return Rate(units: units, scale: scale, direction: direction);
  }

  @override
  bool operator ==(Object other) =>
      other is Rate && other.units == units && other.scale == scale && other.direction == direction;

  @override
  int get hashCode => Object.hash(units, scale, direction);

  @override
  String toString() => 'Rate($plain, ${direction.id})';
}

/// Why a typed rate can't be used. The sheet maps these to its copy.
enum RateProblem { empty, invalid, zero }

typedef ParsedRate = ({Rate? rate, RateProblem? problem});

final _leadingZeros = RegExp('^0+');

/// The mark a rate is typed with in [locale]: its decimal separator, "." or
/// "," (any other becomes "."), as amounts are pre-filled ([inputAmount]).
String rateMark(String locale) {
  final sep = NumberFormat.decimalPattern(intlNumberLocale(locale)).symbols.DECIMAL_SEP;
  return sep == ',' ? ',' : '.';
}

/// Digits, then optionally [mark] and more digits: never a grouping mark, so
/// "1,400" is no rate where "," groups thousands (en) and 1.4 where it's the
/// decimal separator (de).
RegExp _rateText(String mark) => RegExp('^([0-9]*)(?:${RegExp.escape(mark)}([0-9]*))?\$');

/// Reads a typed rate ("39.12" with "." as the [mark], "39,12" with ","):
/// at most [maxRateDecimals] decimals and [maxRateDigits] digits, and more
/// than 0. Any other character, the other mark included, is
/// [RateProblem.invalid].
ParsedRate parseRate(String text, RateDirection direction, {required String mark}) {
  assert(mark == '.' || mark == ',');
  final t = text.trim();
  if (t.isEmpty) return (rate: null, problem: RateProblem.empty);
  final m = _rateText(mark).firstMatch(t);
  if (m == null) return (rate: null, problem: RateProblem.invalid);
  final whole = m[1]!;
  final fraction = m[2] ?? '';
  if (whole.isEmpty && fraction.isEmpty) return (rate: null, problem: RateProblem.invalid);
  if (fraction.length > maxRateDecimals) return (rate: null, problem: RateProblem.invalid);
  final digits = (whole + fraction).replaceFirst(_leadingZeros, '');
  if (digits.isEmpty) return (rate: null, problem: RateProblem.zero);
  if (digits.length > maxRateDigits) return (rate: null, problem: RateProblem.invalid);
  return (
    rate: Rate(units: int.parse(digits), scale: fraction.length, direction: direction),
    problem: null,
  );
}

/// [amountMinor] of [currency] in [home]'s minor units, at [rate]: converted
/// once, and rounded once, halves up. Null when that's less than one minor
/// unit, or more than [maxAmountMinor] ([convertToHome] says which).
///
/// - toHome: amount × units × 10^d(home) ÷ (10^scale × 10^d(currency))
/// - fromHome: amount × 10^scale × 10^d(home) ÷ (units × 10^d(currency))
///
/// d is a currency's minor digits (decision 28): €12.34 at "1 EUR = 39.12
/// THB" is 1234 × 3912 × 100 ÷ (100 × 100) = 48274.08, so ฿482.74.
int? toHomeMinor({
  required int amountMinor,
  required String currency,
  required String home,
  required Rate rate,
}) => convertToHome(amountMinor: amountMinor, currency: currency, home: home, rate: rate).minor;

/// Why a conversion gives no amount: under one minor unit of the home
/// currency, or over [maxAmountMinor].
enum ConversionProblem { tooSmall, tooLarge }

typedef Conversion = ({int? minor, ConversionProblem? problem});

/// [toHomeMinor], saying why when there's no amount.
Conversion convertToHome({
  required int amountMinor,
  required String currency,
  required String home,
  required Rate rate,
}) {
  if (amountMinor <= 0) {
    throw ArgumentError.value(amountMinor, 'amountMinor', 'must be positive');
  }
  final from = _tenTo(minorDigitsOf(currency));
  final to = _tenTo(minorDigitsOf(home));
  final scale = _tenTo(rate.scale);
  final amount = BigInt.from(amountMinor);
  final units = BigInt.from(rate.units);
  final (numerator, denominator) = switch (rate.direction) {
    RateDirection.toHome => (amount * units * to, scale * from),
    RateDirection.fromHome => (amount * scale * to, units * from),
  };
  final quotient = numerator ~/ denominator;
  final rest = numerator.remainder(denominator);
  final rounded = rest * BigInt.two >= denominator ? quotient + BigInt.one : quotient;
  if (rounded < BigInt.one) return (minor: null, problem: ConversionProblem.tooSmall);
  if (rounded > BigInt.from(maxAmountMinor)) {
    return (minor: null, problem: ConversionProblem.tooLarge);
  }
  return (minor: rounded.toInt(), problem: null);
}

/// 10 to the [n], by multiplying (the money path uses no power function).
BigInt _tenTo(int n) {
  var r = BigInt.one;
  for (var i = 0; i < n; i++) {
    r *= BigInt.from(10);
  }
  return r;
}

/// [rate] as its field is pre-filled: its digits with [mark] ("39,12" in de).
/// [parseRate] reads it back to the same rate.
String rateInput(Rate rate, String mark) => rate.plain.replaceFirst('.', mark);

/// The rate as typed, with currency codes, for the CSV:
/// "1 EUR = 39.12 THB" or "1 THB = 0.0256 EUR".
String rateText(Rate rate, {required String currency, required String home}) =>
    switch (rate.direction) {
      RateDirection.toHome => '1 $currency = ${rate.plain} $home',
      RateDirection.fromHome => '1 $home = ${rate.plain} $currency',
    };
