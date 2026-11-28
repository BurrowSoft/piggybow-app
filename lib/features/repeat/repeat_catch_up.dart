import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/clock.dart';
import '../../core/services.dart';

/// Keeps repeats caught up (JournalStore.catchUpRepeats, with LocalDay's
/// today): at app start, on every resume, when the phone's zone changes,
/// and at local midnight while the app is open. Behind the lock too, since
/// nothing shows until it's unlocked.
class RepeatCatchUp extends StatefulWidget {
  const RepeatCatchUp({
    super.key,
    required this.services,
    required this.child,
  });

  final AppServices services;
  final Widget child;

  @override
  State<RepeatCatchUp> createState() => _RepeatCatchUpState();
}

class _RepeatCatchUpState extends State<RepeatCatchUp> {
  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _services.localDay.addListener(_run);
    _lifecycle = AppLifecycleListener(onResume: _run);
    _run();
  }

  @override
  void dispose() {
    _services.localDay.removeListener(_run);
    _lifecycle.dispose();
    _midnight?.cancel();
    super.dispose();
  }

  void _run() => unawaited(_catchUp());

  Future<void> _catchUp() async {
    try {
      await _services.journal.catchUpRepeats(
        today: _services.localDay.todayWire,
      );
    } on Object catch (error, stack) {
      // Reported (crash reports scrub it); the next start, resume or
      // midnight tries again.
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'repeats'),
      );
    }
    if (mounted) _armMidnight();
  }

  /// Again just after the next local midnight (in the phone's zone, DST
  /// included).
  void _armMidnight() {
    _midnight?.cancel();
    final day = _services.localDay;
    final next = Clock.wallClock(addDays(day.today, 1), 0, day.zone);
    final wait = next.difference(_services.clock.nowUtc());
    _midnight = Timer(
      (wait.isNegative ? Duration.zero : wait) + const Duration(seconds: 1),
      _run,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
