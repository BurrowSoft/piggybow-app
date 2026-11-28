import 'summary.dart' show Period;

/// Feature 6, the days noted this week: Home's This week card says how many
/// different days of [period] have at least one entry of any type, by each
/// entry's own day ([localDates]). It never counts or mentions the days
/// without one.
int notedDays(Iterable<String> localDates, Period period) => {
  for (final day in localDates)
    if (period.contains(day)) day,
}.length;

/// The line shows from this many days; with fewer, the card says nothing.
const notedDaysMin = 2;
