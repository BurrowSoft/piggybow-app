import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

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
  static final _categories = stringMapStoreFactory.store('categories');
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

  /// Adds a spend or a save. A save goes to [goalId] when it names an active
  /// goal (the Add sheet's choice with several goals), else to the goal a
  /// save goes to by default ([activeGoal]), if any.
  Future<Entry> addEntry({
    required EntryType type,
    required int amountMinor,
    required String currency,
    required String localDate,
    SpendCategory? category,
    String? customCategory,
    Feeling? feeling,
    String note = '',
    String? goalId,
  }) async {
    final now = _clock.nowUtc();
    final spend = type == EntryType.spent;
    if (spend && customCategory != null) await _checkCustom(customCategory);
    final entry = Entry(
      id: _newId(),
      type: type,
      amountMinor: amountMinor,
      currency: currency,
      category: spend && customCategory == null ? category : null,
      customCategory: spend ? customCategory : null,
      feeling: spend ? feeling : null,
      note: note.trim(),
      goalId: spend ? null : await _saveGoal(goalId),
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
  /// drops its category and feeling and goes to the goal chosen, else to
  /// the default goal, if it had none. A save moved to another goal moves
  /// only to an active one. Its id, currency and creation time never change.
  Future<Entry> updateEntry(Entry changed) async {
    final old = await entry(changed.id);
    if (old == null) throw StateError('no entry ${changed.id}');
    final spend = changed.type == EntryType.spent;
    var goalId = spend ? null : changed.goalId;
    if (!spend && old.type == EntryType.spent) {
      goalId = await _saveGoal(changed.goalId);
    } else if (!spend && goalId != null && goalId != old.goalId) {
      goalId = await _saveGoal(goalId);
    }
    final custom = spend ? changed.customCategory : null;
    if (custom != null && custom != old.customCategory) await _checkCustom(custom);
    final updated = Entry(
      id: old.id,
      type: changed.type,
      amountMinor: changed.amountMinor,
      currency: old.currency,
      category: spend && custom == null ? changed.category : null,
      customCategory: custom,
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

  /// Every active goal, oldest first, so Home's cards keep their places.
  /// One without Plus; with Plus several (decision 79), and those stay after
  /// Plus ends.
  Future<List<Goal>> activeGoals() async {
    final snaps = await _goals.find(
      _db,
      finder: Finder(
        filter: Filter.equals('status', GoalStatus.active.id),
        sortOrders: [SortOrder('created_at')],
      ),
    );
    return [for (final s in snaps) ?Goal.fromMap(s.key, s.value)];
  }

  /// The goal a new save goes to by default, if any: the active goal, or
  /// with several, the one last saved to (else the oldest).
  Future<Goal?> activeGoal() async {
    final active = await activeGoals();
    if (active.length <= 1) return active.firstOrNull;
    final ids = {for (final g in active) g.id};
    Entry? last;
    for (final e in await entries()) {
      if (e.type != EntryType.saved || !ids.contains(e.goalId)) continue;
      if (last == null || e.createdAt.isAfter(last.createdAt)) last = e;
    }
    final lastGoal = last?.goalId;
    return lastGoal == null
        ? active.first
        : active.firstWhere((g) => g.id == lastGoal);
  }

  /// The goal a save goes to: [chosen] when it names an active goal
  /// (anything else is refused), else the default ([activeGoal]).
  Future<String?> _saveGoal(String? chosen) async {
    if (chosen == null) return (await activeGoal())?.id;
    final g = await goal(chosen);
    if (g == null || g.status != GoalStatus.active) {
      throw ArgumentError.value(chosen, 'goalId', 'not an active goal');
    }
    return chosen;
  }

  /// Reached goals, the latest reached first (Me's Reached goals).
  Future<List<Goal>> reachedGoals() async {
    final reached = [
      for (final g in await goals())
        if (g.status == GoalStatus.reached) g,
    ];
    reached.sort(
      (a, b) => (b.reachedAt ?? b.updatedAt).compareTo(a.reachedAt ?? a.updatedAt),
    );
    return reached;
  }

  Future<Goal?> goal(String id) async {
    final m = await _goals.record(id).get(_db);
    return m == null ? null : Goal.fromMap(id, m);
  }

  /// Stores [goal]; a new target can reach it (the goal screens own the
  /// other rules). A goal becomes active beside another only with
  /// [allowAnother] (Plus, decision 79); a goal that's already active can
  /// always be edited, so goals kept after Plus ends stay editable.
  Future<void> putGoal(Goal goal, {bool allowAnother = false}) async {
    if (goal.targetMinor <= 0) {
      throw ArgumentError.value(goal.targetMinor, 'targetMinor');
    }
    if (goal.startMinor < 0) {
      throw ArgumentError.value(goal.startMinor, 'startMinor');
    }
    // Without Plus, one active goal at a time: a second one is refused,
    // whatever asks.
    if (goal.status == GoalStatus.active && !allowAnother) {
      final stored = await this.goal(goal.id);
      if (stored?.status != GoalStatus.active) {
        final others = [
          for (final g in await activeGoals())
            if (g.id != goal.id) g.id,
        ];
        if (others.isNotEmpty) {
          throw StateError('goal ${others.first} is already active');
        }
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
  /// goal is no longer active, so the next save goes to another active goal,
  /// if any.
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

  // ---------------------------------------------------------- categories

  /// Your own categories (Plus, decision 79), oldest first, hidden ones too.
  /// They're never deleted, only hidden.
  Future<List<CustomCategory>> customCategories() async {
    final snaps = await _categories.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('created_at')]),
    );
    return [for (final s in snaps) ?CustomCategory.fromMap(s.key, s.value)];
  }

  /// A new id for a category of your own.
  String newCategoryId() => '${CustomCategory.idPrefix}${_newId()}';

  /// Stores [category]: its name trimmed, never empty, at most
  /// [categoryNameMax] characters, and not the name of another of your own
  /// (in any case; the screen also checks the built-ins' names).
  Future<void> putCustomCategory(CustomCategory category) async {
    if (!CustomCategory.isCustomId(category.id)) {
      throw ArgumentError.value(category.id, 'id');
    }
    final name = category.name.trim();
    if (name.isEmpty || name.characters.length > categoryNameMax) {
      throw ArgumentError.value(category.name, 'name');
    }
    final lower = name.toLowerCase();
    for (final c in await customCategories()) {
      if (c.id != category.id && c.name.toLowerCase() == lower) {
        throw StateError('a category named "$name" exists');
      }
    }
    await _categories
        .record(category.id)
        .put(_db, category.copyWith(name: name).toMap());
    notifyListeners();
  }

  /// The built-in categories hidden from the Add sheet (free for everyone).
  Future<Set<SpendCategory>> hiddenBuiltIns() async {
    final ids = await _settings.record('hidden_categories').get(_db);
    return {
      for (final id in ids is List ? ids : const []) ?SpendCategory.fromId(id),
    };
  }

  Future<void> setBuiltInHidden(SpendCategory category, bool hidden) async {
    final now = await hiddenBuiltIns();
    if (hidden) {
      now.add(category);
    } else {
      now.remove(category);
    }
    await _settings.record('hidden_categories').put(_db, [
      for (final c in SpendCategory.values)
        if (now.contains(c)) c.id,
    ]);
    notifyListeners();
  }

  /// Hides a category of your own from the Add sheet, or shows it again
  /// (free, like the built-ins'); its spends keep it either way.
  Future<void> setCustomHidden(String id, bool hidden) async {
    await _checkCustom(id);
    await _categories.record(id).update(_db, {'hidden': hidden});
    notifyListeners();
  }

  /// A spend goes only to a category of your own that exists.
  Future<void> _checkCustom(String id) async {
    if (!CustomCategory.isCustomId(id) ||
        !await _categories.record(id).exists(_db)) {
      throw ArgumentError.value(id, 'customCategory', 'no such category');
    }
  }

  // ---------------------------------------------------------------- all

  /// Erases every entry, goal and journal setting on the phone.
  Future<void> wipe() async {
    await _db.transaction((txn) async {
      await _entries.delete(txn);
      await _goals.delete(txn);
      await _categories.delete(txn);
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
    if (e.type == EntryType.spent &&
        e.category == null &&
        e.customCategory == null) {
      throw ArgumentError('a spend needs a category');
    }
    if (e.note.characters.length > maxNoteLength) {
      throw ArgumentError('the note is over $maxNoteLength characters');
    }
  }
}
