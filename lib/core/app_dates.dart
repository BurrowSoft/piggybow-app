import 'package:intl/intl.dart';

/// Every user-facing date in the UI goes through these (decision 89 for the
/// locale, decision 193 for the era), the year card's title included.
/// Storage, exports and file names (piggybow-2026.png too) stay Gregorian
/// and never use them.
///
/// Thai UI dates show the Buddhist-era year (พ.ศ., 2026 → 2569), as Thai
/// readers expect. The date locale's language is the UI language, and the
/// UI can only be Thai when THAI_OFFERED ships it (1.1 F, thai_reviewed), so
/// no separate switch is needed.
abstract final class AppDates {
  /// "Friday, 2 October 2026"; Thai: "วันศุกร์ที่ 2 ตุลาคม 2569".
  static String full(String dateLocale, DateTime date) =>
      _format(DateFormat.yMMMMEEEEd(dateLocale), dateLocale, date);

  /// "October 2026"; Thai: "ตุลาคม 2569".
  static String monthYear(String dateLocale, DateTime month) =>
      _format(DateFormat.yMMMM(dateLocale), dateLocale, month);

  /// "Oct 2026"; Thai BE (Plus's Year and All time period line).
  static String monthYearShort(String dateLocale, DateTime month) =>
      _format(DateFormat.yMMM(dateLocale), dateLocale, month);

  /// "1 December 2026", in the language's own order, no weekday (the
  /// privacy-change notice's date, as the web's dateInSentence); Thai BE.
  static String longDate(String dateLocale, DateTime day) =>
      _format(DateFormat.yMMMMd(dateLocale), dateLocale, day);

  /// "Oct 2, 2026" (the import preview's range, as the web's); Thai BE.
  static String dayMonthYear(String dateLocale, DateTime day) =>
      _format(DateFormat.yMMMd(dateLocale), dateLocale, day);

  /// The year alone, "2026"; Thai: "2569" (the year card's title).
  static String year(String dateLocale, int year) =>
      _format(DateFormat.y(dateLocale), dateLocale, DateTime(year));

  /// "Fri, Oct 2" (no year).
  static String dayShort(String dateLocale, DateTime day) =>
      _format(DateFormat.MMMEd(dateLocale), dateLocale, day);

  /// "Tuesday, 10 November" (no year): Insights → AI's reflection rows
  /// (board 30c); another year's day says its year ([full]).
  static String dayLong(String dateLocale, DateTime day, {required int thisYear}) =>
      day.year == thisYear
      ? _format(DateFormat.MMMMEEEEd(dateLocale), dateLocale, day)
      : full(dateLocale, day);

  /// Thai dates use the Buddhist era.
  static bool usesBuddhistEra(String dateLocale) =>
      dateLocale == 'th' || dateLocale.startsWith('th_');

  /// The Buddhist era is the Gregorian year + 543 (the calendar is the same).
  static const buddhistEraOffset = 543;

  static String _format(DateFormat format, String locale, DateTime date) {
    if (!usesBuddhistEra(locale)) return format.format(date);
    // Swap every year field for the BE year as a quoted literal; the date
    // itself is unchanged, so the weekday stays right. Quoted text in the
    // pattern is kept as it is.
    final pattern = format.pattern!.replaceAllMapped(
      RegExp(r"'[^']*'|y+"),
      (m) =>
          m[0]!.startsWith("'") ? m[0]! : "'${date.year + buddhistEraOffset}'",
    );
    return DateFormat(pattern, locale).format(date);
  }
}
