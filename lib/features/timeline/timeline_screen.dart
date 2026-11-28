import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/button_label.dart';
import '../../core/clock.dart';
import '../../core/day_label.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/category.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/money.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../add/add_again.dart';
import '../add/entry_sheet.dart';
import '../goal/take_out_sheet.dart';
import '../../core/fit_text.dart';
import '../shell/tab_top.dart';

/// Every spend and save, newest day first, under day headers with that
/// day's totals; All / Spent / Saved. A row opens its Edit sheet; a
/// long-press offers to add it again today.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

enum _Filter { all, spent, saved }

class _TimelineScreenState extends State<TimelineScreen>
    with ScrollsToTopOnTabTap {
  _Filter _filter = _Filter.all;
  List<Entry>? _entries;
  Map<String, Goal> _goals = const {};

  /// Your own categories by id (Plus): a spend in one shows its name and icon.
  Map<String, CustomCategory> _customs = const {};
  AppServices? _services;

  @override
  AppTab get tab => AppTab.timeline;

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
    final goals = <String, Goal>{};
    for (final id in {for (final e in entries) ?e.goalId}) {
      final g = await store.goal(id);
      if (g != null) goals[id] = g;
    }
    final customs = {for (final c in await store.customCategories()) c.id: c};
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _goals = goals;
      _customs = customs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = _entries;
    final shown = all == null
        ? null
        : [
            for (final e in all)
              if (_filter == _Filter.all ||
                  (_filter == _Filter.spent) == (e.type == EntryType.spent))
                e,
          ];
    return TestId.container(
      'timeline-screen',
      child: Scaffold(
        appBar: AppBar(title: AppBarTitle(l10n.tlTitle)),
        floatingActionButton: all == null || all.isEmpty
            ? null
            : TestId(
                'tl-add',
                button: true,
                child: FloatingActionButton(
                  // Its own tag: Home's Add button is alive in the shell too.
                  heroTag: 'tl-add',
                  tooltip: l10n.addSheetLabel,
                  onPressed: () => showEntrySheet(context),
                  child: const Icon(Icons.add),
                ),
              ),
        body: all == null
            ? const SizedBox.shrink()
            : all.isEmpty
            ? const _Empty()
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SegmentedButton<_Filter>(
                      showSelectedIcon: false,
                      segments: [
                        for (final (f, label) in [
                          (_Filter.all, l10n.tlAll),
                          (_Filter.spent, l10n.tlSpent),
                          (_Filter.saved, l10n.tlSaved),
                        ])
                          ButtonSegment(
                            value: f,
                            label: TestId(
                              'tl-filter-${f.name}',
                              button: true,
                              selected: _filter == f,
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
                      selected: {_filter},
                      onSelectionChanged: (s) =>
                          setState(() => _filter = s.first),
                    ),
                  ),
                  Expanded(
                    child: _Days(
                      entries: shown!,
                      goals: _goals,
                      customs: _customs,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The entries (newest day first) as one lazily built list: each day's
/// header, then its rows. Only what is on screen is built, even for a
/// thousand entries on one day.
class _Days extends StatelessWidget {
  const _Days({
    required this.entries,
    required this.goals,
    required this.customs,
  });

  final List<Entry> entries;
  final Map<String, Goal> goals;
  final Map<String, CustomCategory> customs;

  @override
  Widget build(BuildContext context) {
    final days = <String, List<Entry>>{};
    for (final e in entries) {
      (days[e.localDate] ??= []).add(e);
    }
    final items = <_Item>[
      for (final MapEntry(key: day, value: list) in days.entries) ...[
        _DayItem(parseWireDate(day)!, list),
        for (final e in list) _RowItem(e),
      ],
    ];
    final locale = context.session.device.localeName;
    return ListView.builder(
      primary: true,
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      itemBuilder: (context, i) => switch (items[i]) {
        _DayItem(:final date, :final entries) => _DayHeader(
          date: date,
          entries: entries,
        ),
        _RowItem(:final entry) => _Row(
          entry: entry,
          goal: goals[entry.goalId],
          customs: customs,
          locale: locale,
        ),
      },
    );
  }
}

/// One line of the Timeline's list: a day's header, or an entry.
sealed class _Item {
  const _Item();
}

class _DayItem extends _Item {
  const _DayItem(this.date, this.entries);

  final DateTime date;
  final List<Entry> entries;
}

class _RowItem extends _Item {
  const _RowItem(this.entry);

  final Entry entry;
}

/// Today, Yesterday or the date, with that day's totals.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.entries});

  final DateTime date;
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = context.session.device.localeName;
    final today = context.services.localDay.today;
    final label = dayLabel(
      l10n,
      context.session.dateLocale,
      date,
      today: today,
    );
    // The day's totals in integer minor units; only the ones that aren't 0.
    final currency = entries.first.currency;
    var spent = 0, saved = 0;
    // Money taken out of savings is in neither total (its row shows it).
    for (final e in entries) {
      if (e.type == EntryType.spent) {
        spent += e.amountMinor;
      } else if (e.type == EntryType.saved) {
        saved += e.amountMinor;
      }
    }
    final totals = [
      if (spent > 0) l10n.tlDaySpent(formatMoney(spent, currency, locale)),
      if (saved > 0) l10n.tlDaySaved(formatMoney(saved, currency, locale)),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Semantics(
            header: true,
            child: Text(label, style: theme.textTheme.titleSmall),
          ),
          Text(
            totals,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.goal,
    required this.customs,
    required this.locale,
  });

  final Entry entry;
  final Goal? goal;
  final Map<String, CustomCategory> customs;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = entry;
    final money = formatMoney(e.amountMinor, e.currency, locale);
    final String title;
    final String? subtitle;
    final Widget icon;
    final Widget amount;
    if (e.type == EntryType.spent) {
      // A built-in's name, or your own category's (Plus).
      final categoryId = e.categoryId!;
      final category = categoryName(l10n, categoryId, customs);
      final feeling = switch (e.feeling) {
        Feeling.worthIt => l10n.feelWorth,
        Feeling.notSure => l10n.feelNotSure,
        Feeling.notReally => l10n.feelNotReally,
        null => null,
      };
      title = e.note.isNotEmpty ? e.note : category;
      subtitle = [category, ?feeling].join(' · ');
      icon = Icon(
        categoryIcon(categoryId, customs),
        color: theme.colorScheme.onSurfaceVariant,
      );
      // Spends in ink: never red, never a minus sign.
      amount = Text(
        money,
        maxLines: 1,
        softWrap: false,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      );
    } else if (e.type == EntryType.withdraw) {
      final takenOut = goal == null
          ? l10n.goalTakenOutRow
          : l10n.tlTakenOutOf(goal!.name);
      title = e.note.isNotEmpty ? e.note : takenOut;
      subtitle = e.note.isNotEmpty ? takenOut : null;
      icon = const _MiniRainbow();
      // Taken out of savings: in ink, never red; a minus, as it goes down.
      amount = Text(
        '$minusSign$money',
        maxLines: 1,
        softWrap: false,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      );
    } else {
      final savedFor = goal == null
          ? l10n.tlSavedRow
          : l10n.tlSavedFor(goal!.name);
      title = e.note.isNotEmpty ? e.note : savedFor;
      subtitle = e.note.isNotEmpty ? savedFor : null;
      icon = const _MiniRainbow();
      amount = Text(
        '+$money',
        maxLines: 1,
        softWrap: false,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      );
    }
    final takenOutOf = e.type == EntryType.withdraw ? goal : null;
    return TestId(
      'tl-row-${e.id}',
      button: true,
      child: InkWell(
        // A withdrawal opens its own sheet (out of its goal).
        onTap: takenOutOf != null
            ? () => showTakeOutSheet(context, goal: takenOutOf, editing: e)
            : e.type == EntryType.withdraw
            ? null
            : () => showEntrySheet(context, editing: e),
        // Add again today (a save only while its goal is still active; a
        // spend in a category of your own only with Plus).
        onLongPress: canAddAgain(e, goal, plus: context.services.plus?.active ?? false)
            ? () => offerAddAgain(context, e)
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LayoutBuilder(
              builder: (context, box) {
                // At large text the amount gets its own line under the note,
                // so the note keeps room for whole words.
                final stacked =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                // One line; a very large amount gets smaller rather than
                // pushing the note out.
                final oneLine = FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: amount,
                );
                return Row(
                  children: [
                    SizedBox(width: 32, child: Center(child: icon)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // In ink: the theme's bodyLarge is muted.
                          Text(
                            title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (stacked)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: oneLine,
                            ),
                        ],
                      ),
                    ),
                    if (!stacked) ...[
                      const SizedBox(width: 12),
                      // At most half the row.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth / 2),
                        child: oneLine,
                      ),
                    ],
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

/// A save's icon: three small arcs (decorative).
class _MiniRainbow extends StatelessWidget {
  const _MiniRainbow();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: 24,
      height: 14,
      child: CustomPaint(painter: _MiniRainbowPainter()),
    ),
  );
}

class _MiniRainbowPainter extends CustomPainter {
  const _MiniRainbowPainter();

  static const _colours = [
    Color(0xFFE27D9A),
    Color(0xFFF2A07B),
    Color(0xFFF3C24F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height);
    for (final (i, c) in _colours.indexed) {
      final r = size.width / 2 - 1.5 - i * 3.5;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r),
        3.14159265,
        3.14159265,
        false,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniRainbowPainter oldDelegate) => false;
}

/// No entries yet: the pig (calm) and a way to add the first one.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: SvgPicture.asset('assets/pig/pig-calm.svg', height: 140),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.tlEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tlEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TestId(
              'tl-empty-add',
              button: true,
              child: FilledButton(
                onPressed: () => showEntrySheet(context),
                child: ButtonLabel(l10n.tlEmptyButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
