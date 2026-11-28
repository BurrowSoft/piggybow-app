import 'package:flutter/foundation.dart';

/// Consent kinds as stored server-side (`consents.kind`).
enum ConsentKind {
  privacy('privacy'),
  terms('terms'),
  ai('ai'),
  age18('age_18');

  const ConsentKind(this.wire);
  final String wire;
}

@immutable
class ConsentItem {
  const ConsentItem(
    this.kind,
    this.version, {
    this.granted = true,
    this.locale,
  });

  final ConsentKind kind;
  final String version;
  final bool granted;

  /// The app's language when this was agreed to (decision 224). `es` before the
  /// date Spanish legal text went live (decisions log) means English pages. A
  /// record of how it was shown, so not part of what makes two items equal.
  final String? locale;

  Map<String, Object> toJson() => {
    'kind': kind.wire,
    'version': version,
    'granted': granted,
    'locale': ?locale,
  };

  @override
  bool operator ==(Object other) =>
      other is ConsentItem &&
      other.kind == kind &&
      other.version == version &&
      other.granted == granted;

  @override
  int get hashCode => Object.hash(kind, version, granted);
}

/// AI tone (`user_settings.tone`).
enum Tone { warm, direct, brief }

/// Focus areas (`user_settings.focus_areas`); [id] is the stored value and
/// the Semantics id suffix (`setup-focus-<id>`).
enum FocusArea {
  sleep('sleep'),
  stress('stress'),
  work('work'),
  study('study'),
  relationships('relationships'),
  family('family'),
  health('health'),
  selfEsteem('self_esteem');

  const FocusArea(this.id);
  final String id;
}

@immutable
class ReminderTime {
  const ReminderTime(this.hour, this.minute);

  final int hour;
  final int minute;

  /// Piggybow's evening nudge (plan §3.10).
  static const defaultTime = ReminderTime(20, 0);

  /// `HH:MM`, as Postgres `time` accepts it.
  String get wire =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

@immutable
class SetupChoices {
  const SetupChoices({
    this.focusAreas = const {},
    this.tone = Tone.warm,
    this.reminderOn = true,
    this.reminderTime = ReminderTime.defaultTime,
  });

  final Set<FocusArea> focusAreas;
  final Tone tone;
  final bool reminderOn;
  final ReminderTime reminderTime;
}

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.isAnonymous = false,
  });

  final String id;

  /// '' for an anonymous user.
  final String email;

  /// Started without an email (no-signup-start, decision 216): only this
  /// phone can use the account until an email is added.
  final bool isAnonymous;
}

/// The v2 notice slugs this build has words for (UX, 23 Nov): "ai" only.
const noticeSlugs = {'ai'};

/// The slug of a v2 notice id ("2026-12-01-ai" → "ai") when this build has
/// words for it, else null (the web's policyNoticeSlug).
String? policyNoticeSlug(String id) {
  final slug = RegExp(r'^\d{4}-\d{2}-\d{2}-(.+)$').firstMatch(id)?[1];
  return slug != null && noticeSlugs.contains(slug) ? slug : null;
}

/// What the app needs to know about the signed-in account to route it.
@immutable
class AccountState {
  const AccountState({
    required this.consents,
    required this.onboarded,
    this.timeZone = 'UTC',
    this.country,
    this.locale,
    this.reminderOn = true,
    this.reminderTime = ReminderTime.defaultTime,
    this.creditBalance = 0,
    this.aiAvailable = false,
    this.aiEnabled = false,
    this.policyNoticeId,
    this.policyNoticeSeen,
    this.policyNoticeV2Id,
    this.policyNoticeV2Seen,
    this.tone = Tone.warm,
    this.focusAreas = const {},
  });

  /// The latest consent per kind.
  final Map<ConsentKind, ConsentItem> consents;

  /// `profiles.onboarded_at` is set (the setup step was completed).
  final bool onboarded;

  /// `profiles.time_zone` (IANA): defines the user's "today".
  final String timeZone;

  /// `profiles.country` (ISO 3166-1 alpha-2), or null.
  final String? country;

  /// `profiles.locale`: the account's saved language, or null if unknown.
  final String? locale;

  /// `user_settings.reminder_on` / `reminder_time` (Me → Daily reminder).
  final bool reminderOn;
  final ReminderTime reminderTime;

  /// AI credits (`get_my_credits().balance`): Delete account warns when > 0.
  final int creditBalance;

  /// `get_me().ai_available`: the global AI switch (decision 110).
  final bool aiAvailable;

  /// `user_settings.ai_enabled` (Me → AI).
  final bool aiEnabled;

  /// `get_me().policy_notice_id` (019): the privacy-change notice that's out,
  /// or null (none).
  final String? policyNoticeId;

  /// `user_settings.policy_notice_seen`: the notice this person dismissed.
  final String? policyNoticeSeen;

  /// A notice is out that this person hasn't dismissed (as the web's
  /// policyNoticeToShow: an empty id is none).
  bool get policyNoticeDue {
    final id = policyNoticeId;
    return id != null && id.isNotEmpty && id != policyNoticeSeen;
  }

  /// `get_me().policy_notice_v2_id` (043): every notice after Plus's,
  /// `YYYY-MM-DD-<slug>` (UX, 23 Nov; the web reads the same field).
  final String? policyNoticeV2Id;

  /// `settings.policy_notice_v2_seen`: the v2 notice this person dismissed.
  final String? policyNoticeV2Seen;

  /// A v2 notice is out, not dismissed, and its slug is one this build has
  /// words for ([noticeSlugs]); any other shows nothing (as the web's
  /// policyNoticeToShow).
  bool get policyNoticeV2Due {
    final id = policyNoticeV2Id;
    return id != null && id.isNotEmpty && id != policyNoticeV2Seen && policyNoticeSlug(id) != null;
  }

  /// `user_settings.tone` / `focus_areas` (Me → AI).
  final Tone tone;
  final Set<FocusArea> focusAreas;

  /// AI consent at [version], granted (the latest record).
  bool hasAiConsent(String version) {
    final c = consents[ConsentKind.ai];
    return c != null && c.granted && c.version == version;
  }

  /// Reflect is shown only with all three (reflect.md "Gate").
  bool aiUsable(String consentVersion) =>
      aiAvailable && aiEnabled && hasAiConsent(consentVersion);

  /// The device copy for an offline start (decision 93), per user id.
  Map<String, Object?> toCacheJson() => {
    'consents': [for (final c in consents.values) c.toJson()],
    'onboarded': onboarded,
    'timeZone': timeZone,
    'country': country,
    'locale': locale,
    'reminderOn': reminderOn,
    'reminderTime': reminderTime.wire,
    'creditBalance': creditBalance,
    'aiAvailable': aiAvailable,
    'aiEnabled': aiEnabled,
    'policyNoticeId': policyNoticeId,
    'policyNoticeSeen': policyNoticeSeen,
    'policyNoticeV2Id': policyNoticeV2Id,
    'policyNoticeV2Seen': policyNoticeV2Seen,
    'tone': tone.name,
    'focusAreas': [for (final f in focusAreas) f.id],
  };

  /// Null when the copy is unreadable (an older or damaged one): the app
  /// then starts as without a copy.
  static AccountState? fromCacheJson(Map<String, dynamic> j) {
    try {
      final time = (j['reminderTime'] as String).split(':');
      return AccountState(
        consents: {
          for (final c in (j['consents'] as List).cast<Map>())
            for (final kind in ConsentKind.values)
              if (kind.wire == c['kind'])
                kind: ConsentItem(
                  kind,
                  c['version'] as String,
                  granted: c['granted'] as bool,
                ),
        },
        onboarded: j['onboarded'] as bool,
        timeZone: j['timeZone'] as String,
        country: j['country'] as String?,
        locale: j['locale'] as String?,
        reminderOn: j['reminderOn'] as bool,
        reminderTime: ReminderTime(int.parse(time[0]), int.parse(time[1])),
        creditBalance: (j['creditBalance'] as num).toInt(),
        aiAvailable: j['aiAvailable'] as bool,
        aiEnabled: j['aiEnabled'] as bool,
        // Absent in a copy from an older build: no notice until get_me says.
        policyNoticeId: j['policyNoticeId'] as String?,
        policyNoticeSeen: j['policyNoticeSeen'] as String?,
        // Absent in a copy from a build before 1.4.2: none until get_me says.
        policyNoticeV2Id: j['policyNoticeV2Id'] as String?,
        policyNoticeV2Seen: j['policyNoticeV2Seen'] as String?,
        tone: Tone.values.byName(j['tone'] as String),
        focusAreas: {
          for (final id in (j['focusAreas'] as List).cast<String>())
            for (final f in FocusArea.values)
              if (f.id == id) f,
        },
      );
    } on Object {
      return null;
    }
  }

  AccountState copyWith({
    Map<ConsentKind, ConsentItem>? consents,
    String? timeZone,
    String? country,
    bool clearCountry = false,
    String? locale,
    bool? reminderOn,
    ReminderTime? reminderTime,
    int? creditBalance,
    bool? aiEnabled,
    String? policyNoticeSeen,
    String? policyNoticeV2Seen,
    Tone? tone,
    Set<FocusArea>? focusAreas,
  }) => AccountState(
    consents: consents ?? this.consents,
    onboarded: onboarded,
    timeZone: timeZone ?? this.timeZone,
    country: clearCountry ? null : (country ?? this.country),
    locale: locale ?? this.locale,
    reminderOn: reminderOn ?? this.reminderOn,
    reminderTime: reminderTime ?? this.reminderTime,
    creditBalance: creditBalance ?? this.creditBalance,
    aiAvailable: aiAvailable,
    aiEnabled: aiEnabled ?? this.aiEnabled,
    policyNoticeId: policyNoticeId,
    policyNoticeSeen: policyNoticeSeen ?? this.policyNoticeSeen,
    policyNoticeV2Id: policyNoticeV2Id,
    policyNoticeV2Seen: policyNoticeV2Seen ?? this.policyNoticeV2Seen,
    tone: tone ?? this.tone,
    focusAreas: focusAreas ?? this.focusAreas,
  );

  /// Privacy, terms and 18+ are granted at the given current versions.
  bool hasRequiredConsents(Map<ConsentKind, String> requiredVersions) =>
      requiredVersions.entries.every((e) {
        final c = consents[e.key];
        return c != null && c.granted && c.version == e.value;
      });
}

/// Errors the auth and account repositories raise. [code] matches the
/// server's snake_case codes (supabase/contracts/errors.md).
class AppFailure implements Exception {
  const AppFailure(this.code);

  final String code;

  static const emailTaken = AppFailure('email_taken');
  static const badCredentials = AppFailure('bad_credentials');
  static const emailNotConfirmed = AppFailure('email_not_confirmed');
  static const offline = AppFailure('offline');
  static const generic = AppFailure('generic');
  static const rateLimited = AppFailure('rate_limited');

  /// 012: an insert-only check-in met one saved elsewhere (decision 209).
  static const checkInExists = AppFailure('check_in_exists');

  /// The server's code for a call without a valid session (RPCs).
  static const notAuthenticated = AppFailure('not_authenticated');

  /// The account no longer exists (deleted elsewhere): decision 68.
  static const accountGone = AppFailure('account_gone');

  /// The session was revoked (e.g. a password reset elsewhere) but the
  /// account still exists: decision 70.
  static const sessionEnded = AppFailure('session_ended');

  @override
  bool operator ==(Object other) => other is AppFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'AppFailure($code)';
}
