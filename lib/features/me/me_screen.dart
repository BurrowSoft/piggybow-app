import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../data/models.dart' show ReminderTime;
import '../../l10n/gen/app_localizations.dart';
import '../../lock_rules/lock_rules.dart';
import '../../money/money.dart';
import '../../pig/pig_mood.dart' show HappyPick;
import '../../reminder_rules/reminder_rules.dart';
import '../../router.dart';
import '../../session/session_scope.dart';
import '../../settings_rules/settings_rules.dart';
import '../../theme/palettes.dart';
import '../../theme/theme.dart';
import '../currency/currency_picker.dart';
import '../plus/plus_screen.dart';
import '../shell/tab_top.dart';
import 'backup_screens.dart' show backupOffered, restoreOffered;
import 'delete_dialogs.dart';
import 'me_actions.dart';
import 'me_app_lock_section.dart';
import 'pig_name_dialog.dart';
import 'theme_picker.dart';

/// A pick's title, as O2 and Me's subtitle name it.
String happyPickTitle(AppLocalizations l10n, HappyPick pick) => switch (pick) {
  HappyPick.save => l10n.happySaveTitle,
  HappyPick.plan => l10n.happyPlanTitle,
  HappyPick.worth => l10n.happyWorthTitle,
};

/// The App lock row's subtitle for a lock_rules.lockRowKey key.
String lockRowText(AppLocalizations l10n, String key) => switch (key) {
  'meStateOn' => l10n.meStateOn,
  'lockOffAfterRestore' => l10n.lockOffAfterRestore,
  _ => l10n.meStateOff,
};

/// Me (plan §3.8): your pig, money, reminders, your data (feature 21),
/// privacy & security, appearance, about.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> with ScrollsToTopOnTabTap {
  Set<HappyPick>? _picks;
  int? _plan;
  String? _currency;
  bool _granted = true;

  /// How many goals were reached (Reached goals shows from the first).
  int _reached = 0;
  bool _yesterdayFeel = true;
  bool _letters = true;
  (String, String)? _version;
  AppServices? _services;
  AppLifecycleListener? _lifecycle;

  @override
  AppTab get tab => AppTab.me;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final services = _services = context.services;
      services.journal.addListener(_load);
      services.appLock?.addListener(_lockChanged);
      services.plus?.addListener(_lockChanged);
      // Notifications can be turned on or off outside the app.
      _lifecycle = AppLifecycleListener(onResume: _load);
      _load();
      _loadVersion();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    _services?.appLock?.removeListener(_lockChanged);
    _services?.plus?.removeListener(_lockChanged);
    _lifecycle?.dispose();
    super.dispose();
  }

  /// The App lock row follows the lock: on, off, or off after a restore;
  /// the Plus rows follow Plus.
  void _lockChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final services = _services;
    if (services == null) return;
    final store = services.journal;
    final picks = await store.picks();
    final plan = await store.planMinor();
    final currency = await store.currency() ?? 'USD';
    final yesterdayFeel = await store.yesterdayFeelOn();
    final letters = await store.lettersOn();
    final granted = await services.notifications.granted();
    final reached = (await store.reachedGoals()).length;
    if (!mounted) return;
    setState(() {
      _picks = picks;
      _plan = plan;
      _currency = currency;
      _yesterdayFeel = yesterdayFeel;
      _letters = letters;
      _granted = granted;
      _reached = reached;
    });
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = (info.version, info.buildNumber));
    } on Object {
      // No version to show: the row stays out.
    }
  }

  Future<void> _setReminder(bool on, ReminderTime time) async {
    final services = context.services;
    await context.readSession.updateReminder(on: on, time: time);
    if (on) await services.notifications.request();
    await _load();
  }

  /// Me → Theme: Strawberry at once; a Plus theme through Plus (the
  /// paywall when it isn't active), kept only if Plus is active after it.
  Future<void> _pickTheme() async {
    final session = context.readSession;
    final plus = context.services.plus;
    if (plus == null) return;
    final picked = await pickTheme(
      context,
      shown: appliedPalette(session.chosenPalette, plusActive: plus.active),
    );
    if (picked == null || !mounted) return;
    final theme = picked.theme;
    if (theme != null && !await requirePlus(context)) return;
    await session.setPalette(theme);
    if (mounted) setState(() {});
  }

  Future<void> _pickTime(ReminderTime current) async {
    final session = context.readSession;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    await session.updateReminder(
      on: true,
      time: ReminderTime(picked.hour, picked.minute),
    );
  }

  /// Me → Your pig → Name: kept as typed (trimmed, at most 20 characters);
  /// emptied, the pig has no name.
  Future<void> _editPigName() async {
    final session = context.readSession;
    final result = await editPigName(context, current: session.pigName);
    if (result == null) return;
    await session.setPigName(result.name);
  }

  Future<void> _editPlan(String currency, String locale) async {
    final services = context.services;
    final picks = _picks ?? const {};
    final result = await showDialog<_PlanResult>(
      context: context,
      builder: (_) =>
          _PlanDialog(plan: _plan, currency: currency, locale: locale),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _PlanSave(:final minor):
        await services.journal.setPlanMinor(minor);
      case _PlanRemove():
        final removal = removePlan(picks);
        if (removal.openPickerFirst) {
          // The only pick: another one first, then the plan goes.
          unawaited(context.push(MeRoutes.removePlan));
        } else {
          await services.journal.setPicks(removal.picks);
          await services.journal.setPlanMinor(null);
        }
    }
  }

  /// Delete everything: confirmed, then the wipe; onboarding takes over,
  /// from O1. If a step failed, Me says so and can try them all again
  /// (decision 67). Forgot PIN's erase shares these dialogs.
  Future<void> _deleteAll() async {
    final l10n = AppLocalizations.of(context);
    final services = context.services;
    final session = context.readSession;
    final plus = services.plus;
    if (!await confirmDeleteEverything(
      context,
      body: l10n.deleteAllBody,
      idPrefix: 'me-delete',
      // Erasing the app never cancels the store's subscription: it says so,
      // with the way to the store's page.
      note: plus != null && plus.active
          ? PlusKeepsRunning(plus: plus, idPrefix: 'me-delete')
          : null,
    )) {
      return;
    }
    if (!mounted) return;
    await wipeEverything(context, services, session, idPrefix: 'me-delete');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = context.session;
    final services = context.services;
    final config = ConfigScope.of(context);
    final locale = session.device.localeName;
    final picks = _picks;
    final currency = _currency;
    final plan = _plan;
    final version = _version;
    final reminderOn = session.accountState?.reminderOn ?? false;
    final reminderTime =
        session.accountState?.reminderTime ?? ReminderTime.defaultTime;
    final lock = services.appLock;
    final plus = services.plus;
    return TestId.container(
      'me-screen',
      child: Scaffold(
        appBar: AppBar(title: AppBarTitle(l10n.meTitle)),
        body: picks == null || currency == null
            ? const SizedBox.shrink()
            : ListView(
                primary: true,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // Only in builds with Plus (decision 79).
                  if (plus != null) ...[
                    _Section(l10n.meSecPlus),
                    _Row(
                      id: 'me-plus',
                      title: l10n.mePlus,
                      subtitle: plus.active ? l10n.mePlusOn : l10n.mePlusOff,
                      onTap: () => context.push(PlusRoutes.paywall),
                    ),
                    if (plus.active)
                      _Row(
                        id: 'me-plus-manage',
                        title: l10n.plusManage,
                        onTap: plus.manage,
                      ),
                  ],
                  _Section(l10n.meSecPig),
                  _Row(
                    id: 'me-pig-name',
                    title: l10n.mePigName,
                    subtitle: session.pigName ?? l10n.mePigNameNone,
                    onTap: _editPigName,
                  ),
                  _Row(
                    id: 'me-happy',
                    title: l10n.meHappy,
                    subtitle: happySubtitle(
                      picks,
                      (pick) => happyPickTitle(l10n, pick),
                    ),
                    onTap: () => context.push(MeRoutes.happy),
                  ),
                  _Row(
                    id: 'me-plan',
                    title: l10n.mePlan,
                    subtitle: plan == null
                        ? l10n.mePlanNotSet
                        : formatMoney(plan, currency, locale),
                    onTap: () => _editPlan(currency, locale),
                  ),
                  // From the first goal reached (for everyone; decision 79).
                  if (_reached > 0)
                    _Row(
                      id: 'me-reached',
                      title: l10n.meReachedGoals,
                      subtitle: l10n.meReachedGoalsCount(_reached),
                      onTap: () => context.push(MeRoutes.reached),
                    ),
                  // Home's "How did yesterday feel?" (on unless switched off).
                  TestId(
                    'me-yesterday-feel',
                    child: SwitchListTile(
                      title: Text(l10n.meYesterdayFeel),
                      value: _yesterdayFeel,
                      onChanged: (on) =>
                          context.services.journal.setYesterdayFeelOn(on),
                    ),
                  ),
                  // Home's monthly letter from the pig (on unless switched off).
                  TestId(
                    'me-letters',
                    child: SwitchListTile(
                      title: Text(l10n.meLetters),
                      value: _letters,
                      onChanged: (on) =>
                          context.services.journal.setLettersOn(on),
                    ),
                  ),
                  _Section(l10n.meSecMoney),
                  _Row(
                    id: 'me-currency',
                    title: l10n.meCurrency,
                    subtitle: l10n.currencyRow(
                      l10n.currencyName(currency),
                      currencySymbolOf(currency, locale),
                    ),
                    onTap: () async {
                      await changeCurrency(context);
                      await _load();
                    },
                  ),
                  // For everyone: hiding is free; your own are Plus's.
                  _Row(
                    id: 'me-categories',
                    title: l10n.meCategories,
                    subtitle: l10n.meCategoriesSub,
                    onTap: () => context.push(MeRoutes.categories),
                  ),
                  _Section(l10n.meSecReminders),
                  TestId(
                    'me-reminder',
                    child: SwitchListTile(
                      title: Text(l10n.meReminder),
                      value: reminderOn,
                      onChanged: (on) => _setReminder(on, reminderTime),
                    ),
                  ),
                  if (reminderOn)
                    _Row(
                      id: 'me-reminder-time',
                      title: l10n.meReminderTime,
                      subtitle: MaterialLocalizations.of(context)
                          .formatTimeOfDay(
                            TimeOfDay(
                              hour: reminderTime.hour,
                              minute: reminderTime.minute,
                            ),
                          ),
                      onTap: () => _pickTime(reminderTime),
                    ),
                  if (reminderRow(on: reminderOn, permissionGranted: _granted) ==
                      ReminderRow.onButNotificationsOff)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.meNotifOff,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TestId(
                            'me-open-settings',
                            button: true,
                            child: TextButton(
                              onPressed: services.notifications.openSettings,
                              child: Text(l10n.meOpenSettings),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Your data (feature 21): a backup file to keep or move
                  // with, its restore, and the spreadsheet export.
                  _Section(l10n.meSecData),
                  if (backupOffered(context))
                    _Row(
                      id: 'me-backup',
                      title: l10n.meBackup,
                      subtitle: l10n.meBackupHint,
                      onTap: () => context.push(MeRoutes.backup),
                    ),
                  if (restoreOffered(context))
                    _Row(
                      id: 'me-restore',
                      title: l10n.meRestore,
                      subtitle: l10n.meRestoreHint,
                      onTap: () => context.push(MeRoutes.restore),
                    ),
                  _Row(
                    id: 'me-export',
                    title: l10n.meExport,
                    subtitle: l10n.meExportHint,
                    onTap: () => exportJournal(services, l10n: l10n),
                  ),
                  _Section(l10n.meSecPrivacy),
                  if (config.appLockEnabled && lock != null)
                    _Row(
                      id: 'me-lock',
                      title: l10n.meLock,
                      subtitle: lockRowText(
                        l10n,
                        lockRowKey(
                          lockOn: lock.enabled,
                          restoreNoticePending: lock.restoreNoticePending,
                        ),
                      ),
                      onTap: () {
                        unawaited(lock.dismissRestoreNotice());
                        context.push(MeRoutes.lock);
                      },
                    ),
                  _Row(
                    id: 'me-delete',
                    title: l10n.meDeleteAll,
                    onTap: _deleteAll,
                  ),
                  _Section(l10n.meSecAppearance),
                  // Three rows: whole at any text size (decision 66).
                  RadioGroup<ThemeMode>(
                    groupValue: session.themeMode,
                    onChanged: (mode) {
                      if (mode != null) session.setThemeMode(mode);
                    },
                    child: Column(
                      children: [
                        for (final (id, label, mode) in [
                          ('me-theme-system', l10n.themeSystem, ThemeMode.system),
                          ('me-theme-light', l10n.themeLight, ThemeMode.light),
                          ('me-theme-dark', l10n.themeDark, ThemeMode.dark),
                        ])
                          TestId(
                            id,
                            child: RadioListTile<ThemeMode>(
                              value: mode,
                              title: Text(label),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (plus != null)
                    _Row(
                      id: 'me-theme',
                      title: l10n.meTheme,
                      subtitle: themeRowSubtitle(
                        l10n,
                        chosen: session.chosenPalette,
                        plusActive: plus.active,
                      ),
                      onTap: _pickTheme,
                    ),
                  _Section(l10n.meSecAbout),
                  _Row(
                    id: 'me-privacy',
                    title: l10n.mePrivacy,
                    onTap: () => context.push(MeRoutes.privacy),
                  ),
                  // Only once piggybow.com/support is live (SUPPORT_URL).
                  if (config.supportUrl.isNotEmpty)
                    _Row(
                      id: 'me-help',
                      title: l10n.meHelp,
                      onTap: () => launchUrl(
                        Uri.parse(config.supportUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  if (version != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: TestId.container(
                        'me-version',
                        child: Text(
                          l10n.meVersion(version.$1, version.$2),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A section's title.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// One row: its title in ink, its subtitle muted (ListTile's own colours).
class _Row extends StatelessWidget {
  const _Row({
    required this.id,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String id;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return TestId(
      id,
      button: true,
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}

sealed class _PlanResult {
  const _PlanResult();
}

final class _PlanSave extends _PlanResult {
  const _PlanSave(this.minor);

  final int minor;
}

final class _PlanRemove extends _PlanResult {
  const _PlanRemove();
}

/// The weekly plan's amount (plan §3.8, decision 63): Save, Cancel, and
/// Remove plan when one is set. A plan needs no "weekly plan" pick
/// (decision 34).
class _PlanDialog extends StatefulWidget {
  const _PlanDialog({
    required this.plan,
    required this.currency,
    required this.locale,
  });

  final int? plan;
  final String currency;
  final String locale;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final _amount = TextEditingController(
    text: widget.plan == null
        ? ''
        : inputAmount(widget.plan!, widget.currency, widget.locale),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final parsed = parseAmount(_amount.text, widget.currency);
    if (parsed.problem != null) {
      setState(
        () => _error = parsed.problem == AmountProblem.tooBig
            ? l10n.addAmountTooBig
            : l10n.happyPlanNeeded,
      );
      return;
    }
    Navigator.of(context).pop(_PlanSave(parsed.minor!));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: WholeWordsText(
        l10n.mePlan,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      content: TestId(
        'me-plan-amount',
        child: TextField(
          // Asks the keyboard not to learn from what is typed here (Android).
          enableIMEPersonalizedLearning: false,
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: context.inputText,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(l10n.happyPlanField),
            ),
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
      ),
      actions: [
        TestId(
          'me-plan-cancel',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ),
        if (widget.plan != null)
          TestId(
            'me-plan-remove',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(const _PlanRemove()),
              child: Text(l10n.mePlanRemove),
            ),
          ),
        TestId(
          'me-plan-save',
          button: true,
          child: TextButton(onPressed: _save, child: Text(l10n.save)),
        ),
      ],
    );
  }
}

/// Me → App lock: the lock's own settings (the PIN, biometrics, lock after).
class MeLockPage extends StatelessWidget {
  const MeLockPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TestId.container(
      'me-lock-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.meLock)),
        body: ListView(children: const [MeAppLockSection()]),
      ),
    );
  }
}

/// Me → Your privacy (plan §3.8): the short version, in the app. The
/// crash-report line only in builds with a Sentry DSN; after the lines, the
/// full policy's link once PRIVACY_URL is set, opening in the browser.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final config = ConfigScope.of(context);
    final lines = [
      l10n.privacy1,
      l10n.privacy2,
      if (config.sentryDsn.isNotEmpty) l10n.privacy3,
      l10n.privacy4,
      l10n.privacy5,
    ];
    return TestId.container(
      'me-privacy-screen',
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.privacyTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  line,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            if (config.privacyUrl.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TestId(
                  'privacy-policy',
                  button: true,
                  child: TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(config.privacyUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(l10n.privacyPolicyLink),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
