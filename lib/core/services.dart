import 'package:flutter/widgets.dart';

import '../data/plus.dart';
import '../features/plus/plus_store.dart';
import '../features/reminder/reminder_scheduler.dart';
import '../journal/journal_store.dart';
import '../pig/pig_mood.dart' show PigReaction;
import 'app_lock.dart';
import 'clock.dart';
import 'device.dart';
import 'local_day.dart';
import 'staging_tools.dart';

/// The app's dependencies beyond the session (which covers the device
/// account). v0.1 runs on the phone only: nothing here talks to a server.
class AppServices {
  AppServices({
    required this.clock,
    required this.localDay,
    required this.journal,
    required this.reminders,
    required this.notifications,
    this.appLock,
    this.plus,
    this.plusStore,
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

  /// What was just added, for the pig's reaction (plan §4.4): set after an
  /// Add, cleared when the app goes to the background.
  final lastAdd = ValueNotifier<PigReaction?>(null);

  /// Whether onboarding is done (the journal's flag, read at start): the
  /// router shows onboarding until it is, and never after.
  final ValueNotifier<bool> onboarded;

  /// App lock; null when APP_LOCK_ENABLED is off.
  final AppLock? appLock;

  /// The Plus plumbing (no UI in v0.1): null while PLUS_ENABLED is off.
  final PlusRepository? plus;
  final PlusStore? plusStore;

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
