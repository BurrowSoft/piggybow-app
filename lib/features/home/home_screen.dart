import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/button_label.dart';
import '../../core/button_pair.dart';
import '../../core/fit_text.dart';
import '../../core/plan_bar.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../data/models.dart' show ReminderTime;
import '../../goal/goal_progress.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/money.dart';
import '../../pig/pig_mood.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../summary/summary.dart';
import '../../tips/tips.dart';
import '../add/entry_sheet.dart';
import '../goal/rainbow.dart';
import '../pig/pig_view.dart';
import '../plus/plus_screen.dart';
import '../shell/tab_top.dart';

/// Home (plan §3.2): the pig and its line, the reminder offer after the first
/// entry, the goal card, this week, today's idea, and Add.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// What Home shows, read from the journal in one go.
class _HomeData {
  const _HomeData({
    required this.entries,
    required this.goals,
    required this.actives,
    required this.progress,
    required this.picks,
    required this.plan,
    required this.offerAnswered,
    required this.currency,
  });

  final List<Entry> entries;
  final List<Goal> goals;

  /// The active goals, oldest first, and each one's progress by id.
  final List<Goal> actives;
  final Map<String, int> progress;
  final Set<HappyPick> picks;
  final int? plan;
  final bool offerAnswered;
  final String currency;
}

class _HomeScreenState extends State<HomeScreen> with ScrollsToTopOnTabTap {
  _HomeData? _data;
  AppServices? _services;
  int? _tip;

  @override
  AppTab get tab => AppTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final services = _services = context.services;
      services.journal.addListener(_load);
      services.localDay.addListener(_load);
      services.lastAdd.addListener(_rebuild);
      _load();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    _services?.localDay.removeListener(_load);
    _services?.lastAdd.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final entries = await store.entries();
    final goals = await store.goals();
    final actives = await store.activeGoals();
    final data = _HomeData(
      entries: entries,
      goals: goals,
      actives: actives,
      progress: {for (final g in actives) g.id: await store.goalProgress(g)},
      picks: await store.picks(),
      plan: await store.planMinor(),
      offerAnswered: await store.reminderOfferAnswered(),
      currency: await store.currency() ?? 'USD',
    );
    // A goal just reached is celebrated once (plan §3.4); an ended goal
    // never is.
    for (final g in goals) {
      if (g.status == GoalStatus.reached &&
          g.reachedAt != null &&
          !await store.celebrated(g.id)) {
        await store.markCelebrated(g.id);
        if (mounted) unawaited(context.push(GoalRoutes.done(g.id)));
        break;
      }
    }
    if (!mounted) return;
    setState(() => _data = data);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    return TestId.container(
      'home-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.tabHome)),
        floatingActionButton: TestId(
          'home-add',
          button: true,
          child: FloatingActionButton.extended(
            // Timeline has an Add button too, and the shell keeps both tabs
            // alive: one tag each, or a route over the shell finds two heroes.
            heroTag: 'home-add',
            onPressed: () => showEntrySheet(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.homeAdd),
          ),
        ),
        body: data == null
            ? const SizedBox.shrink()
            : ListView(
                primary: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  _Pig(data: data),
                  if (data.entries.isNotEmpty &&
                      !data.offerAnswered &&
                      context.session.accountState?.reminderOn != true) ...[
                    const SizedBox(height: 16),
                    const _ReminderOffer(),
                  ],
                  const SizedBox(height: 16),
                  if (data.actives.isEmpty)
                    _NoGoalCard(data: data)
                  else ...[
                    for (final (i, g) in data.actives.indexed) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _GoalCard(
                        id: i == 0 ? 'goal-card' : 'goal-card-${i + 1}',
                        goal: g,
                        progress: data.progress[g.id] ?? 0,
                        currency: data.currency,
                      ),
                    ],
                    // Builds with Plus only; without it, the paywall first.
                    if (context.services.plus != null) ...[
                      const SizedBox(height: 8),
                      const _NewGoal(),
                    ],
                  ],
                  const SizedBox(height: 16),
                  _WeekCard(data: data),
                  const SizedBox(height: 16),
                  _IdeaCard(
                    tip: _tip ?? tipForDay(context.services.localDay.today),
                    onAnother: () => setState(
                      () => _tip = nextTip(
                        _tip ?? tipForDay(context.services.localDay.today),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The pig, its mood from the week (plan §4.2) and its line: the reaction
/// to what was just added, if any (§4.4).
class _Pig extends StatelessWidget {
  const _Pig({required this.data});

  final _HomeData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = context.services;
    final state = pigMood(
      picks: data.picks,
      planMinor: data.plan,
      entries: [
        for (final e in data.entries)
          MoodEntry(
            type: e.type.id,
            amountMinor: e.amountMinor,
            feeling: e.feeling?.id,
            localDate: e.localDate,
            createdAt: e.createdAt,
          ),
      ],
      // Every goal's stamps, ended ones too (the contract's rule 1, decision
      // 53): a band or reach from the last 24 h keeps its line after End.
      goals: [
        for (final g in data.goals)
          GoalMarks(
            name: g.name,
            bandReachedAt: g.bandReachedAt,
            reachedAt: g.reachedAt,
          ),
      ],
      now: services.clock.nowUtc(),
      today: services.localDay.todayWire,
    );
    final key = pigBubbleKey(state, services.lastAdd.value);
    return Column(
      children: [
        // Its own node, read before the line: "Your pig looks calm." (R2).
        Semantics(
          container: true,
          identifier: 'home-pig',
          label: pigA11yLabel(l10n, state.mood),
          child: PigView(mood: state.mood),
        ),
        const SizedBox(height: 8),
        TestId.container(
          'home-pig-line',
          child: Semantics(
            liveRegion: true,
            child: PigBubble(text: pigLineText(l10n, key, state.args)),
          ),
        ),
      ],
    );
  }
}

/// Once, after the first entry, until answered (plan §3.2).
class _ReminderOffer extends StatelessWidget {
  const _ReminderOffer();

  static const time = ReminderTime(20, 0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final at = MaterialLocalizations.of(context)
        .formatTimeOfDay(const TimeOfDay(hour: 20, minute: 0));
    Future<void> answer({required bool yes}) async {
      final services = context.services;
      final session = context.readSession;
      if (yes) {
        await session.updateReminder(on: true, time: time);
        await services.notifications.request();
      }
      await services.journal.answerReminderOffer();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.reminderOfferTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.reminderOfferBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // One line when both fit; else full width, the yes on top
            // (decision 57).
            ButtonPair(
              secondary: TestId(
                'home-reminder-no',
                button: true,
                child: TextButton(
                  onPressed: () => answer(yes: false),
                  child: ButtonLabel(l10n.reminderOfferNo),
                ),
              ),
              primary: TestId(
                'home-reminder-yes',
                button: true,
                child: FilledButton(
                  onPressed: () => answer(yes: true),
                  child: ButtonLabel(l10n.reminderOfferYes(at)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// With no active goal: a way to start one (and the last goal's name if it
/// was reached).
class _NoGoalCard extends StatelessWidget {
  const _NoGoalCard({required this.data});

  final _HomeData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final last = data.goals.firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.goalCardEmptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.goalCardEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TestId(
              'goal-create',
              button: true,
              child: FilledButton.tonal(
                onPressed: () => context.push(GoalRoutes.create),
                child: ButtonLabel(l10n.goalCardEmptyButton),
              ),
            ),
            // Under the button (decision 57).
            if (last != null && last.status == GoalStatus.reached) ...[
              const SizedBox(height: 8),
              // Opens the reached goal's read-only detail (R1).
              TestId(
                'goal-card-reached',
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push(GoalRoutes.detail(last.id)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.goalCardReached(last.name),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Home's New goal, under the last goal card, in builds with Plus: a goal
/// beside the ones there needs Plus (decision 79), so without it the
/// paywall opens first.
class _NewGoal extends StatelessWidget {
  const _NewGoal();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TestId(
      'home-new-goal',
      button: true,
      child: FilledButton.tonalIcon(
        onPressed: () async {
          if (!await requirePlus(context)) return;
          if (context.mounted) unawaited(context.push(GoalRoutes.create));
        },
        icon: const Icon(Icons.add),
        label: ButtonLabel(l10n.homeNewGoal),
      ),
    );
  }
}

/// One active goal's rainbow and numbers; a tap opens it. With Plus there
/// can be several, oldest first (decision 79).
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.id,
    required this.goal,
    required this.progress,
    required this.currency,
  });

  /// The card's test id: goal-card for the first, then goal-card-2 and on.
  final String id;
  final Goal goal;
  final int progress;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final percent = goalPercent(
      progressMinor: progress,
      targetMinor: goal.targetMinor,
    );
    final saved = formatMoney(progress, currency, locale);
    final target = formatMoney(goal.targetMinor, currency, locale);
    return TestId(
      id,
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(GoalRoutes.detail(goal.id)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Builder(
              builder: (context) {
                final numbers = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    WholeWordsText(
                      l10n.goalCardProgress(saved, target),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      l10n.goalCardPercent(percent),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
                // At large text the rainbow goes above the numbers, so the
                // amounts get the card's whole width.
                if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 160,
                          child: Rainbow(percent: percent),
                        ),
                      ),
                      const SizedBox(height: 12),
                      numbers,
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 96, child: Rainbow(percent: percent)),
                    const SizedBox(width: 16),
                    Expanded(child: numbers),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// This week (Monday to today): spent, saved, the plan bar, and the spends
/// that felt worth it.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.data});

  final _HomeData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final today = context.services.localDay.todayWire;
    final week = summarize(
      period: periodContaining(PeriodKind.week, today),
      today: today,
      entries: [for (final e in data.entries) SummaryEntry.of(e)],
      planMinor: data.plan,
      locale: context.session.dateLocale,
      categoryLabel: (id) => SpendCategory.fromId(id)?.label(l10n) ?? id,
    );
    String money(int minor) => formatMoney(minor, data.currency, locale);
    final ink = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final percent = week.planPercent;
    return TestId.container(
      'home-week',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.weekTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(l10n.weekSpent(money(week.spentMinor)), style: ink),
                  Text(l10n.weekSaved(money(week.savedMinor)), style: ink),
                ],
              ),
              if (percent != null && data.plan != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.weekPlan(money(data.plan!)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                PlanBar(percent: percent),
              ],
              if (week.worth > 0) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.weekWorth(week.worth),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's idea (plan §4.5): one a day; "Another idea" steps to the next.
class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.tip, required this.onAnother});

  final int tip;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return TestId.container(
      'home-idea',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.ideaTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // The cards' body style (decision 57).
              Text(
                tipText(l10n, tip),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TestId(
                  'home-idea-another',
                  button: true,
                  child: TextButton(
                    onPressed: onAnother,
                    child: ButtonLabel(l10n.ideaAnother),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
