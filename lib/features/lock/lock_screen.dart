import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_lock.dart';
import '../../core/button_label.dart';
import '../../core/fit_text.dart';
import '../../core/semantics_id.dart';
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../lock_rules/lock_rules.dart';
import '../../session/app_session.dart';
import '../../theme/theme.dart';
import '../me/delete_dialogs.dart';

/// The PIN's dots and a 12-key pad (digits, delete, OK). [onDone] gets the
/// typed PIN when OK is pressed with 4–6 digits.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onDone,
    this.error,
    this.enabled = true,
    this.extra,
  });

  final String title;
  final Future<void> Function(String pin) onDone;
  final String? error;
  final bool enabled;

  /// Shown above the pad (the biometrics button on the lock screen).
  final Widget? extra;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  /// OK with fewer than 4 digits: pinTooShort under the
  /// dots until the next key.
  bool _tooShort = false;

  void _type(String d) {
    if (!widget.enabled || _pin.length >= 6) return;
    setState(() {
      _pin += d;
      _tooShort = false;
    });
  }

  void _delete() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _tooShort = false;
    });
  }

  Future<void> _ok() async {
    if (!widget.enabled) return;
    if (_pin.length < 4) {
      setState(() => _tooShort = true);
      return;
    }
    if (!AppLock.validPin(_pin)) return;
    final pin = _pin;
    setState(() => _pin = '');
    await widget.onDone(pin);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    Widget key(String id, Widget child, VoidCallback onTap, String label) =>
        TestId(
          id,
          button: true,
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 72,
              child: Material(
                color: palette.pillBackground,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        );
    // Three 72 dp keys a row with up to 10 dp either side; on a narrow
    // screen (320 dp, 200% text) the gaps shrink, never the keys.
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth.isFinite
            ? ((constraints.maxWidth - 3 * 72) / 6).clamp(2.0, 10.0)
            : 10.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // The count only (never the digits); spoken as "n of 6".
            TestId(
              'pin-dots',
              child: Semantics(
                label: '${_pin.length}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 6; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? palette.accent : null,
                          border: Border.all(color: palette.mutedText),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // At least 44 dp so the pad doesn't jump; taller when a long message
            // wraps at large text.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: (_tooShort ? l10n.pinTooShort : widget.error) == null
                    ? null
                    : TestId(
                        'pin-error',
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _tooShort ? l10n.pinTooShort : widget.error!,
                            style: text.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            ?widget.extra,
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in row)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gap),
                        child: key(
                          'pin-key-$d',
                          Text(d, style: text.headlineSmall),
                          () => _type(d),
                          d,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap),
                    child: key(
                      'pin-key-delete',
                      const Icon(Icons.backspace_outlined),
                      _delete,
                      l10n.lockDelete,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap),
                    child: key(
                      'pin-key-0',
                      Text('0', style: text.headlineSmall),
                      () => _type('0'),
                      '0',
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap),
                    child: key(
                      'pin-key-ok',
                      Icon(Icons.check_rounded, color: palette.accent),
                      _ok,
                      MaterialLocalizations.of(context).okButtonLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A new PIN, typed twice: [onChosen] gets it once both match; a mismatch
/// starts over. Me → App lock uses it to turn the lock on, and Forgot PIN
/// after the phone's own screen lock let the person in.
class NewPinPad extends StatefulWidget {
  const NewPinPad({super.key, required this.onChosen});

  final Future<void> Function(String pin) onChosen;

  @override
  State<NewPinPad> createState() => _NewPinPadState();
}

class _NewPinPadState extends State<NewPinPad> {
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
    await widget.onChosen(pin);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PinPad(
      // A new pad per step (the typed digits start empty).
      key: ValueKey(_first == null),
      title: _first == null ? l10n.lockSetPin : l10n.lockConfirmPin,
      error: _error,
      onDone: _done,
    );
  }
}

/// An iPhone says Face ID or Touch ID, as the system does; everywhere else,
/// the general words. [kind] is null until the device has answered.
String lockUseLabel(AppLocalizations l10n, BiometricKind? kind) =>
    switch (kind) {
      BiometricKind.faceId => l10n.lockUseFaceId,
      BiometricKind.touchId => l10n.lockUseTouchId,
      _ => l10n.lockUseBiometrics,
    };

String lockHintLabel(AppLocalizations l10n, BiometricKind? kind) =>
    switch (kind) {
      BiometricKind.faceId => l10n.meAppLockHintFaceId,
      BiometricKind.touchId => l10n.meAppLockHintTouchId,
      _ => l10n.meAppLockHint,
    };

/// Over the whole app while locked: the PIN pad, biometrics when on (asked
/// for once as it shows), and "Forgot PIN?" (plan §3.11, decision 19): the
/// phone's own screen lock, then a new PIN; or, behind a second confirm,
/// erase and start over. It sits above the app's Navigator, so it has its
/// own, for its dialogs.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key, required this.lock, required this.session});

  final AppLock lock;
  final AppSession session;

  @override
  Widget build(BuildContext context) => TestId.container(
    'lock-screen',
    child: Navigator(
      onGenerateRoute: (_) => PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => _LockBody(lock: lock, session: session),
      ),
    ),
  );
}

class _LockBody extends StatefulWidget {
  const _LockBody({required this.lock, required this.session});

  final AppLock lock;
  final AppSession session;

  @override
  State<_LockBody> createState() => _LockBodyState();
}

class _LockBodyState extends State<_LockBody> {
  String? _error;
  Timer? _tick;

  late final Future<BiometricKind> _kind = widget.lock.biometrics.kind();

  @override
  void initState() {
    super.initState();
    _startTick();
    if (widget.lock.biometricsOn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _biometrics());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Re-renders the wait countdown each second while it runs.
  void _startTick() {
    _tick?.cancel();
    if (widget.lock.waitRemaining == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (widget.lock.waitRemaining == null) t.cancel();
    });
  }

  Future<void> _biometrics() async {
    if (!mounted) return;
    await widget.lock.unlockWithBiometrics(
      AppLocalizations.of(context).lockBiometricReason,
    );
  }

  Future<void> _pin(String pin) async {
    final ok = await widget.lock.unlockWithPin(pin);
    if (!mounted || ok) return;
    setState(
      () => _error = widget.lock.waitRemaining == null
          ? AppLocalizations.of(context).lockWrongPin
          : null,
    );
    _startTick();
  }

  /// Forgot PIN: the phone's own screen lock first when it has one, then a
  /// new PIN; erase only as the other way, behind a second confirm.
  Future<void> _forgot() async {
    final l10n = AppLocalizations.of(context);
    final paths = forgotPinPaths(
      deviceHasScreenLock: await widget.lock.biometrics.screenLockSet(),
    );
    if (!mounted) return;
    final choice = await showDialog<ForgotPinChoice>(
      context: context,
      builder: (_) => ForgotPinDialog(paths: paths),
    );
    if (!mounted) return;
    switch (choice) {
      case ForgotPinChoice.screenLock:
        // A pass shows the new-PIN pad (AppLock.mayResetPin).
        await widget.lock.verifyWithScreenLock(l10n.lockBiometricReason);
      case ForgotPinChoice.erase:
        await _erase();
      case null:
        break;
    }
  }

  /// Erase and start over: "Delete everything?" once more, then Delete
  /// everything's own wipe. The journal goes first and the PIN only after
  /// it (decision 67), so a journal that can't be erased keeps its lock. The
  /// lock screen stays up until it's done; then onboarding starts, from O1.
  Future<void> _erase() async {
    final l10n = AppLocalizations.of(context);
    final services = context.services;
    final sure = await confirmDeleteEverything(
      context,
      body: l10n.lockEraseBody,
      idPrefix: 'lock-erase',
    );
    if (!sure || !mounted) return;
    widget.lock.setErasing(on: true);
    try {
      await wipeEverything(
        context,
        services,
        widget.session,
        idPrefix: 'lock-erase',
      );
    } finally {
      widget.lock.setErasing(on: false);
    }
  }

  Widget _enterPin(AppLocalizations l10n) {
    final lock = widget.lock;
    final wait = lock.waitRemaining;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PinPad(
          title: l10n.lockEnterPin,
          enabled: wait == null,
          error: wait != null ? l10n.lockWait(wait.inSeconds + 1) : _error,
          onDone: _pin,
          extra: lock.biometricsOn
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TestId(
                    'lock-biometrics',
                    button: true,
                    child: FutureBuilder(
                      future: _kind,
                      builder: (context, kind) => IconButton.filledTonal(
                        onPressed: _biometrics,
                        tooltip: lockUseLabel(l10n, kind.data),
                        icon: Icon(
                          kind.data == BiometricKind.faceId
                              ? Icons.face_rounded
                              : Icons.fingerprint_rounded,
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 16),
        TestId(
          'lock-forgot',
          button: true,
          child: TextButton(
            onPressed: _forgot,
            child: ButtonLabel(l10n.lockForgot),
          ),
        ),
      ],
    );
  }

  Widget _newPin(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      NewPinPad(onChosen: widget.lock.resetPin),
      const SizedBox(height: 16),
      TestId(
        'lock-new-pin-cancel',
        button: true,
        child: TextButton(
          onPressed: widget.lock.cancelResetPin,
          child: ButtonLabel(l10n.cancel),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return ListenableBuilder(
      listenable: widget.lock,
      builder: (context, _) {
        final lock = widget.lock;
        return Material(
          color: palette.background,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: SvgPicture.asset(palette.logoAsset, height: 56),
                    ),
                    const SizedBox(height: 24),
                    if (lock.erasing)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      )
                    else if (lock.mayResetPin)
                      _newPin(l10n)
                    else
                      _enterPin(l10n),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What the person picked in Forgot PIN's dialog.
enum ForgotPinChoice { screenLock, erase }

/// Forgot PIN's dialog (plan §3.11): with a phone screen lock, that first
/// (the filled button) and erase as the secondary text button; without one,
/// erase only, saying why (decision 71).
class ForgotPinDialog extends StatelessWidget {
  const ForgotPinDialog({super.key, required this.paths});

  final ForgotPinPaths paths;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final device = paths == ForgotPinPaths.deviceThenErase;
    return AlertDialog(
      // At the largest text sizes its words outgrow a small screen.
      scrollable: true,
      // Whole words at large text: a dialog is narrow.
      title: WholeWordsText(
        l10n.lockForgotTitle,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: device
            ? [
                Text(l10n.lockForgotBodyDevice),
                const SizedBox(height: 12),
                Text(l10n.lockForgotBodyErase),
              ]
            : [Text(l10n.lockForgotBodyEraseOnly)],
      ),
      // Stacked when they don't fit a line: the main way back on top.
      actionsOverflowDirection: VerticalDirection.up,
      actions: [
        TestId(
          'lock-forgot-cancel',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: ButtonLabel(l10n.cancel),
          ),
        ),
        TestId(
          'lock-forgot-erase',
          button: true,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(ForgotPinChoice.erase),
            child: ButtonLabel(l10n.lockForgotErase),
          ),
        ),
        if (device)
          TestId(
            'lock-forgot-device',
            button: true,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(ForgotPinChoice.screenLock),
              child: ButtonLabel(l10n.lockForgotUseDevice),
            ),
          ),
      ],
    );
  }
}

/// Wraps the app: the lock screen over everything while locked (and while
/// Forgot PIN's erase runs); a plain cover while the app is in the
/// background, so the app switcher's preview shows nothing. The lock belongs
/// to the phone, not to an account (decision 70).
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.lock,
    required this.session,
    required this.child,
  });

  final AppLock? lock;
  final AppSession session;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = widget.lock;
    // `on`, not `enabled`: a PIN still being stored counts (row 18).
    if (lock == null || !lock.on) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        setState(() => _covered = true);
      case AppLifecycleState.paused:
        lock.wentAway();
        setState(() => _covered = true);
      case AppLifecycleState.resumed:
        lock.cameBack();
        setState(() => _covered = false);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    if (lock == null) return widget.child;
    return ListenableBuilder(
      listenable: Listenable.merge([lock, widget.session]),
      builder: (context, _) {
        final showLock =
            lock.erasing || (lock.locked && widget.session.user != null);
        final covered = _covered && lock.on;
        final hidden = showLock || covered;
        return Stack(
          children: [
            // Under the lock or the cover the app is unreachable: not read
            // by TalkBack/VoiceOver, not tappable, not focusable (#50 review).
            ExcludeSemantics(
              excluding: hidden,
              child: IgnorePointer(
                ignoring: hidden,
                child: ExcludeFocus(excluding: hidden, child: widget.child),
              ),
            ),
            if (showLock)
              Positioned.fill(
                child: LockScreen(lock: lock, session: widget.session),
              )
            else if (covered)
              Positioned.fill(
                child: TestId.container(
                  'lock-cover',
                  child: ColoredBox(color: context.palette.background),
                ),
              ),
          ],
        );
      },
    );
  }
}
