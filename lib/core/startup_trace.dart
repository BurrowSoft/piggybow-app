/// Where main() is in its start-up, step by step (the video build's splash
/// hang, 23 Nov: the process alive, the logo up, no screen, no log line).
///
/// main() names each step before it waits on it. In the store builds that's
/// all: one field written per step, nothing read, nothing logged. Only the
/// video build's own entry listens, so its watchdog can say which step
/// stalled or threw.
abstract final class StartupTrace {
  /// The step main() is on (or 'start' before the first).
  static String step = 'start';

  /// The video build's watchdog; null everywhere else.
  static void Function(String step)? listener;

  static void mark(String name) {
    step = name;
    listener?.call(name);
  }
}
