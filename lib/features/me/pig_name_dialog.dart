import 'package:flutter/material.dart';

import '../../core/app_dialog.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../pig/pig_name.dart';
import '../../theme/theme.dart';

/// Me → Your pig → Name (feature 1): the name, up to [pigNameMaxLength]
/// characters; empty is no name. Returns what to keep (a record, so clearing
/// the name isn't a cancel), or null when cancelled.
Future<({String? name})?> editPigName(
  BuildContext context, {
  required String? current,
}) => showAppDialog<({String? name})>(
  context: context,
  builder: (_) => _PigNameDialog(current: current),
);

class _PigNameDialog extends StatefulWidget {
  const _PigNameDialog({required this.current});

  final String? current;

  @override
  State<_PigNameDialog> createState() => _PigNameDialogState();
}

class _PigNameDialogState extends State<_PigNameDialog> {
  late final _name = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() =>
      Navigator.of(context).pop((name: normalizePigName(_name.text)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: WholeWordsText(
        l10n.pigNameTitle,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      content: TestId(
        'me-pig-name-field',
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: pigNameMaxLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          style: context.inputText,
          decoration: InputDecoration(hintText: l10n.pigNameHint),
        ),
      ),
      actions: [
        TestId(
          'me-pig-name-cancel',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ),
        TestId(
          'me-pig-name-save',
          button: true,
          child: TextButton(onPressed: _save, child: Text(l10n.save)),
        ),
      ],
    );
  }
}
