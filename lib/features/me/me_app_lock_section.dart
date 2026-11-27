import 'package:flutter/material.dart';

import '../../core/app_dialog.dart';
import '../../core/app_lock.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/session_scope.dart';
import '../lock/lock_screen.dart';
import '../shell/piggybow_back.dart';

/// Me → App lock (1.1 C): off by default; on → a PIN (twice), then
/// biometrics if the device has them; "Lock after". Absent while the feature
/// is off (AppConfig.appLockEnabled).
class MeAppLockSection extends StatefulWidget {
  const MeAppLockSection({super.key});

  @override
  State<MeAppLockSection> createState() => _MeAppLockSectionState();
}

class _MeAppLockSectionState extends State<MeAppLockSection> {
  /// Asked once, so a rebuild doesn't flash the general words.
  Future<BiometricKind>? _kind;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _kind ??= context.services.appLock?.biometrics.kind();
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.services.appLock;
    if (lock == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          TestId(
            'me-app-lock',
            selected: lock.enabled,
            child: SwitchListTile(
              value: lock.enabled,
              title: Text(l10n.meAppLock),
              subtitle: FutureBuilder<BiometricKind>(
                future: _kind,
                builder: (context, kind) =>
                    Text(lockHintLabel(l10n, kind.data)),
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: (on) async {
                if (!on) {
                  await lock.clear();
                  return;
                }
                if (context.readSession.user?.isAnonymous ?? false) {
                  final go = await _noEmailNotice(context);
                  if (go != true || !context.mounted) return;
                }
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => PinSetupPage(lock: lock)),
                );
              },
            ),
          ),
          if (lock.enabled) ...[
            FutureBuilder<bool>(
              future: lock.biometrics.available(),
              builder: (context, snap) => snap.data == true
                  ? TestId(
                      'me-lock-biometrics',
                      selected: lock.biometricsOn,
                      child: SwitchListTile(
                        value: lock.biometricsOn,
                        title: FutureBuilder<BiometricKind>(
                          future: _kind,
                          builder: (context, kind) =>
                              Text(lockUseLabel(l10n, kind.data)),
                        ),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (on) => lock.setBiometrics(on: on),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.meLockAfter,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            RadioGroup<LockAfter>(
              groupValue: lock.lockAfter,
              onChanged: (v) {
                if (v != null) lock.setLockAfter(v);
              },
              child: Column(
                children: [
                  for (final (v, label) in [
                    (LockAfter.immediately, l10n.lockImmediately),
                    (LockAfter.oneMinute, l10n.lock1Min),
                    (LockAfter.fiveMinutes, l10n.lock5Min),
                  ])
                    TestId(
                      'me-lock-after-${v.name}',
                      button: true,
                      selected: lock.lockAfter == v,
                      child: RadioListTile<LockAfter>(
                        value: v,
                        title: Text(label),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The person, not just whoever holds the unlocked phone: biometrics when
/// they're on, else (or when that's cancelled) the PIN.
Future<bool> confirmItsYou(BuildContext context, AppLock lock) async {
  final l10n = AppLocalizations.of(context);
  final navigator = Navigator.of(context);
  if (lock.biometricsOn &&
      await lock.biometrics.authenticate(l10n.lockBiometricReason)) {
    return true;
  }
  final ok = await navigator.push<bool>(
    MaterialPageRoute(builder: (_) => PinConfirmPage(lock: lock)),
  );
  return ok ?? false;
}

/// The PIN once, unlocking nothing: pops true when it's right.
class PinConfirmPage extends StatefulWidget {
  const PinConfirmPage({super.key, required this.lock});

  final AppLock lock;

  @override
  State<PinConfirmPage> createState() => _PinConfirmPageState();
}

class _PinConfirmPageState extends State<PinConfirmPage> {
  String? _error;
  int _tries = 0;

  Future<void> _done(String pin) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    if (await widget.lock.confirmPin(pin)) {
      navigator.pop(true);
      return;
    }
    if (mounted) {
      setState(() {
        _error = l10n.lockWrongPin;
        _tries++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TestId.container(
      'pin-confirm-screen',
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitle(l10n.meAppLock),
          leadingWidth: 64,
          leading: PiggybowBack(
            id: 'pin-confirm-back',
            to: l10n.tabMe,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PinPad(
              // Empty again after a wrong one.
              key: ValueKey(_tries),
              title: l10n.lockEnterPin,
              error: _error,
              onDone: _done,
            ),
          ),
        ),
      ),
    );
  }
}

/// A PIN twice, then (if available) one biometric check to turn it on.
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key, required this.lock});

  final AppLock lock;

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  String? _first;
  String? _error;

  Future<void> _done(String pin) async {
    final l10n = AppLocalizations.of(context);
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = l10n.lockPinMismatch;
      });
      return;
    }
    final navigator = Navigator.of(context);
    await widget.lock.setPin(pin);
    if (await widget.lock.biometrics.available() &&
        await widget.lock.biometrics.authenticate(l10n.lockBiometricReason)) {
      await widget.lock.setBiometrics(on: true);
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TestId.container(
      'pin-setup-screen',
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitle(l10n.meAppLock),
          leadingWidth: 64,
          leading: PiggybowBack(
            id: 'pin-setup-back',
            to: l10n.tabMe,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PinPad(
              // A new pad per step (the typed digits start empty).
              key: ValueKey(_first == null),
              title: _first == null ? l10n.lockSetPin : l10n.lockConfirmPin,
              error: _error,
              onDone: _done,
            ),
          ),
        ),
      ),
    );
  }
}

/// Before a lock on an account with no email: a forgotten PIN has no way back
/// (decision 216). True: go on with the PIN.
Future<bool?> _noEmailNotice(BuildContext context) async {
  return showAppDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return TestId.container(
        'me-lock-no-email',
        child: AlertDialog(
          scrollable: true,
          content: Text(l10n.meLockNoEmailNotice),
          actions: [
            TestId(
              'me-lock-continue',
              button: true,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.meLockContinue),
              ),
            ),
          ],
        ),
      );
    },
  );
}
