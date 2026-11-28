import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../backup/backup_file.dart';
import '../../backup/backup_flow.dart';
import '../../backup/backup_snapshot.dart';
import '../../core/fit_text.dart';
import '../../core/labeled_field.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart' show Routes;
import '../../session/session_scope.dart';
import '../../theme/theme.dart';
import '../onboarding/onboarding_screens.dart' show onboardedAtStart;

/// A password field for a backup: hidden unless shown, and the keyboard
/// neither learns it nor suggests (it's never stored or logged). Its label
/// is never cut off (LabeledField).
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.id,
    required this.label,
    required this.controller,
    required this.shown,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
    this.toggle,
  });

  final String id;
  final String label;
  final TextEditingController controller;
  final bool shown;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  /// The show/hide eye, on the first field.
  final Widget? toggle;

  @override
  Widget build(BuildContext context) => TestId(
    id,
    child: LabeledField(
      label: label,
      decoration: InputDecoration(suffixIcon: toggle),
      field: (decoration) => TextField(
        controller: controller,
        // What people type is ink, never the hint grey (decision 206).
        style: context.inputText,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: !shown,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        onSubmitted: onSubmitted,
        decoration: decoration,
      ),
    ),
  );
}

/// A zero-width space: a line may break there, and nothing shows.
final _breakHere = String.fromCharCode(0x200B);

/// A file name ("piggybow-backup-2026-09-30.piggybow") is one long word: on
/// a narrow line it may break after its own - . and _, never inside a part.
String _breakable(String name) =>
    name.replaceAllMapped(RegExp('[-._]'), (m) => '${m[0]}$_breakHere');

class _ShowToggle extends StatelessWidget {
  const _ShowToggle({
    required this.id,
    required this.shown,
    required this.onChanged,
  });

  final String id;
  final bool shown;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TestId(
      id,
      button: true,
      child: IconButton(
        tooltip: shown ? l10n.backupHidePassword : l10n.backupShowPassword,
        icon: Icon(shown ? Icons.visibility_off : Icons.visibility),
        onPressed: () => onChanged(!shown),
      ),
    );
  }
}

/// A line under the fields: what went wrong, or what's happening.
class _Line extends StatelessWidget {
  const _Line(this.id, this.text, {this.error = false});

  final String id;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TestId.container(
        id,
        child: Semantics(
          liveRegion: true,
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: error
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// The working state of a button: a small spinner and what it's doing.
class _Working extends StatelessWidget {
  const _Working(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Flexible(child: Text(text, textAlign: TextAlign.center)),
    ],
  );
}

/// Me → Back up to a file (feature 21): a password, the same again, the
/// hint, and the line that it can't be recovered; then the share sheet.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _shown = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _backUp() async {
    final l10n = AppLocalizations.of(context);
    final password = _password.text;
    final error = password.characters.length < backupMinPassword
        ? l10n.backupTooShort(backupMinPassword)
        : password != _again.text
        ? l10n.backupMismatch
        : null;
    setState(() {
      _error = error;
      _busy = error == null;
    });
    if (error != null) return;
    final services = context.services;
    final session = context.readSession;
    try {
      await backUpToFile(services, session, password);
      if (mounted) context.pop();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.backupNotMade;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = _error;
    return TestId.container(
      'backup-screen',
      child: Scaffold(
        appBar: AppBar(title: AppBarTitle(l10n.meBackup)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(l10n.backupBody, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            // Right under what the password is for, so it's on screen at
            // the largest text, before any scrolling.
            TestId.container(
              'backup-no-recovery',
              child: Text(
                l10n.backupNoRecovery,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PasswordField(
              id: 'backup-password',
              label: l10n.backupPassword,
              controller: _password,
              shown: _shown,
              autofocus: true,
              toggle: _ShowToggle(
                id: 'backup-show',
                shown: _shown,
                onChanged: (shown) => setState(() => _shown = shown),
              ),
            ),
            const SizedBox(height: 12),
            _PasswordField(
              id: 'backup-again',
              label: l10n.backupPasswordAgain,
              controller: _again,
              shown: _shown,
              onSubmitted: (_) => _busy ? null : _backUp(),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.backupHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (error != null) _Line('backup-error', error, error: true),
            const SizedBox(height: 24),
            TestId(
              'backup-go',
              button: true,
              child: FilledButton(
                onPressed: _busy ? null : _backUp,
                child: _busy
                    ? _Working(l10n.backupWorking)
                    : Text(l10n.backupAction, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restore from a file (feature 21), from Me or from the first screen
/// ("Moving from another phone?"): the file, its password, the whole of it
/// checked, then, over a journal with notes, a clear "Replace?"; then the
/// journal is back, and Done goes Home (onboarding follows the restored
/// journal).
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  ({String name, String text})? _file;
  bool _shown = false;
  bool _busy = false;
  String? _error;
  BackupSnapshot? _restored;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _why(AppLocalizations l10n, Object error) => switch (error) {
    BackupWontOpen() => l10n.restoreWrongPassword,
    NotABackup() => l10n.restoreNotBackup,
    BackupTooNew() => l10n.restoreTooNew,
    _ => l10n.restoreNotDone,
  };

  Future<void> _choose() async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = await BackupHooks.current.pickFile();
      if (!mounted || file == null) return;
      setState(() {
        _file = file;
        _error = null;
      });
      _focus.requestFocus();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _why(l10n, error));
    }
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final file = _file;
    if (file == null) return;
    final services = context.services;
    final session = context.readSession;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // All of it is opened and checked before anything is touched.
      final backup = await readBackup(file.text, _password.text);
      if (!mounted) return;
      final blank = await services.journal.isBlank();
      if (!mounted) return;
      if (!blank) {
        // Nothing turns while the person decides.
        setState(() => _busy = false);
        if (!await _confirmReplace(context) || !mounted) return;
        setState(() => _busy = true);
      }
      await restoreBackup(services, session, backup);
      if (mounted) {
        setState(() {
          _busy = false;
          _restored = backup;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _why(l10n, error);
      });
      // The password stays, ready to be checked and tried again.
      _focus.requestFocus();
    }
  }

  Future<void> _done() async {
    final services = context.services;
    // The restored journal says whether onboarding is done.
    services.onboarded.value = await onboardedAtStart(services.journal);
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final file = _file;
    final error = _error;
    final restored = _restored;
    return TestId.container(
      'restore-screen',
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitle(l10n.meRestore),
          automaticallyImplyLeading: restored == null,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: restored != null
              ? [
                  TestId.container(
                    'restore-done',
                    child: Text(
                      l10n.restoreDone,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (restored.prefs.reminderWasOn)
                    _Line('restore-reminder', l10n.restoreReminder),
                  const SizedBox(height: 24),
                  TestId(
                    'restore-finish',
                    button: true,
                    child: FilledButton(
                      onPressed: _done,
                      child: Text(l10n.done, textAlign: TextAlign.center),
                    ),
                  ),
                ]
              : [
                  Text(
                    file == null ? l10n.restoreChooseBody : l10n.restoreBody,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  if (file != null) ...[
                    TestId.container(
                      'restore-file',
                      child: Semantics(
                        label: file.name,
                        child: ExcludeSemantics(
                          child: Text(
                            _breakable(file.name),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PasswordField(
                      id: 'restore-password',
                      label: l10n.backupPassword,
                      controller: _password,
                      focusNode: _focus,
                      shown: _shown,
                      autofocus: true,
                      onSubmitted: (_) => _busy ? null : _restore(),
                      toggle: _ShowToggle(
                        id: 'restore-show',
                        shown: _shown,
                        onChanged: (shown) => setState(() => _shown = shown),
                      ),
                    ),
                  ],
                  if (error != null) _Line('restore-error', error, error: true),
                  const SizedBox(height: 24),
                  if (file == null)
                    TestId(
                      'restore-choose',
                      button: true,
                      child: FilledButton(
                        onPressed: _choose,
                        child: Text(
                          l10n.restoreChoose,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else ...[
                    TestId(
                      'restore-go',
                      button: true,
                      child: FilledButton(
                        onPressed: _busy ? null : _restore,
                        child: _busy
                            ? _Working(l10n.restoreWorking)
                            : Text(
                                l10n.restoreAction,
                                textAlign: TextAlign.center,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TestId(
                      'restore-other',
                      button: true,
                      child: TextButton(
                        onPressed: _busy ? null : _choose,
                        child: Text(
                          l10n.restoreOtherFile,
                          textAlign: TextAlign.center,
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

/// "Replace everything?": true when the person confirms.
Future<bool> _confirmReplace(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // At the largest text sizes its words outgrow a small screen.
      scrollable: true,
      title: WholeWordsText(
        l10n.restoreReplaceTitle,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      content: TestId.container(
        'restore-replace-body',
        child: Text(l10n.restoreReplaceBody),
      ),
      actions: [
        TestId(
          'restore-replace-cancel',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
        ),
        TestId(
          'restore-replace',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.restoreReplace),
          ),
        ),
      ],
    ),
  );
  return sure == true;
}
