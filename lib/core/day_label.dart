import '../l10n/gen/app_localizations.dart';
import 'app_dates.dart';

/// A day as the UI names it (decision 48: no ISO date on screen): "Today",
/// "Yesterday", or the weekday and date ("Wed, Sep 30"), with the year for
/// a day in another year ("Wed, Dec 31, 2025"). Timeline's day headers and
/// a goal's saves both use it. [today] is the live zone's day (LocalDay).
String dayLabel(
  AppLocalizations l10n,
  String dateLocale,
  DateTime day, {
  required DateTime today,
}) {
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(day, today)) return l10n.tlToday;
  if (same(day, DateTime(today.year, today.month, today.day - 1))) {
    return l10n.tlYesterday;
  }
  return day.year == today.year
      ? AppDates.dayShort(dateLocale, day)
      : AppDates.dayShortWithYear(dateLocale, day);
}
