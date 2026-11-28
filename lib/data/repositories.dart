import 'models.dart';

/// Profile facts sent with the signup, recorded by the server's auth trigger.
class SignupProfile {
  const SignupProfile({
    required this.locale,
    required this.timeZone,
    required this.country,
    required this.consents,
  });

  final String locale;

  /// IANA zone from the device, e.g. `Asia/Bangkok`.
  final String timeZone;

  /// ISO 3166-1 alpha-2 from the device region, or null.
  final String? country;

  /// Privacy, terms and 18+, recorded with the signup (never the AI
  /// consent: that one is asked only where AI is turned on).
  final List<ConsentItem> consents;

  Map<String, Object?> toMetadata() => {
    'locale': locale,
    'time_zone': timeZone,
    'country': country,
    'consents': [for (final c in consents) c.toJson()],
  };
}

abstract interface class AuthRepository {
  AuthUser? get currentUser;

  /// Fires when the auth client drops the session on its own (the refresh
  /// token was rejected, e.g. revoked by a password reset elsewhere). The
  /// session is already gone; nothing to sign out. Decision 70.
  Stream<void> get sessionDroppedElsewhere;

  /// The session's token was refreshed: whatever failed for want of one can
  /// read again.
  Stream<void> get sessionRefreshed;

  /// Creates the account. With email confirmation on there is no session
  /// afterwards; the user confirms, then signs in.
  Future<void> signUp({
    required String email,
    required String password,
    required SignupProfile profile,
  });

  /// Creates an account without an email and signs it in (no-signup-start,
  /// decision 216). The profile carries the consents, as at signup, so the
  /// same trigger builds the profile, settings and consents.
  Future<AuthUser> signInAnonymously({required SignupProfile profile});

  /// Back up your journal, step 1 (decision 216): sends a confirmation link
  /// to [email] for the signed-in anonymous account; the user id stays.
  /// Throws [AppFailure.emailTaken] when another account has it.
  Future<void> addEmail(String email);

  /// Step 2: the signed-in user as the server has it now (after the link,
  /// the email shows and the account is no longer anonymous).
  Future<AuthUser?> reloadUser();

  /// Step 3, once the email is confirmed (the server refuses a password on
  /// an account without one).
  Future<void> setPassword(String password);

  /// The language emails go out in (user_metadata.locale; send-email).
  Future<void> updateLanguage(String locale);

  /// Throws [AppFailure.badCredentials] or [AppFailure.emailNotConfirmed].
  Future<AuthUser> signIn({required String email, required String password});

  Future<void> resendConfirmation(String email);

  /// Always succeeds for a well-formed email (no account enumeration).
  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

abstract interface class AccountRepository {
  Future<AccountState> load();

  /// For a signed-in user (an old account or a new policy version).
  Future<void> recordConsents(List<ConsentItem> consents);

  /// Saves the setup choices and sets `profiles.onboarded_at`.
  Future<void> completeSetup(SetupChoices choices);

  /// Me → Daily reminder (`update_settings`).
  Future<void> updateReminder({required bool on, required ReminderTime time});

  /// Everything the user created (`export_my_data`), as the server sends it.
  Future<Map<String, dynamic>> exportMyData();

  /// Me → Language & region (`update_profile`); null = unchanged, country
  /// '' = not set.
  Future<void> updateProfile({
    String? locale,
    String? timeZone,
    String? country,
  });


  /// The privacy-change notice was dismissed (`policy_notice_seen`, 019).
  /// Throws `invalid_value` when [id] isn't the one out any more.
  Future<void> markPolicyNotice(String id);

  /// The v2 notice was dismissed (`policy_notice_v2_seen`, 043), the same
  /// rules: `invalid_value` when [id] isn't the one out any more.
  Future<void> markPolicyNoticeV2(String id);

  /// Deletes the account and every row right away (`delete_my_account`).
  Future<void> deleteMyAccount();
}

/// The device copy of the account state, for an offline start (decision 93
/// in the original app); per user id. v0.1's device backend never goes
/// offline, so the app passes none; the session keeps the hook.
abstract interface class AccountCache {
  AccountState? cachedAccount(String userId);
  Future<void> putCachedAccount(String userId, AccountState state);
}
