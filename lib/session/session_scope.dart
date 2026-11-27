import 'package:flutter/widgets.dart';

import 'app_session.dart';

/// Makes the [AppSession] available to every screen.
class SessionScope extends InheritedNotifier<AppSession> {
  const SessionScope({
    super.key,
    required AppSession session,
    required super.child,
  }) : super(notifier: session);

  static AppSession of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<SessionScope>()
        : context.getInheritedWidgetOfExactType<SessionScope>();
    return scope!.notifier!;
  }
}

extension SessionContext on BuildContext {
  /// The session, rebuilding this widget when it changes.
  AppSession get session => SessionScope.of(this);

  /// The session for event handlers (no rebuild dependency).
  AppSession get readSession => SessionScope.of(this, listen: false);
}
