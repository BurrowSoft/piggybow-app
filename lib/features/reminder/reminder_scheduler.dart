import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'reminder_plan.dart';

/// The words on the notification: copy keys only, never anything the person
/// wrote (lock screens are public).
class ReminderCopy {
  const ReminderCopy({
    required this.title,
    required this.body,
    required this.channelName,
  });

  final String title;
  final String body;

  /// The Android notification channel's name (Settings → Notifications).
  final String channelName;
}

/// Local notifications for the daily reminder (a fake in widget tests).
abstract interface class ReminderScheduler {
  /// Replaces every scheduled reminder with [plan].
  Future<void> replaceAll(List<PlannedReminder> plan, ReminderCopy copy);

  /// Cancels every daily reminder, scheduled or already shown.
  Future<void> cancelAll();
}

/// flutter_local_notifications: inexact alarms that may fire while the
/// phone idles (no exact-alarm permission). The plugin's boot receiver
/// re-schedules them after a restart (RECEIVE_BOOT_COMPLETED).
class PlatformReminderScheduler implements ReminderScheduler {
  PlatformReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

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
      )
      .then((_) {});

  /// The plugin only makes a channel the first time one of its notifications
  /// shows, so the phone's settings wouldn't list it until then. Made as soon
  /// as the reminder is on, with the same name and default importance its
  /// notifications use, so it can be muted or changed beforehand. Making an
  /// existing channel again only renames it (the app language), never resets
  /// what the person chose.
  Future<void> _ensureChannel(String id, String name) async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(AndroidNotificationChannel(id, name));
  }

  NotificationDetails _dailyDetails(ReminderCopy copy) => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      copy.channelName,
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
    if (plan.isNotEmpty) await _ensureChannel(channelId, copy.channelName);
    final details = _dailyDetails(copy);
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: copy.title,
        body: copy.body,
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
