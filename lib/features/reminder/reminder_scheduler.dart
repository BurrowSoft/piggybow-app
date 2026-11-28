import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../reminder_rules/reminder_rules.dart';
import 'reminder_plan.dart';

/// The words on the notification: copy keys only, never anything the person
/// wrote (lock screens are public).
class ReminderCopy {
  ReminderCopy({
    required this.title,
    required this.bodies,
    required this.channelName,
    required this.channelDescription,
  }) : assert(bodies.length == reminderBodyCount);

  final String title;

  /// notifBody1 to notifBody3: a day's reminder uses
  /// bodies[reminderBody(day) - 1], so the words change from day to day.
  final List<String> bodies;

  /// The Android notification channel's name and description (Settings →
  /// Notifications).
  final String channelName;
  final String channelDescription;

  /// The body of the reminder that fires on [day] (its local date).
  String bodyFor(DateTime day) => bodies[reminderBody(day) - 1];
}

/// Local notifications for the daily reminder (a fake in widget tests).
abstract interface class ReminderScheduler {
  /// Replaces every scheduled reminder with [plan].
  Future<void> replaceAll(List<PlannedReminder> plan, ReminderCopy copy);

  /// Cancels every daily reminder, scheduled or already shown.
  Future<void> cancelAll();

  /// A reminder tapped (a start from one included) and not yet answered:
  /// the Add sheet opens once for it (plan §3.10).
  ValueListenable<bool> get tapPending;

  /// Answers the pending tap: true once, then false until another one, so
  /// a shell built later never replays a tap already answered.
  bool takeTap();

  /// Starts listening for taps, and takes a start from a reminder as one.
  Future<void> listen();
}

/// flutter_local_notifications: inexact alarms that may fire while the
/// phone idles (no exact-alarm permission). The plugin's boot receiver
/// re-schedules them after a restart (RECEIVE_BOOT_COMPLETED).
class PlatformReminderScheduler implements ReminderScheduler {
  PlatformReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;
  final _tapPending = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get tapPending => _tapPending;

  @override
  bool takeTap() {
    if (!_tapPending.value) return false;
    _tapPending.value = false;
    return true;
  }

  @override
  Future<void> listen() async {
    await _init();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) _tapPending.value = true;
  }

  static const channelId = 'daily_reminder';

  /// Every daily reminder, scheduled or already shown.
  Future<void> _cancelDaily() async {
    final ids = {
      for (final p in await _plugin.pendingNotificationRequests()) p.id,
      for (final a in await _plugin.getActiveNotifications())
        if (a.id != null) a.id!,
    };
    for (final id in ids) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          // Permission is asked when the reminder is turned on, never by
          // merely starting the plugin.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (_) => _tapPending.value = true,
      )
      .then((_) {});

  /// The plugin only makes a channel the first time one of its notifications
  /// shows, so the phone's settings wouldn't list it until then. Made as soon
  /// as the reminder is on, with the same name and default importance its
  /// notifications use, so it can be muted or changed beforehand. Making an
  /// existing channel again only renames it (the app language), never resets
  /// what the person chose.
  Future<void> _ensureChannel(String id, ReminderCopy copy) async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          AndroidNotificationChannel(
            id,
            copy.channelName,
            description: copy.channelDescription,
          ),
        );
  }

  NotificationDetails _dailyDetails(ReminderCopy copy) => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      copy.channelName,
      channelDescription: copy.channelDescription,
      icon: 'ic_notification',
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  @override
  Future<void> replaceAll(List<PlannedReminder> plan, ReminderCopy copy) async {
    await _init();
    await _cancelDaily();
    if (plan.isNotEmpty) await _ensureChannel(channelId, copy);
    final details = _dailyDetails(copy);
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: copy.title,
        body: copy.bodyFor(r.at),
        scheduledDate: r.at,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _cancelDaily();
  }
}
