// The daily reminder's rules (plan §3.10, §0.8): which of the three bodies a day's notification
// uses, when a restore needs the reminder scheduled again, and what Me's reminder row shows.
// When it fires is lib/features/reminder/reminder_plan.dart's job.

/// How many bodies rotate (notifBody1-notifBody3).
const int reminderBodyCount = 3;

/// The body for a reminder firing on [fireDate]: 1-3, by (dayOfYear - 1) mod 3 of that date, so
/// 1 January uses notifBody1. Only the date's year, month and day count.
int reminderBody(DateTime fireDate) {
  final day = DateTime.utc(fireDate.year, fireDate.month, fireDate.day);
  final dayOfYear = day.difference(DateTime.utc(fireDate.year)).inDays + 1;
  return (dayOfYear - 1) % reminderBodyCount + 1;
}

/// After a restore the settings say the reminder is on, but nothing is scheduled on the new phone:
/// schedule it again at the first start (§0.8).
bool reminderNeedsReschedule({required bool prefsOn, required bool isScheduled}) => prefsOn && !isScheduled;

/// Me's reminder row: the switch, plus meNotifOff and meOpenSettings when the reminder is on but
/// the phone won't show its notifications.
enum ReminderRow { off, on, onButNotificationsOff }

ReminderRow reminderRow({required bool on, required bool permissionGranted}) {
  if (!on) return ReminderRow.off;
  return permissionGranted ? ReminderRow.on : ReminderRow.onButNotificationsOff;
}
