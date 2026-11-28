import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

import 'device.dart';

/// The home-screen shortcut (Android): "Add a spend" starts the app, or
/// brings it back, with an action MainActivity.kt keeps until Flutter takes
/// it. The shell answers it with Home and the Add sheet on Spent.
abstract class LaunchActions {
  /// An "Add a spend" not yet answered.
  ValueListenable<bool> get addSpendPending;

  /// Answers it: true once per use of the shortcut.
  bool takeAddSpend();

  /// Reads the action the app was started with, and hears later ones.
  Future<void> listen();
}

class PlatformLaunchActions implements LaunchActions {
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
      if (await channel.invokeMethod<String>(takeLaunchActionMethod) == addSpendAction) {
        _addSpend.value = true;
      }
    } on Object {
      // Nothing to read where there's no MainActivity (the iPhone, for now).
    }
  }
}
