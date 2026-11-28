import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/button_label.dart';
import '../../core/clock.dart';
import '../../core/fit_text.dart';
import '../../core/line_breaks.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../journal/journal_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/currency.dart';
import '../../money/money.dart';
import '../../pig/pig_mood.dart' show PigReaction;
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../theme/theme.dart';
import '../plus/plus_screen.dart';

/// Opens the Add sheet on [start] (Spent unless said), or the Edit sheet for
/// [editing], on the root navigator: full height over the tab bar, so no
/// tab can be switched under a half-finished entry. True when something
/// was saved or deleted; after an add, "Added" shows (and is read out) on
/// the caller's own Scaffold, under its + (each tab has its own
/// messenger).
Future<bool> showEntrySheet(
  BuildContext context, {
  EntryType start = EntryType.spent,
  Entry? editing,
  String? goalId,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EntrySheet(start: start, editing: editing, goalId: goalId),
  );
  if (saved == true && editing == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.addedSnack)));
  }
  return saved == true;
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

  /// Null until the journal's currency and today are read.
  String? _currency;
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

  /// Add was pressed: missing fields now say so.
  bool _tried = false;
  bool _busy = false;

  /// The last Add, Save or Delete failed in the store.
  bool _failed = false;

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
    final currency = e?.currency ?? await store.currency() ?? 'USD';
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
    if (!mounted) return;
    final (hidden, customs) = await _readCategories();
    if (!mounted) return;
    final today = services.localDay.today;
    setState(() {
      _hidden = hidden;
      _customs = customs;
      _currency = currency;
      _goals = active;
      _goalId = goalId;
      _goalName = goal?.name;
      _today = today;
      _date = e?.date ?? today;
      if (e != null) {
        _amount.text = inputAmount(e.amountMinor, currency, _locale);
      }
    });
  }

  @override
  void dispose() {
    _sheetsOpen--;
    _services?.plus?.removeListener(_plusChanged);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  ParsedAmount? get _parsed {
    final currency = _currency;
    return currency == null ? null : parseAmount(_amount.text, currency);
  }

  /// The amount's error line: after Add for an empty or zero amount; at once
  /// for a pasted amount that can't be read, or one that's too large.
  String? _amountError(AppLocalizations l10n) {
    final problem = _parsed?.problem;
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
    if (parsed.problem != null || (spend && !_hasCategory)) {
      setState(() => _tried = true);
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    final services = context.services;
    final store = services.journal;
    final editing = widget.editing;
    try {
      if (editing == null) {
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
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'entry sheet',
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = true;
    });
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.deleteEntryTitle),
        content: Text(l10n.deleteEntryBody),
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
    if (picked != null && mounted) setState(() => _date = dateOnly(picked));
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
  List<_Tile> _tiles(AppLocalizations l10n) {
    final plus = context.services.plus;
    final picked = _category?.id ?? _custom;
    final byId = {for (final c in _customs) c.id: c};
    final number = {for (final (i, c) in _customs.indexed) c.id: i + 1};
    void pick(String id) => setState(() {
      _category = SpendCategory.fromId(id);
      _custom = _category == null ? id : null;
    });
    return [
      for (final id in offeredCategories(
        hidden: _hidden,
        customs: _customs,
        plus: plus?.active ?? false,
        keep: [?widget.editing?.categoryId, ?picked],
      ))
        _Tile(
          id: number.containsKey(id)
              ? 'add-cat-custom-${number[id]}'
              : 'add-cat-$id',
          label: categoryName(l10n, id, byId),
          icon: categoryIcon(id, byId),
          selected: id == picked,
          onTap: () => pick(id),
        ),
      if (plus != null)
        _Tile(
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
                              _AmountFormatter(minorDigitsOf(currency)),
                            ],
                            onChanged: (_) => setState(() {}),
                            // Typed text in ink, larger for the amount.
                            style: context.inputText?.copyWith(fontSize: 24),
                            decoration: InputDecoration(
                              labelText: l10n.addAmountLabel,
                              prefixText: '${_symbol(currency)} ',
                              errorText: amountError,
                              errorMaxLines: 3,
                            ),
                          ),
                        ),
                        // How the amount was read, whenever it can be.
                        if (amountError == null && parsed?.minor != null)
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
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (spend) ...[
                          Text(
                            l10n.addCategoryLabel,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          _CategoryGrid(tiles: _tiles(l10n)),
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
                      ],
                    ),
            ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.errGeneric,
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

/// One cell of the category grid: a category, or Add category ([selected]
/// null: an action, never picked).
class _Tile {
  const _Tile({
    required this.id,
    required this.label,
    required this.icon,
    this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool? selected;
  final VoidCallback onTap;
}

/// The tiles, three to a row (a short last row keeps the same cell width);
/// each row as tall as its tallest label (large text wraps, never cuts).
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    // One size for every label: each word whole in its cell (a third of the
    // row, less the gaps and padding), smaller only when it must.
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = wholeWordsScaler(
          context,
          texts: [for (final t in tiles) t.label],
          style: theme.textTheme.bodySmall,
          available: (box.maxWidth - 16) / 3 - 16,
        );
        Widget cell(_Tile t) {
          final on = t.selected ?? false;
          return TestId(
            t.id,
            button: true,
            selected: t.selected,
            child: Material(
              color: on
                  ? context.palette.pillBackground
                  : theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: on ? accent : theme.colorScheme.outlineVariant,
                  width: on ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: t.onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.icon, color: on ? accent : null),
                        const SizedBox(height: 4),
                        Text(
                          t.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                          textScaler: scaler,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            for (var row = 0; row < tiles.length; row += 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: row + i < tiles.length
                              ? cell(tiles[row + i])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Typing: digits and at most one decimal mark ("." or ","), with no more
/// decimals than the currency has. A paste (several characters at once) goes
/// in as it is, and the field says when it can't be read.
class _AmountFormatter extends TextInputFormatter {
  _AmountFormatter(int decimals)
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
