import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/fit_text.dart';
import '../../core/plan_bar.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/locale.dart';
import '../../money/money.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../summary/summary.dart';
import '../shell/segmented.dart';
import '../shell/tab_top.dart';
import 'patterns_view.dart';

/// The Summary tab (plan §3.7, decisions 29 and 52): a week or a month at a
/// time, back as far as the oldest entry's period. Spent and saved, the plan
/// bar (the current week only), spending by category, and how the spends
/// felt. No comparison with another period: it would turn into a score.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

/// What Summary reads from the journal, in one go.
class _SummaryData {
  const _SummaryData({
    required this.entries,
    required this.currency,
    required this.planMinor,
    required this.customs,
  });

  final List<SummaryEntry> entries;
  final String currency;
  final int? planMinor;

  /// Your own categories by id (Plus): their spends show under their names.
  final Map<String, CustomCategory> customs;
}

class _SummaryScreenState extends State<SummaryScreen>
    with ScrollsToTopOnTabTap {
  _SummaryData? _data;
  AppServices? _services;
  PeriodKind _kind = PeriodKind.week;

  /// The period shown; null is the current one (it moves on with the day).
  Period? _shown;

  @override
  AppTab get tab => AppTab.summary;

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
    final store = context.services.journal;
    final entries = await store.entries();
    final data = _SummaryData(
      entries: [for (final e in entries) SummaryEntry.of(e)],
      currency: await store.currency() ?? 'USD',
      planMinor: await store.planMinor(),
      customs: {for (final c in await store.customCategories()) c.id: c},
    );
    if (!mounted) return;
    setState(() => _data = data);
  }

  Period _current(PeriodKind kind) =>
      periodContaining(kind, context.services.localDay.todayWire);

  /// Week ↔ Month: from the current period to the other kind's current one;
  /// from an earlier one, to the period holding its first day.
  void _switchKind(PeriodKind kind) {
    if (kind == _kind) return;
    final shown = _shown;
    final next = shown == null || shown == _current(_kind)
        ? null
        : periodContaining(kind, shown.start);
    setState(() {
      _kind = kind;
      _shown = next == _current(kind) ? null : next;
    });
  }

  void _shift(Period from, int by) {
    final next = periodShift(from, by);
    setState(() => _shown = next == _current(_kind) ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    return TestId.container(
      'summary-screen',
      child: Scaffold(
        appBar: AppBar(title: AppBarTitle(l10n.sumTitle)),
        body: data == null ? const SizedBox.shrink() : _body(context, data),
      ),
    );
  }

  Widget _body(BuildContext context, _SummaryData data) {
    final l10n = AppLocalizations.of(context);
    final today = context.services.localDay.todayWire;
    final current = _current(_kind);
    final shown = _shown;
    // A day change can't leave a period "after" today on screen.
    final period = shown == null || shown.start.compareTo(current.start) > 0
        ? current
        : shown;
    final s = summarize(
      period: period,
      today: today,
      entries: data.entries,
      planMinor: data.planMinor,
      locale: context.session.dateLocale,
      categoryLabel: (id) => categoryName(l10n, id, data.customs),
    );
    final week = _kind == PeriodKind.week;
    final locale = context.session.device.localeName;
    String money(int minor) => formatMoney(minor, data.currency, locale);
    final plan = data.planMinor;

    return ListView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        PiggybowSegmented<PeriodKind>(
          segments: [
            ('sum-week', l10n.sumWeek, PeriodKind.week),
            ('sum-month', l10n.sumMonth, PeriodKind.month),
          ],
          selected: _kind,
          onSelected: _switchKind,
        ),
        const SizedBox(height: 8),
        _PeriodRow(
          label: s.label,
          prevLabel: week ? l10n.sumPrevWeek : l10n.sumPrevMonth,
          nextLabel: week ? l10n.sumNextWeek : l10n.sumNextMonth,
          onPrev: s.hasPrev ? () => _shift(period, -1) : null,
          onNext: s.hasNext ? () => _shift(period, 1) : null,
        ),
        const SizedBox(height: 8),
        if (s.isEmpty)
          TestId.container(
            'sum-empty',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                week ? l10n.sumEmptyWeek : l10n.sumEmptyMonth,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else ...[
          _Totals(spent: money(s.spentMinor), saved: money(s.savedMinor)),
          if (s.planPercent != null && plan != null) ...[
            const SizedBox(height: 12),
            _PlanCard(amount: money(plan), percent: s.planPercent!),
          ],
          if (s.categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CategoryCard(
              rows: s.categories,
              label: (id) => categoryName(l10n, id, data.customs),
              money: money,
              percent: NumberFormat.percentPattern(intlNumberLocale(locale)),
            ),
          ],
          if (s.showWorth) ...[
            const SizedBox(height: 12),
            _WorthCard(
              line: l10n.sumWorthLine(s.worth, s.notSure, s.notReally),
            ),
          ],
        ],
        // Plus's Patterns (feature 20): the last 8 weeks, whatever period
        // is shown; the teaser without Plus; nothing in a build without it.
        PatternsCard(entries: data.entries, customs: data.customs),
      ],
    );
  }
}

/// The arrows and the period between them. An arrow at a bound is disabled,
/// never hidden, so the label stays put (decision 29).
class _PeriodRow extends StatelessWidget {
  const _PeriodRow({
    required this.label,
    required this.prevLabel,
    required this.nextLabel,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final String prevLabel;
  final String nextLabel;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w600);
    return Row(
      children: [
        TestId(
          'sum-prev',
          button: true,
          child: IconButton(
            tooltip: prevLabel,
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
          ),
        ),
        Expanded(
          child: TestId.container(
            'sum-period-label',
            child: WholeWordsText(
              label,
              style: style,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        TestId(
          'sum-next',
          button: true,
          child: IconButton(
            tooltip: nextLabel,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ),
      ],
    );
  }
}

/// An amount on one line, made smaller rather than broken.
class _Amount extends StatelessWidget {
  const _Amount(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, style: style, maxLines: 1, softWrap: false),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.id, required this.children});

  final String id;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => TestId.container(
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
  );
}

/// Spent and Saved side by side, or stacked full width when either total
/// would otherwise be shrunk below its size at 1× text to fit half the width
/// (a total near the maximum at large text, decision 58).
class _Totals extends StatelessWidget {
  const _Totals({required this.spent, required this.saved});

  final String spent;
  final String saved;

  static const _gap = 12.0;

  /// [_Section]'s padding, 16 dp a side.
  static const _padding = 32.0;

  /// Whether [amount] fits [width] at the person's text size, but no bigger
  /// than 1×: the size it is never shrunk below.
  static bool _fits(BuildContext context, String amount, double width) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(_TotalCard.amountStyle(Theme.of(context)));
    final painter = TextPainter(
      text: TextSpan(text: amount, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1),
      maxLines: 1,
    )..layout();
    final fits = painter.width <= width;
    painter.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spentCard = _TotalCard(
      id: 'sum-spent',
      title: l10n.sumSpent,
      amount: spent,
    );
    final savedCard = _TotalCard(
      id: 'sum-saved',
      title: l10n.sumSaved,
      amount: saved,
      accent: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - _gap) / 2 - _padding;
        if (_fits(context, spent, half) && _fits(context, saved, half)) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: spentCard),
                const SizedBox(width: _gap),
                Expanded(child: savedCard),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [spentCard, const SizedBox(height: _gap), savedCard],
        );
      },
    );
  }
}

/// Spent or Saved for the period. Saved is in the accent, as on Home.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.id,
    required this.title,
    required this.amount,
    this.accent = false,
  });

  final String id;
  final String title;
  final String amount;
  final bool accent;

  /// The total's style; [_Totals] measures with it (its colour aside).
  static TextStyle? amountStyle(ThemeData theme, {bool accent = false}) =>
      theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: accent ? theme.colorScheme.primary : theme.colorScheme.onSurface,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      id: id,
      children: [
        // Plain Text (one word): the row sizes both cards to the taller one,
        // and a LayoutBuilder-based text can't report its height ahead.
        Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        _Amount(amount, style: amountStyle(theme, accent: accent)),
      ],
    );
  }
}

/// The weekly plan and its bar (the current week, with a plan set).
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.amount, required this.percent});

  final String amount;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Section(
      id: 'sum-plan-bar',
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(l10n.sumPlan, style: theme.textTheme.titleSmall),
            _Amount(
              amount,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PlanBar(percent: percent),
      ],
    );
  }
}

/// Spending by category, largest first: each with its total and its whole
/// share of the period's spending; the bars are scaled to the largest.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.rows,
    required this.label,
    required this.money,
    required this.percent,
  });

  final List<CategoryRow> rows;
  final String Function(String id) label;
  final String Function(int minor) money;
  final NumberFormat percent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final largest = rows.first.amountMinor;
    return _Section(
      id: 'sum-by-category',
      children: [
        Text(l10n.sumByCategory, style: theme.textTheme.titleSmall),
        for (final row in rows) ...[
          const SizedBox(height: 10),
          TestId.container(
            'sum-cat-${row.id}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(label(row.id), style: theme.textTheme.bodyMedium),
                    _Amount(
                      // The floored whole percent, formatted for the locale;
                      // the double is for display only (decision 52).
                      l10n.sumCategoryShare(
                        money(row.amountMinor),
                        percent.format(row.percent / 100),
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // The bar's length only: no amount is ever read back from it.
                ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: largest == 0 ? 0 : row.amountMinor / largest,
                    color: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// How the period's spends felt (only when one of them has a feeling).
class _WorthCard extends StatelessWidget {
  const _WorthCard({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Section(
      id: 'sum-worth',
      children: [
        Text(l10n.sumWorthTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          line,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
