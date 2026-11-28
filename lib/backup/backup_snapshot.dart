// Feature 21, what a backup file carries: the plaintext that backup_file.dart
// seals, schema 1. The person's journal (every entry and goal, and the
// journal settings that travel) and the few settings that matter outside it:
// language, appearance, the chosen theme and the reminder's time.
//
// Never in it: the app lock (its PIN, settings and fail count in secure
// storage, and its plain app_lock.* markers), the device account and its id,
// Plus, first-run markers and other device-only flags. It's built from named
// fields only, never by copying a store or the shared preferences whole.

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/local_prefs.dart';
import '../data/models.dart' show ReminderTime;
import 'backup_file.dart' show BackupTooNew, NotABackup;

/// The plaintext's schema this build writes and the newest it reads.
const backupSchema = 1;

/// One older schema's step to the next: it gets schema n's JSON and returns
/// schema n + 1's.
typedef BackupMigration = Map<String, Object?> Function(Map<String, Object?>);

/// Each older schema's step, by the schema it upgrades. Empty while 1 is the
/// only schema; the build that writes schema 2 adds `1: …` here, so files from
/// this one still restore.
const Map<int, BackupMigration> backupMigrations = {};

/// The journal as JournalStore keeps it (JournalStore.snapshot).
class JournalSnapshot {
  const JournalSnapshot({
    required this.entries,
    required this.goals,
    required this.settings,
  });

  /// Every entry, by id, as the store writes it.
  final Map<String, Map<String, Object?>> entries;

  /// Every goal (active, reached and ended), by id, with its stamps.
  final Map<String, Map<String, Object?>> goals;

  /// The journal settings that travel (JournalStore.travelsWith).
  final Map<String, Object?> settings;
}

/// The settings that matter outside the journal.
class PrefsSnapshot {
  const PrefsSnapshot({
    required this.localeCode,
    required this.appearance,
    required this.palette,
    required this.reminderTime,
    required this.reminderWasOn,
  });

  /// What this phone has now: [prefs]' named fields, and the reminder.
  factory PrefsSnapshot.take(
    LocalPrefs prefs, {
    required bool reminderOn,
    required ReminderTime reminderTime,
  }) => PrefsSnapshot(
    localeCode: prefs.localeCode,
    appearance: prefs.appearance,
    palette: prefs.palette,
    reminderTime: reminderTime,
    reminderWasOn: reminderOn,
  );

  /// The app's language code; null: the phone's.
  final String? localeCode;

  /// system | light | dark; null: system.
  final String? appearance;

  /// The chosen theme as stored; it shows only while Plus is live.
  final String? palette;

  final ReminderTime reminderTime;

  /// Whether the reminder was on. A restore sets it off either way
  /// ([restoredReminder]) and says so when it was on.
  final bool reminderWasOn;

  /// The reminder as a restore sets it: off, at the backup's time. The new
  /// phone has to grant notifications itself.
  ({bool on, ReminderTime time}) get restoredReminder =>
      (on: false, time: reminderTime);
}

/// A whole backup's plaintext.
class BackupSnapshot {
  const BackupSnapshot({required this.journal, required this.prefs});

  final JournalSnapshot journal;
  final PrefsSnapshot prefs;

  Map<String, Object?> toJson() => {
    'schema': backupSchema,
    'journal': {
      'entries': journal.entries,
      'goals': journal.goals,
      'settings': journal.settings,
    },
    'prefs': {
      'locale': prefs.localeCode,
      'appearance': prefs.appearance,
      'palette': prefs.palette,
      'reminder_time': prefs.reminderTime.wire,
      'reminder_on': prefs.reminderWasOn,
    },
  };

  /// [json] (what openBackup returned) as a snapshot. Its shape is checked
  /// here: [NotABackup] for anything this build can't read, [BackupTooNew]
  /// for a newer schema; an older schema is migrated first. Its content (the
  /// entries, goals and settings) is checked by JournalStore before anything
  /// is replaced.
  static BackupSnapshot fromJson(
    Object? json, {
    @visibleForTesting Map<int, BackupMigration> migrations = backupMigrations,
    @visibleForTesting int schema = backupSchema,
  }) {
    if (json is! Map<String, Object?>) throw const NotABackup();
    var map = json;
    final written = map['schema'];
    if (written is! int || written < 1) throw const NotABackup();
    if (written > schema) throw const BackupTooNew();
    var from = written;
    while (from < schema) {
      final step = migrations[from];
      if (step == null) throw const NotABackup();
      map = step(map);
      from += 1;
    }
    final journal = map['journal'];
    final prefs = map['prefs'];
    if (journal is! Map<String, Object?> || prefs is! Map<String, Object?>) {
      throw const NotABackup();
    }
    return BackupSnapshot(
      journal: JournalSnapshot(
        entries: _records(journal['entries']),
        goals: _records(journal['goals']),
        settings: _map(journal['settings']),
      ),
      prefs: PrefsSnapshot(
        localeCode: _optionalString(prefs['locale']),
        appearance: _optionalString(prefs['appearance']),
        palette: _optionalString(prefs['palette']),
        reminderTime: _time(prefs['reminder_time']),
        reminderWasOn: _bool(prefs['reminder_on']),
      ),
    );
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : throw const NotABackup();

Map<String, Map<String, Object?>> _records(Object? value) {
  final records = <String, Map<String, Object?>>{};
  for (final MapEntry(:key, :value) in _map(value).entries) {
    if (key.isEmpty) throw const NotABackup();
    records[key] = _map(value);
  }
  return records;
}

String? _optionalString(Object? value) => switch (value) {
  null => null,
  final String s => s,
  _ => throw const NotABackup(),
};

bool _bool(Object? value) =>
    value is bool ? value : throw const NotABackup();

final _wireTime = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

ReminderTime _time(Object? value) {
  final m = value is String ? _wireTime.firstMatch(value) : null;
  if (m == null) throw const NotABackup();
  return ReminderTime(int.parse(m[1]!), int.parse(m[2]!));
}
