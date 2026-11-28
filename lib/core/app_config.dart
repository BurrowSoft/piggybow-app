import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';

/// Build-time configuration, read from `--dart-define-from-file=env/<flavor>.json`.
///
/// Only public values belong here (the Sentry DSN, page links). v0.1 has no
/// server: there is no backend URL or key at all.
class AppConfig {
  const AppConfig({
    required this.flavor,
    this.sentryDsn = '',
    this.disableAnimations = false,
    this.fakeNow,
    this.thaiOffered = false,
    this.frOffered = false,
    this.esOffered = false,
    this.ptBrOffered = false,
    this.deOffered = false,
    this.itOffered = false,
    this.appLockEnabled = true,
    this.plusEnabled = false,
    this.plusFakeStore = false,
    this.backupFileEnabled = true,
    this.privacyUrl = '',
    this.supportUrl = '',
  });

  factory AppConfig.fromEnvironment() {
    final flavor = Flavor.resolve(
      nativeFlavor: appFlavor,
      envFlavor: const String.fromEnvironment('FLAVOR'),
    );
    final isProd = flavor == Flavor.prod;
    return AppConfig(
      flavor: flavor,
      sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
      // Test hooks are ignored in prod builds, whatever the env file says.
      disableAnimations:
          !isProd && const bool.fromEnvironment('DISABLE_ANIMATIONS'),
      thaiOffered: const bool.fromEnvironment('THAI_OFFERED'),
      frOffered: const bool.fromEnvironment('FR_OFFERED'),
      esOffered: const bool.fromEnvironment('ES_OFFERED'),
      ptBrOffered: const bool.fromEnvironment('PT_BR_OFFERED'),
      deOffered: const bool.fromEnvironment('DE_OFFERED'),
      itOffered: const bool.fromEnvironment('IT_OFFERED'),
      // The app lock is in v0.1 (plan P12): on in every build unless an env
      // file says otherwise, and none does (a test checks).
      appLockEnabled: const bool.fromEnvironment(
        'APP_LOCK_ENABLED',
        defaultValue: true,
      ),
      plusEnabled: const bool.fromEnvironment('PLUS_ENABLED'),
      // Rows only: a debug build of staging, never a release or prod build
      // (kDebugMode is a compile-time false there).
      plusFakeStore:
          kDebugMode &&
          flavor == Flavor.staging &&
          const bool.fromEnvironment('PLUS_FAKE_STORE'),
      // Never in a release build until the privacy policy and Help describe
      // the backup file (UX): kReleaseMode is a compile-time true there.
      backupFileEnabled:
          !kReleaseMode &&
          const bool.fromEnvironment('BACKUP_FILE', defaultValue: true),
      privacyUrl: const String.fromEnvironment('PRIVACY_URL'),
      supportUrl: const String.fromEnvironment('SUPPORT_URL'),
      fakeNow: isProd
          ? null
          : DateTime.tryParse(const String.fromEnvironment('FAKE_NOW')),
    );
  }

  final Flavor flavor;

  /// Empty (dev, CI, tests, and v0.1 until a Sentry project exists): Sentry
  /// stays off entirely.
  final String sentryDsn;

  /// Staging flavor: page transitions off so Maestro flows don't wait on them.
  final bool disableAnimations;

  /// Staging flavor: a fixed "now" (ISO-8601 with offset) for deterministic dates.
  final DateTime? fakeNow;

  /// Languages besides English: each one is off until its translation is
  /// reviewed (v0.1 ships English only).
  final bool thaiOffered;
  final bool frOffered;
  final bool esOffered;
  final bool ptBrOffered;
  final bool deOffered;
  final bool itOffered;

  /// The draft languages and whether each is offered yet.
  Map<String, bool> get _drafts => {
    'th': thaiOffered,
    'fr': frOffered,
    'es': esOffered,
    'pt': ptBrOffered,
    'de': deOffered,
    'it': itOffered,
  };

  /// The UI languages the pickers offer, English first: every bundled one,
  /// minus each draft language until it's reviewed. A bundled language with
  /// no switch here is never offered.
  List<String> shippedLocaleCodes(Iterable<String> bundled) => [
    'en',
    for (final code in bundled)
      if (code != 'en' && (_drafts[code] ?? false)) code,
  ];

  /// App lock (PIN or the phone's biometrics): the lock screen and its
  /// settings.
  final bool appLockEnabled;

  /// Piggybow Plus: the store plumbing only (no Plus UI in v0.1). Off
  /// everywhere.
  final bool plusEnabled;

  /// PLUS_FAKE_STORE: a store with a price that never buys, for the
  /// tester's rows. Debug builds of staging only.
  final bool plusFakeStore;

  /// Feature 21, the backup file: Me's Back up and Restore, and O1's
  /// "Moving from another phone?". Off in every release build until the
  /// privacy policy and Help describe it; on in debug and profile builds
  /// (BACKUP_FILE=false turns it off there too).
  final bool backupFileEnabled;

  /// The website's privacy policy and support pages, once each is live
  /// (PRIVACY_URL, SUPPORT_URL). Empty = no link anywhere in the app, so a
  /// link never opens a page that isn't there yet.
  final String privacyUrl;
  final String supportUrl;
}

enum Flavor {
  dev,
  staging,
  prod;

  /// Unknown or missing values fall back to dev, never to prod.
  static Flavor parse(String value) =>
      Flavor.values.firstWhere((f) => f.name == value, orElse: () => dev);

  /// The native build flavor (`--flavor`) wins. A different FLAVOR in the env
  /// file means the wrong env file was passed (e.g. `--flavor prod` with
  /// env/staging.json): fail at startup instead of shipping test hooks.
  static Flavor resolve({String? nativeFlavor, required String envFlavor}) {
    if (nativeFlavor == null) return parse(envFlavor);
    if (envFlavor.isNotEmpty && envFlavor != nativeFlavor) {
      throw StateError(
        'FLAVOR "$envFlavor" does not match --flavor "$nativeFlavor". '
        'Pass --dart-define-from-file=env/$nativeFlavor.json.',
      );
    }
    return parse(nativeFlavor);
  }
}

/// The build's configuration, for screens that show or hide by it (Me:
/// the crash-report line, the policy and help links, the app lock).
class ConfigScope extends InheritedWidget {
  const ConfigScope({super.key, required this.config, required super.child});

  final AppConfig config;

  static AppConfig of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConfigScope>()!.config;

  @override
  bool updateShouldNotify(ConfigScope old) => old.config != config;
}
