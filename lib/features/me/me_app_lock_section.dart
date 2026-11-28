import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../l10n/platform_text.dart';
import '../lock/lock_screen.dart';
import '../shell/piggybow_back.dart';

/// Me → App lock (plan §3.11): off until turned on; on → a PIN (twice), then
/// biometrics if the phone has them; "Lock after". A forgotten PIN has a way
/// back (the phone's own screen lock, or erase), so turning it on needs no
/// warning.
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
                    Text(
                      lockHintLabel(
                        l10n,
                        kind.data,
                        Theme.of(context).platform,
                      ),
                    ),
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: (on) async {
                if (!on) {
                  await lock.clear();
                  return;
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
                              Text(
                                lockUseLabel(
                                  l10n,
                                  kind.data,
                                  Theme.of(context).platform,
                                ),
                              ),
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

/// A PIN twice, then (if available) one biometric check to turn it on.
class PinSetupPage extends StatelessWidget {
  const PinSetupPage({super.key, required this.lock});

  final AppLock lock;

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
            child: NewPinPad(
              onChosen: (pin) async {
                final navigator = Navigator.of(context);
                await lock.setPin(pin);
                if (await lock.biometrics.available() &&
                    await lock.biometrics.authenticate(
                      l10n.lockBiometricReason,
                    )) {
                  await lock.setBiometrics(on: true);
                }
                if (context.mounted) navigator.pop();
              },
            ),
          ),
        ),
      ),
    );
  }
}
