import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'clock.dart';

/// Facts about the device the app reads at signup (and later in Me).
abstract interface class DeviceContext {
  /// IANA zone, e.g. `Asia/Bangkok`.
  Future<String> timeZone();

  /// ISO 3166-1 alpha-2 region of the device locale, or null.
  String? get countryCode;

  /// Language of the device, e.g. `th`.
  String get languageCode;

  /// The phone's own locale (e.g. `th_TH`): numbers and money follow it,
  /// whatever the app's language.
  String get localeName;
}

class PlatformDeviceContext implements DeviceContext {
  const PlatformDeviceContext();

  @override
  Future<String> timeZone() async {
    String? name;
    try {
      name = (await FlutterTimezone.getLocalTimezone()).identifier;
    } on Object {
      name = null;
    }
    // No answer, or a name the zone database lacks (it would read as UTC):
    // a zone at the phone's current offset instead.
    return Clock.knownZoneOr(name, DateTime.now().timeZoneOffset);
  }

  @override
  String? get countryCode {
    final code = PlatformDispatcher.instance.locale.countryCode;
    return code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : null;
  }

  @override
  String get languageCode => PlatformDispatcher.instance.locale.languageCode;

  @override
  String get localeName => PlatformDispatcher.instance.locale.toString();
}

/// Notification permission (Android 13+, iOS), asked when the user finishes
/// setup with the reminder on, and when they turn it on in Me.
abstract interface class NotificationPermission {
  /// True when notifications may be shown.
  Future<bool> request();

  /// Whether notifications are allowed now, without asking (Me re-checks
  /// on open and resume).
  Future<bool> granted();

  /// The phone's own notification settings for Piggybow (Me → Open
  /// settings, decision 63). iPhone gets its settings URL later.
  Future<void> openSettings();
}

/// The channel MainActivity.kt answers on, and its methods (tests check that
/// both sides use these names).
const settingsChannel = 'com.burrowsoft.piggybow/settings';
const openNotificationSettingsMethod = 'openNotificationSettings';
const androidSdkMethod = 'androidSdk';

/// The phone's Android version as its SDK level (26 = Android 8), read once at
/// start-up; null where there is none to read (iOS, a test) or the call
/// fails.
Future<int?> readAndroidSdk() async {
  try {
    return await const MethodChannel(
      settingsChannel,
    ).invokeMethod<int>(androidSdkMethod);
  } on Object {
    return null;
  }
}

class PlatformNotificationPermission implements NotificationPermission {
  const PlatformNotificationPermission();

  @override
  Future<void> openSettings() async {
    try {
      await const MethodChannel(
        settingsChannel,
      ).invokeMethod<void>(openNotificationSettingsMethod);
    } on Object {
      // No settings screen to open (another platform, for now): nothing to do.
    }
  }

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
