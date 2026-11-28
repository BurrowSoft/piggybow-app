import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/data/models.dart';
import 'package:piggybow/features/add/entry_sheet.dart';
import 'package:piggybow/features/reminder/reminder_plan.dart';
import 'package:piggybow/features/reminder/reminder_scheduler.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
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
      expect(copy.title, 'Piggybow');
      expect(copy.bodies, [en.notifBody1, en.notifBody2, en.notifBody3]);
      expect(copy.channelName, 'Daily reminder');
      expect(
        copy.channelDescription,
        'A gentle evening nudge to note your day.',
      );
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

    test('the body changes from day to day: 1, 2, 3, then 1 again', () {
      final copy = ReminderCopy(
        title: en.notifTitle,
        bodies: [en.notifBody1, en.notifBody2, en.notifBody3],
        channelName: en.reminderChannelName,
        channelDescription: en.reminderChannelDesc,
      );
      expect([for (var d = 1; d <= 4; d++) copy.bodyFor(DateTime(2027, 1, d))], [
        'Anything to note today?',
        'A minute for your money journal?',
        'Spent or saved something today? Jot it down.',
        'Anything to note today?',
      ]);
    });

    testWidgets("an entry added today drops today's reminder; tomorrow's stays", (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      await app.session.updateReminder(on: true, time: nine);
      await tester.pumpAndSettle();
      expect(app.reminders.scheduled.first.id, 20261002);

      await tester.runAsync(
        () => app.journal.addEntry(
          type: EntryType.spent,
          amountMinor: 100,
          currency: 'THB',
          localDate: '2026-10-01',
          category: SpendCategory.food,
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        app.reminders.scheduled.first.id,
        20261003,
        reason: 'added today, even for yesterday: tonight is skipped',
      );
    });

    testWidgets('a reminder tapped opens the Add sheet', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      expect(find.byType(EntrySheet), findsNothing);
      app.reminders.tap();
      await tester.pumpAndSettle();
      expect(find.byType(EntrySheet), findsOneWidget);
    });

    testWidgets('a tap opens one sheet: a shell built later replays none', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.reminders.tap();
      await tester.pumpAndSettle();
      expect(find.byType(EntrySheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(EntrySheet))).pop();
      await tester.pumpAndSettle();
      // Away from the tabs and back, as after Delete everything: a new shell.
      app.services.onboarded.value = false;
      await tester.pumpAndSettle();
      tester.expectScreen('onb-welcome');
      app.services.onboarded.value = true;
      await tester.pumpAndSettle();
      tester.expectScreen('home-screen');
      expect(find.byType(EntrySheet), findsNothing);
    });

    testWidgets('a tap while a sheet is up opens no other', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.reminders.tap();
      await tester.pumpAndSettle();
      app.reminders.tap();
      await tester.pumpAndSettle();
      expect(find.byType(EntrySheet), findsOneWidget);
      expect(app.reminders.tapPending.value, isFalse, reason: 'answered');
    });
  });
}
