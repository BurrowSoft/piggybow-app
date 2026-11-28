import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_dates.dart';
import '../../core/clock.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/goal.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../router.dart';
import '../../session/session_scope.dart';

/// Me → Reached goals: every goal reached, the latest first, each with the
/// day it was reached; a tap opens its read-only detail. For everyone, in
/// every build (the person's own goals; decision 79). Me shows the way here
/// once a first goal is reached.
class ReachedGoalsScreen extends StatefulWidget {
  const ReachedGoalsScreen({super.key});

  @override
  State<ReachedGoalsScreen> createState() => _ReachedGoalsScreenState();
}

class _ReachedGoalsScreenState extends State<ReachedGoalsScreen> {
  List<Goal>? _goals;
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
    final services = _services;
    if (services == null) return;
    final goals = await services.journal.reachedGoals();
    if (mounted) setState(() => _goals = goals);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goals = _goals;
    return TestId.container(
      'reached-goals-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.reachedGoalsTitle)),
        body: goals == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final (i, g) in goals.indexed)
                    TestId(
                      'reached-goal-${i + 1}',
                      button: true,
                      child: ListTile(
                        title: Text(g.name),
                        subtitle: Text(l10n.reachedGoalOn(_day(context, g))),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () => context.push(MeRoutes.reachedGoal(g.id)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// The day the goal was reached, on this phone's calendar: "Wed, Sep 30",
  /// with the year when it isn't this year's.
  String _day(BuildContext context, Goal g) {
    final services = context.services;
    final dateLocale = context.session.dateLocale;
    final day = Clock.localDateOf(g.reachedAt ?? g.updatedAt, services.localDay.zone);
    return day.year == services.localDay.today.year
        ? AppDates.dayShort(dateLocale, day)
        : AppDates.dayShortWithYear(dateLocale, day);
  }
}
