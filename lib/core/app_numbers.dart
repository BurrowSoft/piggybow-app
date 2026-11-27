import 'package:intl/intl.dart';

/// Every user-facing decimal in the UI goes through these (localization
/// plan, 2026-11-05): the locale's decimal mark and grouping, "3.8" in
/// English, "3,8" in French and German, "20 000" in French. Pass the UI
/// language (AppLocalizations.localeName), so the numbers always match the
/// words around them. Exports and storage keep plain numbers and never use
/// them.
abstract final class AppNumbers {
  /// [value] with exactly [decimals] digits after the mark: 3.84 → "3.8".
  static String fixed(String locale, double value, int decimals) =>
      NumberFormat(
        decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}',
        locale,
      ).format(value);

  /// Whole hours without a mark, else one decimal: 7 → "7", 7.5 → "7.5".
  static String hours(String locale, double h) =>
      fixed(locale, h, h == h.roundToDouble() ? 0 : 1);
}
