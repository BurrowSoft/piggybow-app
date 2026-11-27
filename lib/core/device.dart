import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Facts about the device the app reads at signup (and later in Me).
abstract interface class DeviceContext {
  /// IANA zone, e.g. `Asia/Bangkok`.
  Future<String> timeZone();

  /// ISO 3166-1 alpha-2 region of the device locale, or null.
  String? get countryCode;

  /// Language of the device, e.g. `th`.
  String get languageCode;
}

class PlatformDeviceContext implements DeviceContext {
  const PlatformDeviceContext();

  @override
  Future<String> timeZone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      return 'UTC';
    }
  }

  @override
  String? get countryCode {
    final code = PlatformDispatcher.instance.locale.countryCode;
    return code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : null;
  }

  @override
  String get languageCode => PlatformDispatcher.instance.locale.languageCode;
}

/// Notification permission (Android 13+, iOS), asked when the user finishes
/// setup with the reminder on, and when they turn it on in Me.
abstract interface class NotificationPermission {
  /// True when notifications may be shown.
  Future<bool> request();

  /// Whether notifications are allowed now, without asking (Me re-checks
  /// on open and resume).
  Future<bool> granted();
}

class PlatformNotificationPermission implements NotificationPermission {
  const PlatformNotificationPermission();

  @override
  Future<bool> granted() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) return await android.areNotificationsEnabled() ?? true;
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? true;
    return true;
  }

  @override
  Future<bool> request() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }
}
