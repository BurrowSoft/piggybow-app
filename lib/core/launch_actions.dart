import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

import 'device.dart';

/// The home-screen shortcut and widget (Android): "Add a spend" starts the
/// app, or brings it back, with an action MainActivity.kt keeps until
/// Flutter takes it. The shell answers it with Home and the Add sheet on
/// Spent. From the widget (its "+" or the widget itself), the app lock, if
/// on, comes back first.
abstract class LaunchActions {
  /// An "Add a spend" not yet answered.
  ValueListenable<bool> get addSpendPending;

  /// Answers it: true once per use of the shortcut.
  bool takeAddSpend();

  /// Reads the action the app was started with, and hears later ones.
  Future<void> listen();
}

class PlatformLaunchActions implements LaunchActions {
  PlatformLaunchActions({this.onFromWidget});

  /// The app opened from the home-screen widget: main.dart locks the app
  /// lock now, so the lock screen always comes first (UX).
  final VoidCallback? onFromWidget;

  final _addSpend = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get addSpendPending => _addSpend;

  @override
  bool takeAddSpend() {
    if (!_addSpend.value) return false;
    _addSpend.value = false;
    return true;
  }

  @override
  Future<void> listen() async {
    const channel = MethodChannel(settingsChannel);
    // The app already open: MainActivity says one is waiting.
    channel.setMethodCallHandler((call) async {
      if (call.method == launchActionMethod) await _take(channel);
    });
    // The app started from the shortcut.
    await _take(channel);
  }

  Future<void> _take(MethodChannel channel) async {
    try {
      final action = await channel.invokeMethod<String>(takeLaunchActionMethod);
      if (action == widgetAddSpendAction || action == widgetOpenAction) {
        onFromWidget?.call();
      }
      if (action == addSpendAction || action == widgetAddSpendAction) {
        _addSpend.value = true;
      }
    } on Object {
      // Nothing to read where there's no MainActivity (the iPhone, for now).
    }
  }
}
