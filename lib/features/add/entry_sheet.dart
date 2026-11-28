import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/button_label.dart';
import '../../core/clock.dart';
import '../../core/line_breaks.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../journal/journal_store.dart';
import '../../journal/quick_amounts.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/currency.dart';
import '../../money/money.dart';
import '../../money/rate.dart';
import '../../pig/pig_mood.dart' show PigReaction;
import '../../repeat/repeat.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../theme/theme.dart';
import '../currency/currency_picker.dart';
import '../plus/plus_screen.dart';
import '../repeat/repeat_choice.dart';
import 'add_again.dart';
import 'category_grid.dart';

/// Opens the Add sheet on [start] (Spent unless said), or the Edit sheet for
/// [editing], on the root navigator: full height over the tab bar, so no
/// tab can be switched under a half-finished entry. True when something
/// was saved, deleted or added again; after an add, "Added" shows (and is
/// read out) on the caller's own Scaffold, under its + (each tab has its
/// own messenger), and after Add again today, "Added again for today".
Future<bool> showEntrySheet(
  BuildContext context, {
  EntryType start = EntryType.spent,
  Entry? editing,
  String? goalId,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final services = context.services;
  final result = await showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EntrySheet(start: start, editing: editing, goalId: goalId),
  );
  // The edit sheet's menu: the entry as saved, added again today (any
  // change not saved is left, as when the sheet is closed).
  if (result is _AddAgain && editing != null) {
    await addAgainAndSay(services, editing, messenger: messenger, l10n: l10n);
    return true;
  }
  final saved = result == true;
  if (saved && editing == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.addedSnack)));
  }
  return saved;
}

/// What the edit sheet answers when its menu's "Add again today" is chosen.
class _AddAgain {
  const _AddAgain();
}

/// Entry sheets up now: a reminder tapped while one is opens no other.
var _sheetsOpen = 0;

/// Whether an entry sheet (adding or editing) is up.
bool get entrySheetOpen => _sheetsOpen > 0;

/// A full-height sheet: Spent or Saved, the amount, a spend's category and
/// feeling (or a save's goal), a note and the day.
class EntrySheet extends StatefulWidget {
  const EntrySheet({
    super.key,
    this.start = EntryType.spent,
    this.editing,
    this.goalId,
  });

  final EntryType start;
  final Entry? editing;

  /// A new save's goal to start with (a goal's own Add savings).
  final String? goalId;

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late EntryType _type = widget.editing?.type ?? widget.start;
  final _amount = TextEditingController();
  final _note = TextEditingController();

  /// A spend's category: a built-in, or one of your own (one or the other).
  SpendCategory? _category;
  String? _custom;
  Feeling? _feeling;

  /// The built-ins hidden from the sheet, and your own categories (oldest
  /// first): what the grid offers (offeredCategories).
  Set<SpendCategory> _hidden = const {};
  List<CustomCategory> _customs = const [];
  AppServices? _services;

  /// The entry's currency: the journal's (home) currency for a new entry,
  /// or another one picked with the currency chip (feature 19). Null until
  /// the journal's currency and today are read.
  String? _currency;

  /// The journal's home currency; null until read.
  String? _home;

  /// In another currency: the rate, typed one way or the other. The flip
  /// keeps what was typed each way.
  final _rate = TextEditingController();
  RateDirection _direction = RateDirection.toHome;
  final _rateTyped = <RateDirection, String>{};

  /// The journal's entries, for the quick amounts (adding only).
  List<Entry> _entries = const [];
  DateTime? _date;
  DateTime? _today;
  String? _goalName;

  /// The active goals, oldest first, and the goal a save goes to. With two
  /// or more (Plus, decision 79) the sheet lets the person choose.
  List<Goal> _goals = const [];
  String? _goalId;

  /// A save's goal can be chosen: two or more active goals, and the entry
  /// isn't a save already kept by a goal that's no longer active (reached
  /// or ended: it stays there).
  bool get _goalChoice =>
      _goals.length >= 2 &&
      (_goalId == null || _goals.any((g) => g.id == _goalId));

  /// An edited entry can be added again today (its menu offers it).
  bool _canAddAgain = false;

  /// Adding: how the new entry repeats (its day follows the picked day).
  RepeatChoice _repeat = RepeatChoice.none;

  /// Editing an entry of a repeat: that repeat (kept when stopped).
  Repeat? _repeatOf;

  /// Add was pressed: missing fields now say so.
  bool _tried = false;
  bool _busy = false;

  /// The last Add, Save or Delete failed in the store.
  bool _failed = false;

  /// An edited save whose goal had money taken out: the least it can be
  /// (0: it can go entirely), and whether a change was refused for that.
  int _saveFloor = 0;
  bool _lockedOut = false;

  bool get _editing => widget.editing != null;

  String get _locale => context.readSession.device.localeName;

  @override
  void initState() {
    super.initState();
    _sheetsOpen++;
    final e = widget.editing;
    if (e != null) {
      _category = e.category;
      _custom = e.customCategory;
      _feeling = e.feeling;
      _note.text = e.note;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Your own categories are in the grid while Plus is on.
      (_services = context.services).plus?.addListener(_plusChanged);
      _load();
    });
  }

  void _plusChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasCategory => _category != null || _custom != null;

  Future<(Set<SpendCategory>, List<CustomCategory>)> _readCategories() async {
    final store = context.services.journal;
    return (await store.hiddenBuiltIns(), await store.customCategories());
  }

  Future<void> _load() async {
    final services = context.services;
    final store = services.journal;
    final e = widget.editing;
    final home = await store.currency() ?? 'USD';
    // A new entry starts in the home currency (UX); an edit, in its own.
    final currency = e?.currency ?? home;
    // A save shows where it goes: its own goal when it has one, else the
    // goal it was opened for (if active), else the default goal (where a
    // new save goes).
    final active = await store.activeGoals();
    final preset = widget.goalId;
    final goalId =
        e?.goalId ??
        (active.any((g) => g.id == preset)
            ? preset
            : (await store.activeGoal())?.id);
    final goal = goalId == null ? null : await store.goal(goalId);
    // Adding: the quick amounts come from what was spent before.
    final entries = e == null ? await store.entries() : const <Entry>[];
    final floor = e == null ? 0 : await store.saveFloor(e);
    final repeatId = e?.repeatId;
    final repeat = repeatId == null ? null : await store.repeat(repeatId);
    if (!mounted) return;
    final (hidden, customs) = await _readCategories();
    if (!mounted) return;
    final today = services.localDay.today;
    setState(() {
      _hidden = hidden;
      _customs = customs;
      _home = home;
      _currency = currency;
      _goals = active;
      _goalId = goalId;
      _entries = entries;
      _goalName = goal?.name;
      _canAddAgain =
          e != null &&
          canAddAgain(
            e,
            goalId == null ? null : goal,
            plus: services.plus?.active ?? false,
          );
      _saveFloor = floor;
      _repeatOf = repeat;
      _today = today;
      _date = e?.date ?? today;
      if (e != null) {
        _amount.text = inputAmount(e.amountMinor, currency, _locale);
        final rate = e.rate;
        if (rate != null) {
          _direction = rate.direction;
          _rate.text = rateInput(rate, _mark);
        }
      }
    });
  }

  /// A quick amount's tap: the amount field takes it (the caret at its end);
  /// nothing is saved until Add.
  void _useQuickAmount(int minor, String currency) {
    final text = inputAmount(minor, currency, _locale);
    setState(
      () => _amount.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  @override
  void dispose() {
    _sheetsOpen--;
    _services?.plus?.removeListener(_plusChanged);
    _amount.dispose();
    _note.dispose();
    _rate.dispose();
    super.dispose();
  }

  /// The phone's decimal separator: the only mark a rate is typed with (UX).
  String get _mark => rateMark(_locale);

  /// The entry is in another currency than the journal's.
  bool get _abroad {
    final currency = _currency;
    final home = _home;
    return currency != null && home != null && currency != home;
  }

  /// The typed rate, read; null in the home currency.
  ParsedRate? get _parsedRate =>
      _abroad ? parseRate(_rate.text, _direction, mark: _mark) : null;

  /// The amount in the home currency, once the amount and the rate are both
  /// read; null until then, and in the home currency.
  Conversion? get _conversion {
    final minor = _parsed?.minor;
    final rate = _parsedRate?.rate;
    if (minor == null || rate == null) return null;
    return convertToHome(
      amountMinor: minor,
      currency: _currency!,
      home: _home!,
      rate: rate,
    );
  }

  /// The rate's error line: after Add for an empty or zero rate; at once for
  /// one that can't be read, and for an amount that comes out too small or
  /// too large in the home currency.
  String? _rateError(AppLocalizations l10n) {
    final problem = _parsedRate?.problem;
    if (problem != null) {
      return switch (problem) {
        RateProblem.invalid => l10n.rateFormatError(_mark, '36${_mark}5'),
        RateProblem.empty => _tried ? l10n.rateEmpty : null,
        RateProblem.zero => _tried ? l10n.rateZero : null,
      };
    }
    return switch (_conversion?.problem) {
      null => null,
      ConversionProblem.tooLarge => l10n.addAmountTooBig,
      ConversionProblem.tooSmall => l10n.rateTooSmall(
        formatMoney(1, _home!, _locale),
      ),
    };
  }

  /// The currency chip: the picker, then, in another currency, the last rate
  /// typed for it (if any).
  Future<void> _pickCurrency() async {
    final current = _currency;
    final home = _home;
    if (current == null || home == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CurrencyPickerScreen(current: current)),
    );
    if (picked == null || picked == current || !mounted) return;
    final last = picked == home
        ? null
        : await context.services.journal.lastRate(picked);
    if (!mounted) return;
    setState(() {
      _currency = picked;
      _rateTyped.clear();
      _direction = last?.direction ?? RateDirection.toHome;
      _rate.text = last == null ? '' : rateInput(last, _mark);
    });
  }

  /// ⇄: the rate typed the other way ("1 THB = 0.0256 EUR"). What was typed
  /// each way is kept, so flipping back loses nothing.
  void _flip() {
    setState(() {
      _rateTyped[_direction] = _rate.text;
      _direction = _direction == RateDirection.toHome
          ? RateDirection.fromHome
          : RateDirection.toHome;
      _rate.text = _rateTyped[_direction] ?? '';
    });
  }

  ParsedAmount? get _parsed {
    final currency = _currency;
    return currency == null ? null : parseAmount(_amount.text, currency);
  }

  /// The amount's error line: after Add for an empty or zero amount; at once
  /// for a pasted amount that can't be read, or one that's too large, or for
  /// a save lowered below what was taken out of its goal.
  String? _amountError(AppLocalizations l10n) {
    final parsed = _parsed;
    final minor = parsed?.minor;
    // The floor is a home amount: in another currency, the amount converted
    // (none until the rate is read).
    final atHome = _abroad ? _conversion?.minor : minor;
    if (_saveFloor > 0 &&
        _type == EntryType.saved &&
        atHome != null &&
        atHome < _saveFloor) {
      return l10n.saveLockedByTakeOut(_goalName ?? '');
    }
    final problem = parsed?.problem;
    return switch (problem) {
      null => null,
      AmountProblem.tooBig => l10n.addAmountTooBig,
      AmountProblem.invalid => l10n.addAmountError,
      AmountProblem.empty ||
      AmountProblem.zero => _tried ? l10n.addAmountError : null,
    };
  }

  Future<void> _submit() async {
    final currency = _currency;
    final date = _date;
    final parsed = _parsed;
    if (_busy || currency == null || date == null || parsed == null) return;
    final spend = _type == EntryType.spent;
    final l10n = AppLocalizations.of(context);
    // In another currency, a rate that converts the amount (feature 19).
    final abroad = _abroad;
    final rate = _parsedRate?.rate;
    final converted = _conversion?.minor;
    if (parsed.problem != null ||
        (spend && !_hasCategory) ||
        _amountError(l10n) != null ||
        (abroad && converted == null)) {
      setState(() => _tried = true);
      return;
    }
    // A save its goal needs can't become a spend (money was taken out).
    if (_saveFloor > 0 && spend) {
      setState(() {
        _failed = true;
        _lockedOut = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _lockedOut = false;
    });
    final services = context.services;
    final store = services.journal;
    final editing = widget.editing;
    try {
      if (editing == null) {
        // A repeat stays in the home currency for now: in another currency,
        // Add makes none.
        final repeat = abroad ? null : scheduleFor(_repeat, date);
        await store.addEntry(
          type: _type,
          amountMinor: parsed.minor!,
          currency: currency,
          localDate: wireDate(date),
          category: _category,
          customCategory: _custom,
          feeling: _feeling,
          note: _note.text,
          goalId: spend ? null : _goalId,
          // The first of a repeat: it adds the next ones on their days.
          repeat: repeat,
          today: repeat == null ? null : services.localDay.todayWire,
          rate: abroad ? rate : null,
        );
        // The pig answers what was just added (plan §4.4).
        services.lastAdd.value = !spend
            ? PigReaction.save
            : switch (_feeling) {
                Feeling.worthIt => PigReaction.worth,
                Feeling.notSure => PigReaction.notSure,
                Feeling.notReally => PigReaction.notReally,
                null => PigReaction.spend,
              };
      } else {
        await store.updateEntry(
          editing.copyWith(
            type: _type,
            amountMinor: parsed.minor!,
            category: _category,
            customCategory: _custom,
            clearCategory: !_hasCategory,
            feeling: _feeling,
            clearFeeling: _feeling == null,
            note: _note.text,
            localDate: wireDate(date),
            // The goal chosen (several goals), else the one it has.
            goalId: spend ? null : _goalId,
            // Its currency may change; the store converts it again (or, back
            // in the home currency, keeps no rate).
            currency: currency,
            rate: abroad ? rate : null,
            convertedMinor: abroad ? converted : null,
            clearRate: !abroad,
          ),
        );
      }
    } on Object catch (error, stack) {
      _storeFailed(error, stack);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// The store refused or failed: the sheet stays usable and says so once,
  /// and the error is reported (crash reports scrub it).
  void _storeFailed(Object error, StackTrace stack) {
    // Refused because money was taken out of the goal: said, not reported.
    final locked = error is LockedByTakeOut;
    if (!locked) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'entry sheet',
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = true;
      _lockedOut = locked;
    });
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    // A save its goal needs can't go (money was taken out): said at once.
    if (_saveFloor > 0) {
      setState(() {
        _failed = true;
        _lockedOut = true;
      });
      return;
    }
    // An entry of a running repeat: deleting it doesn't stop the repeat.
    final stillRepeats = _repeatOf?.running ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.deleteEntryTitle),
        content: stillRepeats
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.deleteEntryBody),
                  const SizedBox(height: 8),
                  TestId(
                    'delete-repeat-note',
                    child: Text(l10n.repeatDeleteNote),
                  ),
                ],
              )
            : Text(l10n.deleteEntryBody),
        actions: [
          TestId(
            'delete-cancel',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: ButtonLabel(l10n.cancel),
            ),
          ),
          TestId(
            'delete-confirm',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: ButtonLabel(l10n.deleteEntryConfirm),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await context.services.journal.deleteEntry(widget.editing!.id);
    } on Object catch (error, stack) {
      _storeFailed(error, stack);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickDate() async {
    final today = _today;
    final date = _date;
    if (today == null || date == null) return;
    // Drop the amount's focus first: when the picker closes, the keyboard
    // doesn't come back and the sheet doesn't jump up to the amount.
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      // No future days.
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    final day = dateOnly(picked);
    setState(() {
      _date = day;
      // The repeat's day follows the picked day; "the last day" only while
      // the picked day is its month's last.
      if (!repeatChoicesFor(day).contains(_repeat)) {
        _repeat = RepeatChoice.monthly;
      }
    });
  }

  /// Adding: how the entry repeats, from the choices for its day.
  Future<void> _pickRepeat() async {
    final date = _date;
    if (date == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showRepeatChoices(
      context,
      date: date,
      dateLocale: context.readSession.dateLocale,
      current: _repeat,
    );
    if (picked != null && mounted) setState(() => _repeat = picked);
  }

  /// "Manage": the sheet closes, and the repeat's page opens in Me.
  void _manageRepeat(Repeat repeat) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    router.go(MeRoutes.repeat(repeat.id));
  }

  /// Add category (Plus): the paywall first without it, then the editor
  /// over the sheet; the new category comes back picked.
  Future<void> _addCategory() async {
    // As for the date: the keyboard doesn't come back to the amount.
    FocusManager.instance.primaryFocus?.unfocus();
    if (!await requirePlus(context) || !mounted) return;
    final id = await context.push<String>(CategoryRoutes.create);
    if (!mounted) return;
    final (hidden, customs) = await _readCategories();
    if (!mounted) return;
    setState(() {
      _hidden = hidden;
      _customs = customs;
      if (id != null) {
        _category = null;
        _custom = id;
      }
    });
  }

  /// The grid: the categories offered (the spend's own and the one picked
  /// always among them), then Add category in builds with Plus.
  List<CategoryTile> _tiles(AppLocalizations l10n) {
    final plus = context.services.plus;
    final picked = _category?.id ?? _custom;
    return [
      ...categoryTiles(
        l10n,
        ids: offeredCategories(
          hidden: _hidden,
          customs: _customs,
          plus: plus?.active ?? false,
          keep: [?widget.editing?.categoryId, ?picked],
        ),
        customs: _customs,
        picked: picked,
        idPrefix: 'add-cat',
        onPick: (id) => setState(() {
          _category = SpendCategory.fromId(id);
          _custom = _category == null ? id : null;
        }),
      ),
      if (plus != null)
        CategoryTile(
          id: 'add-cat-add',
          label: l10n.categoryAdd,
          icon: Icons.add,
          onTap: _addCategory,
        ),
    ];
  }

  String _dateLabel(AppLocalizations l10n, DateTime date, DateTime today) {
    if (date == today) return l10n.addDateToday;
    if (date == DateTime(today.year, today.month, today.day - 1)) {
      return l10n.addDateYesterday;
    }
    return DateFormat.yMMMd(context.readSession.dateLocale).format(date);
  }

  String _symbol(String currency) {
    try {
      return NumberFormat.simpleCurrency(
        locale: _locale,
        name: currency,
      ).currencySymbol;
    } on Object {
      return currency;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currency = _currency;
    final date = _date;
    final today = _today;
    final spend = _type == EntryType.spent;
    final parsed = _parsed;
    final amountError = _amountError(l10n);
    final home = _home;
    final abroad = _abroad;
    final rateError = _rateError(l10n);
    final converted = _conversion?.minor;
    // The rate as typed: "1 EUR = [39.12] THB", or the other way round.
    final (rateFrom, rateTo) = switch ((currency, home)) {
      (final c?, final h?) =>
        _direction == RateDirection.toHome ? (c, h) : (h, c),
      _ => ('', ''),
    };
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      color: theme.colorScheme.surface,
      // Above the keyboard: the form scrolls, and Add stays in reach.
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  TestId(
                    'add-back',
                    button: true,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.cancel,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        _editing ? l10n.editSheetLabel : l10n.addSheetLabel,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  // The entry's menu (as the goal's): Add again today, also
                  // offered by a long-press on its Timeline row.
                  if (_editing && _canAddAgain)
                    TestId(
                      'edit-more',
                      button: true,
                      child: PopupMenuButton<String>(
                        enabled: !_busy,
                        onSelected: (_) =>
                            Navigator.of(context).pop(const _AddAgain()),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'again',
                            child: TestId(
                              'edit-repeat',
                              child: Text(l10n.entryRepeat),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: currency == null || date == null || today == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        SegmentedButton<EntryType>(
                          showSelectedIcon: false,
                          segments: [
                            for (final (t, id, label) in [
                              (
                                EntryType.spent,
                                'add-seg-spent',
                                l10n.addSegSpent,
                              ),
                              (
                                EntryType.saved,
                                'add-seg-saved',
                                l10n.addSegSaved,
                              ),
                            ])
                              ButtonSegment(
                                value: t,
                                label: TestId(
                                  id,
                                  button: true,
                                  selected: _type == t,
                                  // One word: whole, smaller only if it must.
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          selected: {_type},
                          onSelectionChanged: (s) =>
                              setState(() => _type = s.first),
                        ),
                        const SizedBox(height: 16),
                        TestId(
                          'add-amount',
                          child: TextField(
                            // Asks the keyboard not to learn from what is typed here (Android).
                            enableIMEPersonalizedLearning: false,
                            controller: _amount,
                            autofocus: !_editing,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: minorDigitsOf(currency) > 0,
                            ),
                            inputFormatters: [
                              AmountInputFormatter(minorDigitsOf(currency)),
                            ],
                            onChanged: (_) => setState(() {}),
                            // Typed text in ink, larger for the amount.
                            style: context.inputText?.copyWith(fontSize: 24),
                            decoration: InputDecoration(
                              labelText: l10n.addAmountLabel,
                              prefixText: '${_symbol(currency)} ',
                              errorText: amountError,
                              // The take-out lock names the goal: up to 40
                              // characters, at text ×2.
                              errorMaxLines: 8,
                            ),
                          ),
                        ),
                        // How the amount was read, whenever it can be; not
                        // in another currency, where it would only repeat the
                        // field (the amount at home follows the rate).
                        if (!abroad &&
                            amountError == null &&
                            parsed?.minor != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 12),
                            child: TestId(
                              'add-amount-preview',
                              // One line, whole: smaller only if the largest
                              // amount can't fit at 320 dp and 200 % text.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  l10n.addAmountPreview(
                                    formatMoney(
                                      parsed!.minor!,
                                      currency,
                                      _locale,
                                    ),
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  style: muted,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        // The entry's currency: the home one unless another
                        // is picked (feature 19).
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TestId(
                            'add-currency',
                            button: true,
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.currency_exchange,
                                size: 18,
                              ),
                              label: Semantics(
                                label: l10n.addCurrency(
                                  l10n.currencyName(currency),
                                ),
                                child: ExcludeSemantics(child: Text(currency)),
                              ),
                              onPressed: _busy ? null : _pickCurrency,
                            ),
                          ),
                        ),
                        if (abroad) ...[
                          const SizedBox(height: 16),
                          Text(
                            l10n.rateLabel,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TestId(
                                  'add-rate',
                                  child: TextField(
                                    // Asks the keyboard not to learn from what is
                                    // typed here (Android).
                                    enableIMEPersonalizedLearning: false,
                                    controller: _rate,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [_RateFormatter(_mark)],
                                    onChanged: (_) => setState(() {}),
                                    style: context.inputText,
                                    decoration: InputDecoration(
                                      // "1 EUR =", over what's typed.
                                      labelText: l10n.rateOne(rateFrom),
                                      // "THB", always shown after it.
                                      suffixIcon: Padding(
                                        padding: const EdgeInsetsDirectional
                                            .only(start: 8, end: 12),
                                        child: Text(
                                          rateTo,
                                          style: context.inputText,
                                        ),
                                      ),
                                      suffixIconConstraints:
                                          const BoxConstraints(minHeight: 48),
                                      errorText: rateError,
                                      errorMaxLines: 4,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              TestId(
                                'add-rate-flip',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(Icons.swap_horiz),
                                  tooltip: l10n.rateFlip,
                                  onPressed: _flip,
                                ),
                              ),
                            ],
                          ),
                        ],
                        // In another currency: the amount at home, as it
                        // will be counted, once the rate is read. A sentence
                        // (UX), so it can't be read as a second sum; it
                        // wraps at large text. Under the rate it comes from
                        // (UX).
                        if (abroad && amountError == null && converted != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 12),
                            child: TestId(
                              'add-converted',
                              child: Text(
                                l10n.travelHomeAmount(
                                  formatMoney(converted, home!, _locale),
                                ),
                                style: muted,
                              ),
                            ),
                          ),
                        // By the picked category's id: a built-in or your
                        // own (#49). After the money being typed: its
                        // currency, rate and amount at home (UX).
                        if (spend && !_editing && _hasCategory)
                          _QuickAmounts(
                            amounts: quickAmounts(
                              _entries,
                              categoryId: (_category?.id ?? _custom)!,
                              currency: currency,
                            ),
                            currency: currency,
                            locale: _locale,
                            onUse: (minor) => _useQuickAmount(minor, currency),
                          ),
                        const SizedBox(height: 16),
                        if (spend) ...[
                          Text(
                            l10n.addCategoryLabel,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          CategoryGrid(tiles: _tiles(l10n)),
                          if (_tried && !_hasCategory)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  l10n.addCategoryError,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                        ] else if (_goalChoice) ...[
                          // Several goals (Plus): which one this save is for,
                          // one always picked, oldest goal first.
                          Text(
                            l10n.addSaveToward,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (i, g) in _goals.indexed)
                                TestId(
                                  'add-goal-${i + 1}',
                                  button: true,
                                  selected: _goalId == g.id,
                                  child: ChoiceChip(
                                    label: Text(g.name),
                                    selected: _goalId == g.id,
                                    showCheckmark: false,
                                    onSelected: (_) => setState(() {
                                      _goalId = g.id;
                                      _goalName = g.name;
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ] else
                          Text(
                            _goalName == null
                                ? l10n.addNoGoal
                                : l10n.addGoesTo(_goalName!),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 16),
                        TestId(
                          'add-note',
                          child: TextField(
                            // Asks the keyboard not to learn from what is typed here (Android).
                            enableIMEPersonalizedLearning: false,
                            controller: _note,
                            maxLength: maxNoteLength,
                            // Up to 3 lines, so a long note is seen whole;
                            // still one line of text: Enter is Done, and a
                            // pasted line break becomes a space.
                            minLines: 1,
                            maxLines: 3,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            inputFormatters: const [LineBreaksAsSpaces()],
                            textCapitalization: TextCapitalization.sentences,
                            style: context.inputText,
                            decoration: InputDecoration(
                              labelText: l10n.addNoteLabel,
                              hintText: spend
                                  ? l10n.addNoteHintSpent
                                  : l10n.addNoteHintSaved,
                              hintMaxLines: 2,
                              errorMaxLines: 3,
                            ),
                          ),
                        ),
                        if (spend) ...[
                          const SizedBox(height: 8),
                          Text(
                            l10n.addFeelingLabel,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (f, id, label) in [
                                (
                                  Feeling.worthIt,
                                  'add-feel-worth',
                                  l10n.feelWorth,
                                ),
                                (
                                  Feeling.notSure,
                                  'add-feel-not-sure',
                                  l10n.feelNotSure,
                                ),
                                (
                                  Feeling.notReally,
                                  'add-feel-not-really',
                                  l10n.feelNotReally,
                                ),
                              ])
                                TestId(
                                  id,
                                  button: true,
                                  selected: _feeling == f,
                                  child: ChoiceChip(
                                    label: Text(label),
                                    selected: _feeling == f,
                                    showCheckmark: false,
                                    // Tap again to clear: "Worth it?" is optional.
                                    onSelected: (_) => setState(
                                      () => _feeling = _feeling == f ? null : f,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TestId(
                            'add-date',
                            button: true,
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.calendar_today,
                                size: 18,
                              ),
                              label: Text(_dateLabel(l10n, date, today)),
                              onPressed: _pickDate,
                            ),
                          ),
                        ),
                        // Adding only: whether it repeats, worded from the
                        // picked day.
                        if (!_editing) ...[
                          const SizedBox(height: 8),
                          _RepeatRow(
                            choice: _repeat,
                            date: date,
                            onTap: _pickRepeat,
                            off: abroad ? l10n.repeatHomeCurrencyOnly : null,
                          ),
                        ],
                        // Editing an entry of a repeat: which one, and
                        // where to change it.
                        if (_editing && _repeatOf != null)
                          _RepeatInfo(
                            entry: widget.editing!,
                            repeat: _repeatOf!,
                            onManage: () => _manageRepeat(_repeatOf!),
                          ),
                      ],
                    ),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _lockedOut
                        ? l10n.saveLockedByTakeOut(_goalName ?? '')
                        : l10n.errGeneric,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                // Side by side when they fit; when they don't (large text),
                // they stack, Save on top: whole words always.
                child: _editing
                    ? OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.end,
                        overflowDirection: VerticalDirection.up,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TestId(
                            'edit-delete',
                            button: true,
                            child: TextButton(
                              onPressed: _busy ? null : _delete,
                              child: ButtonLabel(l10n.editDelete),
                            ),
                          ),
                          TestId(
                            'edit-save',
                            button: true,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: ButtonLabel(l10n.editSave),
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: TestId(
                          'add-submit',
                          button: true,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: ButtonLabel(l10n.addSubmit),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feature 3: the last different amounts spent in the picked category,
/// newest first, as chips; a tap uses one ("Use $12.50").
class _QuickAmounts extends StatelessWidget {
  const _QuickAmounts({
    required this.amounts,
    required this.currency,
    required this.locale,
    required this.onUse,
  });

  final List<int> amounts;
  final String currency;
  final String locale;
  final ValueChanged<int> onUse;

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, minor) in amounts.indexed)
            TestId(
              'add-quick-$i',
              button: true,
              child: ActionChip(
                label: Builder(
                  builder: (context) {
                    final text = formatMoney(minor, currency, locale);
                    return Semantics(
                      label: l10n.quickAmountUse(text),
                      excludeSemantics: true,
                      child: Text(text),
                    );
                  },
                ),
                onPressed: () => onUse(minor),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Add sheet's Repeat row: "Doesn't repeat", or the schedule the picked
/// day makes, with the shorter-months hint for days 29 and 30. With [off],
/// why this entry can't repeat: the row says so in the hint's place,
/// "Doesn't repeat" over it, and can't be tapped (the choice made is kept
/// for when it can again).
class _RepeatRow extends StatelessWidget {
  const _RepeatRow({
    required this.choice,
    required this.date,
    required this.onTap,
    this.off,
  });

  final RepeatChoice choice;
  final DateTime date;
  final VoidCallback onTap;
  final String? off;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final off = this.off;
    final schedule = off == null ? scheduleFor(choice, date) : null;
    final value = schedule == null
        ? l10n.repeatNone
        : scheduleText(l10n, context.session.dateLocale, schedule);
    final hint = off ?? scheduleHint(l10n, schedule);
    return TestId(
      'add-repeat',
      button: off == null,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.repeat),
        title: Text(l10n.addRepeat),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value),
            if (hint != null)
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: off == null ? const Icon(Icons.chevron_right) : null,
        onTap: off == null ? onTap : null,
      ),
    );
  }
}

/// Editing an entry of a repeat: "Added by your repeat: Every month on day
/// 1" (or that the repeat is stopped), with Manage while it runs. The
/// repeat's first entry, the person's own, shows just its schedule.
class _RepeatInfo extends StatelessWidget {
  const _RepeatInfo({
    required this.entry,
    required this.repeat,
    required this.onManage,
  });

  final Entry entry;
  final Repeat repeat;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final schedule = scheduleText(
      l10n,
      context.session.dateLocale,
      repeat.schedule,
    );
    final text = entry.auto
        ? (repeat.running ? l10n.repeatFrom(schedule) : l10n.repeatFromStopped)
        : (repeat.running ? schedule : null);
    if (text == null) return const SizedBox.shrink();
    final line = Row(
      children: [
        Icon(Icons.repeat, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    final manage = repeat.running
        ? TestId(
            'edit-repeat-manage',
            button: true,
            child: TextButton(
              onPressed: onManage,
              child: ButtonLabel(l10n.repeatManage),
            ),
          )
        : null;
    // At large text Manage goes under the line, at its end, as a Timeline
    // row's amount does: the line keeps the sheet's width.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TestId.container(
        'edit-repeat',
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  line,
                  if (manage != null)
                    Align(alignment: AlignmentDirectional.centerEnd, child: manage),
                ],
              )
            : Row(
                children: [
                  Expanded(child: line),
                  ?manage,
                ],
              ),
      ),
    );
  }
}

/// Typing: digits and at most one decimal mark ("." or ","), with no more
/// decimals than the currency has. A paste (several characters at once) goes
/// in as it is, and the field says when it can't be read.
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter(int decimals)
    : _allowed = decimals == 0
          ? RegExp(r'^[0-9]*$')
          : RegExp('^[0-9]*([.,][0-9]{0,$decimals})?\$');

  final RegExp _allowed;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final pasted = newValue.text.length - oldValue.text.length > 1;
    return pasted || _allowed.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Typing a rate: digits and at most one [mark] (the phone's decimal
/// separator, never a grouping mark), with at most [maxRateDecimals]
/// decimals and [maxRateDigits] digits, leading zeros aside. A paste goes in
/// as it is, and the field says when it can't be read.
class _RateFormatter extends TextInputFormatter {
  _RateFormatter(this.mark)
    : _allowed = RegExp(
        '^[0-9]*(${RegExp.escape(mark)}[0-9]{0,$maxRateDecimals})?\$',
      );

  final String mark;
  final RegExp _allowed;
  static final _leadingZeros = RegExp('^0+');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final pasted = text.length - oldValue.text.length > 1;
    if (pasted) return newValue;
    final digits = text.replaceAll(mark, '').replaceFirst(_leadingZeros, '');
    return _allowed.hasMatch(text) && digits.length <= maxRateDigits
        ? newValue
        : oldValue;
  }
}
