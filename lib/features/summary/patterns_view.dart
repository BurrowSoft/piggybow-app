import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/button_label.dart';
import '../../core/button_pair.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../summary/patterns.dart';
import '../../summary/summary.dart';
import '../plus/plus_screen.dart';

// Feature 20, Patterns (a Plus perk; specs/insights-plan.md): the card at
// the end of Summary and its own screen. With Plus, how spends felt over the
// last 8 weeks; without it, a plain teaser once there's enough to go on, with
// "See Plus" and "Hide" (for good). A build without Plus shows nothing.

/// One pattern in words, never a number.
String patternText(
  AppLocalizations l10n,
  FeelingPattern pattern, {
  required String dateLocale,
}) {
  String category(String id) => SpendCategory.fromId(id)?.label(l10n) ?? id;
  return switch (pattern.kind) {
    PatternKind.overallWorth => l10n.patternsOverallWorth,
    PatternKind.categoryWorth => l10n.patternsCategoryWorth(
      category(pattern.category!),
    ),
    PatternKind.categoryMixed => l10n.patternsCategoryMixed(
      category(pattern.category!),
    ),
    PatternKind.weekdayWorth => l10n.patternsWeekdayWorth(
      // 1–7 January 2024 is Monday to Sunday.
      DateFormat.EEEE(
        intlDateLocale(dateLocale),
      ).format(DateTime.utc(2024, 1, pattern.weekday!)),
    ),
  };
}

FeelingPatterns _patterns(BuildContext context, List<SummaryEntry> entries) {
  final l10n = AppLocalizations.of(context);
  return feelingPatterns(
    entries: entries,
    today: context.services.localDay.todayWire,
    categoryLabel: (id) => SpendCategory.fromId(id)?.label(l10n) ?? id,
  );
}

/// The end of Summary: the first pattern with Plus, the teaser without it.
class PatternsCard extends StatefulWidget {
  const PatternsCard({super.key, required this.entries});

  /// The whole journal, as Summary reads it.
  final List<SummaryEntry> entries;

  @override
  State<PatternsCard> createState() => _PatternsCardState();
}

class _PatternsCardState extends State<PatternsCard> {
  @override
  Widget build(BuildContext context) {
    final plus = context.services.plus;
    if (plus == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: plus,
      builder: (context, _) {
        final result = _patterns(context, widget.entries);
        if (plus.active) return _PlusCard(result: result);
        final prefs = context.session.prefs;
        if (result.state == PatternsState.notYet ||
            prefs.patternsTeaserHidden) {
          return const SizedBox.shrink();
        }
        return _Teaser(
          onHide: () async {
            await prefs.hidePatternsTeaser();
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.id, required this.children});

  final String id;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TestId.container(
      id,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

TextStyle? _muted(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
}

class _PlusCard extends StatelessWidget {
  const _PlusCard({required this.result});

  final FeelingPatterns result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final first = result.patterns.firstOrNull;
    return _Card(
      id: 'sum-patterns',
      children: [
        Text(l10n.sumPatterns, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        TestId(
          'sum-patterns-line',
          child: WholeWordsText(
            switch (result.state) {
              PatternsState.notYet => l10n.patternsNotYet,
              PatternsState.none => l10n.patternsNone,
              PatternsState.found => patternText(
                l10n,
                first!,
                dateLocale: context.session.dateLocale,
              ),
            },
            style: result.state == PatternsState.found
                ? theme.textTheme.bodyLarge
                : _muted(context),
          ),
        ),
        if (result.state == PatternsState.found)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TestId(
              'sum-patterns-see-all',
              button: true,
              child: TextButton(
                onPressed: () => context.push(SummaryRoutes.patterns),
                child: ButtonLabel(l10n.sumPatternsSeeAll),
              ),
            ),
          ),
      ],
    );
  }
}

/// Without Plus: what Patterns does, in general words. Never the person's own
/// patterns blurred, no lock, no count, no pop-up.
class _Teaser extends StatelessWidget {
  const _Teaser({this.onHide});

  /// Null on the Patterns screen: no "Hide" there.
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final see = TestId(
      'sum-patterns-see-plus',
      button: true,
      child: FilledButton.tonal(
        onPressed: () => requirePlus(context),
        child: ButtonLabel(l10n.patternsPlusSee),
      ),
    );
    final hide = onHide;
    return _Card(
      id: 'sum-patterns-teaser',
      children: [
        Text(l10n.patternsPlusTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        WholeWordsText(l10n.patternsPlusBody, style: _muted(context)),
        const SizedBox(height: 8),
        if (hide == null)
          Align(alignment: AlignmentDirectional.centerEnd, child: see)
        else
          ButtonPair(
            secondary: TestId(
              'sum-patterns-hide',
              button: true,
              child: TextButton(
                onPressed: hide,
                child: ButtonLabel(l10n.patternsPlusHide),
              ),
            ),
            primary: see,
          ),
      ],
    );
  }
}

/// Summary → Patterns: up to 3 patterns, the window, and what was read.
class PatternsScreen extends StatefulWidget {
  const PatternsScreen({super.key});

  @override
  State<PatternsScreen> createState() => _PatternsScreenState();
}

class _PatternsScreenState extends State<PatternsScreen> {
  List<SummaryEntry>? _entries;
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final services = _services = context.services;
      services.journal.addListener(_load);
      services.localDay.addListener(_load);
      _load();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    _services?.localDay.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await context.services.journal.entries();
    if (!mounted) return;
    setState(
      () => _entries = [
        // Notes are never read: SummaryEntry has none.
        for (final e in entries)
          SummaryEntry(
            type: e.type.id,
            amountMinor: e.amountMinor,
            category: e.category?.id,
            feeling: e.feeling?.id,
            localDate: e.localDate,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _entries;
    final plus = context.services.plus;
    return TestId.container(
      'patterns-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.sumPatterns)),
        body: entries == null
            ? const SizedBox.shrink()
            : ListenableBuilder(
                listenable: plus ?? const AlwaysStoppedAnimation(0),
                builder: (context, _) =>
                    _body(context, entries, plus?.active ?? false),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, List<SummaryEntry> entries, bool plus) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = _patterns(context, entries);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Plus ended while here: the teaser, never the patterns.
        if (!plus)
          const _Teaser()
        else ...[
          TestId(
            'patterns-window',
            child: Text(l10n.patternsWindow, style: _muted(context)),
          ),
          if (result.state == PatternsState.found)
            for (final (i, pattern) in result.patterns.indexed)
              _Card(
                id: 'patterns-line-$i',
                children: [
                  WholeWordsText(
                    patternText(
                      l10n,
                      pattern,
                      dateLocale: context.session.dateLocale,
                    ),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TestId(
                result.state == PatternsState.notYet
                    ? 'patterns-not-yet'
                    : 'patterns-none',
                child: WholeWordsText(
                  result.state == PatternsState.notYet
                      ? l10n.patternsNotYet
                      : l10n.patternsNone,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
          const SizedBox(height: 24),
          TestId(
            'patterns-privacy',
            child: WholeWordsText(
              l10n.patternsPrivacy,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
