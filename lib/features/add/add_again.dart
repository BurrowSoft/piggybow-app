import 'package:flutter/material.dart';

import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../journal/entry.dart';
import '../../journal/goal.dart';
import '../../l10n/gen/app_localizations.dart';

/// Whether [entry] can be added again today: a spend, except one in a
/// category of your own while Plus is off ([plus]: your own categories are
/// Plus's); a save while the goal it went to ([goal]) is still active, or
/// when it went to none. A save whose goal was reached or ended doesn't
/// offer it, and money taken out of savings never does (UX: addEntry
/// refuses a withdrawal anyway).
bool canAddAgain(Entry entry, Goal? goal, {required bool plus}) => switch (entry.type) {
  EntryType.spent => entry.customCategory == null || plus,
  EntryType.saved => entry.goalId == null || goal?.status == GoalStatus.active,
  EntryType.withdraw => false,
};

/// [entry] again, dated today: the same type, amount, category (built-in or
/// your own) and note. The feeling is asked fresh (none yet). A save goes to
/// its own goal, still active, named outright (with two or more goals, not
/// the one a new save goes to by default); a save that had none stays with
/// none (never moved into a goal).
Future<Entry> addAgainToday(AppServices services, Entry entry) =>
    services.journal.addEntry(
      type: entry.type,
      amountMinor: entry.amountMinor,
      currency: entry.currency,
      localDate: services.localDay.todayWire,
      category: entry.category,
      customCategory: entry.customCategory,
      note: entry.note,
      goalId: entry.type == EntryType.saved ? entry.goalId : null,
      noGoal: entry.type == EntryType.saved && entry.goalId == null,
    );

/// Adds [entry] again and says so on [messenger] ("Added again for today",
/// with Undo: it removes that copy, nothing else). A store failure says so
/// instead, and is reported.
Future<void> addAgainAndSay(
  AppServices services,
  Entry entry, {
  required ScaffoldMessengerState? messenger,
  required AppLocalizations l10n,
}) async {
  final Entry copy;
  try {
    copy = await addAgainToday(services, entry);
  } on Object catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack, library: 'add again'),
    );
    messenger?.showSnackBar(SnackBar(content: Text(l10n.errGeneric)));
    return;
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l10n.entryRepeated),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => services.journal.deleteEntry(copy.id),
        ),
      ),
    );
}

/// A long-press on a Timeline row: a small sheet with its one action, "Add
/// again today" (never an instant copy, so a long-press by mistake adds
/// nothing).
Future<void> offerAddAgain(BuildContext context, Entry entry) async {
  final l10n = AppLocalizations.of(context);
  final services = context.services;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final chosen = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TestId(
          'tl-repeat',
          button: true,
          child: ListTile(
            leading: const Icon(Icons.replay),
            title: Text(l10n.entryRepeat),
            onTap: () => Navigator.of(sheet).pop(true),
          ),
        ),
      ),
    ),
  );
  if (chosen != true) return;
  await addAgainAndSay(services, entry, messenger: messenger, l10n: l10n);
}
