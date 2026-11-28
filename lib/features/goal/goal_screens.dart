import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/button_label.dart';
import '../../core/day_label.dart';
import '../../core/fit_text.dart';
import '../../core/line_breaks.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../goal/goal_progress.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/money.dart';
import '../../pig/pig_mood.dart' show PigMood;
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../theme/theme.dart';
import '../add/entry_sheet.dart';
import '../pig/pig_view.dart';
import 'rainbow.dart';

/// Up to 40 characters, as people count them.
const goalNameMax = 40;

/// Create a goal, or edit one (plan §3.4): what for, the amount, what's
/// already saved. In onboarding it is O3 (plan §3.1), the optional first
/// goal: "Start my rainbow" saves it and "Maybe later" doesn't; both end
/// onboarding, and the router goes Home.
class GoalEditScreen extends StatefulWidget {
  const GoalEditScreen({super.key, this.goalId, this.onboarding = false});

  /// The goal to edit; null to create one.
  final String? goalId;

  /// Onboarding's O3 rather than the goal form.
  final bool onboarding;

  @override
  State<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends State<GoalEditScreen> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _start = TextEditingController();
  Goal? _goal;
  String? _currency;
  bool _tried = false;
  bool _busy = false;

  String get _locale => context.readSession.device.localeName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final currency = await store.currency() ?? 'USD';
    final id = widget.goalId;
    final goal = id == null ? null : await store.goal(id);
    if (!mounted) return;
    setState(() {
      _currency = currency;
      _goal = goal;
      if (goal != null) {
        _name.text = goal.name;
        _target.text = inputAmount(goal.targetMinor, currency, _locale);
        if (goal.startMinor > 0) {
          _start.text = inputAmount(goal.startMinor, currency, _locale);
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _start.dispose();
    super.dispose();
  }

  String? _nameError(AppLocalizations l10n) {
    final name = _name.text.trim();
    if (!_tried && name.isEmpty) return null;
    return name.isEmpty || name.characters.length > goalNameMax
        ? l10n.goalNameError
        : null;
  }

  String? _targetError(AppLocalizations l10n) {
    final problem = parseAmount(_target.text, _currency!).problem;
    return switch (problem) {
      null => null,
      AmountProblem.tooBig => l10n.addAmountTooBig,
      AmountProblem.invalid => l10n.goalAmountError,
      AmountProblem.empty ||
      AmountProblem.zero => _tried ? l10n.goalAmountError : null,
    };
  }

  String? _startError(AppLocalizations l10n) {
    if (_start.text.trim().isEmpty) return null;
    return switch (parseAmount(
      _start.text,
      _currency!,
      allowZero: true,
    ).problem) {
      null => null,
      AmountProblem.tooBig => l10n.addAmountTooBig,
      _ => l10n.addAmountError,
    };
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final currency = _currency;
    if (_busy || currency == null) return;
    setState(() => _tried = true);
    if (_nameError(l10n) != null ||
        _targetError(l10n) != null ||
        _startError(l10n) != null) {
      return;
    }
    final target = parseAmount(_target.text, currency).minor!;
    final start = _start.text.trim().isEmpty
        ? 0
        : parseAmount(_start.text, currency, allowZero: true).minor!;
    setState(() => _busy = true);
    final services = context.services;
    final now = services.clock.nowUtc();
    final old = _goal;
    final goal = old == null
        ? Goal(
            id: services.journal.newId(),
            name: _name.text.trim(),
            targetMinor: target,
            startMinor: start,
            createdAt: now,
            updatedAt: now,
          )
        : old.copyWith(
            name: _name.text.trim(),
            targetMinor: target,
            startMinor: start,
            updatedAt: now,
          );
    // A goal beside another active one only with Plus (decision 79); the
    // way here asked for it first (Home's New goal, requirePlus).
    await services.journal.putGoal(
      goal,
      allowAnother: services.plus?.active ?? false,
    );
    if (widget.onboarding) {
      await _finishOnboarding(services);
    } else if (mounted) {
      context.pop();
    }
  }

  /// O3's two buttons end onboarding: the journal's flag, then the router
  /// takes the person Home.
  Future<void> _finishOnboarding(AppServices services) async {
    await services.journal.setOnboarded();
    services.onboarded.value = true;
  }

  Future<void> _later() async {
    if (_busy) return;
    final services = context.services;
    setState(() => _busy = true);
    await _finishOnboarding(services);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currency = _currency;
    final editing = widget.goalId != null;
    final onboarding = widget.onboarding;
    final theme = Theme.of(context);
    return TestId.container(
      onboarding ? 'onb-goal' : 'goal-edit-screen',
      child: Scaffold(
        appBar: AppBar(title: onboarding ? null : Text(l10n.goalTitle)),
        body: currency == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (onboarding) ...[
                    Text(
                      l10n.onbGoalTitle,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.onbGoalBody, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 16),
                  ],
                  TestId(
                    'goal-name',
                    child: TextField(
                      controller: _name,
                      autofocus: !editing && !onboarding,
                      textCapitalization: TextCapitalization.sentences,
                      // Up to 3 lines, so a long name is seen whole, but one
                      // line of text: it shows in one-line places (decision
                      // 61). Enter is Done; a pasted break becomes a space.
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [LineBreaksAsSpaces()],
                      maxLength: goalNameMax,
                      style: context.inputText,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.goalNameLabel,
                        hintText: l10n.goalNameHint,
                        hintMaxLines: 2,
                        errorText: _nameError(l10n),
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TestId(
                    'goal-amount',
                    child: TextField(
                      controller: _target,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: context.inputText,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.goalAmountLabel,
                        errorText: _targetError(l10n),
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TestId(
                    'goal-start',
                    child: TextField(
                      controller: _start,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: context.inputText,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        // One line, whole: smaller only if it must.
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(l10n.goalStartLabel),
                        ),
                        errorText: _startError(l10n),
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TestId(
                    onboarding ? 'onb-goal-start' : 'goal-submit',
                    button: true,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: ButtonLabel(
                        onboarding
                            ? l10n.onbGoalStart
                            : editing
                            ? l10n.goalSave
                            : l10n.goalCreate,
                      ),
                    ),
                  ),
                  if (onboarding) ...[
                    const SizedBox(height: 8),
                    TestId(
                      'onb-goal-later',
                      button: true,
                      child: TextButton(
                        onPressed: _busy ? null : _later,
                        child: ButtonLabel(l10n.onbGoalLater),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// A goal (plan §3.4): the big rainbow, how far along, its saves (newest
/// first, tap to edit), Add savings, and Edit goal / End goal.
class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final String goalId;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  Goal? _goal;
  int _progress = 0;
  List<Entry> _saves = const [];
  String _currency = 'USD';
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_services = context.services).journal.addListener(_load);
      _load();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final goal = await store.goal(widget.goalId);
    final progress = goal == null ? 0 : await store.goalProgress(goal);
    final saves = await store.goalSaves(widget.goalId);
    final currency = await store.currency() ?? 'USD';
    if (!mounted) return;
    setState(() {
      _goal = goal;
      _progress = progress;
      _saves = saves;
      _currency = currency;
    });
  }

  Future<void> _end() async {
    final l10n = AppLocalizations.of(context);
    final goal = _goal!;
    final services = context.services;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.goalEndTitle),
        content: Text(l10n.goalEndBody),
        actions: [
          TestId(
            'goal-end-cancel',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: ButtonLabel(l10n.cancel),
            ),
          ),
          TestId(
            'goal-end-confirm',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: ButtonLabel(l10n.goalEndConfirm),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await services.journal.putGoal(
      goal.copyWith(
        status: GoalStatus.ended,
        updatedAt: services.clock.nowUtc(),
      ),
    );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goal = _goal;
    final locale = context.session.device.localeName;
    String money(int minor) => formatMoney(minor, _currency, locale);
    return TestId.container(
      'goal-screen',
      child: Scaffold(
        appBar: AppBar(
          title: Text(goal?.name ?? l10n.goalTitle),
          actions: [
            if (goal != null && goal.status == GoalStatus.active)
              TestId(
                'goal-menu',
                button: true,
                child: PopupMenuButton<String>(
                  onSelected: (choice) => choice == 'edit'
                      ? context.push(GoalRoutes.edit(goal.id))
                      : _end(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: TestId('goal-edit', child: Text(l10n.goalEdit)),
                    ),
                    PopupMenuItem(
                      value: 'end',
                      child: TestId('goal-end', child: Text(l10n.goalEnd)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        body: goal == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Builder(
                    builder: (context) {
                      final percent = goalPercent(
                        progressMinor: _progress,
                        targetMinor: goal.targetMinor,
                      );
                      return Rainbow(
                        percent: percent,
                        semanticLabel: l10n.goalRainbowLabel(
                          percent,
                          money(_progress),
                          money(goal.targetMinor),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  WholeWordsText(
                    l10n.goalCardProgress(
                      money(_progress),
                      money(goal.targetMinor),
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (!goalReached(
                    progressMinor: _progress,
                    targetMinor: goal.targetMinor,
                  ))
                    WholeWordsText(
                      l10n.goalToGo(money(goal.targetMinor - _progress)),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (goal.status == GoalStatus.active) ...[
                    const SizedBox(height: 16),
                    TestId(
                      'goal-add-savings',
                      button: true,
                      child: FilledButton.icon(
                        // This goal's own: with several, the sheet starts on it.
                        onPressed: () => showEntrySheet(
                          context,
                          start: EntryType.saved,
                          goalId: goal.id,
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.goalAddSavings),
                      ),
                    ),
                  ],
                  // No saves yet: no header over nothing (decision 57).
                  if (_saves.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.goalSavesHeader,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                  for (final e in _saves)
                    TestId(
                      'goal-save-${e.id}',
                      button: true,
                      child: InkWell(
                        onTap: () => showEntrySheet(context, editing: e),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: _SaveRow(
                              title: e.note.isNotEmpty
                                  ? e.note
                                  : l10n.tlSavedRow,
                              day: dayLabel(
                                l10n,
                                context.session.dateLocale,
                                e.date,
                                today: context.services.localDay.today,
                              ),
                              amount: '+${money(e.amountMinor)}',
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

/// One of a goal's saves: its note (or "Saved"), its day, and "+amount" in
/// the accent. At large text the amount goes on its own line under the day.
class _SaveRow extends StatelessWidget {
  const _SaveRow({
    required this.title,
    required this.day,
    required this.amount,
  });

  final String title;
  final String day;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final money = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: Text(
        amount,
        maxLines: 1,
        softWrap: false,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // In ink: the theme's bodyLarge is muted.
        Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          day,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (stacked)
          Align(alignment: AlignmentDirectional.centerEnd, child: money),
      ],
    );
    if (stacked) return text;
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          Expanded(child: text),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
            child: money,
          ),
        ],
      ),
    );
  }
}

/// The goal reached (plan §3.4): shown once, full screen.
class GoalDoneScreen extends StatefulWidget {
  const GoalDoneScreen({super.key, required this.goalId});

  final String goalId;

  @override
  State<GoalDoneScreen> createState() => _GoalDoneScreenState();
}

class _GoalDoneScreenState extends State<GoalDoneScreen> {
  Goal? _goal;
  String _currency = 'USD';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.services.journal;
      final goal = await store.goal(widget.goalId);
      final currency = await store.currency() ?? 'USD';
      if (!mounted) return;
      setState(() {
        _goal = goal;
        _currency = currency;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goal = _goal;
    final locale = context.session.device.localeName;
    return TestId.container(
      'goal-done-screen',
      child: Scaffold(
        body: SafeArea(
          child: goal == null
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Center(child: PigView(mood: PigMood.delighted)),
                    const SizedBox(height: 16),
                    const Rainbow(percent: 100),
                    const SizedBox(height: 24),
                    Text(
                      l10n.goalDoneTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    // The amount stays whole: smaller only if it must be.
                    WholeWordsText(
                      l10n.goalDoneBody(
                        goal.name,
                        formatMoney(goal.targetMinor, _currency, locale),
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TestId(
                      'goal-done-new',
                      button: true,
                      child: FilledButton(
                        onPressed: () =>
                            context.pushReplacement(GoalRoutes.create),
                        child: ButtonLabel(l10n.goalDoneNew),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TestId(
                      'goal-done-close',
                      button: true,
                      child: TextButton(
                        onPressed: () => context.pop(),
                        child: ButtonLabel(l10n.goalDoneClose),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
