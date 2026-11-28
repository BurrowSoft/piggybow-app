import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/repeat/repeat_choice.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/repeat/repeat.dart';

/// How the Add sheet offers a repeat, worded from the picked day; what each
/// choice makes; and how a repeat is named.
void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('the choices for a day: "the last day" only on a month\'s last day before the 31st', () {
    // Friday 2 October 2026.
    expect(repeatChoicesFor(DateTime(2026, 10, 2)), [
      RepeatChoice.none,
      RepeatChoice.monthly,
      RepeatChoice.weekly,
    ]);
    expect(repeatChoicesFor(DateTime(2026, 9, 30)), [
      RepeatChoice.none,
      RepeatChoice.monthly,
      RepeatChoice.lastDay,
      RepeatChoice.weekly,
    ]);
    expect(repeatChoicesFor(DateTime(2027, 2, 28)), contains(RepeatChoice.lastDay));
    expect(
      repeatChoicesFor(DateTime(2026, 10, 31)),
      isNot(contains(RepeatChoice.lastDay)),
      reason: 'day 31 is the last day already',
    );
  });

  test('each choice\'s schedule follows the day', () {
    final day = DateTime(2026, 9, 30);
    expect(scheduleFor(RepeatChoice.none, day), isNull);
    expect(scheduleFor(RepeatChoice.monthly, day), const RepeatSchedule.monthly(30));
    expect(scheduleFor(RepeatChoice.lastDay, day), RepeatSchedule.lastDay);
    // Wednesday.
    expect(scheduleFor(RepeatChoice.weekly, day), const RepeatSchedule.weekly(3));
    // A day that isn't its month's last: "the last day" becomes its day.
    expect(
      scheduleFor(RepeatChoice.lastDay, DateTime(2026, 10, 15)),
      const RepeatSchedule.monthly(15),
    );
  });

  test('a schedule in words, and the hint for days 29 and 30', () {
    expect(scheduleText(l10n, 'en_US', const RepeatSchedule.monthly(15)), 'Every month on day 15');
    expect(scheduleText(l10n, 'en_US', RepeatSchedule.lastDay), 'Every month on the last day');
    expect(scheduleText(l10n, 'en_US', const RepeatSchedule.weekly(7)), 'Every week on Sunday');
    expect(weekdayName('en_US', 1), 'Monday');
    expect(scheduleHint(l10n, const RepeatSchedule.monthly(29)), 'In shorter months, on the last day.');
    expect(scheduleHint(l10n, const RepeatSchedule.monthly(30)), isNotNull);
    expect(scheduleHint(l10n, const RepeatSchedule.monthly(28)), isNull);
    expect(scheduleHint(l10n, RepeatSchedule.lastDay), isNull);
    expect(scheduleHint(l10n, const RepeatSchedule.weekly(5)), isNull);
    expect(scheduleHint(l10n, null), isNull);
    expect(repeatA11y(l10n, RepeatKind.monthly), 'Repeats every month');
    expect(repeatA11y(l10n, RepeatKind.weekly), 'Repeats every week');
  });

  test('a repeat\'s name: its note, else its category, else "Save"', () {
    expect(repeatName(l10n, note: 'Rent', category: SpendCategory.home), 'Rent');
    expect(repeatName(l10n, note: '', category: SpendCategory.home), 'Home & bills');
    expect(repeatName(l10n, note: '', category: null), 'Save');
  });
}
