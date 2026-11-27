import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/data/models.dart';
import 'package:piggybow/features/reminder/reminder_plan.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

import 'helpers.dart';

void main() {
  Clock(); // loads the time zone database
  final bangkok = tz.getLocation('Asia/Bangkok');
  const nine = ReminderTime(21, 0);

  group('planReminders', () {
    // 2 October 2026, 08:30 in Bangkok.
    final morning = DateTime.utc(2026, 10, 2, 1, 30);

    test('off → nothing', () {
      expect(
        planReminders(
          on: false,
          time: nine,
          location: bangkok,
          nowUtc: morning,
          checkedInToday: false,
        ),
        isEmpty,
      );
    });

    test('before the time: today and the next 29 days, ids by date', () {
      final plan = planReminders(
        on: true,
        time: nine,
        location: bangkok,
        nowUtc: morning,
        checkedInToday: false,
      );
      expect(plan, hasLength(reminderWindowDays));
      expect(plan.first.id, 20261002);
      expect(plan.first.at, tz.TZDateTime(bangkok, 2026, 10, 2, 21));
      expect(plan.first.at.toUtc(), DateTime.utc(2026, 10, 2, 14));
      expect(plan[1].id, 20261003);
      expect(plan.last.id, 20261031);
    });

    test('today skipped: today goes, tomorrow stays', () {
      final plan = planReminders(
        on: true,
        time: nine,
        location: bangkok,
        nowUtc: morning,
        checkedInToday: true,
      );
      expect(plan.first.id, 20261003);
      expect(plan, hasLength(reminderWindowDays - 1));
    });

    test('after the time: starts tomorrow', () {
      final plan = planReminders(
        on: true,
        time: const ReminderTime(7, 0),
        location: bangkok,
        nowUtc: morning,
        checkedInToday: false,
      );
      expect(plan.first.id, 20261003);
    });

    test('the local time holds across a DST change (London, 25 Oct)', () {
      final london = tz.getLocation('Europe/London');
      final plan = planReminders(
        on: true,
        time: nine,
        location: london,
        nowUtc: DateTime.utc(2026, 10, 20, 9),
        checkedInToday: false,
      );
      for (final r in plan) {
        expect((r.at.hour, r.at.minute), (21, 0), reason: '${r.id}');
      }
      // 20:00Z in BST, 21:00Z after the change.
      expect(plan.first.at.toUtc().hour, 20);
      expect(plan.firstWhere((r) => r.id == 20261026).at.toUtc().hour, 21);
    });
  });

  group('ReminderSync (the device account)', () {
    final en = lookupAppLocalizations(const Locale('en'));

    testWidgets('a new device account: the reminder is off, nothing planned', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      expect(app.session.accountState?.reminderOn, isFalse);
      expect(app.reminders.scheduled, isEmpty);
      expect(app.reminders.replaces, 0);
    });

    testWidgets('on: today + 29 at its time, the copy only; kept on the phone', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      await app.session.updateReminder(on: true, time: nine);
      await tester.pumpAndSettle();

      final plan = app.reminders.scheduled;
      expect(plan, hasLength(reminderWindowDays));
      expect(plan.first.id, 20261002, reason: '08:30 now: tonight is ahead');
      expect(plan.first.at, tz.TZDateTime(bangkok, 2026, 10, 2, 21));
      final copy = app.reminders.copy!;
      expect(copy.title, en.appName);
      expect(copy.body, en.reminderBody);
      expect(copy.channelName, en.meReminder);
      // Saved in the device account (no server).
      expect(app.prefs.deviceAccount, contains('"reminder_on":true'));
      expect(app.prefs.deviceAccount, contains('"reminder_time":"21:00"'));
    });

    testWidgets('off again: every reminder is cancelled', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      await app.session.updateReminder(on: true, time: nine);
      await tester.pumpAndSettle();
      expect(app.reminders.scheduled, isNotEmpty);

      await app.session.updateReminder(on: false, time: nine);
      await tester.pumpAndSettle();
      expect(app.reminders.scheduled, isEmpty);
      expect(app.reminders.cancels, greaterThan(0));
    });
  });
}
