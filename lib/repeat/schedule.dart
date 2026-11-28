// The days a repeat falls on: calendar maths only, on date-only values (no
// time, no zone), so neither DST nor the phone's zone can move or double a
// day. "Today" comes from the caller (LocalDay, the phone's live zone).

import 'dart:math' as math;

import '../core/clock.dart';
import 'repeat.dart';

/// How far back a catch-up may still add: nothing older than a year before
/// today. A gap of months is filled in; a clock that jumped years ahead
/// can't flood the journal.
const repeatCatchUpMonths = 12;

/// The number of days in [month] of [year].
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Whether [date] is its month's last day (30 April, 28 or 29 February…).
bool isLastDayOfMonth(DateTime date) =>
    date.day == daysInMonth(date.year, date.month);

/// [day] of [month] in [year], or the month's last day when it's shorter.
DateTime monthlyDate(int year, int month, int day) =>
    DateTime(year, month, math.min(day, daysInMonth(year, month)));

/// The days [schedule] falls on after [after] (not included) up to
/// [through] (included), oldest first; at most [limit] of them.
List<DateTime> occurrences(
  RepeatSchedule schedule, {
  required DateTime after,
  required DateTime through,
  int limit = 1000,
}) {
  final days = <DateTime>[];
  if (!through.isAfter(after)) return days;
  switch (schedule.kind) {
    case RepeatKind.monthly:
      var year = after.year;
      var month = after.month;
      while (days.length < limit) {
        final d = monthlyDate(year, month, schedule.day);
        if (d.isAfter(through)) break;
        if (d.isAfter(after)) days.add(d);
        if (++month > 12) {
          month = 1;
          year++;
        }
      }
    case RepeatKind.weekly:
      final ahead = (schedule.day - after.weekday) % 7;
      var d = addDays(after, ahead == 0 ? 7 : ahead);
      while (!d.isAfter(through) && days.length < limit) {
        days.add(d);
        d = addDays(d, 7);
      }
  }
  return days;
}

/// The latest day [schedule] fell on from [first] up to [through], both
/// included; [first] itself (the person's own first entry) when there's
/// none after it.
DateTime lastOccurrence(
  RepeatSchedule schedule, {
  required DateTime first,
  required DateTime through,
}) {
  final DateTime last;
  switch (schedule.kind) {
    case RepeatKind.monthly:
      final inMonth = monthlyDate(through.year, through.month, schedule.day);
      last = inMonth.isAfter(through)
          ? monthlyDate(through.year, through.month - 1, schedule.day)
          : inMonth;
    case RepeatKind.weekly:
      last = addDays(through, -((through.weekday - schedule.day) % 7));
  }
  return last.isAfter(first) ? last : first;
}

/// The last day of the month (monthly) or of the Monday-to-Sunday week
/// (weekly) that holds [date].
DateTime periodEnd(RepeatKind kind, DateTime date) => switch (kind) {
  RepeatKind.monthly => DateTime(
    date.year,
    date.month,
    daysInMonth(date.year, date.month),
  ),
  RepeatKind.weekly => addDays(date, DateTime.sunday - date.weekday),
};

/// When a schedule changes from [old] to [changed]: the last day the new
/// schedule skips, or null. It starts after the days already dealt with
/// ([madeThrough]), and never adds a second entry in the month (or week, by
/// the new schedule's kind) that holds the old schedule's last one: moving
/// rent from the 1st to the 5th on 3 November skips to 30 November, so no
/// second November rent. [first] is the repeat's first day.
DateTime? skipAfterChange({
  required RepeatSchedule old,
  required RepeatSchedule changed,
  required DateTime first,
  required DateTime madeThrough,
}) {
  if (changed == old) return null;
  final last = lastOccurrence(old, first: first, through: madeThrough);
  final end = periodEnd(changed.kind, last);
  return end.isAfter(madeThrough) ? end : null;
}

/// How far a repeat's "made through" can be after today and still be real:
/// a trip across time zones can move today back by up to 2 days.
const repeatZoneSlackDays = 2;

/// How far a schedule change's skip can be after today and still be real:
/// it ends at most a month after the change, plus the zones' 2 days.
const repeatSkipSlackDays = 33;

/// Whether [madeThrough] is further after [today] than any time zone
/// explains: the clock was set ahead for a catch-up, then put right.
bool clockWasAhead(DateTime madeThrough, DateTime today) =>
    madeThrough.isAfter(addDays(today, repeatZoneSlackDays));

/// Whether a schedule change's [skipThrough] is too far after [today] to be
/// real (made while the clock was set ahead).
bool skipFromClockAhead(DateTime skipThrough, DateTime today) =>
    skipThrough.isAfter(addDays(today, repeatSkipSlackDays));

/// The first day a catch-up on [today] may still add: the same day a year
/// earlier (28 February for 29 February).
DateTime catchUpStart(DateTime today) =>
    monthlyDate(today.year, today.month - repeatCatchUpMonths, today.day);

/// The days a catch-up on [today] adds for [repeats]: for each running
/// repeat, its days after its "made through" day (and after a schedule
/// change's skip) up to [today], none before [catchUpStart]. Oldest first;
/// on the same day, the older repeat first.
List<(Repeat, DateTime)> dueOccurrences(List<Repeat> repeats, DateTime today) {
  final from = addDays(catchUpStart(today), -1);
  final due = <(Repeat, DateTime)>[];
  for (final r in repeats) {
    if (!r.running) continue;
    final made = parseWireDate(r.madeThrough);
    if (made == null) continue;
    var after = made.isAfter(from) ? made : from;
    final skip = parseWireDate(r.skipThrough);
    if (skip != null && skip.isAfter(after)) after = skip;
    for (final d in occurrences(r.schedule, after: after, through: today)) {
      due.add((r, d));
    }
  }
  due.sort((a, b) {
    final byDay = a.$2.compareTo(b.$2);
    return byDay != 0 ? byDay : a.$1.createdAt.compareTo(b.$1.createdAt);
  });
  return due;
}

/// The id of the entry [repeatId] adds on [day]: one per repeat and day, so
/// a second run can never add the same day twice.
String repeatEntryId(String repeatId, DateTime day) =>
    'repeat-$repeatId-${wireDate(day)}';
