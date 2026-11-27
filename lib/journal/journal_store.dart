import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

import '../core/clock.dart';
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

  /// The journal file in the app's private support folder.
  static Future<JournalStore> open({required Clock clock}) async {
    final dir = await getApplicationSupportDirectory();
    final db = await databaseFactoryIo.openDatabase('${dir.path}/journal.db');
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

  // ------------------------------------------------------------- entries

  /// Every entry, newest day first; within a day, the newest added first.
  Future<List<Entry>> entries() async {
    final snaps = await _entries.find(
      _db,
      finder: Finder(
        sortOrders: [SortOrder('local_date', false), SortOrder('created_at', false)],
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
    if (!spend && old.type == EntryType.spent) goalId = (await activeGoal())?.id;
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
    notifyListeners();
    return updated;
  }

  Future<void> deleteEntry(String id) async {
    await _entries.record(id).delete(_db);
    notifyListeners();
  }

  // --------------------------------------------------------------- goals

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

  /// Stores [goal] as it is (the goal screens own the rules).
  Future<void> putGoal(Goal goal) async {
    await _goals.record(goal.id).put(_db, goal.toMap());
    notifyListeners();
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

  Future<void> close() => _db.close();

  static void _check(Entry e) {
    if (e.amountMinor <= 0) throw ArgumentError.value(e.amountMinor, 'amountMinor');
    if (e.date.isAfter(DateTime(9999))) throw ArgumentError.value(e.localDate, 'localDate');
    if (e.type == EntryType.spent && e.category == null) {
      throw ArgumentError('a spend needs a category');
    }
    if (e.note.characters.length > maxNoteLength) {
      throw ArgumentError('the note is over $maxNoteLength characters');
    }
  }
}
