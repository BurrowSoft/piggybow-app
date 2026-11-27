import 'package:timezone/timezone.dart' as tz;

import '../../data/models.dart';

/// How many days ahead reminders are scheduled. A daily *repeating*
/// notification can't skip one day (no reminder on a day with a check-in),
/// so each day gets its own one-shot notification, re-planned on every
/// app start, resume and settings change. Someone who doesn't open
/// the app for this long stops getting reminders.
const reminderWindowDays = 30;

/// One planned reminder: [id] is the local date as yyyymmdd (stable, so a
/// re-plan replaces rather than duplicates).
class PlannedReminder {
  const PlannedReminder(this.id, this.at);

  final int id;
  final tz.TZDateTime at;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'PlannedReminder($id, $at)';
}

/// The reminders to schedule from [nowUtc]: one per day at [time] in
/// [location] (the profile's zone), for [reminderWindowDays] days. Today's
/// is left out once its time has passed or when today already has a
/// check-in; tomorrow's and later are always there. Off → none.
List<PlannedReminder> planReminders({
  required bool on,
  required ReminderTime time,
  required tz.Location location,
  required DateTime nowUtc,
  required bool checkedInToday,
  int days = reminderWindowDays,
}) {
  if (!on) return const [];
  final now = tz.TZDateTime.from(nowUtc, location);
  final plan = <PlannedReminder>[];
  for (var d = 0; d < days; d++) {
    if (d == 0 && checkedInToday) continue;
    // Calendar arithmetic (never Duration(days:)): DST-safe.
    final at = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + d,
      time.hour,
      time.minute,
    );
    if (!at.isAfter(now)) continue;
    plan.add(PlannedReminder(at.year * 10000 + at.month * 100 + at.day, at));
  }
  return plan;
}
