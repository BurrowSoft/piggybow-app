import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

import '../core/clock.dart';
import '../goal/goal_progress.dart';
import '../money/rate.dart';
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

  /// The journal's format. 2 since entries in another currency (feature 19):
  /// a journal of a later format, written by a newer Piggybow, is refused
  /// ([JournalTooNew]), never half-read.
  static const format = 2;

  /// The journal file in the app's private support folder.
  static Future<JournalStore> open({required Clock clock}) async {
    final dir = await getApplicationSupportDirectory();
    final db = await databaseFactoryIo.openDatabase('${dir.path}/$fileName');
    await _checkFormat(db);
    return JournalStore._(db, clock: clock);
  }

  /// An empty journal in memory (tests); [factory] opens the same one again.
  static Future<JournalStore> inMemory({
    required Clock clock,
    String Function()? newId,
    DatabaseFactory? factory,
  }) async {
    final db = await (factory ?? newDatabaseFactoryMemory()).openDatabase('journal.db');
    await _checkFormat(db);
    return JournalStore._(db, clock: clock, newId: newId);
  }

  /// Refuses a newer format; marks an older (or a new) journal with this one.
  static Future<void> _checkFormat(Database db) async {
    final stored = await _settings.record('format').get(db);
    if (stored is int && stored > format) {
      await db.close();
      throw JournalTooNew(stored);
    }
    if (stored != format) await _settings.record('format').put(db, format);
  }

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
  ///
  /// In another currency than the journal's, it needs the [rate] typed: the
  /// amount is converted once, into the home currency, and that rate is kept
  /// as the last one for [currency] (feature 19).
  Future<Entry> addEntry({
    required EntryType type,
    required int amountMinor,
    required String currency,
    required String localDate,
    SpendCategory? category,
    Feeling? feeling,
    String note = '',
    Rate? rate,
  }) async {
    final now = _clock.nowUtc();
    final spend = type == EntryType.spent;
    final converted = await _converted(amountMinor, currency, rate);
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
      rate: converted == null ? null : rate,
      convertedMinor: converted,
    );
    _check(entry);
    await _entries.record(entry.id).put(_db, entry.toMap());
    if (entry.rate != null) await _keepRate(currency, entry.rate!);
    await _advance(entry.goalId);
    notifyListeners();
    return entry;
  }

  /// Saves an edit. Spent ↔ Saved is allowed: a spend drops its goal, a save
  /// drops its category and feeling and goes to the active goal if it had
  /// none. Its id and creation time never change.
  ///
  /// Its currency may: in another currency than the journal's it needs a
  /// rate, and its amount is converted again (that entry only); back in the
  /// journal's currency it keeps no rate.
  Future<Entry> updateEntry(Entry changed) async {
    final old = await entry(changed.id);
    if (old == null) throw StateError('no entry ${changed.id}');
    final spend = changed.type == EntryType.spent;
    var goalId = spend ? null : changed.goalId;
    if (!spend && old.type == EntryType.spent) {
      goalId = (await activeGoal())?.id;
    }
    final converted = await _converted(changed.amountMinor, changed.currency, changed.rate);
    final updated = Entry(
      id: old.id,
      type: changed.type,
      amountMinor: changed.amountMinor,
      currency: changed.currency,
      category: spend ? changed.category : null,
      feeling: spend ? changed.feeling : null,
      note: changed.note.trim(),
      goalId: goalId,
      localDate: changed.localDate,
      createdAt: old.createdAt,
      updatedAt: _clock.nowUtc(),
      rate: converted == null ? null : changed.rate,
      convertedMinor: converted,
    );
    _check(updated);
    await _entries.record(updated.id).put(_db, updated.toMap());
    if (updated.rate != null) await _keepRate(updated.currency, updated.rate!);
    await _advance(old.goalId);
    if (updated.goalId != old.goalId) await _advance(updated.goalId);
    notifyListeners();
    return updated;
  }

  /// [amountMinor] of [currency] in the journal's home currency, or null when
  /// [currency] is the home one (a rate is then refused). Another currency
  /// needs a [rate], and a result from 1 minor unit to the 12-digit cap.
  Future<int?> _converted(int amountMinor, String currency, Rate? rate) async {
    final home = await this.currency();
    if (home == null || currency == home) {
      if (rate != null) {
        throw ArgumentError.value(rate, 'rate', 'only for another currency than the journal\'s');
      }
      return null;
    }
    if (rate == null) {
      throw ArgumentError.value(currency, 'currency', 'another currency needs a rate');
    }
    if (amountMinor <= 0) throw ArgumentError.value(amountMinor, 'amountMinor');
    final converted = toHomeMinor(
      amountMinor: amountMinor,
      currency: currency,
      home: home,
      rate: rate,
    );
    if (converted == null) {
      throw ArgumentError.value(amountMinor, 'amountMinor', 'out of range in $home');
    }
    return converted;
  }

  /// The last rate typed for [currency] (to fill in the next one), if any.
  Future<Rate?> lastRate(String currency) async {
    final rates = await _settings.record('rates').get(_db);
    return rates is Map ? Rate.fromMap(rates[currency]) : null;
  }

  Future<void> _keepRate(String currency, Rate rate) async {
    final record = _settings.record('rates');
    final rates = await record.get(_db);
    await record.put(_db, {
      if (rates is Map) ...rates.cast<String, Object?>(),
      currency: rate.toMap(),
    });
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

  /// A goal's progress: what was already saved, plus every save that names it
  /// (a save in another currency at its home amount).
  Future<int> goalProgress(Goal goal) async {
    var sum = goal.startMinor;
    for (final e in await goalSaves(goal.id)) {
      sum += e.homeMinor;
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
      // Still this format: an emptied journal isn't an older one.
      await _settings.record('format').put(txn, format);
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
}

/// The journal was written by a newer Piggybow, in a later
/// [JournalStore.format]: the app asks for an update instead of opening it.
class JournalTooNew implements Exception {
  const JournalTooNew(this.format);

  /// The journal's own format.
  final int format;

  @override
  String toString() => 'JournalTooNew($format)';
}
