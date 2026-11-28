import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

import '../backup/backup_snapshot.dart' show JournalSnapshot;
import '../core/clock.dart';
import '../goal/goal_progress.dart';
import '../pig/pig_mood.dart' show HappyPick;
import 'category.dart';
import 'entry.dart';
import 'goal.dart';

/// The longest note, in characters as a person counts them (graphemes).
const maxNoteLength = 80;

/// The journal on the phone: entries, goals and the journal's own settings,
/// in one sembast file. Nothing here ever leaves the phone. Listeners hear
/// about every write.
class JournalStore extends ChangeNotifier {
  JournalStore._(this._db, {required this._clock, String Function()? newId})
    : _newId = newId ?? (() => const Uuid().v4());

  /// The journal's file, in the app's private support folder (on Android,
  /// files/): the phone's backup rules name it (decision 72).
  static const fileName = 'journal.db';

  /// The journal file in the app's private support folder.
  static Future<JournalStore> open({required Clock clock}) async {
    final dir = await getApplicationSupportDirectory();
    final db = await databaseFactoryIo.openDatabase('${dir.path}/$fileName');
    return JournalStore._(db, clock: clock);
  }

  /// A fresh, empty journal in memory (tests).
  static Future<JournalStore> inMemory({
    required Clock clock,
    String Function()? newId,
  }) async => JournalStore._(
    await newDatabaseFactoryMemory().openDatabase('journal.db'),
    clock: clock,
    newId: newId,
  );

  final Database _db;
  final Clock _clock;
  final String Function() _newId;

  static final _entries = stringMapStoreFactory.store('entries');
  static final _goals = stringMapStoreFactory.store('goals');
  static final _settings = StoreRef<String, Object?>('settings');

  // ------------------------------------------------------------ settings

  /// The journal's currency (ISO 4217), or null before it's chosen.
  Future<String?> currency() async =>
      await _settings.record('currency').get(_db) as String?;

  Future<void> setCurrency(String code) async {
    await _settings.record('currency').put(_db, code);
    notifyListeners();
  }

  /// What makes the pig happy (onboarding O2, Me). Until it's been picked:
  /// saving something each week.
  Future<Set<HappyPick>> picks() async {
    final ids = await _settings.record('picks').get(_db);
    final picks = {
      for (final id in ids is List ? ids : const [])
        ...HappyPick.values.where((p) => p.name == id),
    };
    return picks.isEmpty ? {HappyPick.save} : picks;
  }

  Future<void> setPicks(Set<HappyPick> picks) async {
    await _settings.record('picks').put(_db, [for (final p in picks) p.name]);
    notifyListeners();
  }

  /// The weekly spending plan, in minor units; null when there's none.
  Future<int?> planMinor() async {
    final v = await _settings.record('plan_minor').get(_db);
    return v is int && v > 0 ? v : null;
  }

  Future<void> setPlanMinor(int? minor) async {
    final record = _settings.record('plan_minor');
    if (minor == null) {
      await record.delete(_db);
    } else {
      await record.put(_db, minor);
    }
    notifyListeners();
  }

  /// Whether nothing was noted or set yet: no entry, no goal, no picks and no
  /// plan (the currency may be set). Launch fixtures write only into such a
  /// journal.
  Future<bool> isBlank() async =>
      await _entries.count(_db) == 0 &&
      await _goals.count(_db) == 0 &&
      !await _settings.record('picks').exists(_db) &&
      !await _settings.record('plan_minor').exists(_db);

  /// Whether onboarding (plan §3.1) was finished; Delete everything erases
  /// it with the rest.
  Future<bool> onboarded() async =>
      await _settings.record('onboarded').get(_db) == true;

  Future<void> setOnboarded() async {
    await _settings.record('onboarded').put(_db, true);
    notifyListeners();
  }

  /// Whether the reminder offer on Home was answered (it shows once).
  Future<bool> reminderOfferAnswered() async =>
      await _settings.record('reminder_offer').get(_db) == true;

  Future<void> answerReminderOffer() async {
    await _settings.record('reminder_offer').put(_db, true);
    notifyListeners();
  }

  // ------------------------------------------------------------- entries

  /// Every entry, newest day first; within a day, the newest added first.
  Future<List<Entry>> entries() async {
    final snaps = await _entries.find(
      _db,
      finder: Finder(
        sortOrders: [
          SortOrder('local_date', false),
          SortOrder('created_at', false),
        ],
      ),
    );
    return [for (final s in snaps) ?Entry.fromMap(s.key, s.value)];
  }

  Future<Entry?> entry(String id) async {
    final m = await _entries.record(id).get(_db);
    return m == null ? null : Entry.fromMap(id, m);
  }

  /// Adds a spend or a save. A save goes to the active goal, if any.
  Future<Entry> addEntry({
    required EntryType type,
    required int amountMinor,
    required String currency,
    required String localDate,
    SpendCategory? category,
    Feeling? feeling,
    String note = '',
  }) async {
    final now = _clock.nowUtc();
    final spend = type == EntryType.spent;
    final entry = Entry(
      id: _newId(),
      type: type,
      amountMinor: amountMinor,
      currency: currency,
      category: spend ? category : null,
      feeling: spend ? feeling : null,
      note: note.trim(),
      goalId: spend ? null : (await activeGoal())?.id,
      localDate: localDate,
      createdAt: now,
      updatedAt: now,
    );
    _check(entry);
    await _entries.record(entry.id).put(_db, entry.toMap());
    await _advance(entry.goalId);
    notifyListeners();
    return entry;
  }

  /// Saves an edit. Spent ↔ Saved is allowed: a spend drops its goal, a save
  /// drops its category and feeling and goes to the active goal if it had
  /// none. Its id, currency and creation time never change.
  Future<Entry> updateEntry(Entry changed) async {
    final old = await entry(changed.id);
    if (old == null) throw StateError('no entry ${changed.id}');
    final spend = changed.type == EntryType.spent;
    var goalId = spend ? null : changed.goalId;
    if (!spend && old.type == EntryType.spent) {
      goalId = (await activeGoal())?.id;
    }
    final updated = Entry(
      id: old.id,
      type: changed.type,
      amountMinor: changed.amountMinor,
      currency: old.currency,
      category: spend ? changed.category : null,
      feeling: spend ? changed.feeling : null,
      note: changed.note.trim(),
      goalId: goalId,
      localDate: changed.localDate,
      createdAt: old.createdAt,
      updatedAt: _clock.nowUtc(),
    );
    _check(updated);
    await _entries.record(updated.id).put(_db, updated.toMap());
    await _advance(old.goalId);
    if (updated.goalId != old.goalId) await _advance(updated.goalId);
    notifyListeners();
    return updated;
  }

  Future<void> deleteEntry(String id) async {
    final old = await entry(id);
    await _entries.record(id).delete(_db);
    await _advance(old?.goalId);
    notifyListeners();
  }

  // --------------------------------------------------------------- goals

  /// A new id for a record (a goal made on its screen).
  String newId() => _newId();

  /// The active goal, if any (one at a time).
  Future<Goal?> activeGoal() async {
    final s = await _goals.findFirst(
      _db,
      finder: Finder(filter: Filter.equals('status', GoalStatus.active.id)),
    );
    return s == null ? null : Goal.fromMap(s.key, s.value);
  }

  Future<Goal?> goal(String id) async {
    final m = await _goals.record(id).get(_db);
    return m == null ? null : Goal.fromMap(id, m);
  }

  /// Stores [goal]; a new target can reach it (the goal screens own the
  /// other rules).
  Future<void> putGoal(Goal goal) async {
    if (goal.targetMinor <= 0) {
      throw ArgumentError.value(goal.targetMinor, 'targetMinor');
    }
    if (goal.startMinor < 0) {
      throw ArgumentError.value(goal.startMinor, 'startMinor');
    }
    // One active goal at a time: a second one is refused, whatever asks.
    if (goal.status == GoalStatus.active) {
      final active = await activeGoal();
      if (active != null && active.id != goal.id) {
        throw StateError('goal ${active.id} is already active');
      }
    }
    await _goals.record(goal.id).put(_db, goal.toMap());
    await _advance(goal.id);
    notifyListeners();
  }

  /// Every goal, ended and reached ones too, newest first.
  Future<List<Goal>> goals() async {
    final snaps = await _goals.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('created_at', false)]),
    );
    return [for (final s in snaps) ?Goal.fromMap(s.key, s.value)];
  }

  /// The saves that name [goalId], newest day first.
  Future<List<Entry>> goalSaves(String goalId) async => [
    for (final e in await entries())
      if (e.type == EntryType.saved && e.goalId == goalId) e,
  ];

  /// A goal's progress: what was already saved, plus every save that names it.
  Future<int> goalProgress(Goal goal) async {
    var sum = goal.startMinor;
    for (final e in await goalSaves(goal.id)) {
      sum += e.amountMinor;
    }
    return sum;
  }

  /// Whether the celebration for reaching [goalId] was shown (it shows once).
  Future<bool> celebrated(String goalId) async =>
      await _settings.record('celebrated.$goalId').get(_db) == true;

  Future<void> markCelebrated(String goalId) async {
    await _settings.record('celebrated.$goalId').put(_db, true);
  }

  /// After a change that can move [goalId]'s progress (a save added, edited,
  /// moved or deleted, or the goal edited): a band, or the goal reached, is
  /// stamped the first time it completes, and never unstamped. A reached
  /// goal is no longer the active one, so the next save goes to no goal.
  /// Only the active goal moves: an ended goal is never stamped (so never
  /// celebrated), and a reached one is already complete.
  Future<void> _advance(String? goalId) async {
    if (goalId == null) return;
    final g = await goal(goalId);
    if (g == null || g.status != GoalStatus.active) return;
    final marks = advanceGoalMarks(
      bandReachedAt: g.bandReachedAt,
      reachedAt: g.reachedAt,
      progressMinor: await goalProgress(g),
      targetMinor: g.targetMinor,
      nowUtc: _clock.nowUtc(),
    );
    final status = marks.reachedAt != null ? GoalStatus.reached : g.status;
    if (marks.bandsJustReached.isEmpty &&
        !marks.justReached &&
        status == g.status) {
      return;
    }
    final now = _clock.nowUtc();
    await _goals
        .record(g.id)
        .put(
          _db,
          g
              .copyWith(
                bandReachedAt: marks.bandReachedAt,
                reachedAt: marks.reachedAt,
                status: status,
                updatedAt: now,
              )
              .toMap(),
        );
  }

  // ---------------------------------------------------------------- all

  /// Erases every entry, goal and journal setting on the phone.
  Future<void> wipe() async {
    await _db.transaction((txn) async {
      await _entries.delete(txn);
      await _goals.delete(txn);
      await _settings.delete(txn);
    });
    notifyListeners();
  }

  // ------------------------------------------------------------- backups

  /// The journal settings a backup carries (feature 21), by key, and every
  /// `celebrated.<goal id>`. Every key this store writes is either here or in
  /// [staysOnPhone] (a test reads this file to check), so whether a new
  /// setting travels is a choice, never an accident.
  static const travels = {
    'currency',
    'picks',
    'plan_minor',
    'onboarded',
    'reminder_offer',
  };

  static const _travelsPrefix = 'celebrated.';

  /// Journal settings that never leave this phone. None yet.
  static const staysOnPhone = <String>{};

  static bool travelsWith(String key) =>
      travels.contains(key) || key.startsWith(_travelsPrefix);

  /// Everything a backup carries of the journal, read in one transaction:
  /// every entry and goal as this build writes them, and the settings that
  /// travel. A record [checkSnapshot] would refuse (one an older build left
  /// unreadable) stays out, so a backup made here always restores.
  Future<JournalSnapshot> snapshot() => _db.transaction((txn) async {
    final entries = await _entries.find(txn);
    final goals = await _goals.find(txn);
    final settings = await _settings.find(txn);
    return JournalSnapshot(
      entries: {
        for (final s in entries)
          if (_entryRecord(s.key, s.value) case final m?) s.key: m,
      },
      goals: {
        for (final s in goals)
          if (_goalRecord(s.key, s.value) case final m?) s.key: m,
      },
      settings: {
        for (final s in settings)
          if (_settingFits(s.key, s.value)) s.key: _plain(s.value),
      },
    );
  });

  /// [snapshot] as this store would write it. A [FormatException] for
  /// anything it never writes: an entry or goal it can't read or would
  /// refuse, a second active goal, a setting that doesn't travel or holds
  /// the wrong kind of value.
  static JournalSnapshot checkSnapshot(JournalSnapshot snapshot) {
    final entries = <String, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in snapshot.entries.entries) {
      entries[key] =
          _entryRecord(key, value) ?? (throw FormatException('entry $key'));
    }
    final goals = <String, Map<String, Object?>>{};
    var active = 0;
    for (final MapEntry(:key, :value) in snapshot.goals.entries) {
      final record =
          _goalRecord(key, value) ?? (throw FormatException('goal $key'));
      if (record['status'] == GoalStatus.active.id && ++active > 1) {
        throw const FormatException('a second active goal');
      }
      goals[key] = record;
    }
    final settings = <String, Object?>{};
    for (final MapEntry(:key, :value) in snapshot.settings.entries) {
      if (!_settingFits(key, value)) throw FormatException('setting $key');
      settings[key] = _plain(value);
    }
    return JournalSnapshot(entries: entries, goals: goals, settings: settings);
  }

  /// The entry as this store writes it, or null for one it can't read or
  /// would refuse.
  static Map<String, Object?>? _entryRecord(String id, Map<String, Object?> m) {
    final entry = id.isEmpty ? null : Entry.fromMap(id, m);
    if (entry == null) return null;
    try {
      _check(entry);
    } on ArgumentError {
      return null;
    }
    return entry.toMap();
  }

  /// The goal as this store writes it, or null for one it can't read.
  static Map<String, Object?>? _goalRecord(String id, Map<String, Object?> m) =>
      id.isEmpty ? null : Goal.fromMap(id, m)?.toMap();

  /// Replaces the whole journal with [snapshot] (a restore): every entry,
  /// goal and travelling setting goes, and the snapshot's take their place,
  /// stamps and all, so a restored rainbow doesn't celebrate again. All of
  /// it is checked first ([checkSnapshot]: nothing is touched on a
  /// [FormatException]); the writing is one transaction, so a failure
  /// halfway leaves the journal exactly as it was. Settings that stay on the
  /// phone are kept.
  Future<void> replaceWith(
    JournalSnapshot snapshot, {
    @visibleForTesting Future<void> Function()? midway,
  }) async {
    final checked = checkSnapshot(snapshot);
    await _db.transaction((txn) async {
      await _entries.delete(txn);
      await _goals.delete(txn);
      for (final s in await _settings.find(txn)) {
        if (travelsWith(s.key)) await _settings.record(s.key).delete(txn);
      }
      await midway?.call();
      for (final MapEntry(:key, :value) in checked.entries.entries) {
        await _entries.record(key).put(txn, value);
      }
      for (final MapEntry(:key, :value) in checked.goals.entries) {
        await _goals.record(key).put(txn, value);
      }
      for (final MapEntry(:key, :value) in checked.settings.entries) {
        await _settings.record(key).put(txn, value);
      }
    });
    notifyListeners();
  }

  static final _currencyCode = RegExp(r'^[A-Z]{3}$');

  static bool _settingFits(String key, Object? value) => switch (key) {
    'currency' => value is String && _currencyCode.hasMatch(value),
    'picks' => value is List && value.every((p) => p is String),
    'plan_minor' => value is int && value > 0,
    'onboarded' || 'reminder_offer' => value is bool,
    _ =>
      key.startsWith(_travelsPrefix) &&
          key.length > _travelsPrefix.length &&
          value is bool,
  };

  /// [value] as plain JSON: the store hands out read-only lists and maps.
  static Object? _plain(Object? value) => switch (value) {
    final List<Object?> list => [for (final v in list) _plain(v)],
    final Map<String, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) key: _plain(value),
    },
    _ => value,
  };

  Future<void> close() => _db.close();

  static void _check(Entry e) {
    if (e.amountMinor <= 0) {
      throw ArgumentError.value(e.amountMinor, 'amountMinor');
    }
    if (e.date.isAfter(DateTime(9999))) {
      throw ArgumentError.value(e.localDate, 'localDate');
    }
    if (e.type == EntryType.spent && e.category == null) {
      throw ArgumentError('a spend needs a category');
    }
    if (e.note.characters.length > maxNoteLength) {
      throw ArgumentError('the note is over $maxNoteLength characters');
    }
  }
}
