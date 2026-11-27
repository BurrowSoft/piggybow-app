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
import '../../theme/theme.dart';
import '../currency/currency_picker.dart';
import '../shell/segmented.dart';
import '../shell/tab_top.dart';
import 'me_actions.dart';
import 'me_app_lock_section.dart';

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

/// Me (plan §3.8): your pig, money, reminders, privacy & security,
/// appearance, about.
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
      // Notifications can be turned on or off outside the app.
      _lifecycle = AppLifecycleListener(onResume: _load);
      _load();
      _loadVersion();
    });
  }

  @override
  void dispose() {
    _services?.journal.removeListener(_load);
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = _services;
    if (services == null) return;
    final store = services.journal;
    final picks = await store.picks();
    final plan = await store.planMinor();
    final currency = await store.currency() ?? 'USD';
    final granted = await services.notifications.granted();
    if (!mounted) return;
    setState(() {
      _picks = picks;
      _plan = plan;
      _currency = currency;
      _granted = granted;
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

  Future<void> _deleteAll() async {
    final l10n = AppLocalizations.of(context);
    final services = context.services;
    final session = context.readSession;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Whole words at large text: a dialog is narrow.
        title: WholeWordsText(
          l10n.deleteAllTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        content: Text(l10n.deleteAllBody),
        actions: [
          TestId(
            'me-delete-cancel',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
          ),
          TestId(
            'me-delete-confirm',
            button: true,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.deleteAllConfirm),
            ),
          ),
        ],
      ),
    );
    if (sure != true) return;
    // Then onboarding takes over, from O1.
    await deleteEverything(services, session);
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
                  _Section(l10n.meSecPig),
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
                  _Section(l10n.meSecPrivacy),
                  if (config.appLockEnabled && lock != null)
                    _Row(
                      id: 'me-lock',
                      title: l10n.meLock,
                      subtitle: lockRowText(
                        l10n,
                        lockRowKey(
                          lockOn: lock.enabled,
                          restoreNoticePending: false,
                        ),
                      ),
                      onTap: () => context.push(MeRoutes.lock),
                    ),
                  _Row(
                    id: 'me-export',
                    title: l10n.meExport,
                    subtitle: l10n.meExportHint,
                    onTap: () => exportJournal(services),
                  ),
                  _Row(
                    id: 'me-delete',
                    title: l10n.meDeleteAll,
                    onTap: _deleteAll,
                  ),
                  _Section(l10n.meSecAppearance),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PiggybowSegmented<ThemeMode>(
                      segments: [
                        ('me-theme-system', l10n.themeSystem, ThemeMode.system),
                        ('me-theme-light', l10n.themeLight, ThemeMode.light),
                        ('me-theme-dark', l10n.themeDark, ThemeMode.dark),
                      ],
                      selected: session.themeMode,
                      onSelected: session.setThemeMode,
                    ),
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

/// Me → Your privacy (plan §3.8): in the app while the web policy isn't
/// live. The crash-report line only in builds with a Sentry DSN; the full
/// policy's link comes with PRIVACY_URL and its own copy.
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
          ],
        ),
      ),
    );
  }
}
