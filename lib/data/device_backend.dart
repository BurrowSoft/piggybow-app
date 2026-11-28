import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/local_prefs.dart';
import 'models.dart';
import 'repositories.dart';

/// v0.1's backend: this phone only (no account, no server). A device account
/// stands in for the server's: an id made on the first start, and the
/// settings the session reads (language, time zone, reminder). It's what the
/// session signs in as, so the app's account-shaped code runs unchanged; the
/// person never sees an account.
///
/// Email paths (sign up, sign in, add an email, passwords) don't exist on the
/// phone: they throw [UnsupportedError] if anything ever reaches them.
class DeviceBackend implements AuthRepository, AccountRepository {
  DeviceBackend._(this._prefs, this._account, this._newId, this._now);

  /// Opens the device account, making it on the first start, and records
  /// [timeZone] (the phone's own zone right now: "today" follows the phone).
  /// Until onboarding exists, a new account starts as set up, with the
  /// reminder off.
  static Future<DeviceBackend> open({
    required LocalPrefs prefs,
    required String timeZone,
    String locale = 'en',
    String? country,
    String Function()? newId,
    DateTime Function()? now,
  }) async {
    final makeId = newId ?? () => const Uuid().v4();
    var account = _DeviceAccount.decode(prefs.deviceAccount);
    if (account == null) {
      account = _DeviceAccount(
        id: makeId(),
        createdAt: (now ?? DateTime.now)().toUtc(),
        timeZone: timeZone,
        locale: locale,
        country: country,
        onboarded: true,
        reminderOn: false,
        reminderTime: ReminderTime.defaultTime,
        consents: const {},
      );
      await prefs.setDeviceAccount(account.encode());
    } else if (account.timeZone != timeZone) {
      account = account.copyWith(timeZone: timeZone);
      await prefs.setDeviceAccount(account.encode());
    }
    return DeviceBackend._(prefs, account, makeId, now ?? DateTime.now);
  }

  final LocalPrefs _prefs;
  final String Function() _newId;
  final DateTime Function() _now;
  _DeviceAccount? _account;

  _DeviceAccount get _current => _account ?? (throw AppFailure.accountGone);

  /// Delete everything (plan §3.8): a fresh device account with a new id,
  /// as on a first start. The prefs were cleared first.
  Future<void> startOver({required String timeZone, String? country}) =>
      _save(
        _DeviceAccount(
          id: _newId(),
          createdAt: _now().toUtc(),
          timeZone: timeZone,
          locale: 'en',
          country: country,
          onboarded: true,
          reminderOn: false,
          reminderTime: ReminderTime.defaultTime,
          consents: const {},
        ),
      );

  Future<void> _save(_DeviceAccount account) async {
    _account = account;
    await _prefs.setDeviceAccount(account.encode());
  }

  // ------------------------------------------------------------------ auth

  @override
  AuthUser? get currentUser {
    final a = _account;
    return a == null ? null : AuthUser(id: a.id, email: '', isAnonymous: true);
  }

  @override
  Stream<void> get sessionDroppedElsewhere => const Stream.empty();

  @override
  Stream<void> get sessionRefreshed => const Stream.empty();

  /// A new device account (after Delete): the profile's language, zone,
  /// country and consents. The existing one when there is one.
  @override
  Future<AuthUser> signInAnonymously({required SignupProfile profile}) async {
    if (_account == null) {
      await _save(
        _DeviceAccount(
          id: _newId(),
          createdAt: DateTime.now().toUtc(),
          timeZone: profile.timeZone,
          locale: profile.locale,
          country: profile.country,
          onboarded: false,
          reminderOn: false,
          reminderTime: ReminderTime.defaultTime,
          consents: {for (final c in profile.consents) c.kind: c},
        ),
      );
    }
    return currentUser!;
  }

  @override
  Future<AuthUser?> reloadUser() async => currentUser;

  @override
  Future<void> updateLanguage(String locale) async =>
      _save(_current.copyWith(locale: locale));

  /// Nothing to sign out of: the data stays on the phone.
  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required SignupProfile profile,
  }) => throw UnsupportedError('no accounts in v0.1');

  @override
  Future<void> addEmail(String email) =>
      throw UnsupportedError('no accounts in v0.1');

  @override
  Future<void> setPassword(String password) =>
      throw UnsupportedError('no accounts in v0.1');

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      throw UnsupportedError('no accounts in v0.1');

  @override
  Future<void> resendConfirmation(String email) =>
      throw UnsupportedError('no accounts in v0.1');

  @override
  Future<void> sendPasswordReset(String email) =>
      throw UnsupportedError('no accounts in v0.1');

  // --------------------------------------------------------------- account

  @override
  Future<AccountState> load() async {
    final a = _current;
    return AccountState(
      consents: Map.unmodifiable(a.consents),
      onboarded: a.onboarded,
      timeZone: a.timeZone,
      country: a.country,
      locale: a.locale,
      reminderOn: a.reminderOn,
      reminderTime: a.reminderTime,
    );
  }

  @override
  Future<void> recordConsents(List<ConsentItem> consents) async => _save(
    _current.copyWith(
      consents: {..._current.consents, for (final c in consents) c.kind: c},
    ),
  );

  @override
  Future<void> completeSetup(SetupChoices choices) async => _save(
    _current.copyWith(
      onboarded: true,
      reminderOn: choices.reminderOn,
      reminderTime: choices.reminderTime,
    ),
  );

  @override
  Future<void> updateReminder({
    required bool on,
    required ReminderTime time,
  }) async => _save(_current.copyWith(reminderOn: on, reminderTime: time));

  @override
  Future<void> updateProfile({
    String? locale,
    String? timeZone,
    String? country,
  }) async {
    final a = _current;
    await _save(
      a.copyWith(
        locale: locale,
        timeZone: timeZone,
        country: country,
        clearCountry: country == '',
      ),
    );
  }

  /// The device account's settings (the journal's own export comes with it).
  @override
  Future<Map<String, dynamic>> exportMyData() async {
    final a = _current;
    return {
      'format': 'piggybow-export',
      'format_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'profile': {
        'locale': a.locale,
        'time_zone': a.timeZone,
        'country': a.country,
      },
      'settings': {
        'reminder_on': a.reminderOn,
        'reminder_time': a.reminderTime.wire,
      },
    };
  }

  /// No policy notices on the phone.
  @override
  Future<void> markPolicyNotice(String id) async {}

  @override
  Future<void> markPolicyNoticeV2(String id) async {}

  /// Forgets the device account. The next start makes a new one.
  @override
  Future<void> deleteMyAccount() async {
    _account = null;
    await _prefs.setDeviceAccount(null);
  }
}

/// The stored device account.
class _DeviceAccount {
  const _DeviceAccount({
    required this.id,
    required this.createdAt,
    required this.timeZone,
    required this.locale,
    required this.country,
    required this.onboarded,
    required this.reminderOn,
    required this.reminderTime,
    required this.consents,
  });

  final String id;
  final DateTime createdAt;
  final String timeZone;
  final String locale;
  final String? country;
  final bool onboarded;
  final bool reminderOn;
  final ReminderTime reminderTime;
  final Map<ConsentKind, ConsentItem> consents;

  _DeviceAccount copyWith({
    String? timeZone,
    String? locale,
    String? country,
    bool clearCountry = false,
    bool? onboarded,
    bool? reminderOn,
    ReminderTime? reminderTime,
    Map<ConsentKind, ConsentItem>? consents,
  }) => _DeviceAccount(
    id: id,
    createdAt: createdAt,
    timeZone: timeZone ?? this.timeZone,
    locale: locale ?? this.locale,
    country: clearCountry ? null : (country ?? this.country),
    onboarded: onboarded ?? this.onboarded,
    reminderOn: reminderOn ?? this.reminderOn,
    reminderTime: reminderTime ?? this.reminderTime,
    consents: consents ?? this.consents,
  );

  String encode() => jsonEncode({
    'v': 1,
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'time_zone': timeZone,
    'locale': locale,
    'country': country,
    'onboarded': onboarded,
    'reminder_on': reminderOn,
    'reminder_time': reminderTime.wire,
    'consents': [for (final c in consents.values) c.toJson()],
  });

  /// Null for none, or for a copy this build can't read (a fresh one is
  /// made: it holds settings only, never the journal).
  static _DeviceAccount? decode(String? json) {
    if (json == null) return null;
    try {
      final j = jsonDecode(json) as Map<String, dynamic>;
      final time = (j['reminder_time'] as String).split(':');
      return _DeviceAccount(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        timeZone: j['time_zone'] as String,
        locale: j['locale'] as String,
        country: j['country'] as String?,
        onboarded: j['onboarded'] as bool,
        reminderOn: j['reminder_on'] as bool,
        reminderTime: ReminderTime(int.parse(time[0]), int.parse(time[1])),
        consents: {
          for (final c in (j['consents'] as List).cast<Map<String, dynamic>>())
            for (final kind in ConsentKind.values)
              if (kind.wire == c['kind'])
                kind: ConsentItem(
                  kind,
                  c['version'] as String,
                  granted: c['granted'] as bool,
                  locale: c['locale'] as String?,
                ),
        },
      );
    } on Object {
      return null;
    }
  }
}
