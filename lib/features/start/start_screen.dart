import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/button_label.dart';
import '../../core/failure_text.dart';
import '../../core/semantics_id.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart';
import '../../session/session_scope.dart';

/// While a stored session is restored: a spinner, "Taking longer than
/// usual…" after 3 s, and after a failure or ~10 s the error + Try again.
/// The stored session is kept throughout (never sign out on an outage).
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  static const slowAfter = Duration(seconds: 3);

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _slow = false;
    _timer = Timer(StartScreen.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tryAgain() {
    setState(_startTimer);
    unawaited(context.readSession.restore());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = context.session;
    final failure = session.startState == StartState.failed
        ? session.startFailure
        : null;

    return TestId.container(
      'start-screen',
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failure == null) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    // Live regions: screen readers announce them on appear.
                    if (_slow)
                      TestId(
                        'start-slow',
                        child: Semantics(
                          liveRegion: true,
                          child: Text(l10n.slowLoading),
                        ),
                      ),
                  ] else ...[
                    TestId(
                      'start-error',
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          failureText(l10n, failure),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TestId(
                      'start-retry',
                      button: true,
                      child: FilledButton(
                        onPressed: _tryAgain,
                        child: ButtonLabel(l10n.tryAgain),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
