// Today's idea (plan §4.5): one of 20 static tips per day, rotating by the day of the year, with
// "Another idea" stepping to the next. Habits, not advice; the texts are tip01-tip20 in app_en.arb.

import '../l10n/gen/app_localizations.dart';

const int tipCount = 20;

/// The tip for a local date, 1-20: tips[(dayOfYear - 1) mod 20], so 1 January is tip 1,
/// 20 January tip 20 and 21 January tip 1 again. Only the date's year, month and day count.
int tipForDay(DateTime localDate) {
  final day = DateTime.utc(localDate.year, localDate.month, localDate.day);
  final dayOfYear = day.difference(DateTime.utc(localDate.year)).inDays + 1;
  return (dayOfYear - 1) % tipCount + 1;
}

/// "Another idea": the next tip, 20 wraps to 1.
int nextTip(int tip) {
  _check(tip);
  return tip % tipCount + 1;
}

/// The tip's text in the app's language.
String tipText(AppLocalizations l10n, int tip) {
  _check(tip);
  return switch (tip) {
    1 => l10n.tip01,
    2 => l10n.tip02,
    3 => l10n.tip03,
    4 => l10n.tip04,
    5 => l10n.tip05,
    6 => l10n.tip06,
    7 => l10n.tip07,
    8 => l10n.tip08,
    9 => l10n.tip09,
    10 => l10n.tip10,
    11 => l10n.tip11,
    12 => l10n.tip12,
    13 => l10n.tip13,
    14 => l10n.tip14,
    15 => l10n.tip15,
    16 => l10n.tip16,
    17 => l10n.tip17,
    18 => l10n.tip18,
    19 => l10n.tip19,
    _ => l10n.tip20,
  };
}

void _check(int tip) {
  if (tip < 1 || tip > tipCount) throw RangeError.range(tip, 1, tipCount, 'tip');
}
