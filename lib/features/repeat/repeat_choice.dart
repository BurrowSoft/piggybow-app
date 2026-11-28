import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../repeat/repeat.dart';
import '../../repeat/schedule.dart';

/// How an entry on a day can repeat, as the Add sheet offers it.
enum RepeatChoice {
  none('none'),
  monthly('monthly'),
  lastDay('last-day'),
  weekly('weekly');

  const RepeatChoice(this.id);

  /// The Semantics id stem (`repeat-choice-<id>`).
  final String id;
}

/// The choices for an entry on [date]. "The last day" only when [date] is
/// its month's last day and not the 31st, since day 31 already is the last
/// day (a pay day on 30 April can mean either).
List<RepeatChoice> repeatChoicesFor(DateTime date) => [
  RepeatChoice.none,
  RepeatChoice.monthly,
  if (isLastDayOfMonth(date) && date.day < 31) RepeatChoice.lastDay,
  RepeatChoice.weekly,
];

/// The schedule [choice] makes from [date], or null for none. The day
/// follows [date]: a "last day" that [date] no longer offers becomes its
/// day of the month.
RepeatSchedule? scheduleFor(RepeatChoice choice, DateTime date) =>
    switch (choice) {
      RepeatChoice.none => null,
      RepeatChoice.monthly => RepeatSchedule.monthly(date.day),
      RepeatChoice.lastDay =>
        repeatChoicesFor(date).contains(RepeatChoice.lastDay)
            ? RepeatSchedule.lastDay
            : RepeatSchedule.monthly(date.day),
      RepeatChoice.weekly => RepeatSchedule.weekly(date.weekday),
    };

/// The locale's full name of weekday [day], 1 (Monday) to 7 (Sunday).
String weekdayName(String dateLocale, int day) =>
    // 1 January 2024 was a Monday.
    DateFormat.EEEE(dateLocale).format(DateTime(2024, 1, day));

/// [schedule] in words: "Every month on day 15", "Every month on the last
/// day" (day 31), "Every week on Sunday".
String scheduleText(
  AppLocalizations l10n,
  String dateLocale,
  RepeatSchedule schedule,
) => switch (schedule.kind) {
  RepeatKind.monthly =>
    schedule.day == 31
        ? l10n.repeatMonthlyLast
        : l10n.repeatMonthly(schedule.day),
  RepeatKind.weekly => l10n.repeatWeekly(
    weekdayName(dateLocale, schedule.day),
  ),
};

/// The hint under a monthly schedule on day 29 or 30, which some months
/// don't have; null for any other.
String? scheduleHint(AppLocalizations l10n, RepeatSchedule? schedule) =>
    schedule != null &&
        schedule.kind == RepeatKind.monthly &&
        (schedule.day == 29 || schedule.day == 30)
    ? l10n.repeatShortMonths
    : null;

/// What TalkBack reads for a repeat's mark.
String repeatA11y(AppLocalizations l10n, RepeatKind kind) => switch (kind) {
  RepeatKind.monthly => l10n.repeatA11yMonthly,
  RepeatKind.weekly => l10n.repeatA11yWeekly,
};

/// A repeat's (or one of its entries') name: its note, else its category
/// (a built-in's, or your own's from [customs] by id), else "Save".
String repeatName(
  AppLocalizations l10n, {
  required String note,
  required String? categoryId,
  required Map<String, CustomCategory> customs,
}) => note.isNotEmpty
    ? note
    : categoryId != null
    ? categoryName(l10n, categoryId, customs)
    : l10n.repeatSaveName;

/// The name of [entry], one a repeat added.
String repeatEntryName(
  AppLocalizations l10n,
  Entry entry,
  Map<String, CustomCategory> customs,
) => repeatName(
  l10n,
  note: entry.note,
  categoryId: entry.categoryId,
  customs: customs,
);

/// Asks how an entry on [date] repeats: the choices for that day, [current]
/// marked. Without [withNone], "Doesn't repeat" isn't offered (a repeat's
/// own page stops it with its own button). Null when dismissed.
Future<RepeatChoice?> showRepeatChoices(
  BuildContext context, {
  required DateTime date,
  required String dateLocale,
  required RepeatChoice current,
  bool withNone = true,
}) {
  final l10n = AppLocalizations.of(context);
  String label(RepeatChoice c) => switch (c) {
    RepeatChoice.none => l10n.repeatNone,
    RepeatChoice.lastDay => l10n.repeatMonthlyLast,
    _ => scheduleText(l10n, dateLocale, scheduleFor(c, date)!),
  };
  return showDialog<RepeatChoice>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: Text(l10n.addRepeat),
      children: [
        for (final c in repeatChoicesFor(date))
          if (withNone || c != RepeatChoice.none)
            TestId(
              'repeat-choice-${c.id}',
              button: true,
              selected: c == current,
              // A ListTile: each choice at least 48 dp tall. Whole words
              // ("Wednesday" at 320 dp and 200 % text), smaller only if
              // they must be.
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: WholeWordsText(label(c)),
                subtitle: c == RepeatChoice.monthly
                    ? switch (scheduleHint(l10n, scheduleFor(c, date))) {
                        final hint? => Text(hint),
                        null => null,
                      }
                    : null,
                // Decorative: the choice's own Semantics says selected.
                trailing: c == current
                    ? Icon(
                        Icons.check,
                        color: Theme.of(dialog).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(dialog, c),
              ),
            ),
      ],
    ),
  );
}
