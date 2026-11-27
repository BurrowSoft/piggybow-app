import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/pig/pig_mood.dart' show rotatingLine;
import 'package:piggybow/reminder_rules/reminder_rules.dart';

void main() {
  group('the body: (dayOfYear - 1) mod 3', () {
    test('1 January is body 1, then 2, 3 and back to 1', () {
      expect(reminderBody(DateTime(2026, 1, 1)), 1);
      expect(reminderBody(DateTime(2026, 1, 2)), 2);
      expect(reminderBody(DateTime(2026, 1, 3)), 3);
      expect(reminderBody(DateTime(2026, 1, 4)), 1);
    });

    test('2 December 2026 (day 336) is body 3; 31 December is body 2 (365) or 3 (366, leap year)', () {
      expect(reminderBody(DateTime(2026, 12, 2)), 3);
      expect(reminderBody(DateTime(2026, 12, 31)), 2);
      expect(reminderBody(DateTime(2028, 12, 31)), 3);
    });

    test('the next 7 fires follow the day rotation', () {
      final start = DateTime(2026, 12, 2, 20);
      final bodies = [for (var i = 0; i < 7; i++) reminderBody(DateTime(start.year, start.month, start.day + i, 20))];
      expect(bodies, [3, 1, 2, 3, 1, 2, 3]);
    });

    test('only the date counts, not the time or the zone (a 20:00 fire on a DST day)', () {
      expect(reminderBody(DateTime(2026, 3, 29, 20)), reminderBody(DateTime.utc(2026, 3, 29)));
      expect(reminderBody(DateTime(2026, 10, 25, 23, 59)), reminderBody(DateTime(2026, 10, 25)));
    });

    test('it agrees with the pig\'s rotation for every day of two years', () {
      const keys = ['notifBody1', 'notifBody2', 'notifBody3'];
      for (var d = DateTime.utc(2026); d.year < 2028; d = d.add(const Duration(days: 1))) {
        final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        expect('notifBody${reminderBody(d)}', rotatingLine(keys, iso), reason: iso);
      }
    });
  });

  test('after a restore: on in the settings but not scheduled → schedule again; otherwise not', () {
    expect(reminderNeedsReschedule(prefsOn: true, isScheduled: false), isTrue);
    expect(reminderNeedsReschedule(prefsOn: true, isScheduled: true), isFalse);
    expect(reminderNeedsReschedule(prefsOn: false, isScheduled: false), isFalse);
    expect(reminderNeedsReschedule(prefsOn: false, isScheduled: true), isFalse);
  });

  test('Me\'s reminder row: meNotifOff only when it\'s on and notifications are blocked', () {
    expect(reminderRow(on: false, permissionGranted: false), ReminderRow.off);
    expect(reminderRow(on: false, permissionGranted: true), ReminderRow.off);
    expect(reminderRow(on: true, permissionGranted: true), ReminderRow.on);
    expect(reminderRow(on: true, permissionGranted: false), ReminderRow.onButNotificationsOff);
  });
}
