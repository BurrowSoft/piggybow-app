import 'package:flutter/widgets.dart';

import '../features/plus/plus_entitlement.dart';
import '../features/reminder/reminder_scheduler.dart';
import '../journal/journal_store.dart';
import '../pig/pig_mood.dart' show PigReaction;
import '../tips/pig_tips.dart';
import 'app_lock.dart';
import 'clock.dart';
import 'device.dart';
import 'launch_actions.dart';
import 'local_day.dart';
import 'staging_tools.dart';

/// The app's dependencies beyond the session (which covers the device
/// account). Only [pigTips] talks to a server, and only once the person
/// turns tips on.
class AppServices {
  AppServices({
    required this.clock,
    required this.localDay,
    required this.journal,
    required this.reminders,
    required this.notifications,
    required this.launchActions,
    this.appLock,
    this.plus,
    this.pigTips,
    this.stagingTestError = stagingToolsEnabled ? throwStagingTestError : null,
    bool onboarded = true,
  }) : onboarded = ValueNotifier(onboarded);

  final Clock clock;

  /// Today on this phone (its live time zone).
  final LocalDay localDay;

  /// The journal: entries, goals and the journal's settings.
  final JournalStore journal;

  /// The daily reminder's notifications (flutter_local_notifications).
  final ReminderScheduler reminders;

  /// Asking for, and reading, the permission to show notifications.
  final NotificationPermission notifications;

  /// The home-screen shortcut, "Add a spend" (Android).
  final LaunchActions launchActions;

  /// What was just added, for the pig's reaction (plan §4.4): set after an
  /// Add, cleared when the app goes to the background.
  final lastAdd = ValueNotifier<PigReaction?>(null);

  /// Whether onboarding is done (the journal's flag, read at start): the
  /// router shows onboarding until it is, and never after.
  final ValueNotifier<bool> onboarded;

  /// App lock; null when APP_LOCK_ENABLED is off.
  final AppLock? appLock;

  /// Piggybow Plus: whether it's on, and its purchases (decision 79). null
  /// while PLUS_ENABLED is off, and so in every release build (AppConfig):
  /// then no Plus row, paywall or Plus feature shows anywhere.
  final PlusEntitlement? plus;

  /// Pig tips: the switch, the day's written tip and Report. Null where the
  /// build has no tips (AI_TIPS_ENABLED off, or no tips project set); A3's
  /// screens show only when it's set and [PigTips.offered].
  final PigTips? pigTips;

  /// Staging and dev builds only: sends a test error to Sentry (if a DSN is set).
  final void Function()? stagingTestError;
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}

extension ServicesContext on BuildContext {
  AppServices get services => ServicesScope.of(this);
}
