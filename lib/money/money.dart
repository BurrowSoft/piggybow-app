// Parsing and formatting amounts held as integer minor units, with no floating point anywhere.
//
// formatMoney gives exactly what intl's NumberFormat.simpleCurrency prints for the same value
// (symbol, its side and spacing, grouping, decimal mark, digits, direction marks), but builds
// it from integers: intl formats the whole units (an int, which it handles exactly), and the
// minor digits are placed right after the last digit, before any symbol that follows.

import 'package:intl/intl.dart' show NumberFormat;

import 'currency.dart';
import 'locale.dart';

/// The largest amount Piggybow stores: 12 digits in minor units.
const int maxAmountMinor = 999999999999;

/// Why a typed amount can't be used. The add sheet maps these to its copy.
enum AmountProblem { empty, invalid, zero, tooBig }

typedef ParsedAmount = ({int? minor, AmountProblem? problem});

const ParsedAmount _empty = (minor: null, problem: AmountProblem.empty);
const ParsedAmount _invalid = (minor: null, problem: AmountProblem.invalid);
const ParsedAmount _zero = (minor: null, problem: AmountProblem.zero);
const ParsedAmount _tooBig = (minor: null, problem: AmountProblem.tooBig);

/// Digits, then optionally one mark ("." or ",") and more digits. Nothing else: no grouping,
/// no symbol, no sign, no exponent, ASCII digits only.
final _amount = RegExp(r'^([0-9]*)(?:([.,])([0-9]*))?$');
final _leadingZeros = RegExp('^0+');

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// Shown amounts can be totals, which may pass the 12-digit cap on single amounts.
void _checkNotNegative(int minor) {
  if (minor < 0) throw ArgumentError.value(minor, 'minor', 'must not be negative');
}

/// An amount that goes back into an input field is a single amount, so the cap applies.
void _checkSingleAmount(int minor) {
  if (minor < 0 || minor > maxAmountMinor) {
    throw ArgumentError.value(minor, 'minor', 'must be between 0 and $maxAmountMinor');
  }
}

/// Reads what someone typed or pasted into an amount field, as minor units of [currency].
///
/// Accepts "12", "12.5", "12,50", ".5" and "12." (surrounding spaces are ignored), with at most
/// as many decimals as the currency has (none for JPY). Zero is [AmountProblem.zero] unless
/// [allowZero] (only "Already saved" allows it). More than 12 digits is [AmountProblem.tooBig].
ParsedAmount parseAmount(String text, String currency, {bool allowZero = false}) {
  final digits = minorDigitsOf(currency);
  final t = text.trim();
  if (t.isEmpty) return _empty;
  final m = _amount.firstMatch(t);
  if (m == null) return _invalid;
  final whole = m[1]!;
  final mark = m[2];
  final fraction = m[3] ?? '';
  if (whole.isEmpty && fraction.isEmpty) return _invalid;
  if (mark != null && digits == 0) return _invalid;
  if (fraction.length > digits) return _invalid;
  final all = (whole + fraction.padRight(digits, '0')).replaceFirst(_leadingZeros, '');
  if (all.isEmpty) return allowZero ? (minor: 0, problem: null) : _zero;
  if (all.length > 12) return _tooBig;
  final minor = int.parse(all);
  if (minor > maxAmountMinor) return _tooBig;
  return (minor: minor, problem: null);
}

/// [minor] units of [currency] as the [locale] shows money: (123456, THB, en_US) → "฿1,234.56";
/// (123456, EUR, de_DE) → "1.234,56 €" with a no-break space. Equal to intl's own output.
String formatMoney(int minor, String currency, String locale) {
  _checkNotNegative(minor);
  final digits = minorDigitsOf(currency);
  final format = NumberFormat.simpleCurrency(
    locale: intlNumberLocale(locale),
    name: currency,
    decimalDigits: 0,
  );
  final unit = _pow10(digits);
  final whole = format.format(minor ~/ unit);
  if (digits == 0) return whole;

  final symbols = format.symbols;
  final zero = symbols.ZERO_DIGIT.codeUnitAt(0);
  var last = -1;
  for (var i = whole.length - 1; i >= 0; i--) {
    final c = whole.codeUnitAt(i);
    if (c >= zero && c <= zero + 9) {
      last = i;
      break;
    }
  }
  if (last < 0) throw StateError('no digits in "$whole"');
  final minorDigits = (minor % unit).toString().padLeft(digits, '0');
  final localized = String.fromCharCodes(minorDigits.codeUnits.map((c) => zero + (c - 0x30)));
  return whole.substring(0, last + 1) + symbols.DECIMAL_SEP + localized + whole.substring(last + 1);
}

/// The amount as an edit field is pre-filled: ASCII digits and the [locale]'s decimal mark
/// ("." or ","; any other mark becomes "."), no grouping, no symbol. [parseAmount] reads it
/// back to the same [minor]: (120050, USD, de_DE) → "1200,50"; (1200, JPY, any) → "1200".
String inputAmount(int minor, String currency, String locale) {
  _checkSingleAmount(minor);
  final digits = minorDigitsOf(currency);
  if (digits == 0) return '$minor';
  final sep = NumberFormat.decimalPattern(intlNumberLocale(locale)).symbols.DECIMAL_SEP;
  final mark = sep == ',' ? ',' : '.';
  final unit = _pow10(digits);
  return '${minor ~/ unit}$mark${(minor % unit).toString().padLeft(digits, '0')}';
}

/// The amount for files (the CSV): "." as the mark and no grouping, whatever the locale.
/// (120050, THB) → "1200.50"; (5, USD) → "0.05"; (1200, JPY) → "1200".
String plainAmount(int minor, String currency) {
  _checkNotNegative(minor);
  final digits = minorDigitsOf(currency);
  if (digits == 0) return '$minor';
  final unit = _pow10(digits);
  return '${minor ~/ unit}.${(minor % unit).toString().padLeft(digits, '0')}';
}

/// The minus sign (U+2212, not a hyphen) in front of money taken out of
/// savings, the one amount shown going down. Spends never have one.
final String minusSign = String.fromCharCode(0x2212);
