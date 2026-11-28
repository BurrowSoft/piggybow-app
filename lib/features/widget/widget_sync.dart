// Keeps the home-screen widget's snapshot (feature 16) in step with the app.
// It's written at start, on resume, and whenever something the widget shows
// changes: the journal (entries, goals, the currency, Delete everything),
// the day, the app lock, Plus, the theme or the language.
//
// One write at a time, after a short quiet spell, and only when the snapshot
// changed. When the widget may have to show less (the lock turned on, Plus
// ending, Delete everything), there's no quiet spell: it's written at once.
// A write that fails waits for the next change: never break the app over
// the widget.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/device.dart' show settingsChannel;
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart';
import '../../theme/palettes.dart';
import '../plus/plus_entitlement.dart';
import 'widget_snapshot.dart';

/// Where the snapshot goes: the widget's own store on the phone.
abstract interface class WidgetBridge {
  /// Hands over [snapshotJson] (widget_snapshot.dart's map, as JSON).
  Future<void> update(String snapshotJson);
}

/// Android's widget, through the app's settings channel. Off Android, or on
/// a build whose Android side has no widget, it does nothing.
class ChannelWidgetBridge implements WidgetBridge {
  const ChannelWidgetBridge();

  /// The settings channel's method that stores and draws a snapshot.
  static const method = 'updateWidget';

  @override
  Future<void> update(String snapshotJson) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await const MethodChannel(
        settingsChannel,
      ).invokeMethod<void>(method, snapshotJson);
    } on MissingPluginException {
      // No widget on this build's Android side.
    }
  }
}

/// Plus as the widget reads it: active or not, from the entitlement (#45),
/// told whenever that changes. A build without Plus ([plus] null) is never
/// active.
class PlusActive implements ValueListenable<bool> {
  const PlusActive(this.plus);

  final PlusEntitlement? plus;

  @override
  bool get value => plus?.active ?? false;

  @override
  void addListener(VoidCallback listener) => plus?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => plus?.removeListener(listener);
}

class WidgetSync extends StatefulWidget {
  const WidgetSync({
    super.key,
    required this.enabled,
    required this.session,
    required this.services,
    required this.plusActive,
    this.bridge = const ChannelWidgetBridge(),
    this.quiet = const Duration(seconds: 1),
    required this.child,
  });

  /// Whether this build offers the widget (builds with Plus). Where it
  /// doesn't, nothing is ever written.
  final bool enabled;
  final AppSession session;
  final AppServices services;

  /// Whether Plus is active now: the widget is a Plus perk.
  final ValueListenable<bool> plusActive;
  final WidgetBridge bridge;

  /// How long things stay quiet before a write (a burst of changes, such as
  /// an import or Delete everything, writes once).
  final Duration quiet;
  final Widget child;

  @override
  State<WidgetSync> createState() => _WidgetSyncState();
}

class _WidgetSyncState extends State<WidgetSync> {
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  Timer? _turn;
  bool _running = false;
  bool _again = false;

  /// The last snapshot handed over, as JSON: the same one isn't sent twice.
  String? _last;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    widget.session.addListener(_schedule);
    _services.journal.addListener(_onJournal);
    _services.localDay.addListener(_schedule);
    _services.appLock?.addListener(_writeNow);
    widget.plusActive.addListener(_writeNow);
    _lifecycle = AppLifecycleListener(onResume: _schedule);
    _armTurn();
    _schedule();
  }

  @override
  void dispose() {
    if (widget.enabled) {
      widget.session.removeListener(_schedule);
      _services.journal.removeListener(_onJournal);
      _services.localDay.removeListener(_schedule);
      _services.appLock?.removeListener(_writeNow);
      widget.plusActive.removeListener(_writeNow);
    }
    _lifecycle?.dispose();
    _timer?.cancel();
    _turn?.cancel();
    super.dispose();
  }

  /// One timer to the next turn of the day in the phone's zone (00:00, 04:00
  /// and 22:00, as Home's: #62), set again at each, so the widget turns with
  /// the day even while the app stays open.
  void _armTurn() {
    _turn?.cancel();
    _turn = Timer(_services.clock.untilNextTurn(_services.localDay.zone), () {
      _schedule();
      _armTurn();
    });
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.quiet, _write);
  }

  /// No quiet spell when the widget may have to show less: the lock turned
  /// on, or Plus ending, has to reach the home screen before the app can be
  /// swiped away. (Turned off, or back, it's as quick, and as harmless.)
  void _writeNow() {
    _timer?.cancel();
    unawaited(_write());
  }

  /// Delete everything leaves a blank journal: written at once too. Any other
  /// change to the journal waits for the quiet spell.
  Future<void> _onJournal() async {
    var blank = false;
    try {
      blank = await _services.journal.isBlank();
    } on Object {
      // Read as not blank: the quiet spell, then the usual write.
    }
    if (!mounted) return;
    if (blank) {
      _writeNow();
    } else {
      _schedule();
    }
  }

  /// One write at a time; a change meanwhile writes once more afterwards.
  Future<void> _write() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final json = jsonEncode(await _snapshot());
        if (!mounted) return;
        if (json != _last) {
          await widget.bridge.update(json);
          _last = json;
        }
      } while (_again && mounted);
    } on Object {
      // A journal that can't be read, or a widget that can't be reached,
      // leaves the widget as it was. The next change, start or resume writes
      // again.
    } finally {
      _running = false;
    }
  }

  Future<Map<String, Object?>> _snapshot() async {
    final session = widget.session;
    final l10n = lookupAppLocalizations(session.locale);
    final plusActive = widget.plusActive.value;
    // The applied theme: Me → Theme's choice while Plus is active (#51), else
    // the default.
    final theme =
        appliedPalette(session.chosenPalette, plusActive: plusActive)?.name ??
        widgetDefaultTheme;
    // On, or being turned on: the widget never lags behind the lock.
    final lockOn = _services.appLock?.on ?? false;
    // Without Plus or with the lock on, there's nothing to read: decided at
    // once, so no journal read can hold it back (or fail it).
    final private = privateWidgetSnapshot(
      l10n: l10n,
      theme: theme,
      plusActive: plusActive,
      lockOn: lockOn,
    );
    if (private != null) return private;
    final store = _services.journal;
    // Home's first card: the oldest active goal (#47), not the one a new
    // save goes to by default.
    final goal = (await store.activeGoals()).firstOrNull;
    return widgetSnapshot(
      l10n: l10n,
      locale: session.device.localeName,
      theme: theme,
      plusActive: plusActive,
      lockOn: lockOn,
      today: _services.localDay.todayWire,
      currency: await store.currency(),
      entries: await store.entries(),
      goal: goal,
      goalProgressMinor: goal == null ? 0 : await store.goalProgress(goal),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
