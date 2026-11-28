import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';

import '../backup/backup_snapshot.dart' show JournalSnapshot;
import '../core/clock.dart';
import '../goal/goal_progress.dart';
import '../money/currency.dart' show supportedCurrencies;
import '../money/money.dart' show maxAmountMinor;
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

  /// Whether Home asks how yesterday's spends felt (Me → Your pig): on until
  /// it's switched off. Delete everything clears it with the journal.
  Future<bool> yesterdayFeelOn() async =>
      await _settings.record('yesterday_feel_off').get(_db) != true;

  Future<void> setYesterdayFeelOn(bool on) async {
    await _settings.record('yesterday_feel_off').put(_db, !on);
    notifyListeners();
  }

  /// The day (YYYY-MM-DD) "Not now" hid that question: it stays hidden for
  /// the rest of that day.
  Future<String?> yesterdayFeelHiddenOn() async =>
      await _settings.record('yesterday_feel_hidden').get(_db) as String?;

  Future<void> hideYesterdayFeel(String today) async {
    await _settings.record('yesterday_feel_hidden').put(_db, today);
    notifyListeners();
  }

  /// Whether Home shows the pig's monthly letter (Me → Your pig): on until
  /// it's switched off. Delete everything clears it with the journal.
  Future<bool> lettersOn() async =>
      await _settings.record('letters_off').get(_db) != true;

  Future<void> setLettersOn(bool on) async {
    await _settings.record('letters_off').put(_db, !on);
    notifyListeners();
  }

  /// The month (YYYY-MM) whose letter "Thanks!" put away.
  Future<String?> letterDismissed() async =>
      await _settings.record('letter_dismissed').get(_db) as String?;

  Future<void> dismissLetter(String month) async {
    await _settings.record('letter_dismissed').put(_db, month);
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
  /// save goes to by default ([activeGoal]), if any; with [noGoal], to none
  /// (a save added again that had none stays so).
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
    bool noGoal = false,
  }) async {
    // Out of a goal, within what it has: takeOut.
    if (type == EntryType.withdraw) {
      throw ArgumentError.value(type, 'type', 'a withdrawal goes through takeOut');
    }
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
      goalId: spend || noGoal ? null : await _saveGoal(goalId),
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
  /// only to an active one. A withdrawal stays one, out of the same goal,
  /// and at most what that goal has (its own amount counted back); nothing
  /// becomes one. A save can't go lower than [saveFloor], nor leave its goal
  /// while it has one ([LockedByTakeOut]). Its id, currency and creation
  /// time never change.
  Future<Entry> updateEntry(Entry changed) async {
    final old = await entry(changed.id);
    if (old == null) throw StateError('no entry ${changed.id}');
    final withdraw = old.type == EntryType.withdraw;
    if (withdraw != (changed.type == EntryType.withdraw)) {
      throw ArgumentError.value(changed.type, 'type', 'a withdrawal stays one');
    }
    if (withdraw) {
      await _checkTakeOut(
        old.goalId!,
        changed.amountMinor,
        countedBack: old.amountMinor,
      );
    }
    // Money was taken out of this save's goal: it keeps at least that much.
    final floor = await saveFloor(old);
    if (floor > 0) {
      final staysThere =
          changed.type == EntryType.saved && changed.goalId == old.goalId;
      if (!staysThere || changed.amountMinor < floor) {
        throw LockedByTakeOut(old.goalId!);
      }
    }
    final spend = changed.type == EntryType.spent;
    var goalId = spend ? null : (withdraw ? old.goalId : changed.goalId);
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

  /// Deletes an entry; never a save its goal needs, because money was taken
  /// out of it ([LockedByTakeOut]).
  Future<void> deleteEntry(String id) async {
    final old = await entry(id);
    if (old != null && await saveFloor(old) > 0) {
      throw LockedByTakeOut(old.goalId!);
    }
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
    // What was already saved can't go below what was taken out of it.
    final old = await this.goal(goal.id);
    if (old != null &&
        goal.startMinor < old.startMinor &&
        goal.startMinor < await startFloor(old)) {
      throw LockedByTakeOut(goal.id);
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

  /// The saves that name [goalId], and what was taken out of it, newest day
  /// first: the goal's own list.
  Future<List<Entry>> goalSaves(String goalId) async => [
    for (final e in await entries())
      if (e.type != EntryType.spent && e.goalId == goalId) e,
  ];

  /// A goal's progress: what was already saved, plus every save that names
  /// it, less what was taken out of it. It never goes below 0: a withdrawal
  /// is at most what the goal has, and nothing that makes up for one can be
  /// lowered or removed ([saveFloor], [startFloor]); the 0 here is only a
  /// safety net for a journal from elsewhere.
  Future<int> goalProgress(Goal goal) async {
    final sum = await _rawProgress(goal);
    return sum < 0 ? 0 : sum;
  }

  /// [goalProgress] before its safety net.
  Future<int> _rawProgress(Goal goal) async {
    var sum = goal.startMinor;
    for (final e in await goalSaves(goal.id)) {
      sum += e.type == EntryType.withdraw ? -e.amountMinor : e.amountMinor;
    }
    return sum;
  }

  /// The least [save] can be changed to while it stays in its goal, which
  /// can't go below 0 once money was taken out of it: 0 when it could go
  /// entirely (be deleted, moved, made a spend). 0 for anything else.
  Future<int> saveFloor(Entry save) async {
    final goalId = save.goalId;
    if (save.type != EntryType.saved || goalId == null) return 0;
    final g = await goal(goalId);
    if (g == null) return 0;
    final without = await _rawProgress(g) - save.amountMinor;
    return without >= 0 ? 0 : -without;
  }

  /// The least [goal]'s "already saved" can be changed to, for the same
  /// reason: 0 when nothing was taken out of it beyond its saves.
  Future<int> startFloor(Goal goal) async {
    final without = await _rawProgress(goal) - goal.startMinor;
    return without >= 0 ? 0 : -without;
  }

  /// Takes [amountMinor] out of [goalId]'s savings on [localDate]: at most
  /// what the goal has now (its progress). A goal stays reached (that's an
  /// event); its rainbow goes down by it. The pig says nothing about it.
  Future<Entry> takeOut({
    required String goalId,
    required int amountMinor,
    required String currency,
    required String localDate,
    String note = '',
  }) async {
    await _checkTakeOut(goalId, amountMinor);
    final now = _clock.nowUtc();
    final entry = Entry(
      id: _newId(),
      type: EntryType.withdraw,
      amountMinor: amountMinor,
      currency: currency,
      note: note.trim(),
      goalId: goalId,
      localDate: localDate,
      createdAt: now,
      updatedAt: now,
    );
    _check(entry);
    await _entries.record(entry.id).put(_db, entry.toMap());
    notifyListeners();
    return entry;
  }

  /// What [goalId] has to take out of: its progress, plus [countedBack] (an
  /// edited withdrawal's own amount).
  Future<int> takeOutLimit(String goalId, {int countedBack = 0}) async {
    final g = await goal(goalId);
    if (g == null) throw ArgumentError.value(goalId, 'goalId', 'no such goal');
    return await goalProgress(g) + countedBack;
  }

  Future<void> _checkTakeOut(
    String goalId,
    int amountMinor, {
    int countedBack = 0,
  }) async {
    final limit = await takeOutLimit(goalId, countedBack: countedBack);
    if (amountMinor > limit) {
      throw StateError('more than the goal has saved ($amountMinor > $limit)');
    }
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
    'hidden_categories',
    // Me → Your pig's switches, and the month whose letter was put away
    // (UX, 28 Nov): a restore in the same month doesn't show it again.
    'yesterday_feel_off',
    'letters_off',
    'letter_dismissed',
  };

  static const _travelsPrefix = 'celebrated.';

  /// Journal settings that never leave this phone: today's "Not now" on
  /// Home's yesterday question, a one-day state (UX, 28 Nov).
  static const staysOnPhone = {'yesterday_feel_hidden'};

  /// The stores a backup carries. A new store is a choice too: the test that
  /// classifies the settings checks every store this file opens.
  static const backedUpStores = {'entries', 'goals', 'categories', 'settings'};

  static bool travelsWith(String key) =>
      travels.contains(key) || key.startsWith(_travelsPrefix);

  /// Everything a backup carries of the journal, read in one transaction:
  /// every entry, goal and category of your own as this build writes them,
  /// and the settings that travel. A record [checkSnapshot] would refuse
  /// (one an older build left unreadable, a spend in a category that isn't
  /// there) stays out, so a backup made here always restores.
  Future<JournalSnapshot> snapshot() => _db.transaction((txn) async {
    final entries = await _entries.find(txn);
    final goals = await _goals.find(txn);
    final categories = {
      for (final s in await _categories.find(txn))
        s.key: ?_categoryRecord(s.key, s.value),
    };
    final settings = await _settings.find(txn);
    return JournalSnapshot(
      entries: {
        for (final s in entries)
          if (_entryRecord(s.key, s.value) case final m?
              when _categoryKnown(m, categories))
            s.key: m,
      },
      goals: {for (final s in goals) s.key: ?_goalRecord(s.key, s.value)},
      categories: categories,
      settings: {
        for (final s in settings)
          if (_settingFits(s.key, s.value)) s.key: _plain(s.value),
      },
    );
  });

  /// [snapshot] as this store would write it. A [FormatException] for
  /// anything it never writes: an entry, goal or category of your own it
  /// can't read or would refuse, a spend in a category of your own the
  /// backup doesn't carry, two of your own with the same name, a second
  /// active goal, a setting that doesn't travel or holds the wrong kind of
  /// value.
  static JournalSnapshot checkSnapshot(JournalSnapshot snapshot) {
    final categories = <String, Map<String, Object?>>{};
    final names = <String>{};
    for (final MapEntry(:key, :value) in snapshot.categories.entries) {
      final record =
          _categoryRecord(key, value) ??
          (throw FormatException('category $key'));
      if (!names.add((record['name']! as String).toLowerCase())) {
        throw FormatException('two categories named ${record['name']}');
      }
      categories[key] = record;
    }
    final entries = <String, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in snapshot.entries.entries) {
      final record =
          _entryRecord(key, value) ?? (throw FormatException('entry $key'));
      if (!_categoryKnown(record, categories)) {
        throw FormatException('entry $key: no such category');
      }
      entries[key] = record;
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
    return JournalSnapshot(
      entries: entries,
      goals: goals,
      categories: categories,
      settings: settings,
    );
  }

  /// A category of your own as this store writes it ([putCustomCategory]'s
  /// rules: your own id, a name trimmed, not empty, at most
  /// [categoryNameMax] characters), or null.
  static Map<String, Object?>? _categoryRecord(
    String id,
    Map<String, Object?> m,
  ) {
    final category = CustomCategory.fromMap(id, m);
    if (category == null) return null;
    final name = category.name.trim();
    if (name.isEmpty || name.characters.length > categoryNameMax) return null;
    return category.copyWith(name: name).toMap();
  }

  /// Whether an entry's category of your own, if it has one, is in
  /// [categories] (a spend goes only to one that exists).
  static bool _categoryKnown(
    Map<String, Object?> entry,
    Map<String, Map<String, Object?>> categories,
  ) {
    final id = entry['category'];
    return !CustomCategory.isCustomId(id) || categories.containsKey(id);
  }

  /// The entry as this store writes it, or null for one it can't read, would
  /// refuse, or can't show: a currency this build doesn't list (its money
  /// can't be formatted) or an amount over [maxAmountMinor] (its edit sheet
  /// can't open).
  static Map<String, Object?>? _entryRecord(String id, Map<String, Object?> m) {
    final entry = id.isEmpty ? null : Entry.fromMap(id, m);
    if (entry == null ||
        !supportedCurrencies.contains(entry.currency) ||
        entry.amountMinor > maxAmountMinor) {
      return null;
    }
    try {
      _check(entry);
    } on ArgumentError {
      return null;
    }
    return entry.toMap();
  }

  /// The goal as this store writes it, or null for one it can't read or
  /// can't show (a target or a start over [maxAmountMinor]).
  static Map<String, Object?>? _goalRecord(String id, Map<String, Object?> m) {
    final goal = id.isEmpty ? null : Goal.fromMap(id, m);
    if (goal == null ||
        goal.targetMinor > maxAmountMinor ||
        goal.startMinor > maxAmountMinor) {
      return null;
    }
    return goal.toMap();
  }

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
      await _categories.delete(txn);
      for (final s in await _settings.find(txn)) {
        if (travelsWith(s.key)) await _settings.record(s.key).delete(txn);
      }
      await midway?.call();
      for (final MapEntry(:key, :value) in checked.categories.entries) {
        await _categories.record(key).put(txn, value);
      }
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

  static bool _settingFits(String key, Object? value) => switch (key) {
    'currency' => supportedCurrencies.contains(value),
    'picks' => value is List && value.every((p) => p is String),
    'plan_minor' => value is int && value > 0 && value <= maxAmountMinor,
    'onboarded' || 'reminder_offer' => value is bool,
    'hidden_categories' =>
      value is List && value.every((id) => SpendCategory.fromId(id) != null),
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
    if (e.type == EntryType.spent &&
        e.category == null &&
        e.customCategory == null) {
      throw ArgumentError('a spend needs a category');
    }
    if (e.type == EntryType.withdraw && e.goalId == null) {
      throw ArgumentError('a withdrawal is out of a goal');
    }
    if (e.note.characters.length > maxNoteLength) {
      throw ArgumentError('the note is over $maxNoteLength characters');
    }
  }
}

/// Refused: a save, or a goal's "already saved", can't be lowered or taken
/// out of its goal below what was taken out of it (the goal would hold less
/// than nothing). The screens say which goal: change or remove that
/// withdrawal first.
class LockedByTakeOut implements Exception {
  const LockedByTakeOut(this.goalId);

  final String goalId;

  @override
  String toString() => 'LockedByTakeOut($goalId)';
}
