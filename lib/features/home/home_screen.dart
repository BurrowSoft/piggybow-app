import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/button_label.dart';
import '../../core/button_pair.dart';
import '../../core/clock.dart' show wireDate;
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
    required this.active,
    required this.progress,
    required this.picks,
    required this.plan,
    required this.offerAnswered,
    required this.currency,
    required this.unfeltYesterday,
  });

  final List<Entry> entries;

  /// Up to three of yesterday's spends with no feeling yet, for "How did
  /// yesterday feel?"; empty when Me switched it off or "Not now" hid it today.
  final List<Entry> unfeltYesterday;
  final List<Goal> goals;
  final Goal? active;
  final int progress;
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
    final localDay = context.services.localDay;
    final entries = await store.entries();
    final goals = await store.goals();
    final active = await store.activeGoal();
    // Yesterday on this phone (its own time zone): its spends with no feeling
    // yet, in the order they were added, three at most. Never a count of the
    // rest.
    final today = localDay.today;
    final yesterday = wireDate(DateTime(today.year, today.month, today.day - 1));
    final ask = await store.yesterdayFeelOn() &&
        await store.yesterdayFeelHiddenOn() != localDay.todayWire;
    final unfelt = ask
        ? ([
            for (final e in entries)
              if (e.type == EntryType.spent && e.localDate == yesterday && e.feeling == null) e,
          ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)))
            .take(3)
            .toList()
        : const <Entry>[];
    final data = _HomeData(
      entries: entries,
      goals: goals,
      active: active,
      progress: active == null ? 0 : await store.goalProgress(active),
      picks: await store.picks(),
      plan: await store.planMinor(),
      offerAnswered: await store.reminderOfferAnswered(),
      currency: await store.currency() ?? 'USD',
      unfeltYesterday: unfelt,
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
                  _GoalCard(data: data),
                  const SizedBox(height: 16),
                  _WeekCard(data: data),
                  if (data.unfeltYesterday.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _YesterdayCard(
                      spends: data.unfeltYesterday,
                      // As the edit sheet sets it; the pig doesn't react.
                      onAnswer: (spend, feeling) => context.services.journal
                          .updateEntry(spend.copyWith(feeling: feeling)),
                      onLater: () => context.services.journal
                          .hideYesterdayFeel(context.services.localDay.todayWire),
                    ),
                  ],
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

/// The active goal's rainbow and numbers; with none, a way to start one
/// (and the last goal's name if it was reached).
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.data});

  final _HomeData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final goal = data.active;
    if (goal == null) {
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
    final percent = goalPercent(
      progressMinor: data.progress,
      targetMinor: goal.targetMinor,
    );
    final saved = formatMoney(data.progress, data.currency, locale);
    final target = formatMoney(goal.targetMinor, data.currency, locale);
    return TestId(
      'goal-card',
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
      entries: [
        for (final e in data.entries)
          SummaryEntry(
            type: e.type.id,
            amountMinor: e.amountMinor,
            category: e.category?.id,
            feeling: e.feeling?.id,
            localDate: e.localDate,
          ),
      ],
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

/// How did yesterday feel? Up to three of yesterday's spends with no feeling
/// yet, each with the three feelings. An answer is that spend's feeling, as
/// the edit sheet sets it, and its row goes; the card goes with the last one.
/// "Not now" hides it until tomorrow. It never counts the rest, and never
/// mentions how anything felt.
class _YesterdayCard extends StatelessWidget {
  const _YesterdayCard({
    required this.spends,
    required this.onAnswer,
    required this.onLater,
  });

  final List<Entry> spends;
  final void Function(Entry spend, Feeling feeling) onAnswer;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    return TestId.container(
      'home-yesterday',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.yesterdayFeelTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // The cards' body style (decision 57).
              Text(
                l10n.yesterdayFeelBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final spend in spends) ...[
                const SizedBox(height: 16),
                TestId.container(
                  'home-yesterday-${spend.id}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) {
                          final title = Text(
                            spend.note.isNotEmpty ? spend.note : spend.category!.label(l10n),
                            style: theme.textTheme.bodyLarge,
                          );
                          // Spends in ink: never red, never a minus sign. One
                          // line; a very large amount gets smaller rather than
                          // pushing the title out.
                          final amount = FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              formatMoney(spend.amountMinor, spend.currency, locale),
                              maxLines: 1,
                              softWrap: false,
                              style: theme.textTheme.bodyLarge,
                            ),
                          );
                          // At large text the amount gets its own line under
                          // the title, as on Timeline, so the title keeps
                          // whole words.
                          if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                Align(alignment: AlignmentDirectional.centerEnd, child: amount),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 8),
                              // At most half the row.
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                                child: amount,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (feeling, label) in [
                            (Feeling.worthIt, l10n.feelWorth),
                            (Feeling.notSure, l10n.feelNotSure),
                            (Feeling.notReally, l10n.feelNotReally),
                          ])
                            TestId(
                              'home-yesterday-${spend.id}-${feeling.id}',
                              button: true,
                              child: ChoiceChip(
                                label: Text(label),
                                selected: false,
                                onSelected: (_) => onAnswer(spend, feeling),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TestId(
                  'home-yesterday-later',
                  button: true,
                  child: TextButton(
                    onPressed: onLater,
                    child: ButtonLabel(l10n.yesterdayFeelLater),
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
