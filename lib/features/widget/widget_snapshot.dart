// The home-screen widget's snapshot (feature 16): everything the widget
// draws, ready-made by the app, since the widget never reads the journal.
// Its shape is pinned by test/contracts/widget_snapshot.json, which the
// widget's own (Android) tests read too.
//
// What it may hold is the privacy rule: without Plus, or with the app lock
// on, it holds nothing from the journal at all (no amount, no goal name),
// just the state and its one line.

import '../../goal/goal_progress.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../money/money.dart';

/// The snapshot's shape; the widget ignores one it doesn't know.
const widgetSnapshotVersion = 1;

/// The theme the widget uses when no other applies (themes are Plus).
const widgetDefaultTheme = 'default';

/// What the widget shows: the journal ([ready]), the lock's face
/// ([locked]), or what Plus would bring ([plus]).
enum WidgetState { ready, locked, plus }

/// The snapshot for the widget, as JSON-ready values.
///
/// - Without Plus ([plusActive] false): "Part of Plus", in the default
///   theme. This comes first: it shows nothing from the journal either.
/// - With the app lock on ([lockOn]): "Tap to open".
/// - Otherwise today's spending on [today] (spends only, in the journal's
///   [currency]), and [goal]'s bands and numbers ([goalProgressMinor] is its
///   progress, start included).
///
/// "Spent today" is the sum of today's spends; with entries today but no
/// spend, it's 0; with no entry today, it's null (the widget says nothing
/// was noted). [locale] formats the amounts, as everywhere in the app.
Map<String, Object?> widgetSnapshot({
  required AppLocalizations l10n,
  required String locale,
  required String theme,
  required bool plusActive,
  required bool lockOn,
  required String today,
  required String? currency,
  required Iterable<Entry> entries,
  required Goal? goal,
  required int goalProgressMinor,
}) {
  final private = privateWidgetSnapshot(
    l10n: l10n,
    theme: theme,
    plusActive: plusActive,
    lockOn: lockOn,
  );
  if (private != null) return private;
  String money(int minor) => formatMoney(minor, currency!, locale);
  var noted = false;
  var spent = 0;
  for (final e in entries) {
    if (e.localDate != today) continue;
    noted = true;
    // At its home amount: a spend in another currency, converted (#74).
    if (e.type == EntryType.spent) spent += e.homeMinor;
  }
  return {
    'version': widgetSnapshotVersion,
    'state': WidgetState.ready.name,
    'theme': theme,
    'day': today,
    'text': {
      'spentToday': l10n.widgetSpentToday,
      'nothingToday': l10n.widgetNothingToday,
      'noGoal': l10n.widgetNoGoal,
    },
    'spentToday': noted && currency != null ? money(spent) : null,
    'goal': goal == null || currency == null
        ? null
        : _goal(l10n, goal, goalProgressMinor, money),
  };
}

/// The snapshot without Plus, or with the app lock on: one line and the
/// theme, nothing from the journal. Null when neither applies (the journal's
/// snapshot then). It needs no journal, so it's decided first: a journal
/// that can't be read never holds it back.
Map<String, Object?>? privateWidgetSnapshot({
  required AppLocalizations l10n,
  required String theme,
  required bool plusActive,
  required bool lockOn,
}) {
  if (!plusActive) {
    return {
      'version': widgetSnapshotVersion,
      'state': WidgetState.plus.name,
      'theme': widgetDefaultTheme,
      'text': {'plus': l10n.widgetPlus},
    };
  }
  if (lockOn) {
    return {
      'version': widgetSnapshotVersion,
      'state': WidgetState.locked.name,
      'theme': theme,
      'text': {'locked': l10n.widgetLocked},
    };
  }
  return null;
}

Map<String, Object?> _goal(
  AppLocalizations l10n,
  Goal goal,
  int progressMinor,
  String Function(int minor) money,
) {
  final bands = goalBands(
    progressMinor: progressMinor,
    targetMinor: goal.targetMinor,
  );
  final saved = money(progressMinor);
  final target = money(goal.targetMinor);
  return {
    'name': goal.name,
    'progress': l10n.goalCardProgress(saved, target),
    // Band i is lit once it's reached, as on Home.
    'bands': [for (var i = 0; i < goalBandCount; i++) i < bands],
    'label': l10n.goalRainbowLabel(
      goalPercent(progressMinor: progressMinor, targetMinor: goal.targetMinor),
      saved,
      target,
    ),
  };
}
