// Keeps the home-screen widget's snapshot (feature 16) in step with the app.
// It's written at start, on resume, and whenever something the widget shows
// changes: the journal (entries, goals, the currency, Delete everything),
// the day, the app lock, Plus, the theme or the language.
//
// One write at a time, after a short quiet spell, and only when the snapshot
// changed. A write that fails waits for the next change: never break the
// app over the widget.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/device.dart' show settingsChannel;
import '../../core/services.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../session/app_session.dart';
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
  late final List<Listenable> _sources;
  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  bool _running = false;
  bool _again = false;

  /// The last snapshot handed over, as JSON: the same one isn't sent twice.
  String? _last;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _sources = [
      widget.session,
      _services.journal,
      _services.localDay,
      ?_services.appLock,
      widget.plusActive,
    ];
    if (!widget.enabled) return;
    for (final source in _sources) {
      source.addListener(_schedule);
    }
    _lifecycle = AppLifecycleListener(onResume: _schedule);
    _schedule();
  }

  @override
  void dispose() {
    if (widget.enabled) {
      for (final source in _sources) {
        source.removeListener(_schedule);
      }
    }
    _lifecycle?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.quiet, _write);
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
    final store = _services.journal;
    final goal = await store.activeGoal();
    return widgetSnapshot(
      l10n: lookupAppLocalizations(session.locale),
      locale: session.device.localeName,
      theme: session.palette?.name ?? widgetDefaultTheme,
      plusActive: widget.plusActive.value,
      // On, or being turned on: the widget never lags behind the lock.
      lockOn: _services.appLock?.on ?? false,
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
