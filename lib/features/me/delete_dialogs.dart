import 'package:flutter/material.dart';

import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart';
import 'me_actions.dart';

/// The two dialogs of Delete everything (plan §3.8, decision 67), shared by
/// Me and by Forgot PIN's erase (decision 70) so both say and do the same.
/// [idPrefix] names their buttons: `<prefix>-cancel`, `<prefix>-confirm`,
/// `<prefix>-failed-ok` and `<prefix>-retry`.

/// "Delete everything?" with [body]: true when the person confirms.
Future<bool> confirmDeleteEverything(
  BuildContext context, {
  required String body,
  required String idPrefix,
}) async {
  final l10n = AppLocalizations.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // At the largest text sizes its words outgrow a small screen.
      scrollable: true,
      // Whole words at large text: a dialog is narrow.
      title: WholeWordsText(
        l10n.deleteAllTitle,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      content: Text(body),
      actions: [
        TestId(
          '$idPrefix-cancel',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
        ),
        TestId(
          '$idPrefix-confirm',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteAllConfirm),
          ),
        ),
      ],
    ),
  );
  return sure == true;
}

/// The wipe ([deleteEverything]: the journal first, and only then the lock,
/// the prefs and the account). While a step failed, "Not everything was
/// erased" offers Try again, which runs every step again. True once all of
/// it is erased; false when the person stopped with a step still failing.
Future<bool> wipeEverything(
  BuildContext context,
  AppServices services,
  AppSession session, {
  required String idPrefix,
}) async {
  while (true) {
    if (await deleteEverything(services, session)) return true;
    if (!context.mounted) return false;
    final again = await _notEverythingErased(context, idPrefix);
    if (!again || !context.mounted) return false;
  }
}

Future<bool> _notEverythingErased(BuildContext context, String idPrefix) async {
  final l10n = AppLocalizations.of(context);
  final again = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // At the largest text sizes its words outgrow a small screen.
      scrollable: true,
      title: WholeWordsText(
        l10n.deleteAllFailedTitle,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      content: Text(l10n.deleteAllFailedBody),
      actions: [
        TestId(
          '$idPrefix-failed-ok',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.ok),
          ),
        ),
        TestId(
          '$idPrefix-retry',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteAllRetry),
          ),
        ),
      ],
    ),
  );
  return again == true;
}
