import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/features/reminder/reminder_plan.dart';
import 'package:piggybow/features/reminder/reminder_scheduler.dart';
import 'package:piggybow/theme/theme.dart' show PiggybowColors;
import 'package:timezone/timezone.dart' as tz;

/// PlatformReminderScheduler on the plugin's Android method channel
/// (answered here): replaceAll clears the daily reminders first, then one
/// inexact alarm per planned day with copy only (nothing the person wrote);
/// the plugin is initialised once and never asks for permission by itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Clock(); // loads the time-zone data before the plan below is built
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;

  /// What the plugin reports as scheduled / shown (ids).
  var pending = <int>[];
  var active = <int>[];

  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    pending = [];
    active = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'pendingNotificationRequests' => [
              for (final id in pending)
                {'id': id, 'title': null, 'body': null, 'payload': null},
            ],
            'getActiveNotifications' => [
              for (final id in active) {'id': id, 'channelId': null},
            ],
            _ => null,
          };
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  final copy = ReminderCopy(
    title: 'Piggybow',
    bodies: ['One?', 'Two?', 'Three?'],
    channelName: 'Daily reminder',
    channelDescription: 'A gentle evening nudge to note your day.',
  );
  final bangkok = tz.getLocation('Asia/Bangkok');
  final plan = [
    PlannedReminder(1, tz.TZDateTime(bangkok, 2099, 1, 1, 21)),
    PlannedReminder(2, tz.TZDateTime(bangkok, 2099, 1, 2, 21)),
  ];

  List<String> methods() => calls.map((c) => c.method).toList();
  List<int> cancelledIds() => [
    for (final c in calls.where((c) => c.method == 'cancel'))
      (c.arguments as Map)['id'] as int,
  ];

  test('replaceAll: init once, clear the daily ones, then one alarm per '
      'day', () async {
    final s = PlatformReminderScheduler();
    await s.replaceAll(plan, copy);
    await s.replaceAll(plan, copy);

    expect(methods().where((m) => m == 'initialize'), hasLength(1));
    expect(methods(), [
      'initialize',
      'pendingNotificationRequests',
      'getActiveNotifications',
      'createNotificationChannel',
      'zonedSchedule',
      'zonedSchedule',
      'pendingNotificationRequests',
      'getActiveNotifications',
      'createNotificationChannel',
      'zonedSchedule',
      'zonedSchedule',
    ]);

    final scheduled = [
      for (final c in calls.where((call) => call.method == 'zonedSchedule'))
        Map<String, dynamic>.from(c.arguments as Map),
    ];
    final first = scheduled.first;
    expect(first['id'], 1);
    expect(first['title'], 'Piggybow');
    // The body follows the day: 1 January has the first, the 2nd the next.
    expect(first['body'], 'One?');
    expect(scheduled[1]['body'], 'Two?');
    final specifics = first['platformSpecifics'].toString();
    expect(specifics, contains(PlatformReminderScheduler.channelId));
    expect(specifics, contains('inexactAllowWhileIdle'));
    // The shade's accent is the app's berry (#A8456A), not the system's colour.
    final android = Map<String, Object?>.from(first['platformSpecifics'] as Map);
    final accent = [
      for (final k in ['colorAlpha', 'colorRed', 'colorGreen', 'colorBlue']) android[k] as int,
    ].fold(0, (argb, c) => (argb << 8) | c);
    expect(accent, PiggybowColors.deepRose.toARGB32());
    expect(accent, 0xFFA8456A);
  });

  test('cancelAll initialises the plugin first (small icon)', () async {
    await PlatformReminderScheduler().cancelAll();
    final init = calls.firstWhere((c) => c.method == 'initialize');
    expect(init.arguments.toString(), contains('ic_notification'));
    expect(calls.last.method, 'getActiveNotifications');
  });

  test('an empty plan only clears', () async {
    await PlatformReminderScheduler().replaceAll(const [], copy);
    expect(methods(), [
      'initialize',
      'pendingNotificationRequests',
      'getActiveNotifications',
    ]);
  });

  test('cancelAll removes every daily reminder, scheduled or shown', () async {
    pending = [20991231, 20990101];
    active = [20991230, 20991231];
    await PlatformReminderScheduler().cancelAll();
    expect(cancelledIds().toSet(), {20991231, 20990101, 20991230});
    expect(cancelledIds(), hasLength(3), reason: 'each id once');
  });
}
