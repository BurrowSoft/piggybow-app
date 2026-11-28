import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

import '../core/clock.dart';
import '../goal/goal_progress.dart';
import '../pig/pig_mood.dart' show HappyPick;
import '../repeat/repeat.dart';
import '../repeat/schedule.dart';
import 'category.dart';
import 'entry.dart';
import 'goal.dart';

/// The longest note, in characters as a person counts them (graphemes).
const maxNoteLength = 80;

/// The journal on the phone: entries, goals, repeats and the journal's own
/// settings, in one sembast file. Nothing here ever leaves the phone.
/// Listeners hear about every write.
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
  static final _repeats = stringMapStoreFactory.store('repeats');
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

  /// Whether nothing was noted or set yet: no entry, no goal, no repeat, no
  /// picks and no plan (the currency may be set). Launch fixtures write only
  /// into such a journal.
  Future<bool> isBlank() async =>
      await _entries.count(_db) == 0 &&
      await _goals.count(_db) == 0 &&
      await _repeats.count(_db) == 0 &&
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
  ///
  /// With [repeat], the entry is the first of a repeat on that schedule, and
  /// the journal adds the next ones on their days (catchUpRepeats). [today]
  /// is then the phone's date (LocalDay): a repeat never adds a day before
  /// the one it was made on, even after a first entry dated earlier.
  Future<Entry> addEntry({
    required EntryType type,
    required int amountMinor,
    required String currency,
    required String localDate,
    SpendCategory? category,
    Feeling? feeling,
    String note = '',
    RepeatSchedule? repeat,
    String? today,
  }) async {
    final now = _clock.nowUtc();
    final spend = type == EntryType.spent;
    final repeatId = repeat == null ? null : _newId();
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
      repeatId: repeatId,
    );
    _check(entry);
    if (repeat == null) {
      await _entries.record(entry.id).put(_db, entry.toMap());
    } else {
      final day = parseWireDate(today);
      if (day == null) throw ArgumentError.value(today, 'today');
      final r = Repeat(
        id: repeatId!,
        type: type,
        amountMinor: entry.amountMinor,
        currency: currency,
        category: entry.category,
        note: entry.note,
        schedule: repeat,
        firstDate: entry.localDate,
        madeThrough: wireDate(entry.date.isAfter(day) ? entry.date : day),
        createdAt: now,
        updatedAt: now,
      );
      _checkRepeat(r);
      await _db.transaction((txn) async {
        await _repeats.record(r.id).put(txn, r.toMap());
        await _entries.record(entry.id).put(txn, entry.toMap());
      });
    }
    await _advance(entry.goalId);
    notifyListeners();
    return entry;
  }

  /// Saves an edit. Spent ↔ Saved is allowed: a spend drops its goal, a save
  /// drops its category and feeling and goes to the active goal if it had
  /// none. Its id, currency, creation time, repeat and "added by a repeat"
  /// never change: an edit is for this entry only, never its repeat.
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
      repeatId: old.repeatId,
      auto: old.auto,
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
  Future<Goal?> activeGoal() => _activeGoalIn(_db);

  /// The active goal as [client] (the journal, or a transaction) reads it.
  Future<Goal?> _activeGoalIn(DatabaseClient client) async {
    final s = await _goals.findFirst(
      client,
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

  // ------------------------------------------------------------- repeats

  /// Every repeat, stopped ones too, oldest first.
  Future<List<Repeat>> repeats() async {
    final snaps = await _repeats.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('created_at')]),
    );
    return [for (final s in snaps) ?Repeat.fromMap(s.key, s.value)];
  }

  Future<Repeat?> repeat(String id) async {
    final m = await _repeats.record(id).get(_db);
    return m == null ? null : Repeat.fromMap(id, m);
  }

  /// Saves an edit to a repeat: its amount, category, note and schedule
  /// apply from its next entry on, and the entries it already added stay as
  /// they are. A new schedule never adds a second entry in the month (or
  /// week) that already has the old schedule's last one
  /// (madeThroughAfterChange). Its type, currency, first day and creation
  /// time never change.
  Future<Repeat> updateRepeat(Repeat changed) async {
    final old = await repeat(changed.id);
    if (old == null) throw StateError('no repeat ${changed.id}');
    final made = madeThroughAfterChange(
      old: old.schedule,
      changed: changed.schedule,
      first: parseWireDate(old.firstDate)!,
      madeThrough: parseWireDate(old.madeThrough)!,
    );
    final updated = old.copyWith(
      amountMinor: changed.amountMinor,
      category: changed.category,
      note: changed.note.trim(),
      schedule: changed.schedule,
      madeThrough: wireDate(made),
      updatedAt: _clock.nowUtc(),
    );
    _checkRepeat(updated);
    await _repeats.record(updated.id).put(_db, updated.toMap());
    notifyListeners();
    return updated;
  }

  /// Stops repeat [id] on [today] (the phone's date): it adds nothing more.
  /// The entries it added stay, and so does the repeat (hidden from the
  /// list), so they can still say what made them.
  Future<void> stopRepeat(String id, {required String today}) async {
    if (parseWireDate(today) == null) {
      throw ArgumentError.value(today, 'today');
    }
    final old = await repeat(id);
    if (old == null || !old.running) return;
    final stopped = old.copyWith(stoppedOn: today, updatedAt: _clock.nowUtc());
    await _repeats.record(id).put(_db, stopped.toMap());
    notifyListeners();
  }

  /// One catch-up at a time: a call during a run waits for it to end.
  Future<void> _catchUps = Future<void>.value();

  /// Adds each running repeat's entries for its days after the last day it
  /// dealt with, up to [today] (the phone's date, LocalDay), none older than
  /// a year (dueOccurrences). The app calls it at start, on resume and at
  /// midnight.
  ///
  /// An added entry copies its repeat's amount, category and note, has no
  /// feeling and is marked auto. A save goes to the active goal, as one from
  /// the Add sheet would. Each day is written in one transaction with its
  /// repeat's "made through", and its id is its repeat and day: two runs at
  /// once add nothing twice, and a day whose entry was deleted never comes
  /// back. A [today] before "made through" (the clock or the zone moved
  /// back) adds nothing and moves nothing. Returns what it added, oldest
  /// first.
  Future<List<Entry>> catchUpRepeats({required String today}) {
    final run = _catchUps.then((_) => _catchUp(today));
    _catchUps = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<List<Entry>> _catchUp(String today) async {
    final day = parseWireDate(today);
    if (day == null) throw ArgumentError.value(today, 'today');
    final added = <Entry>[];
    for (final (planned, date) in dueOccurrences(await repeats(), day)) {
      final id = repeatEntryId(planned.id, date);
      final made = await _db.transaction((txn) async {
        // Read again here: the latest amount and note, and whether a run
        // already got this far.
        final m = await _repeats.record(planned.id).get(txn);
        final r = m == null ? null : Repeat.fromMap(planned.id, m);
        if (r == null || !r.running) return null;
        if (!date.isAfter(parseWireDate(r.madeThrough)!)) return null;
        Entry? entry;
        if (await _entries.record(id).get(txn) == null) {
          final now = _clock.nowUtc();
          final spend = r.type == EntryType.spent;
          entry = Entry(
            id: id,
            type: r.type,
            amountMinor: r.amountMinor,
            currency: r.currency,
            category: spend ? r.category : null,
            note: r.note,
            goalId: spend ? null : (await _activeGoalIn(txn))?.id,
            localDate: wireDate(date),
            createdAt: now,
            updatedAt: now,
            repeatId: r.id,
            auto: true,
          );
          _check(entry);
          await _entries.record(id).put(txn, entry.toMap());
        }
        final moved = r.copyWith(madeThrough: wireDate(date));
        await _repeats.record(r.id).put(txn, moved.toMap());
        return entry;
      });
      if (made != null) {
        added.add(made);
        // A save that reaches the goal ends it, so the next goes to none.
        await _advance(made.goalId);
      }
    }
    // Every running repeat has now dealt with today.
    await _db.transaction((txn) async {
      for (final s in await _repeats.find(txn)) {
        final r = Repeat.fromMap(s.key, s.value);
        if (r == null || !r.running) continue;
        if (day.isAfter(parseWireDate(r.madeThrough)!)) {
          final moved = r.copyWith(madeThrough: today);
          await _repeats.record(r.id).put(txn, moved.toMap());
        }
      }
    });
    if (added.isNotEmpty) notifyListeners();
    return added;
  }

  // ---------------------------------------------------------------- all

  /// Erases every entry, goal, repeat and journal setting on the phone.
  Future<void> wipe() async {
    await _db.transaction((txn) async {
      await _entries.delete(txn);
      await _goals.delete(txn);
      await _repeats.delete(txn);
      await _settings.delete(txn);
    });
    notifyListeners();
  }

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

  static void _checkRepeat(Repeat r) {
    if (r.amountMinor <= 0) {
      throw ArgumentError.value(r.amountMinor, 'amountMinor');
    }
    if (!r.schedule.isValid) {
      throw ArgumentError.value(r.schedule, 'schedule');
    }
    if (r.type == EntryType.spent && r.category == null) {
      throw ArgumentError('a repeating spend needs a category');
    }
    if (r.note.characters.length > maxNoteLength) {
      throw ArgumentError('the note is over $maxNoteLength characters');
    }
  }
}
