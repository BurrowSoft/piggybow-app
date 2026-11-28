import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/button_label.dart';
import '../../core/line_breaks.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../journal/journal_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/currency.dart';
import '../../money/money.dart';
import '../../session/session_scope.dart';
import '../../theme/theme.dart';
import '../add/entry_sheet.dart' show AmountInputFormatter;

/// Opens the take-out sheet for [goal] (feature 5): money taken out of its
/// savings, at most what it has; or [editing] one taken out before (with
/// Delete). True when something was saved or deleted; after a new one,
/// "Taken out. It's still your money." shows on the caller's own Scaffold.
Future<bool> showTakeOutSheet(
  BuildContext context, {
  required Goal goal,
  Entry? editing,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TakeOutSheet(goal: goal, editing: editing),
  );
  if (saved == true && editing == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.takeOutDone)));
  }
  return saved == true;
}

/// "Take out of {goal}": the amount and a note. It's dated today; an edit
/// keeps its day. The pig says nothing about it.
class TakeOutSheet extends StatefulWidget {
  const TakeOutSheet({super.key, required this.goal, this.editing});

  final Goal goal;

  /// A withdrawal of [goal]'s to edit; null for a new one.
  final Entry? editing;

  @override
  State<TakeOutSheet> createState() => _TakeOutSheetState();
}

class _TakeOutSheetState extends State<TakeOutSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  /// Null until read: the journal's currency, and what the goal has (an
  /// edited withdrawal's own amount counted back).
  String? _currency;
  int? _limit;

  /// Save was pressed: an empty amount now says so.
  bool _tried = false;
  bool _busy = false;

  /// The last Save or Delete failed in the store.
  bool _failed = false;

  bool get _editing => widget.editing != null;

  String get _locale => context.readSession.device.localeName;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) _note.text = e.note;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final e = widget.editing;
    final currency = e?.currency ?? await store.currency() ?? 'USD';
    final limit = await store.takeOutLimit(
      widget.goal.id,
      countedBack: e?.amountMinor ?? 0,
    );
    if (!mounted) return;
    setState(() {
      _currency = currency;
      _limit = limit;
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

  /// The amount's error line: after Save for an empty or zero amount; at
  /// once for one that can't be read, is too large, or is more than the
  /// goal has.
  String? _amountError(AppLocalizations l10n) {
    final parsed = _parsed;
    final limit = _limit;
    final minor = parsed?.minor;
    if (minor != null && limit != null && minor > limit) {
      return l10n.takeOutTooMuch;
    }
    return switch (parsed?.problem) {
      null => null,
      AmountProblem.tooBig => l10n.addAmountTooBig,
      AmountProblem.invalid => l10n.addAmountError,
      AmountProblem.empty ||
      AmountProblem.zero => _tried ? l10n.addAmountError : null,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final currency = _currency;
    final parsed = _parsed;
    if (_busy || currency == null || parsed == null) return;
    setState(() => _tried = true);
    if (parsed.problem != null || _amountError(l10n) != null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final services = context.services;
    final store = services.journal;
    final editing = widget.editing;
    try {
      if (editing == null) {
        await store.takeOut(
          goalId: widget.goal.id,
          amountMinor: parsed.minor!,
          currency: currency,
          localDate: services.localDay.todayWire,
          note: _note.text,
        );
      } else {
        await store.updateEntry(
          editing.copyWith(amountMinor: parsed.minor!, note: _note.text),
        );
      }
    } on Object catch (error, stack) {
      _storeFailed(error, stack);
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
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
            'takeout-delete-cancel',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: ButtonLabel(l10n.cancel),
            ),
          ),
          TestId(
            'takeout-delete-confirm',
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

  /// The store refused or failed: the sheet stays usable and says so once.
  void _storeFailed(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'take out'),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = true;
    });
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
    final parsed = _parsed;
    final amountError = _amountError(l10n);
    return Material(
      color: theme.colorScheme.surface,
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
                    'takeout-back',
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
                        l10n.takeOutTitle(widget.goal.name),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: currency == null || _limit == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        TestId(
                          'takeout-amount',
                          child: TextField(
                            controller: _amount,
                            // Keyboard learning off, as on every field (#75).
                            enableIMEPersonalizedLearning: false,
                            autofocus: !_editing,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: minorDigitsOf(currency) > 0,
                            ),
                            inputFormatters: [
                              AmountInputFormatter(minorDigitsOf(currency)),
                            ],
                            onChanged: (_) => setState(() {}),
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
                              'takeout-amount-preview',
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
                        TestId(
                          'takeout-note',
                          child: TextField(
                            controller: _note,
                            // Keyboard learning off, as on every field (#75).
                            enableIMEPersonalizedLearning: false,
                            maxLength: maxNoteLength,
                            minLines: 1,
                            maxLines: 3,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.done,
                            inputFormatters: const [LineBreaksAsSpaces()],
                            textCapitalization: TextCapitalization.sentences,
                            style: context.inputText,
                            decoration: InputDecoration(
                              labelText: l10n.addNoteLabel,
                              errorMaxLines: 3,
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
                // Side by side when they fit; stacked, Save on top, when
                // they don't (large text).
                child: _editing
                    ? OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        overflowAlignment: OverflowBarAlignment.end,
                        overflowDirection: VerticalDirection.up,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TestId(
                            'takeout-delete',
                            button: true,
                            child: TextButton(
                              onPressed: _busy ? null : _delete,
                              child: ButtonLabel(l10n.editDelete),
                            ),
                          ),
                          TestId(
                            'takeout-save',
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
                          'takeout-save',
                          button: true,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: ButtonLabel(l10n.save),
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
