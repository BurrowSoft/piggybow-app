import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/clock.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart';
import 'reminder_plan.dart';
import 'reminder_scheduler.dart';

/// Keeps the scheduled daily reminder in step with the settings: re-planned
/// at app start, on resume, and when the reminder, its time, the time zone
/// or the language changes. Reminder off, or no account on the phone: none.
/// The notification carries copy only, never anything the person wrote.
class ReminderSync extends StatefulWidget {
  const ReminderSync({
    super.key,
    required this.session,
    required this.services,
    required this.child,
  });

  final AppSession session;
  final AppServices services;
  final Widget child;

  @override
  State<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends State<ReminderSync> {
  late final AppLifecycleListener _lifecycle;
  Object? _lastKey;
  bool _running = false;
  bool _again = false;

  AppSession get _session => widget.session;
  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _services.journal.addListener(_onJournal);
    _lifecycle = AppLifecycleListener(onResume: _schedule);
    _onSession();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _services.journal.removeListener(_onJournal);
    _lifecycle.dispose();
    super.dispose();
  }

  /// What the plan depends on from the session; re-plan only when it
  /// changes (the session notifies for many other reasons).
  Object? _key() {
    final s = _session.accountState;
    return (
      _session.startState,
      _session.user?.id,
      s?.reminderOn,
      s?.reminderTime,
      s?.timeZone,
      _session.locale.languageCode,
    );
  }

  /// Whether an entry was added today, as of the last plan: today's
  /// reminder is left out once one is (plan §4.7).
  bool? _addedToday;

  /// Only a change in "an entry was added today" re-plans.
  Future<void> _onJournal() async {
    try {
      final added = await _entryAddedToday();
      if (mounted && added != _addedToday) _schedule();
    } on Object {
      // A journal that can't be read leaves the plan as it is: never break
      // the app over a reminder. The next change, start or resume re-plans.
    }
  }

  /// Whether the person added an entry today, in the phone's own zone. One a
  /// repeat added doesn't count: the person hasn't written anything yet.
  Future<bool> _entryAddedToday() async {
    final day = _services.localDay;
    for (final e in await _services.journal.entries()) {
      if (e.auto) continue;
      if (wireDate(Clock.localDateOf(e.createdAt, day.zone)) == day.todayWire) {
        return true;
      }
    }
    return false;
  }

  void _onSession() {
    final key = _key();
    if (key == _lastKey) return;
    _lastKey = key;
    _schedule();
  }

  /// One sync at a time; a request meanwhile runs once more afterwards.
  void _schedule() {
    if (_running) {
      _again = true;
      return;
    }
    unawaited(_loop());
  }

  Future<void> _loop() async {
    _running = true;
    try {
      do {
        _again = false;
        await _sync();
      } while (_again && mounted);
    } finally {
      _running = false;
    }
  }

  Future<void> _sync() async {
    final scheduler = _services.reminders;
    try {
      final user = _session.user;
      final state = _session.accountState;
      if (user == null || state == null) {
        // Only once the start is settled.
        if (_session.startState == StartState.done) await scheduler.cancelAll();
        return;
      }
      if (!state.reminderOn) {
        await scheduler.cancelAll();
        return;
      }
      final l10n = lookupAppLocalizations(_session.locale);
      final addedToday = _addedToday = await _entryAddedToday();
      await scheduler.replaceAll(
        planReminders(
          on: true,
          time: state.reminderTime,
          // The phone's own zone, live (LocalDay), as "today" is everywhere.
          location: _location(_services.localDay.zone),
          nowUtc: _services.clock.nowUtc(),
          checkedInToday: addedToday,
        ),
        ReminderCopy(
          title: l10n.notifTitle,
          bodies: [l10n.notifBody1, l10n.notifBody2, l10n.notifBody3],
          channelName: l10n.reminderChannelName,
          channelDescription: l10n.reminderChannelDesc,
        ),
      );
    } on Object {
      // Best effort: never break the app over a notification; the next
      // start or resume re-plans.
    }
  }

  static tz.Location _location(String zone) {
    try {
      return tz.getLocation(zone);
    } on Object {
      return tz.UTC;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
