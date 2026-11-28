import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';

/// Build-time configuration, read from `--dart-define-from-file=env/<flavor>.json`.
///
/// Only public values belong here (the Sentry DSN, page links, the pig tips
/// project's URL, publishable key and region). The journal has no server:
/// pig tips' project is the only backend, and it never sees the journal.
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
    this.plusRowsOwned = false,
    this.backupFileEnabled = true,
    this.privacyUrl = '',
    this.supportUrl = '',
    this.termsUrl = '',
    this.aiTipsEnabled = false,
    this.tipsUrl = '',
    this.tipsAnonKey = '',
    this.tipsRegion = '',
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
      // Plus stays out of every release build, Android and iPhone alike,
      // until its own release PR lifts this with its gates met (decision 79).
      // kReleaseMode is a compile-time constant: true there, so this is
      // false whatever the env file says.
      plusEnabled: const bool.fromEnvironment('PLUS_ENABLED') && !kReleaseMode,
      // Rows only: a debug build of staging, never a release or prod build
      // (kDebugMode is a compile-time false there).
      plusFakeStore:
          kDebugMode &&
          flavor == Flavor.staging &&
          const bool.fromEnvironment('PLUS_FAKE_STORE'),
      // Rows only, and only on top of the rows' store: the same guard, so
      // never a release or prod build either.
      plusRowsOwned:
          kDebugMode &&
          flavor == Flavor.staging &&
          const bool.fromEnvironment('PLUS_FAKE_STORE') &&
          const bool.fromEnvironment('PLUS_ROWS_OWNED'),
      // Never in a release build until the privacy policy and Help describe
      // the backup file (UX): kReleaseMode is a compile-time true there.
      backupFileEnabled:
          !kReleaseMode &&
          const bool.fromEnvironment('BACKUP_FILE', defaultValue: true),
      privacyUrl: const String.fromEnvironment('PRIVACY_URL'),
      supportUrl: const String.fromEnvironment('SUPPORT_URL'),
      termsUrl: const String.fromEnvironment('TERMS_URL'),
      // Pig tips: only with AI_TIPS_ENABLED, and never in a release build
      // until the release that ships them (with INTERNET) lifts this; the
      // Android build refuses it there too. kReleaseMode is a compile-time
      // constant, so this is false in release whatever the env file says.
      aiTipsEnabled: const bool.fromEnvironment('AI_TIPS_ENABLED') && !kReleaseMode,
      tipsUrl: const String.fromEnvironment('TIPS_URL'),
      tipsAnonKey: const String.fromEnvironment('TIPS_ANON_KEY'),
      tipsRegion: const String.fromEnvironment('TIPS_REGION'),
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

  /// Piggybow Plus (decision 79): its row in Me, the paywall and its
  /// features. Never in a release build yet (fromEnvironment above), and off
  /// in every env file (a test checks).
  final bool plusEnabled;

  /// PLUS_FAKE_STORE: a store with prices that never buys, for the
  /// tester's rows. Debug builds of staging only.
  final bool plusFakeStore;

  /// PLUS_ROWS_OWNED: that store reports an active yearly purchase, so the
  /// tester's rows see Plus on with nothing bought. Debug builds of staging
  /// only, and only with PLUS_FAKE_STORE.
  final bool plusRowsOwned;

  /// Feature 21, the backup file: Me's Back up and Restore, and O1's
  /// "Moving from another phone?". Off in every release build until the
  /// privacy policy and Help describe it; on in debug and profile builds
  /// (BACKUP_FILE=false turns it off there too).
  final bool backupFileEnabled;

  /// The website's privacy policy, support and terms of use pages, once
  /// each is live (PRIVACY_URL, SUPPORT_URL, TERMS_URL). Empty = no link
  /// anywhere in the app, so a link never opens a page that isn't there
  /// yet.
  final String privacyUrl;
  final String supportUrl;
  final String termsUrl;

  /// AI_TIPS_ENABLED: this build offers pig tips (in English, after the
  /// consent sheet). Off in prod's env file until the release that ships
  /// them.
  final bool aiTipsEnabled;

  /// The pig tips project (TIPS_URL, `https://<ref>.supabase.co`), its
  /// publishable key (TIPS_ANON_KEY: the `apikey` header, not a secret) and
  /// its region (TIPS_REGION, sent as `x-region`). Empty: no tips.
  final String tipsUrl;
  final String tipsAnonKey;
  final String tipsRegion;
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
