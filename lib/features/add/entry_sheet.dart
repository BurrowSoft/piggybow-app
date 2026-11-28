import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/button_label.dart';
import '../../core/clock.dart';
import '../../core/fit_text.dart';
import '../../core/line_breaks.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../journal/journal_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/currency.dart';
import '../../money/money.dart';
import '../../pig/pig_mood.dart' show PigReaction;
import '../../session/session_scope.dart';
import '../../theme/theme.dart';

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
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EntrySheet(start: start, editing: editing),
  );
  if (saved == true && editing == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.addedSnack)));
  }
  return saved == true;
}

/// A full-height sheet: Spent or Saved, the amount, a spend's category and
/// feeling (or a save's goal), a note and the day.
class EntrySheet extends StatefulWidget {
  const EntrySheet({super.key, this.start = EntryType.spent, this.editing});

  final EntryType start;
  final Entry? editing;

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late EntryType _type = widget.editing?.type ?? widget.start;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  SpendCategory? _category;
  Feeling? _feeling;

  /// Null until the journal's currency and today are read.
  String? _currency;
  DateTime? _date;
  DateTime? _today;
  String? _goalName;

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
    final e = widget.editing;
    if (e != null) {
      _category = e.category;
      _feeling = e.feeling;
      _note.text = e.note;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = context.services;
    final store = services.journal;
    final e = widget.editing;
    final currency = e?.currency ?? await store.currency() ?? 'USD';
    // A save shows where it goes: its own goal when it has one, else the
    // active goal (where a new save goes).
    final goalId = e?.goalId;
    final goal = goalId != null
        ? await store.goal(goalId)
        : await store.activeGoal();
    if (!mounted) return;
    final today = services.localDay.today;
    setState(() {
      _currency = currency;
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
    if (parsed.problem != null || (spend && _category == null)) {
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
          feeling: _feeling,
          note: _note.text,
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
            clearCategory: _category == null,
            feeling: _feeling,
            clearFeeling: _feeling == null,
            note: _note.text,
            localDate: wireDate(date),
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
                          _CategoryGrid(
                            selected: _category,
                            onPick: (c) => setState(() => _category = c),
                          ),
                          if (_tried && _category == null)
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

/// The nine categories, three to a row; each row as tall as its tallest
/// label (large text wraps, never cuts).
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.selected, required this.onPick});

  final SpendCategory? selected;
  final ValueChanged<SpendCategory> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    const all = SpendCategory.values;
    // One size for the nine labels: each word whole in its cell (a third of
    // the row, less the gaps and padding), smaller only when it must.
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = wholeWordsScaler(
          context,
          texts: [for (final c in all) c.label(l10n)],
          style: theme.textTheme.bodySmall,
          available: (box.maxWidth - 16) / 3 - 16,
        );
        return Column(
          children: [
            for (var row = 0; row < all.length; row += 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, c) in all.skip(row).take(3).indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: TestId(
                            'add-cat-${c.id}',
                            button: true,
                            selected: selected == c,
                            child: Material(
                              color: selected == c
                                  ? context.palette.pillBackground
                                  : theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: selected == c
                                      ? accent
                                      : theme.colorScheme.outlineVariant,
                                  width: selected == c ? 2 : 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onPick(c),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 72,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          c.icon,
                                          color: selected == c ? accent : null,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          c.label(l10n),
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
                          ),
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
