import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_config.dart';
import 'sentry_scrubber.dart';

/// Routes the navigation breadcrumbs skip (push and pop): none yet.
const sentryIgnoredRoutes = <String>[];

/// The app's Sentry navigator observer ([hub] for tests).
SentryNavigatorObserver piggybowNavigatorObserver({Hub? hub}) =>
    SentryNavigatorObserver(hub: hub, ignoreRoutes: sentryIgnoredRoutes);

/// Every Sentry option Piggybow relies on, in one place (tested).
///
/// Privacy rules (product principle 1, decision 49): no user-typed text and no
/// user identity in error reports. So: no user context (never call
/// `Sentry.configureScope` / `setUser`), no release-health sessions (they
/// carry identity and bypass beforeSend), no screenshots, view hierarchy,
/// replay, logs or traces, and the scrubber on every event and breadcrumb.
///
/// Dart errors only in 1.0 (decision 114): events the NATIVE SDKs raise
/// themselves (a native crash, an Android ANR, an iOS watchdog kill or app
/// hang) never
/// pass through the Dart scrubber and can carry an installation id and
/// native context. So native crash handling, ANR and watchdog tracking and
/// native breadcrumbs are off; Dart exceptions are still reported (scrubbed).
void configureSentry(SentryFlutterOptions options, AppConfig config) {
  options
    ..dsn = config.sentryDsn
    ..environment = config.flavor.name
    ..sendDefaultPii = false
    ..enableAutoSessionTracking = false
    ..tracesSampleRate = 0
    ..attachScreenshot = false
    // ignore: experimental_member_use
    ..attachViewHierarchy = false
    ..enableLogs = false
    ..replay.sessionSampleRate = 0
    ..replay.onErrorSampleRate = 0
    ..enableNativeCrashHandling = false
    ..anrEnabled = false
    ..enableWatchdogTerminationTracking = false
    ..enableAppHangTracking =
        false // iOS app hangs (sentry-cocoa events)
    ..enableNdkScopeSync = false
    ..enableAutoNativeBreadcrumbs = false
    ..beforeSend = SentryScrubber.beforeSend
    ..beforeBreadcrumb = SentryScrubber.beforeBreadcrumb;
}
