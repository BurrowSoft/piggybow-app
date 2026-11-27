import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_lock.dart';
import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart';
import '../../theme/theme.dart';

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

/// Over the whole app while locked: the PIN pad, biometrics when on (asked
/// for once as it shows), and "Forgot PIN?" = sign out (clears the lock).
/// An iPhone says Face ID or Touch ID, as the system does; everywhere else, the
/// general words. [kind] is null until the device has answered.
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

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock, required this.session});

  final AppLock lock;
  final AppSession session;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

enum _ForgotStep { none, explained, confirming }

class _LockScreenState extends State<LockScreen> {
  String? _error;
  Timer? _tick;

  /// An account with no email can't sign back in (decision 216), and nothing
  /// else can prove who holds the phone, so a forgotten PIN can't be reset:
  /// signing out is the only way past this screen, and it asks twice, here,
  /// since no Navigator sits above the lock.
  _ForgotStep _forgot = _ForgotStep.none;

  /// Sign out for good only answers after this, so no second tap of a double tap
  /// can reach it, wherever large text has put it.
  static const _confirmDelay = Duration(milliseconds: 800);
  Timer? _confirmTimer;
  bool _confirmReady = false;

  void _setForgot(_ForgotStep step) {
    _confirmTimer?.cancel();
    setState(() {
      _forgot = step;
      _confirmReady = false;
    });
    if (step == _ForgotStep.confirming) {
      _confirmTimer = Timer(_confirmDelay, () {
        if (mounted) setState(() => _confirmReady = true);
      });
    }
    // At large text the pad fills the screen: open on the explanation (triage 37).
    if (step == _ForgotStep.explained) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final at = _forgotAt.currentContext;
        if (at != null) unawaited(Scrollable.ensureVisible(at));
      });
    }
  }

  final _forgotAt = GlobalKey();

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
    _confirmTimer?.cancel();
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

  Future<void> _signOut() async {
    // Erase first: signing out switches the lock to no account
    // at once, so a clear() after it erased nothing of this account's, and
    // signing back in asked for the forgotten PIN again.
    await widget.lock.clear();
    await widget.session.signOut();
  }

  Widget _forgotNoEmail(AppLocalizations l10n) {
    // Sign out for good sits above the text, away from where Sign out anyway was,
    // whatever the text's length in each language (a test checks), and waits
    // for _confirmDelay. Keep trying is pinned below the scrolling part.
    if (_forgot == _ForgotStep.confirming) {
      return Column(
        key: const ValueKey('lock-no-email'),
        children: [
          TestId(
            'lock-sign-out-for-good',
            button: true,
            child: TextButton(
              onPressed: _confirmReady ? _signOut : null,
              child: Text(l10n.lockSignOutForGood, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.lockNoEmailConfirm, textAlign: TextAlign.center),
        ],
      );
    }
    return Column(
      key: const ValueKey('lock-no-email'),
      children: [
        Text(l10n.lockNoEmailExplain, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TestId(
          'lock-sign-out-anyway',
          button: true,
          child: TextButton(
            onPressed: () => _setForgot(_ForgotStep.confirming),
            child: Text(l10n.lockSignOutAnyway, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final noEmail = widget.session.user?.isAnonymous ?? false;
    final palette = context.palette;
    final wait = widget.lock.waitRemaining;
    return TestId.container(
      'lock-screen',
      // Above the app's Navigator (MaterialApp.builder), so no Overlay comes
      // from there; the biometrics button's tooltip needs one.
      child: Overlay.wrap(
        child: Material(
          color: palette.background,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_forgot != _ForgotStep.confirming) ...[
                    ExcludeSemantics(
                      child: SvgPicture.asset(palette.logoAsset, height: 56),
                    ),
                    const SizedBox(height: 24),
                    PinPad(
                      title: l10n.lockEnterPin,
                      enabled: wait == null,
                      error: wait != null
                          ? l10n.lockWait(wait.inSeconds + 1)
                          : _error,
                      onDone: _pin,
                      extra: widget.lock.biometricsOn
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TestId(
                                'lock-biometrics',
                                button: true,
                                child: FutureBuilder(
                                  future: _kind,
                                  builder: (context, kind) =>
                                      IconButton.filledTonal(
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
                    ],
                    if (noEmail && _forgot != _ForgotStep.none)
                      KeyedSubtree(
                        key: _forgotAt,
                        child: _forgotNoEmail(l10n),
                      )
                    else
                      TestId(
                        'lock-forgot',
                        button: true,
                        child: TextButton(
                          onPressed: noEmail
                              ? () => _setForgot(_ForgotStep.explained)
                              : _signOut,
                          child: Text(
                            noEmail ? l10n.lockForgotNoEmail : l10n.lockForgot,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                    ),
                  ),
                ),
                // Always on screen, at any text size: the safe way out.
                if (noEmail && _forgot != _ForgotStep.none)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: TestId(
                      'lock-keep-trying',
                      button: true,
                      child: FilledButton(
                        onPressed: () => _setForgot(_ForgotStep.none),
                        child: Text(
                          l10n.lockKeepTrying,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the app: the lock screen over everything while locked (signed in
/// only); a plain cover while the app is in the background, so the app
/// switcher's preview shows nothing; the lock cleared on sign-out.
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
  String? _uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uid = widget.session.user?.id;
    widget.session.addListener(_sessionChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  /// Each account keeps its own lock on this phone.
  /// Signing out keeps it (the same account back = the lock back); another
  /// account has its own (none at first); a deleted account's goes.
  /// "Forgot PIN?" erases it itself before signing out.
  void _sessionChanged() {
    final lock = widget.lock;
    final previous = _uid;
    final uid = widget.session.user?.id;
    if (uid == previous) return;
    _uid = uid;
    if (lock == null) return;
    final reason = widget.session.signedOutReason;
    if (previous != null &&
        uid == null &&
        (reason == SignedOutReason.deleted ||
            reason == SignedOutReason.accountGone)) {
      unawaited(lock.forget(previous));
    }
    unawaited(lock.switchUser(uid));
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
        final showLock = lock.locked && widget.session.user != null;
        // While another account's lock is read: covered, never the journal.
        final switching = lock.switching && widget.session.user != null;
        final hidden = showLock || switching || (_covered && lock.on);
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
            else if (switching || (_covered && lock.on))
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
