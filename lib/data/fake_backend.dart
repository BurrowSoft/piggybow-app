import 'dart:async';

import '../core/clock.dart';
import 'models.dart';
import 'repositories.dart';

/// An in-memory account backend for tests (and the session's test rows):
/// the server's rules as the original app's migrations had them, minus
/// everything Piggybow doesn't carry. v0.1 runs on [DeviceBackend].
class FakeBackend implements AuthRepository, AccountRepository {
  FakeBackend({this.latency = Duration.zero, Clock? clock})
    : clock = clock ?? Clock();

  final Duration latency;

  /// Decides "today" for date checks, like the server's _user_today().
  final Clock clock;
  final _users = <String, _FakeUser>{};
  _FakeUser? _session;

  /// Test hook: the next call fails with this.
  AppFailure? failNext;

  /// Test hook: a slow account load (the start screen).
  Duration loadLatency = Duration.zero;

  /// Test hook: the next completeSetup fails with this (nothing stored).
  AppFailure? failNextSetup;

  /// What the last signup sent (for tests).
  SignupProfile? lastSignupProfile;
  SetupChoices? lastSetup;
  final sentEmails = <String>[];

  /// Test hook: the phone is offline — every call fails until cleared.
  bool offline = false;

  /// Test hook: every call hangs this long first (a dead connection
  /// mid-session hangs instead of failing).
  Duration stall = Duration.zero;

  Future<void> _tick() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (stall > Duration.zero) await Future<void>.delayed(stall);
    if (offline) throw AppFailure.offline;
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
  }

  /// Seeds an existing account (tests).
  void addUser(
    String email,
    String password, {
    bool confirmed = true,
    List<ConsentItem> consents = const [],
    bool onboarded = false,
    String timeZone = 'UTC',
    String? country,
    String locale = 'en',
  }) {
    _users[email.toLowerCase()] =
        _FakeUser(
            id: 'fake-${_users.length + 1}',
            email: email,
            password: password,
            confirmed: confirmed,
          )
          ..onboarded = onboarded
          ..timeZone = timeZone
          ..country = country
          ..locale = locale
          ..consents.addAll({for (final c in consents) c.kind: c});
  }

  void confirm(String email) => _users[email.toLowerCase()]?.confirmed = true;

  /// As the real client: the user as the stored session last saw it (an
  /// email confirmed elsewhere shows only after [reloadUser], review F2).
  AuthUser? _cachedUser;

  /// Test hook (03, row 6b): the stored session says anonymous although it
  /// already has the email, as a stale flag would.
  bool staleAnonymousFlag = false;

  @override
  AuthUser? get currentUser {
    final s = _session;
    if (s == null) return null;
    final user = _cachedUser?.id == s.id ? _cachedUser! : s.toAuthUser();
    if (!staleAnonymousFlag) return user;
    // Mapped as SupabaseBackend does: an email means linked.
    return AuthUser(id: user.id, email: s.email, isAnonymous: s.email.isEmpty);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required SignupProfile profile,
  }) async {
    await _tick();
    final key = email.toLowerCase();
    if (_users.containsKey(key)) throw AppFailure.emailTaken;
    lastSignupProfile = profile;
    _users[key] =
        _FakeUser(
            id: 'fake-${_users.length + 1}',
            email: email,
            password: password,
            confirmed: !email.contains('+unconfirmed'),
          )
          ..timeZone = profile.timeZone
          ..country = profile.country
          ..consents.addAll({for (final c in profile.consents) c.kind: c});
    sentEmails.add(email);
  }

  @override
  Future<AuthUser> signInAnonymously({required SignupProfile profile}) async {
    await _tick();
    lastSignupProfile = profile;
    final id = 'fake-anon-${_users.length + 1}';
    // Keyed by id: an anonymous user has no email to key by.
    final user =
        _FakeUser(
            id: id,
            email: '',
            password: '',
            confirmed: false,
            isAnonymous: true,
          )
          ..timeZone = profile.timeZone
          ..country = profile.country
          ..consents.addAll({for (final c in profile.consents) c.kind: c});
    _users[id] = user;
    _session = user;
    _cachedUser = null;
    _sessionRevoked = false;
    return user.toAuthUser();
  }

  @override
  Future<void> addEmail(String email) async {
    await _tick();
    final key = email.toLowerCase();
    if (_users.containsKey(key)) throw AppFailure.emailTaken;
    _signedIn.newEmail = email;
    sentEmails.add(email);
  }

  /// Test hook: the link sent by [addEmail] was opened (on the web).
  void confirmAddedEmail() {
    final user = _session;
    // The phone still holds the session from before (review F2).
    _cachedUser ??= user?.toAuthUser();
    final email = user?.newEmail;
    if (user == null || email == null) return;
    _users.remove(user.key);
    user
      ..email = email
      ..newEmail = null
      ..isAnonymous = false
      ..confirmed = true;
    _users[user.key] = user;
  }

  @override
  Future<AuthUser?> reloadUser() async {
    await _tick();
    _cachedUser = _session?.toAuthUser();
    if (staleAnonymousFlag) return currentUser;
    return _cachedUser;
  }

  @override
  Future<void> setPassword(String password) async {
    await _tick();
    final user = _signedIn;
    if (user.isAnonymous) throw AppFailure.generic;
    user.password = password;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await _tick();
    final user = _users[email.toLowerCase()];
    if (user == null || user.password != password) {
      throw AppFailure.badCredentials;
    }
    if (!user.confirmed) throw AppFailure.emailNotConfirmed;
    _session = user;
    _cachedUser = null;
    _sessionRevoked = false;
    return user.toAuthUser();
  }

  @override
  Future<void> resendConfirmation(String email) async {
    await _tick();
    sentEmails.add(email);
  }

  /// Test hook: the language emails would go out in (auth metadata).
  String? emailLanguage;

  @override
  Future<void> updateLanguage(String locale) async {
    await _tick();
    emailLanguage = locale;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _tick();
    if (_users.containsKey(email.toLowerCase())) sentEmails.add(email);
  }

  @override
  Future<void> signOut() async {
    // Like gotrue: the local session goes first, then the server call
    // (which can fail, e.g. offline).
    _session = null;
    _cachedUser = null;
    _sessionRevoked = false;
    await _tick();
  }

  /// The signed-in user; an account deleted elsewhere (deleteUser) keeps a
  /// stale session whose calls fail like the server's.
  _FakeUser get _signedIn {
    final s = _session ?? (throw StateError('not signed in'));
    if (!_users.containsValue(s)) throw AppFailure.accountGone;
    if (_sessionRevoked) throw AppFailure.sessionEnded;
    return s;
  }

  bool _sessionRevoked = false;

  /// Deletes an account server-side (another device, the web deletion page)
  /// while this device keeps its session.
  void deleteUser(String email) => _users.remove(email.toLowerCase());

  /// Revokes this device's session server-side (e.g. a password reset
  /// elsewhere); the account still exists. Calls fail until the next
  /// sign-in (like a still-valid token being rejected).
  void revokeSession() => _sessionRevoked = true;

  /// The server accepts this device's session again (X2: it refused it
  /// only for a while).
  void acceptSessionAgain() => _sessionRevoked = false;

  final _dropped = StreamController<void>.broadcast();

  @override
  Stream<void> get sessionDroppedElsewhere => _dropped.stream;

  @override
  Stream<void> get sessionRefreshed => _refreshed.stream;
  final _refreshed = StreamController<void>.broadcast();

  /// Test hook: the token was refreshed.
  void fireSessionRefreshed() => _refreshed.add(null);

  /// What gotrue-dart does when a refresh is rejected: the session is
  /// removed on the client and a signedOut event fires (no error code).
  void dropSessionAfterFailedRefresh() {
    _session = null;
    _cachedUser = null;
    _sessionRevoked = false;
    _dropped.add(null);
  }

  /// Test hook: load reads the account first and answers after
  /// [loadLatency] (a read that crosses a write made meanwhile).
  bool loadReadsFirst = false;

  /// Account loads started (tests: reconnect is single-flight).
  int loadCalls = 0;

  @override
  Future<AccountState> load() async {
    loadCalls++;
    if (loadReadsFirst) {
      await _tick();
      final early = _snapshot();
      await Future<void>.delayed(loadLatency);
      return early;
    }
    if (loadLatency > Duration.zero) await Future<void>.delayed(loadLatency);
    await _tick();
    return _snapshot();
  }

  AccountState _snapshot() {
    final user = _signedIn;
    return AccountState(
      consents: Map.unmodifiable(user.consents),
      onboarded: user.onboarded,
      timeZone: user.timeZone,
      country: user.country,
      locale: user.locale,
      reminderOn: user.reminderOn,
      reminderTime: user.reminderTime,
      policyNoticeId: policyNoticeId,
      policyNoticeSeen: user.policyNoticeSeen,
      policyNoticeV2Id: policyNoticeV2Id,
      policyNoticeV2Seen: user.policyNoticeV2Seen,
    );
  }

  /// app_config.policy_notice_v2_id (043); null: no v2 notice out.
  String? policyNoticeV2Id;

  /// Test hook: what each markPolicyNoticeV2 sent.
  final markPolicyNoticeV2Calls = <String>[];

  @override
  Future<void> markPolicyNoticeV2(String id) async {
    await _tick();
    markPolicyNoticeV2Calls.add(id);
    // As 043: only the v2 notice that's out.
    if (id != policyNoticeV2Id) throw const AppFailure('invalid_value');
    _signedIn.policyNoticeV2Seen = id;
  }

  /// app_config.policy_notice_id (019); null: no notice out.
  String? policyNoticeId;

  /// Test hook: the next markPolicyNotice fails with this.
  AppFailure? failNextPolicyNotice;

  /// Test hook: what each markPolicyNotice sent.
  final markPolicyNoticeCalls = <String>[];

  @override
  Future<void> markPolicyNotice(String id) async {
    await _tick();
    markPolicyNoticeCalls.add(id);
    final failure = failNextPolicyNotice;
    failNextPolicyNotice = null;
    if (failure != null) throw failure;
    // As 019: only the notice that's out.
    if (id != policyNoticeId) throw const AppFailure('invalid_value');
    _signedIn.policyNoticeSeen = id;
  }

  @override
  Future<void> updateReminder({
    required bool on,
    required ReminderTime time,
  }) async {
    await _tick();
    _signedIn
      ..reminderOn = on
      ..reminderTime = time;
  }

  /// Test hook: how many exports were made.
  int exports = 0;

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    await _tick();
    final u = _signedIn;
    exports++;
    return {
      'format': 'piggybow-export',
      'format_version': 1,
      'exported_at': clock.nowUtc().toIso8601String(),
      'account': {'email': u.email},
      'profile': {
        'locale': u.locale,
        'time_zone': u.timeZone,
        'country': u.country,
      },
      'settings': {
        'reminder_on': u.reminderOn,
        'reminder_time': u.reminderTime.wire,
      },
      'consents': [for (final c in u.consents.values) c.toJson()],
    };
  }

  @override
  Future<void> updateProfile({
    String? locale,
    String? timeZone,
    String? country,
  }) async {
    await _tick();
    final u = _signedIn;
    if (timeZone != null) u.timeZone = timeZone;
    if (country != null) u.country = country.isEmpty ? null : country;
    if (locale != null) u.locale = locale;
  }

  @override
  Future<void> deleteMyAccount() async {
    await _tick();
    _users.remove(_signedIn.key);
  }

  @override
  Future<void> recordConsents(List<ConsentItem> consents) async {
    await _tick();
    _signedIn.consents.addAll({for (final c in consents) c.kind: c});
  }

  @override
  Future<void> completeSetup(SetupChoices choices) async {
    await _tick();
    final failure = failNextSetup;
    failNextSetup = null;
    if (failure != null) throw failure;
    lastSetup = choices;
    _signedIn
      ..onboarded = true
      ..reminderOn = choices.reminderOn
      ..reminderTime = choices.reminderTime;
  }
}

class _FakeUser {
  _FakeUser({
    required this.id,
    required this.email,
    required this.password,
    required this.confirmed,
    this.isAnonymous = false,
  });

  final String id;
  String email;
  String password;
  bool confirmed;
  bool isAnonymous;

  /// An email added by [FakeBackend.addEmail], not confirmed yet.
  String? newEmail;

  /// The key in `_users`: the email, or the id for an anonymous user.
  String get key => isAnonymous ? id : email.toLowerCase();
  bool onboarded = false;
  String timeZone = 'UTC';
  String? country;
  String locale = 'en';
  bool reminderOn = true;
  ReminderTime reminderTime = ReminderTime.defaultTime;
  String? policyNoticeSeen;
  String? policyNoticeV2Seen;
  final consents = <ConsentKind, ConsentItem>{};

  AuthUser toAuthUser() =>
      AuthUser(id: id, email: email, isAnonymous: isAnonymous);
}
