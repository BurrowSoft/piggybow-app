import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/button_label.dart';
import '../../core/clock.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../journal/journal_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/currency.dart';
import '../../money/money.dart';
import '../../repeat/repeat.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../theme/theme.dart';
import '../add/category_grid.dart';
import '../currency/currency_picker.dart';
import 'repeat_choice.dart';

/// Me → Money → Repeating entries: every running repeat, what it adds and
/// when; a tap opens its page. Stopped ones aren't listed.
class RepeatsScreen extends StatefulWidget {
  const RepeatsScreen({super.key});

  @override
  State<RepeatsScreen> createState() => _RepeatsScreenState();
}

class _RepeatsScreenState extends State<RepeatsScreen> {
  List<Repeat>? _repeats;

  /// Your own categories by id, for the names of repeats in them.
  Map<String, CustomCategory> _customs = const {};
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final services = _services = context.services;
      services.journal.addListener(_load);
      _load();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final journal = _services?.journal;
    if (journal == null) return;
    final all = await journal.repeats();
    final customs = await journal.customCategories();
    if (!mounted) return;
    setState(() {
      _repeats = [for (final r in all) if (r.running) r];
      _customs = {for (final c in customs) c.id: c};
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = context.session;
    final locale = session.device.localeName;
    final repeats = _repeats;
    return TestId.container(
      'me-repeats-screen',
      child: Scaffold(
        appBar: AppBar(title: AppBarTitle(l10n.meRepeats)),
        body: repeats == null
            ? const SizedBox.shrink()
            : repeats.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: TestId.container(
                  'me-repeats-empty',
                  child: Text(
                    l10n.meRepeatsNone,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final r in repeats)
                    TestId(
                      'repeat-row-${r.id}',
                      button: true,
                      child: ListTile(
                        title: Text(
                          repeatName(
                            l10n,
                            note: r.note,
                            categoryId: r.categoryId,
                            customs: _customs,
                          ),
                        ),
                        subtitle: Text(
                          [
                            formatMoney(r.amountMinor, r.currency, locale),
                            scheduleText(l10n, session.dateLocale, r.schedule),
                          ].join(' · '),
                        ),
                        onTap: () => context.push(MeRoutes.repeat(r.id)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A repeat's page: its amount, category (spends), note and schedule. Save
/// applies them from its next entry on (entries already added stay as they
/// are); "Stop repeating" ends it, and what it added stays.
class RepeatScreen extends StatefulWidget {
  const RepeatScreen({super.key, required this.repeatId});

  final String repeatId;

  @override
  State<RepeatScreen> createState() => _RepeatScreenState();
}

class _RepeatScreenState extends State<RepeatScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  /// Null until read; stays null for a repeat that's gone or stopped.
  Repeat? _repeat;

  /// A spend's category: a built-in's id, or your own's ("c:…").
  String? _categoryId;
  RepeatSchedule? _schedule;

  /// The built-ins hidden from the grid, and your own categories (oldest
  /// first): what it offers (offeredCategories), as in the Add sheet.
  Set<SpendCategory> _hidden = const {};
  List<CustomCategory> _customs = const [];
  AppServices? _services;
  String? _amountError;
  bool _busy = false;

  /// The last Save or Stop failed in the store.
  bool _failed = false;

  String get _locale => context.readSession.device.localeName;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _services?.plus?.removeListener(_plusChanged);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final r = await store.repeat(widget.repeatId);
    final hidden = await store.hiddenBuiltIns();
    final customs = await store.customCategories();
    if (!mounted || r == null || !r.running) return;
    setState(() {
      _repeat = r;
      _amount.text = inputAmount(r.amountMinor, r.currency, _locale);
      _note.text = r.note;
      _categoryId = r.categoryId;
      _schedule = r.schedule;
      _hidden = hidden;
      _customs = customs;
    });
  }

  /// The repeat's name: its note, else its category's, else "Save".
  String _name(AppLocalizations l10n, Repeat r) => repeatName(
    l10n,
    note: r.note,
    categoryId: r.categoryId,
    customs: {for (final c in _customs) c.id: c},
  );

  /// A new schedule: a day first, then how it repeats from that day.
  Future<void> _changeSchedule() async {
    final services = context.services;
    final dateLocale = context.readSession.dateLocale;
    final today = services.localDay.today;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: addDays(today, -366),
      lastDate: addDays(today, 366),
    );
    if (picked == null || !mounted) return;
    final day = dateOnly(picked);
    final current = _schedule;
    final choice = await showRepeatChoices(
      context,
      date: day,
      dateLocale: dateLocale,
      current: [
        for (final c in repeatChoicesFor(day))
          if (c != RepeatChoice.none && scheduleFor(c, day) == current) c,
      ].firstOrNull ?? RepeatChoice.none,
      withNone: false,
    );
    if (choice == null || !mounted) return;
    setState(() => _schedule = scheduleFor(choice, day));
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final r = _repeat;
    final schedule = _schedule;
    if (r == null || schedule == null || _busy) return;
    final parsed = parseAmount(_amount.text, r.currency);
    if (parsed.problem != null) {
      setState(
        () => _amountError = parsed.problem == AmountProblem.tooBig
            ? l10n.addAmountTooBig
            : l10n.addAmountError,
      );
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final picked = _categoryId;
      await context.services.journal.updateRepeat(
        r.copyWith(
          amountMinor: parsed.minor,
          category: SpendCategory.fromId(picked),
          customCategory: CustomCategory.isCustomId(picked) ? picked : null,
          note: _note.text,
          schedule: schedule,
        ),
      );
    } on Object catch (error, stack) {
      _storeFailed(error, stack);
      return;
    }
    if (mounted) context.pop();
  }

  Future<void> _stop() async {
    final l10n = AppLocalizations.of(context);
    final r = _repeat;
    if (r == null || _busy) return;
    final services = context.services;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        // Whole words, as the plan dialog's title: "repeating" at 320 dp and
        // 200 % text, smaller only if it must be.
        title: WholeWordsText(
          l10n.repeatStopTitle(_name(l10n, r)),
          style: Theme.of(dialog).textTheme.headlineSmall,
        ),
        content: Text(l10n.repeatStopBody),
        actions: [
          TestId(
            'repeat-stop-cancel',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: ButtonLabel(l10n.cancel),
            ),
          ),
          TestId(
            'repeat-stop-confirm',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: ButtonLabel(l10n.repeatStopConfirm),
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
      await services.journal.stopRepeat(
        r.id,
        today: services.localDay.todayWire,
      );
    } on Object catch (error, stack) {
      _storeFailed(error, stack);
      return;
    }
    if (mounted) context.pop();
  }

  /// The store refused or failed: the page stays usable and says so once,
  /// and the error is reported (crash reports scrub it).
  void _storeFailed(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'repeat page',
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = _repeat;
    final schedule = _schedule;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return TestId.container(
      'repeat-screen',
      child: Scaffold(
        appBar: AppBar(
          // One line, all of it: a repeat's name can be a long note.
          title: AppBarTitle(
            r == null ? l10n.meRepeats : _name(l10n, r),
          ),
        ),
        body: r == null || schedule == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  TestId(
                    'repeat-amount',
                    child: TextField(
                      controller: _amount,
                      // Keyboard learning off, as on every field (#75).
                      enableIMEPersonalizedLearning: false,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: minorDigitsOf(r.currency) > 0,
                      ),
                      onChanged: (_) => setState(() => _amountError = null),
                      style: context.inputText?.copyWith(fontSize: 24),
                      decoration: InputDecoration(
                        labelText: l10n.addAmountLabel,
                        prefixText: '${currencySymbolOf(r.currency, _locale)} ',
                        errorText: _amountError,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (r.type == EntryType.spent) ...[
                    Text(
                      l10n.addCategoryLabel,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    // As in the Add sheet: your own while Plus is on, and
                    // the repeat's own always, even hidden or after Plus
                    // ended.
                    CategoryGrid(
                      tiles: categoryTiles(
                        l10n,
                        ids: offeredCategories(
                          hidden: _hidden,
                          customs: _customs,
                          plus: _services?.plus?.active ?? false,
                          keep: [?r.categoryId, ?_categoryId],
                        ),
                        customs: _customs,
                        picked: _categoryId,
                        idPrefix: 'repeat-cat',
                        onPick: (id) => setState(() => _categoryId = id),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TestId(
                    'repeat-note',
                    child: TextField(
                      controller: _note,
                      // Keyboard learning off, as on every field (#75).
                      enableIMEPersonalizedLearning: false,
                      maxLength: maxNoteLength,
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      style: context.inputText,
                      decoration: InputDecoration(
                        labelText: l10n.addNoteLabel,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TestId(
                    'repeat-schedule',
                    button: true,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.repeat),
                      title: Text(l10n.addRepeat),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scheduleText(
                              l10n,
                              context.session.dateLocale,
                              schedule,
                            ),
                          ),
                          if (scheduleHint(l10n, schedule) case final hint?)
                            Text(hint, style: theme.textTheme.bodySmall),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changeSchedule,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TestId.container(
                    'repeat-changes',
                    child: Text(l10n.repeatChangesNote, style: muted),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.errGeneric,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TestId(
                    'repeat-save',
                    button: true,
                    child: FilledButton(
                      onPressed: _busy ? null : _save,
                      child: ButtonLabel(l10n.save),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TestId(
                    'repeat-stop',
                    button: true,
                    child: TextButton(
                      onPressed: _busy ? null : _stop,
                      child: ButtonLabel(l10n.repeatStop),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
