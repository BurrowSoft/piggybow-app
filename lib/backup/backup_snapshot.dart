// Feature 21, what a backup file carries: the plaintext that backup_file.dart
// seals, schema 2. The person's journal (every entry, goal and repeat, their
// own categories, and the journal settings that travel) and the few settings
// that matter outside it: language, appearance, the chosen theme, the pig's
// name and the reminder's time.
//
// Never in it: the app lock (its PIN, settings and fail count in secure
// storage, and its plain app_lock.* markers), the device account and its id,
// Plus, first-run markers and other device-only flags. It's built from named
// fields only, never by copying a store or the shared preferences whole.

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/local_prefs.dart';
import '../data/models.dart' show ReminderTime;
import '../pig/pig_name.dart' show normalizePigName;
import 'backup_file.dart' show BackupTooNew, NotABackup;

/// The plaintext's schema this build writes and the newest it reads. 2:
/// repeats (E), entries in another currency with their rate and home amount
/// (#74), and the pig's name.
const backupSchema = 2;

/// One older schema's step to the next: it gets schema n's JSON and returns
/// schema n + 1's.
typedef BackupMigration = Map<String, Object?> Function(Map<String, Object?>);

/// Each older schema's step, by the schema it upgrades, so a file from an
/// older build still restores.
const Map<int, BackupMigration> backupMigrations = {1: _schema1To2};

/// Schema 1 → 2: a schema 1 file has no repeats and no pig's name. Its
/// entries and settings read as they are (schema 2 only adds to them).
Map<String, Object?> _schema1To2(Map<String, Object?> m) {
  final journal = m['journal'];
  final prefs = m['prefs'];
  if (journal is! Map<String, Object?> || prefs is! Map<String, Object?>) {
    throw const NotABackup();
  }
  return {
    ...m,
    'schema': 2,
    'journal': {...journal, 'repeats': const <String, Object?>{}},
    'prefs': {...prefs, 'pig_name': null},
  };
}

/// The journal as JournalStore keeps it (JournalStore.snapshot).
class JournalSnapshot {
  const JournalSnapshot({
    required this.entries,
    required this.goals,
    this.categories = const {},
    this.repeats = const {},
    required this.settings,
  });

  /// Every entry, by id, as the store writes it.
  final Map<String, Map<String, Object?>> entries;

  /// Every goal (active, reached and ended), by id, with its stamps.
  final Map<String, Map<String, Object?>> goals;

  /// Your own categories (#49), hidden ones too, by id.
  final Map<String, Map<String, Object?>> categories;

  /// The repeats (E), stopped ones too (their entries still name them), by
  /// id.
  final Map<String, Map<String, Object?>> repeats;

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
    this.pigName,
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
    pigName: normalizePigName(prefs.pigName),
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

  /// The pig's name (feature 1); null: none. A restore sets it only when
  /// the file has one.
  final String? pigName;

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
      'categories': journal.categories,
      'repeats': journal.repeats,
      'settings': journal.settings,
    },
    'prefs': {
      'locale': prefs.localeCode,
      'appearance': prefs.appearance,
      'palette': prefs.palette,
      'reminder_time': prefs.reminderTime.wire,
      'reminder_on': prefs.reminderWasOn,
      'pig_name': prefs.pigName,
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
        // Your own categories: none when a file has no such part.
        categories: journal.containsKey('categories')
            ? _records(journal['categories'])
            : const {},
        repeats: _records(journal['repeats']),
        settings: _map(journal['settings']),
      ),
      prefs: PrefsSnapshot(
        localeCode: _optionalString(prefs['locale']),
        appearance: _optionalString(prefs['appearance']),
        palette: _optionalString(prefs['palette']),
        reminderTime: _time(prefs['reminder_time']),
        reminderWasOn: _bool(prefs['reminder_on']),
        pigName: _optionalString(prefs['pig_name']),
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
