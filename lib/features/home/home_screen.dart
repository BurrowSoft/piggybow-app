import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

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
import '../../pig/monthly_letter.dart';
import '../../pig/pig_mood.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../summary/noted_days.dart';
import '../../summary/summary.dart';
import '../../theme/theme.dart';
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
    required this.unfeltYesterday,
    required this.customs,
    required this.letter,
  });

  final List<Entry> entries;

  /// Your own categories by id, for their names (a built-in's is the app's).
  final Map<String, CustomCategory> customs;

  /// Up to three of yesterday's spends with no feeling yet, for "How did
  /// yesterday feel?"; empty when Me switched it off or "Not now" hid it today.
  final List<Entry> unfeltYesterday;
  final List<Goal> goals;

  /// The active goals, oldest first, and each one's progress by id.
  final List<Goal> actives;
  final Map<String, int> progress;
  final Set<HappyPick> picks;
  final int? plan;
  final bool offerAnswered;
  final String currency;

  /// The pig's letter about last month, in a month's first days; null when
  /// there's none to show.
  final MonthlyLetter? letter;
}

class _HomeScreenState extends State<HomeScreen> with ScrollsToTopOnTabTap {
  _HomeData? _data;
  AppServices? _services;

  /// "Another idea" picks, for the day they were picked on ([_readDay]): a
  /// new day starts on its own idea.
  int? _tip;
  String? _readDay;

  /// Home reads again at the next local turn (Clock.turnHours) and when the
  /// app comes back: what it shows depends on the phone's day and hour, not
  /// only on the journal.
  Timer? _turn;
  AppLifecycleListener? _lifecycle;

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
      _lifecycle = AppLifecycleListener(onResume: _load);
      _load();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    _services?.localDay.removeListener(_load);
    _services?.lastAdd.removeListener(_rebuild);
    _lifecycle?.dispose();
    _turn?.cancel();
    super.dispose();
  }

  /// One timer to the next turn of the day in the phone's zone, set again
  /// after every read.
  void _armTurn() {
    final services = _services;
    if (services == null || !mounted) return;
    _turn?.cancel();
    _turn = Timer(services.clock.untilNextTurn(services.localDay.zone), _load);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final store = context.services.journal;
    final localDay = context.services.localDay;
    final entries = await store.entries();
    final goals = await store.goals();
    final actives = await store.activeGoals();
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
    final currency = await store.currency() ?? 'USD';
    final data = _HomeData(
      entries: entries,
      goals: goals,
      actives: actives,
      progress: {for (final g in actives) g.id: await store.goalProgress(g)},
      picks: await store.picks(),
      plan: await store.planMinor(),
      offerAnswered: await store.reminderOfferAnswered(),
      currency: currency,
      unfeltYesterday: unfelt,
      customs: {for (final c in await store.customCategories()) c.id: c},
      letter: monthlyLetter(
        today: localDay.today,
        entries: entries,
        goals: goals,
        currency: currency,
        zone: localDay.zone,
        on: await store.lettersOn(),
        dismissed: await store.letterDismissed(),
      ),
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
    final day = localDay.todayWire;
    setState(() {
      _data = data;
      if (_readDay != day) _tip = null;
      _readDay = day;
    });
    _armTurn();
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
                  // Right under the pig's bubble: the pig hands it over.
                  if (data.letter case final letter?) ...[
                    const SizedBox(height: 16),
                    _LetterCard(
                      letter: letter,
                      currency: data.currency,
                      customs: data.customs,
                      onThanks: () =>
                          context.services.journal.dismissLetter(letter.key),
                    ),
                  ],
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
                  if (data.unfeltYesterday.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _YesterdayCard(
                      spends: data.unfeltYesterday,
                      customs: data.customs,
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
    final day = pigMood(
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
    // 22:00 to 05:59 on the phone's clock, in its zone: the sleepy pig.
    final lastAdd = services.lastAdd.value;
    final state = pigAtNight(
      day,
      night: isNight(services.clock.nowIn(services.localDay.zone).hour),
      lastAdd: lastAdd,
    );
    final key = pigBubbleKey(state, lastAdd);
    final name = context.session.pigName;
    return Column(
      children: [
        // Its own node, read before the line: "Your pig looks calm." (R2).
        Semantics(
          container: true,
          identifier: 'home-pig',
          label: pigA11yLabel(l10n, state.mood),
          child: PigView(mood: state.mood),
        ),
        // Its name, if it has one (feature 1): small and muted, above the
        // speech box.
        if (name != null) ...[
          const SizedBox(height: 4),
          TestId.container(
            'home-pig-name',
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.palette.mutedText),
            ),
          ),
        ],
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

/// This week (Monday to today): spent, saved, the plan bar, the spends that
/// felt worth it, and from 2 days on, how many days had an entry (feature 6).
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.data});

  final _HomeData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final today = context.services.localDay.todayWire;
    final period = periodContaining(PeriodKind.week, today);
    final week = summarize(
      period: period,
      today: today,
      entries: [for (final e in data.entries) SummaryEntry.of(e)],
      planMinor: data.plan,
      locale: context.session.dateLocale,
      categoryLabel: (id) => categoryName(l10n, id, data.customs),
    );
    String money(int minor) => formatMoney(minor, data.currency, locale);
    final ink = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final percent = week.planPercent;
    final noted = notedDays([for (final e in data.entries) e.localDate], period);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
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
                Text(l10n.weekPlan(money(data.plan!)), style: muted),
                const SizedBox(height: 6),
                PlanBar(percent: percent),
              ],
              if (week.worth > 0) ...[
                const SizedBox(height: 12),
                Text(l10n.weekWorth(week.worth), style: muted),
              ],
              if (noted >= notedDaysMin) ...[
                const SizedBox(height: 12),
                TestId(
                  'home-week-noted',
                  child: Text(l10n.weekNotedDays(noted), style: muted),
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
    required this.customs,
    required this.onAnswer,
    required this.onLater,
  });

  final List<Entry> spends;

  /// Your own categories by id: a spend in one is named as you typed it.
  final Map<String, CustomCategory> customs;
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
                            spend.note.isNotEmpty
                                ? spend.note
                                : categoryName(l10n, spend.categoryId ?? '', customs),
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

/// The pig's letter about last month, in a month's first days: the facts that
/// apply as bullets, warmest first, the days always last; "Thanks!" puts it
/// away for that month.
class _LetterCard extends StatelessWidget {
  const _LetterCard({
    required this.letter,
    required this.currency,
    required this.customs,
    required this.onThanks,
  });

  final MonthlyLetter letter;
  final String currency;

  /// Your own categories by id: the "worth it" one may be one of them.
  final Map<String, CustomCategory> customs;
  final VoidCallback onThanks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final month = DateFormat.MMMM(intlDateLocale(locale)).format(letter.month);
    final body = theme.textTheme.bodyMedium;
    final muted = body?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final goals = letter.goalsReached;
    final facts = <(String, String)>[
      if (goals.length == 1)
        ('home-letter-goals', l10n.letterGoal(goals.single))
      else if (goals.length > 1)
        ('home-letter-goals', l10n.letterGoals(goals.length)),
      if (letter.savedMinor > 0)
        ('home-letter-saved', l10n.letterSaved(formatMoney(letter.savedMinor, currency, locale))),
      if (letter.worthCategoryId case final id?)
        ('home-letter-worth', l10n.letterWorth(categoryName(l10n, id, customs))),
      ('home-letter-days', l10n.letterDays(letter.days)),
    ];
    return TestId.container(
      'home-letter',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.letterTitle(month), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              // The cards' body style (decision 57).
              Text(l10n.letterHello(month), style: muted),
              const SizedBox(height: 4),
              for (final (id, fact) in facts)
                TestId.container(
                  id,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(child: Text('•', style: body)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(fact, style: body)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(l10n.letterBye, style: muted),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TestId(
                  'home-letter-thanks',
                  button: true,
                  child: TextButton(
                    onPressed: onThanks,
                    child: ButtonLabel(l10n.letterThanks),
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
