import 'package:sentry_flutter/sentry_flutter.dart';

/// Strips anything a user could have typed from Sentry events and breadcrumbs.
///
/// Rule (product principle 1): no user-typed text in error reports, ever. So
/// we keep exception types, stack traces and machine error codes, and drop
/// free-text messages, request data, user info and non-allowlisted breadcrumbs.
abstract final class SentryScrubber {
  /// The shape of a machine code (lowercase, digits, `_`).
  static final _codeShape = RegExp(r'^[a-z0-9_]{1,64}$');

  /// The app's error codes (AppFailure; supabase/contracts/errors.md): kept
  /// even when a single plain word.
  static const _knownCodes = {
    'offline',
    'generic',
    'account_gone',
    'session_ended',
    'not_authenticated',
    'bad_credentials',
    'email_taken',
    'email_not_confirmed',
    'rate_limited',
    'invalid_value',
    'date_in_future',
    'stale_write',
    'not_found',
    'entry_empty',
    'entry_too_long',
    'ai_disabled',
    'ai_consent_required',
    'daily_limit',
    'ai_budget_exhausted',
    'in_progress',
    'reflect_failed',
    'report_failed',
    'not_enough',
    'report_exists',
    'duplicate',
  };

  /// A value is a machine code only if it is a known code, or code-shaped
  /// AND has a digit or `_` (`23505`, `some_code`): a single plain word like
  /// "tired" could be what the user typed (#Sentry review M2).
  static bool isSafeCode(String value) =>
      _knownCodes.contains(value) ||
      (_codeShape.hasMatch(value) && RegExp(r'[0-9_]').hasMatch(value));

  /// Tags the SDK sets itself; any other tag is dropped (L1).
  static const _allowedTags = {'event.origin', 'event.environment'};

  static const _allowedBreadcrumbCategories = {
    'navigation',
    'app.lifecycle',
    'device.orientation',
    'device.event',
    'ui.lifecycle',
  };

  /// Device/runtime facts only. Everything else is dropped, including
  /// `flutter_error_details` (its widget-tree dump can hold on-screen text)
  /// and any context a future SDK version adds.
  static const _allowedContexts = {
    'device',
    'os',
    'runtime',
    'app',
    'culture',
    'gpu',
    'flutter_context',
  };

  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    for (final key in event.contexts.keys.toList()) {
      if (!_allowedContexts.contains(key)) event.contexts.remove(key);
    }
    // The app context's view names: ids and dates out (L2).
    final app = event.contexts.app;
    final views = app?.viewNames;
    if (app != null && views != null) {
      app.viewNames = [for (final v in views) normalizeRoute(v)];
    }
    final tags = event.tags;
    if (tags != null) {
      event.tags = {
        for (final e in tags.entries)
          if (_allowedTags.contains(e.key)) e.key: e.value,
      };
    }
    event.user = null;
    event.request = null;
    // ignore: deprecated_member_use
    event.extra = null;
    event.serverName = null;
    event.message = null;
    event.breadcrumbs = event.breadcrumbs
        ?.map(scrubBreadcrumb)
        .whereType<Breadcrumb>()
        .toList();
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      final value = exception.value;
      if (value != null && !isSafeCode(value)) {
        exception.value = '[redacted]';
      }
      exception.throwable = null;
      // Mechanism data/description can echo the error's text (L1).
      final mechanism = exception.mechanism;
      if (mechanism != null) {
        mechanism.data = null;
        mechanism.description = null;
      }
    }
    return event;
  }

  static Breadcrumb? beforeBreadcrumb(Breadcrumb? crumb, Hint hint) =>
      crumb == null ? null : scrubBreadcrumb(crumb);

  static Breadcrumb? scrubBreadcrumb(Breadcrumb crumb) {
    if (!_allowedBreadcrumbCategories.contains(crumb.category)) return null;
    crumb.message = null;
    // Navigation crumbs keep only route names (no arguments, no query strings).
    final data = crumb.data;
    if (data != null) {
      crumb.data = {
        for (final key in const ['from', 'to', 'state'])
          if (data[key] is String) key: normalizeRoute(data[key] as String),
      };
    }
    return crumb;
  }

  // A day (/timeline/day/2026-10-02) or a month (/insights/share/2026-10).
  static final _date = RegExp(r'^\d{4}-\d{2}(-\d{2})?$');
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// A route as a pattern: no query or fragment, a calendar date segment as
  /// `[date]` and an id segment as `[id]` (which day or entry is personal;
  /// M1). `/timeline/day/2026-10-02` → `/timeline/day/[date]`.
  static String normalizeRoute(String route) => route
      .split(RegExp(r'[?#]'))
      .first
      .split('/')
      .map(
        (s) => _date.hasMatch(s)
            ? '[date]'
            : _uuid.hasMatch(s)
            ? '[id]'
            : s,
      )
      .join('/');
}
