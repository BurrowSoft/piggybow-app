import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, debugPrint, kDebugMode;
import 'package:flutter/material.dart' show ThemeMode;

import '../theme/palettes.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../core/clock.dart';
import '../core/device.dart';
import '../core/local_prefs.dart';
import '../core/policy.dart';
import '../data/models.dart';
import '../data/repositories.dart';

/// Onboarding and sign-in routes. Paths never carry user data (they end up
/// in Sentry navigation breadcrumbs).
abstract final class Routes {
  static const language = '/language';
  static const welcome = '/welcome';
  static const consent = '/consent';
  static const signup = '/signup';
  static const checkEmail = '/check-email';
  static const signin = '/signin';
  static const setup = '/setup';
  static const home = '/home';

  /// Shown while a stored session is restored (slowLoading, Try again).
  static const start = '/start';

  /// "How was your day?" on a phone with no account (decision 216).
  static const firstOpen = '/first-open';

  /// Reachable while signed out.
  static const signedOut = {
    firstOpen,
    language,
    welcome,
    consent,
    signup,
    checkEmail,
    signin,
  };
}

/// Why the app signed the user out on its own (shown once on Sign in).
enum SignedOutReason {
  none,

  /// The account no longer exists: accountGoneNotice (decision 68).
  accountGone,

  /// The session was revoked, the account still exists: sessionEndedNotice
  /// (decision 70).
  sessionEnded,

  /// The same for an account with no email, which can't sign back in:
  /// sessionEndedNoEmail, never advice it can't follow.
  sessionEndedNoEmail,

  /// The user deleted their account here (Me → Delete account): deleteDone.
  deleted,
}

/// App-wide state that decides where the user is allowed to be: language,
/// sign-in, consents, setup. Screens call its methods; the router listens.
class AppSession extends ChangeNotifier {
  AppSession({
    required this.auth,
    required this.account,
    required this.prefs,
    required this.device,
    required this.aiEnabled,
    required this.shippedLocales,
    this.anonStart = false,
    this.onAnonymousStart,
    this.onSignedIn,
    this.onAccountGone,
    this.onSessionEnded,
    this.onSignedOut,
    this.accountCache,
    this.reconnectEvery = const Duration(seconds: 20),
    Clock? clock,
  }) : assert(shippedLocales.isNotEmpty),
       clock = clock ?? Clock(),
       _locale = _initialLocale(prefs, device, shippedLocales) {
    _settleLanguage();
    _dropped = auth.sessionDroppedElsewhere.listen((_) => _sessionDropped());
    _refreshed = auth.sessionRefreshed.listen((_) => sessionRecovered.value++);
  }

  late final StreamSubscription<void> _dropped;
  late final StreamSubscription<void> _refreshed;

  /// Counts token refreshes, for screens with a read that failed for want of
  /// one: without the offline banner, nothing else tells them to try again.
  final sessionRecovered = ValueNotifier<int>(0);

  /// The auth client removed the session itself (a rejected refresh, at
  /// launch or in the background). The account may still exist, so keep its
  /// device data and show sessionEndedNotice (decision 70). An account-gone
  /// reason already set by a failed call wins.
  void _sessionDropped() {
    final uid = _user?.id ?? _restoringUserId;
    final noEmail = _user?.isAnonymous ?? _restoringIsAnonymous;
    if (uid != null && _signedOutReason != SignedOutReason.accountGone) {
      onSessionEnded?.call(uid);
    }
    _endSlowStart();
    _user = null;
    _accountState = null;
    _pendingPassword = null;
    _startState = StartState.done;
    if (_signedOutReason != SignedOutReason.accountGone) {
      _setSignedOutReason(
        noEmail
            ? SignedOutReason.sessionEndedNoEmail
            : SignedOutReason.sessionEnded,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _dropped.cancel();
    unawaited(_refreshed.cancel());
    sessionRecovered.dispose();
    _reconnect?.cancel();
    offlineListenable.dispose();
    _slowStartSettled.dispose();
    _settleTimer?.cancel();
    super.dispose();
  }

  final AuthRepository auth;
  final AccountRepository account;
  final LocalPrefs prefs;
  final DeviceContext device;

  /// No-signup start (ANON_START_ENABLED, decision 216).
  final bool anonStart;

  /// An anonymous account is in (started, or restored half-finished): save
  /// the first entry; [setUp] = Setup's defaults were just applied (the
  /// reminder offer). True when the first entry was saved. Never throws.
  final Future<bool> Function(String userId, {required bool setUp})?
  onAnonymousStart;

  /// An email sign-in: the text from "How was your day?", if any, becomes
  /// that account's new-entry draft (decision 216, review N2).
  final Future<void> Function(String userId, String timeZone)? onSignedIn;

  /// This build offers AI on this platform (AppConfig.aiOn, PLAN-ai-golive
  /// §4). A person sees AI only when [aiShown].
  final bool aiEnabled;

  /// Language codes the build ships (the ARB files), English first. The beta
  /// ships English only, so the Language step is skipped (decision 32).
  final List<String> shippedLocales;

  /// Wipes one user's data on the device (drafts, pending check-ins, cached
  /// rows) when the server says the account no longer exists (decision 68).
  final Future<void> Function(String userId)? onAccountGone;

  /// The person signed out (Me → Sign out): what must never outlive a
  /// sign-out on a shared device (1.4 D's late-night mark, UX 19 Nov).
  /// Drafts and pending check-ins stay (decision 81).
  final Future<void> Function(String userId)? onSignedOut;

  /// The session ended but the account exists: drop that user's cached
  /// server rows, keep their unsynced drafts + pending check-ins (shown only
  /// after the same user signs in again). Decision 81.
  final Future<void> Function(String userId)? onSessionEnded;

  /// The device copy of the account state for an offline start
  /// (decision 93); null = no offline start (tests that don't need it).
  final AccountCache? accountCache;

  /// The quiet retry's interval while offline (decision 93, S2); null = no
  /// timer (tests drive [reconnect] themselves, so no timer is left running).
  final Duration? reconnectEvery;

  /// Times [lastServerContact] (the app's one source of "now").
  final Clock clock;

  /// R-013: when the server last answered this run (an account read, a
  /// reconnect, any journal call: [noteServerContact]), UTC; null = not
  /// yet, or the user changed. The 11-month warning is timed from this,
  /// never from an open that didn't reach the server (offline, or a slow
  /// start still waiting): 013 counts only those that did.
  ValueListenable<DateTime?> get lastServerContact => _lastServerContact;
  final _lastServerContact = ValueNotifier<DateTime?>(null);

  void noteServerContact() => _lastServerContact.value = clock.nowUtc();

  Future<AccountState> _loadAccount() async {
    final state = await account.load();
    noteServerContact();
    return state;
  }

  /// After Delete everything (plan §3.8): the fresh device account, read in
  /// place, with no trip through the start screen.
  Future<void> reloadAccount() async {
    final user = _user = auth.currentUser;
    _accountState = user == null ? null : await _loadAccount();
    if (user != null) await prefs.setAccountOnDevice(true);
    notifyListeners();
  }

  /// The stored session's user while restore() runs (a background drop can
  /// land before the user is routed in).
  String? _restoringUserId;
  bool _restoringIsAnonymous = false;

  late SignedOutReason _signedOutReason = prefs.sessionEndedNoEmail
      ? SignedOutReason.sessionEndedNoEmail
      : SignedOutReason.none;

  /// Why the user was signed out without asking; Sign in shows the matching
  /// notice (decisions 68 and 70).
  SignedOutReason get signedOutReason => _signedOutReason;

  /// A session came back, so the no-email notice is over: an ordinary sign-out
  /// later mustn't say the journal can't be brought back.
  void _sessionOpened() {
    if (_signedOutReason == SignedOutReason.sessionEndedNoEmail) {
      _setSignedOutReason(SignedOutReason.none);
    }
  }

  void _setSignedOutReason(SignedOutReason reason) {
    _signedOutReason = reason;
    unawaited(
      prefs.setSessionEndedNoEmail(reason == SignedOutReason.sessionEndedNoEmail),
    );
  }

  Locale _locale;
  AuthUser? _user;
  AccountState? _account;

  /// Every account state the app takes is also kept on the device, so the
  /// next start can open offline (decision 93).
  AccountState? get _accountState => _account;
  set _accountState(AccountState? state) {
    _account = state;
    if (state == null) {
      // Every sign-out path lands here: no offline mode without an account.
      _setOffline(false);
      _reconnect?.cancel();
      _fromCopy = false;
    }
    final uid = _user?.id ?? _restoringUserId;
    if (state != null && uid != null && !_offline) {
      unawaited(accountCache?.putCachedAccount(uid, state));
    }
  }

  bool _offline = false;
  Timer? _reconnect;

  /// The account in use is the device copy (an offline start): the first
  /// answer from the server replaces it, and routing re-checks it then.
  bool _fromCopy = false;

  /// The phone is offline (an offline start, or any request that failed
  /// offline, S2): the shell shows offlineBanner until the server answers.
  bool get offline => _offline;

  /// The banner listens here, not to the session: the session also drives
  /// the router's redirects, and a connectivity flip must never rebuild
  /// routes (it once remounted an editor that was popping, S2).
  final offlineListenable = ValueNotifier<bool>(false);

  void _setOffline(bool value) {
    _offline = value;
    offlineListenable.value = value;
  }

  List<ConsentItem>? _pendingConsents;
  String? _pendingEmail;

  /// The password typed at signup, so "I've confirmed my email" can sign in
  /// without retyping. Memory only: never persisted, cleared on sign-in,
  /// sign-out and a new signup.
  String? _pendingPassword;

  Locale get locale => _locale;
  bool get languageChosen =>
      shippedLocales.length == 1 || shippedLocales.contains(prefs.localeCode);
  bool get welcomeSeen => prefs.welcomeSeen;
  AuthUser? get user => _user;
  AccountState? get accountState => _accountState;

  /// UX ruling 1 (23 Nov): AI shows only with this build's AI for the
  /// platform AND get_me().ai_available. No account yet (signed out, the
  /// no-signup start, a restore in progress): false. Me → AI is the way in,
  /// with its own consent sheet. Every AI surface reads this one rule.
  bool get aiShown => aiEnabled && (_accountState?.aiAvailable ?? false);

  /// The locale dates are formatted in (decision 89): the app language in
  /// the device's region (en-US "October 2", en-GB "2 October"), else the
  /// profile country's, else the language's default (en → en_US).
  String get dateLocale {
    final lang = _locale.languageCode;
    for (final region in [device.countryCode, _accountState?.country]) {
      if (region == null) continue;
      final candidate = '${lang}_$region';
      if (DateFormat.localeExists(candidate)) return candidate;
    }
    return lang == 'en' ? 'en_US' : lang;
  }

  /// Consents chosen on the Consent screen, sent with the signup.
  List<ConsentItem>? get pendingConsents => _pendingConsents;

  /// The email the confirmation link was sent to (kept in memory only).
  String? get pendingEmail => _pendingEmail;

  /// "How was your day?" was answered (Save or Skip): Consent then starts
  /// the account without an email. Memory only; the text itself is a
  /// device draft (UserStore.preAccountId).
  bool get firstOpenAnswered => _firstOpenAnswered;
  bool _firstOpenAnswered = false;

  /// Save (true) or Skip (false): whether the text becomes today's entry.
  /// Either way it stays on the device until the account exists, so Back
  /// finds it again.
  bool get firstOpenSaves => _firstOpenSaves;
  bool _firstOpenSaves = false;

  void answerFirstOpen({required bool save}) {
    _firstOpenAnswered = true;
    _firstOpenSaves = save;
    notifyListeners();
  }

  /// Today's one-time "Your first entry is in your timeline." (memory only).
  bool get firstEntryNotice => _firstEntryNotice;
  bool _firstEntryNotice = false;

  /// Got it, or Today was left (UX: only the first arrival shows it).
  void dismissFirstEntryNotice() {
    if (!_firstEntryNotice) return;
    _firstEntryNotice = false;
    notifyListeners();
  }

  /// Someone who used the app before there was a choice of language: an
  /// update never switches their language (UX 2026-11-05).
  static bool _usedBeforeChoice(LocalPrefs prefs) =>
      prefs.localeCode == null && (prefs.welcomeSeen || prefs.accountOnDevice);

  /// The stored choice, else the device language if shipped (not for someone
  /// who has used the app in English until now), else English.
  static Locale _initialLocale(
    LocalPrefs prefs,
    DeviceContext device,
    List<String> shipped,
  ) {
    for (final code in [
      prefs.localeCode,
      if (!_usedBeforeChoice(prefs)) device.languageCode,
    ]) {
      if (shipped.contains(code)) return Locale(code!);
    }
    return Locale(shipped.first);
  }

  /// Once, with a choice of languages and none stored: an earlier user keeps
  /// English, and a new phone in a shipped language lands in it, without the
  /// Language screen. Stored now, so it can't read as "used before" later.
  void _settleLanguage() {
    if (shippedLocales.length == 1 || prefs.localeCode != null) return;
    if (_usedBeforeChoice(prefs) ||
        shippedLocales.contains(device.languageCode)) {
      unawaited(prefs.setLocaleCode(_locale.languageCode));
    }
  }

  /// Picks a language without saving it (the Language screen's selection).
  void previewLanguage(String code) {
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> chooseLanguage(String code) async {
    _locale = Locale(code);
    await prefs.setLocaleCode(code);
    notifyListeners();
  }

  Future<void> markWelcomeSeen() async {
    if (prefs.welcomeSeen) return;
    await prefs.setWelcomeSeen();
    notifyListeners();
  }

  /// What the Consent screen agrees to, each with the app's language (decision 224).
  /// Never an AI item: the AI consent is asked only in Me → AI, through its
  /// confirmation sheet (UX, 23 Nov), so a sign-up, a no-signup start or a
  /// re-consent never records, changes or withdraws it.
  List<ConsentItem> _consentsNow() {
    final ui = _locale.languageCode;
    return [
      ConsentItem(ConsentKind.privacy, PolicyVersions.privacy, locale: ui),
      ConsentItem(ConsentKind.terms, PolicyVersions.terms, locale: ui),
    ];
  }

  ConsentItem get _age18Now => ConsentItem(
    ConsentKind.age18,
    PolicyVersions.age18,
    locale: _locale.languageCode,
  );

  /// Consent screen, signed out: hold the choices for the signup.
  void setPendingConsents() {
    _pendingConsents = _consentsNow();
    notifyListeners();
  }

  Future<void> signUp({required String email, required String password}) async {
    final consents = _pendingConsents;
    if (consents == null) throw StateError('consents come first');
    await auth.signUp(
      email: email,
      password: password,
      profile: SignupProfile(
        locale: _locale.languageCode,
        timeZone: await device.timeZone(),
        country: device.countryCode,
        consents: [
          ...consents,
          // The 18+ checkbox is required to submit the form.
          _age18Now,
        ],
      ),
    );
    _pendingEmail = email;
    _pendingPassword = password;
    notifyListeners();
  }

  /// Check-email screen: sign in with the credentials just typed.
  Future<void> signInAfterConfirming() {
    final email = _pendingEmail;
    final password = _pendingPassword;
    if (email == null || password == null) {
      throw StateError('no pending signup');
    }
    return signIn(email: email, password: password);
  }

  /// How long the start screen waits for the account before it offers
  /// "Try again" (r1 copy: slowLoading).
  static const restoreTimeout = Duration(seconds: 10);

  StartState _startState = StartState.done;
  AppFailure? _startFailure;

  /// While a stored session is being restored the app shows the start
  /// screen, never Sign in or Consent.
  StartState get startState => _startState;

  /// Why the restore failed (offline / generic), for the start screen.
  AppFailure? get startFailure => _startFailure;

  /// App start (and the start screen's Try again): picks up a stored
  /// session (supabase_flutter persists it) and loads the account. Only a
  /// session the server rejects is signed out; offline, a server error or
  /// a timeout keeps it and shows Try again (never sign out on an outage).
  Future<void> restore() async {
    final user = auth.currentUser;
    if (user == null) return;
    // Phones signed in before decision 216 (review B2): a later sign-out
    // must land on Sign in, never on "How was your day?".
    await prefs.setAccountOnDevice(true);
    _restoringUserId = user.id;
    _restoringIsAnonymous = user.isAnonymous;
    _startState = StartState.restoring;
    _startFailure = null;
    notifyListeners();
    // S2 (decision 209): with a device copy of the account, an offline
    // phone opens on it within ~3 s instead of waiting out the token
    // refresh; the quiet retry refreshes once the server answers. Without
    // a copy there's nothing to open on, so the full wait stays.
    final hasCopy = accountCache?.cachedAccount(user.id) != null;
    // Kept so a slow first read can still land after the copy opens.
    final firstRead = _loadAccount();
    try {
      var state = await firstRead.timeout(
        hasCopy ? offlineStartAfter : restoreTimeout,
      );
      var restored = user;
      if (user.isAnonymous) {
        try {
          final (finished, saved) = await _finishAnonymous(user.id, state);
          state = finished;
          _firstEntryNotice = saved;
        } on AppFailure {
          // Retried on the next start; Today opens meanwhile (no Setup).
        }
        // The stored session may predate an email confirmed elsewhere
        // (review F2): the server's word wins.
        try {
          final fresh = await auth.reloadUser();
          if (fresh != null && !fresh.isAnonymous) restored = fresh;
        } on AppFailure {
          // Offline: stays anonymous until the next check.
        }
      }
      if (_startState != StartState.restoring) return; // dropped meanwhile
      _accountState = state;
      _user = restored;
      _sessionOpened();
      _startState = StartState.done;
    } on TimeoutException {
      // Triage row 4 (S2): only slow, not offline. Open on the device copy
      // with NO banner; the first read goes on and replaces the copy when
      // it lands, and only a real offline failure turns the banner on.
      if (!_startSlow(user, firstRead)) _fail(AppFailure.generic);
    } on AppFailure catch (e) {
      if (await _signOutIfRejected(e, user.id)) {
        _startState = StartState.done;
      } else if (!_startOffline(
        // An account without an email the server refused for now (X2):
        // it opens on its copy and retries, like an offline start.
        user.isAnonymous && e != AppFailure.accountGone
            ? AppFailure.offline
            : e,
        user,
      )) {
        _fail(e);
      }
    }
    notifyListeners();
  }

  /// How long a start with a device copy waits before opening on it.
  static const offlineStartAfter = Duration(seconds: 3);

  /// The first read is still on its way after the copy opened (triage row
  /// 4): what the server has is unknown, so nothing may overwrite it. A
  /// check-in saved meanwhile has no version, so it's insert-only
  /// (decision 209) and a day saved elsewhere is asked about, never lost.
  bool get firstReadPending => _firstReadPending;
  bool _firstReadPending = false;

  /// A request timed out while [firstReadPending] (markOffline deferred).
  bool _offlineDeferred = false;

  /// Just after a slow start settled: the screens read again at once, and
  /// on a ~2.5 s link one may cross the 3 s cap. For [settleGrace] that's
  /// still slow, not offline (UX, 03's 500 ms run).
  bool _settling = false;
  Timer? _settleTimer;
  static const settleGrace = Duration(seconds: 10);

  /// Debug builds only (03's network runs): why the banner did or didn't
  /// show. Never in release; no user data.
  void _netLog(String what) {
    if (kDebugMode) debugPrint('[net] $what');
  }

  /// Ticks when a slow start's first read lands after a request timed out
  /// meanwhile: Today reloads quietly instead of having shown the banner.
  ValueListenable<int> get slowStartSettled => _slowStartSettled;
  final _slowStartSettled = ValueNotifier<int>(0);

  /// Bumped whenever the session drops its user (review B1): a slow start's
  /// first read from before that never lands afterwards, even for the same
  /// account signing back in.
  int _startToken = 0;

  /// The user is gone (sign-out, delete, a dropped or rejected session):
  /// the slow-start state goes with it, or markOffline would stay deferred
  /// for the rest of the run (review B1).
  void _endSlowStart() {
    _lastServerContact.value = null;
    _startToken++;
    _firstReadPending = false;
    _offlineDeferred = false;
    _settling = false;
    _settleTimer?.cancel();
  }

  /// A slow first read (no answer within [offlineStartAfter]): opens on
  /// the device copy without the offline banner. False without a copy.
  bool _startSlow(AuthUser user, Future<AccountState> firstRead) {
    final token = _startToken;
    if (_startState != StartState.restoring) return false;
    final cached = accountCache?.cachedAccount(user.id);
    if (cached == null) return false;
    _user = user;
    _sessionOpened();
    _accountState = cached;
    _fromCopy = true;
    _firstReadPending = true;
    _startState = StartState.done;
    unawaited(
      firstRead.then(
        (state) {
          if (token != _startToken || _user?.id != user.id) return;
          _firstReadPending = false;
          _fromCopy = false;
          _accountState = state;
          notifyListeners();
          if (_offlineDeferred) {
            _offlineDeferred = false;
            _settling = true;
            _settleTimer?.cancel();
            _settleTimer = Timer(settleGrace, () => _settling = false);
            _netLog('first read landed: settle reload');
            _slowStartSettled.value++;
          }
        },
        onError: (Object e) async {
          if (token != _startToken || _user?.id != user.id) return;
          _firstReadPending = false;
          _offlineDeferred = false;
          if (e is AppFailure && await _signOutIfRejected(e, user.id)) {
            return;
          }
          // Really unreachable: now it's offline, banner and quiet retry.
          _setOffline(true);
          _startRetrying();
        },
      ),
    );
    return true;
  }

  /// S2 (decision 209): a request failed offline mid-session. The banner
  /// shows (and inline offline lines hide), and the same quiet retry as an
  /// offline start clears it once the server answers.
  void markOffline() {
    if (_offline || _user == null) return;
    // Triage row 4, option (A): while a slow start's first read is still on
    // its way, a request timing out (Today's 3 s read cap) is "slow", not
    // offline yet. Decided when that read ends: it lands → the screens that
    // missed theirs reload quietly ([slowStartSettled]); it fails → the
    // banner.
    if (_firstReadPending) {
      _offlineDeferred = true;
      _netLog('markOffline deferred (first read in flight)');
      return;
    }
    // The settle reload (the screens reading again at once on a slow link)
    // may cross the cap too: still slow, not offline (UX).
    if (_settling) {
      _netLog('markOffline ignored (settle reload)');
      return;
    }
    _netLog('markOffline raised: the banner');
    // The banner only (offlineListenable); nothing about the account or
    // the route changed, so the session doesn't notify.
    _setOffline(true);
    _startRetrying();
  }

  /// The quiet retry while offline (every [reconnectEvery]; none in tests,
  /// which call [reconnect] themselves), plus app resume (the banner).
  void _startRetrying() {
    _reconnect?.cancel();
    final every = reconnectEvery;
    if (every != null) {
      _reconnect = Timer.periodic(every, (_) => reconnect());
    }
  }

  /// Decision 93: offline, with a stored session and a device copy of the
  /// account → open on that copy with offlineBanner; writes queue as
  /// pending. Without a copy: errOffline + Try again (the start screen).
  bool _startOffline(AppFailure e, AuthUser user) {
    if (e != AppFailure.offline || _startState != StartState.restoring) {
      return false;
    }
    final cached = accountCache?.cachedAccount(user.id);
    if (cached == null) return false;
    _setOffline(true);
    _user = user;
    _sessionOpened();
    _accountState = cached;
    _fromCopy = true;
    _startState = StartState.done;
    _startRetrying();
    return true;
  }

  /// Offline start: one quiet try (the timer, or the app coming back to the
  /// foreground). On success the banner goes and the fresh state is kept;
  /// a rejected session signs out as at start (decisions 68/70).
  ///
  /// Single-flight (Reviewer L1): a burst of callers (the timer, resume,
  /// several journal successes) shares the one try in progress.
  Future<void> reconnect() => _reconnecting ??= _reconnectOnce().whenComplete(
    () => _reconnecting = null,
  );

  Future<void>? _reconnecting;

  Future<void> _reconnectOnce() async {
    final uid = _user?.id;
    if (!_offline || uid == null) return;
    try {
      final state = await _loadAccount().timeout(restoreTimeout);
      if (!_offline || _user?.id != uid) return;
      _setOffline(false);
      _reconnect?.cancel();
      final fromCopy = _fromCopy;
      _fromCopy = false;
      // UX ruling 1: aiShown reads get_me().ai_available, so a reconnect that
      // finds the server switch changed must rebuild (critic step 7).
      final wasAi = _accountState?.aiAvailable;
      _accountState = state;
      // An offline start opened on the stored session, which may predate an
      // email confirmed elsewhere (03, row 6b): ask the server once online.
      var linked = false;
      if (_user?.isAnonymous ?? false) {
        try {
          final fresh = await auth.reloadUser();
          if (fresh != null && !fresh.isAnonymous && _user?.id == uid) {
            _user = fresh;
            linked = true;
          }
        } on AppFailure {
          // Asked again on Me / Back up / the next start.
        }
      }
      // Only an account that was the device copy can change what's shown
      // or routed (consents, settings): then the session notifies. A
      // mid-session blip changes nothing, so it never rebuilds routes;
      // except when the server's AI switch changed meanwhile (aiShown).
      if (fromCopy || linked || wasAi != state.aiAvailable) notifyListeners();
    } on TimeoutException {
      // Still offline: the next tick tries again.
    } on AppFailure catch (e) {
      if (await _signOutIfRejected(e, uid)) {
        _setOffline(false);
        _reconnect?.cancel();
      }
    }
  }

  void _fail(AppFailure e) {
    if (_startState != StartState.restoring) return;
    _startState = StartState.failed;
    _startFailure = e == AppFailure.offline ? e : AppFailure.generic;
  }

  /// Signs out when [e] says the server no longer accepts this user:
  /// the account is gone (wipe its device data, decision 68) or the session
  /// was revoked (keep the data, decision 70). Returns whether it did.
  /// An account without an email is only ever signed out when it's gone
  /// (X2): it can't sign back in, so a sign-out would lose the journal.
  /// It stays, and the caller retries as for any failed read.
  Future<bool> _signOutIfRejected(AppFailure e, String userId) async {
    final reason = switch (e) {
      AppFailure(code: 'account_gone') => SignedOutReason.accountGone,
      AppFailure(code: 'session_ended' || 'not_authenticated') =>
        SignedOutReason.sessionEnded,
      _ => null,
    };
    if (reason == null) return false;
    if (reason == SignedOutReason.sessionEnded && _anonymous(userId)) {
      return false;
    }
    try {
      await auth.signOut();
    } on AppFailure {
      // The session is dead anyway; local sign-out must still happen.
    }
    if (reason == SignedOutReason.accountGone) {
      await onAccountGone?.call(userId);
    } else {
      await onSessionEnded?.call(userId);
    }
    _endSlowStart();
    _user = null;
    _accountState = null;
    _pendingPassword = null;
    _setSignedOutReason(reason);
    notifyListeners();
    return true;
  }

  /// Whether [userId] is this phone's account without an email (signed in,
  /// or the stored one while the start still runs).
  bool _anonymous(String userId) {
    final user = _user ?? auth.currentUser;
    return user != null && user.id == userId && user.isAnonymous;
  }

  /// After a failed account write: if the server no longer accepts this
  /// user, sign out (back to Sign in) instead of leaving them stuck on an
  /// error. Never route a missing user to Consent.
  Future<void> _signOutIfAccountGone() async {
    final uid = _user?.id;
    if (uid == null) return;
    try {
      await _loadAccount();
    } on AppFailure catch (e) {
      await _signOutIfRejected(e, uid);
    }
  }

  /// Consent → an account without an email (decision 216): the same
  /// profile and consents as a signup (18+ included), then the rest of
  /// [_finishAnonymous]. Throws [AppFailure] (offline: nothing was created,
  /// or the account was and the call can simply be repeated).
  Future<void> startAnonymously() async {
    final consents = _pendingConsents;
    if (consents == null) throw StateError('consents come first');
    // A repeat after a failure past the sign-in keeps that account.
    final user =
        auth.currentUser ??
        await auth.signInAnonymously(
          profile: SignupProfile(
            locale: _locale.languageCode,
            timeZone: await device.timeZone(),
            country: device.countryCode,
            consents: [
              ...consents,
              _age18Now,
            ],
          ),
        );
    await prefs.setAccountOnDevice(true);
    await prefs.setLocaleCode(_locale.languageCode);
    final (state, saved) = await _finishAnonymous(
      user.id,
      await _loadAccount(),
    );
    _user = user;
    _accountState = state;
    _pendingConsents = null;
    _firstOpenAnswered = false;
    _firstEntryNotice = saved;
    _startedAnonymouslyThisRun = true;
    _setSignedOutReason(SignedOutReason.none);
    notifyListeners();
  }

  /// Back up your journal, step 1 (decision 216): the confirmation link to
  /// [email]. Throws [AppFailure] (emailTaken: another account has it).
  Future<void> addBackupEmail(String email) => auth.addEmail(email);

  /// Step 2: true once the link was opened (the account has its email and
  /// is no longer anonymous); the session then holds that user.
  Future<bool> backupEmailConfirmed() async {
    final user = await auth.reloadUser();
    if (user == null || user.isAnonymous || user.email.isEmpty) return false;
    _user = user;
    notifyListeners();
    return true;
  }

  /// Me, Back up and a resume (review F2): an anonymous account checks
  /// quietly whether its email was confirmed meanwhile (the link opened on
  /// a laptop); if so the session holds the linked user. Never throws.
  Future<void> refreshIfAnonymous() async {
    if (!(_user?.isAnonymous ?? false)) return;
    try {
      await backupEmailConfirmed();
    } on AppFailure {
      // Offline: asked again next time.
    }
  }

  /// Step 3. Then Me says once "Your journal is backed up."
  Future<void> setBackupPassword(String password) async {
    await auth.setPassword(password);
    _backupDoneNotice = true;
    notifyListeners();
  }

  /// The account was started without an email in this run of the app
  /// (memory only): Today's backup card waits for the next app open or a
  /// new day (UX, review N2). Today records the day it first saw this.
  bool get startedAnonymouslyThisRun => _startedAnonymouslyThisRun;
  bool _startedAnonymouslyThisRun = false;
  String? anonymousStartDay;

  bool get backupDoneNotice => _backupDoneNotice;
  bool _backupDoneNotice = false;

  void dismissBackupDoneNotice() {
    _backupDoneNotice = false;
    notifyListeners();
  }

  /// The tail of an anonymous start, also run on every restore of an
  /// anonymous account (an app closed half-way, review B1): Setup's defaults
  /// with the reminder off if not done yet, then [onAnonymousStart] (the
  /// first entry's save; the reminder offer once Setup was done here).
  /// Returns the account and whether the first entry was saved.
  Future<(AccountState, bool)> _finishAnonymous(
    String userId,
    AccountState state,
  ) async {
    var setUp = false;
    if (!state.onboarded) {
      await account.completeSetup(const SetupChoices(reminderOn: false));
      state = await _loadAccount();
      setUp = true;
    }
    final saved = await onAnonymousStart?.call(userId, setUp: setUp) ?? false;
    return (state, saved);
  }

  Future<void> signIn({required String email, required String password}) async {
    final user = await auth.signIn(email: email, password: password);
    final state = await _loadAccount();
    await prefs.setAccountOnDevice(true);
    await onSignedIn?.call(user.id, state.timeZone);
    // The account's language wins over this phone's (UX 2026-11-06), if this
    // build offers it: the app, its emails and reflect's help label agree.
    final saved = state.locale;
    if (saved != null && shippedLocales.contains(saved)) {
      _locale = Locale(saved);
      await prefs.setLocaleCode(saved);
    }
    _user = user;
    _accountState = state;
    _pendingConsents = null;
    _pendingEmail = null;
    _setSignedOutReason(SignedOutReason.none);
    _pendingPassword = null;
    notifyListeners();
  }

  Future<void> resendConfirmation(String email) =>
      auth.resendConfirmation(email);

  Future<void> sendPasswordReset(String email) => auth.sendPasswordReset(email);

  /// Consent screen, signed in (old account or a new policy version).
  Future<void> recordConsents() async {
    try {
      await _recordConsents();
    } on AppFailure {
      await _signOutIfAccountGone();
      rethrow;
    }
  }

  Future<void> _recordConsents() async {
    await account.recordConsents([
      ..._consentsNow(),
      // Signed-in users who never confirmed 18+ (none today) confirm it here.
      _age18Now,
    ]);
    _accountState = await _loadAccount();
    notifyListeners();
  }

  Future<void> completeSetup(SetupChoices choices) async {
    try {
      await account.completeSetup(choices);
      _accountState = await _loadAccount();
    } on AppFailure {
      await _signOutIfAccountGone();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final uid = _user?.id;
    if (uid != null) await onSignedOut?.call(uid);
    try {
      await auth.signOut();
    } on AppFailure {
      // gotrue drops the local session before calling /logout, so an
      // offline (or already revoked) sign-out is still a sign-out here.
    }
    _pendingPassword = null;
    _endSlowStart();
    _user = null;
    _accountState = null;
    notifyListeners();
  }

  /// Account writes made here (refreshAccount ignores a read that started
  /// before one).
  int _accountWrites = 0;

  /// Reloads the account (Me: the reminder and credits may have changed on
  /// another device). Failures keep what's shown; a rejected session signs
  /// out as usual.
  Future<void> refreshAccount() async {
    final uid = _user?.id;
    if (uid == null) return;
    final writesBefore = _accountWrites;
    try {
      final loaded = await _loadAccount();
      // A setting saved meanwhile wins over this (older) read.
      if (_accountWrites != writesBefore || _user?.id != uid) return;
      _accountState = loaded;
      notifyListeners();
    } on AppFailure catch (e) {
      await _signOutIfRejected(e, uid);
    }
  }

  /// Me → Daily reminder. Throws [AppFailure] on failure; the caller shows
  /// the saved value again (decision 111: never a state the server lacks).
  Future<void> updateReminder({
    required bool on,
    required ReminderTime time,
  }) async {
    try {
      await account.updateReminder(on: on, time: time);
    } on AppFailure {
      await _signOutIfAccountGone();
      rethrow;
    }
    _accountWrites++;
    _accountState = _accountState?.copyWith(reminderOn: on, reminderTime: time);
    notifyListeners();
  }

  /// Me → AI on/off (reflect.md): on = the AI consent, then ai_enabled;
  /// off = ai_enabled off, then the recorded withdrawal. On failure the
  /// account is reloaded (what the server really has) and the error
  /// rethrown: the switch shows the saved state (decision 111).
  Future<void> setAiEnabled(bool on) async {
    final consent = ConsentItem(ConsentKind.ai, PolicyVersions.ai, granted: on);
    try {
      if (on) {
        await account.recordConsents([consent]);
        await account.updateAiSettings(enabled: true);
      } else {
        await account.updateAiSettings(enabled: false);
        await account.recordConsents([consent]);
      }
    } on AppFailure {
      await refreshAccount();
      rethrow;
    }
    _accountWrites++;
    final s = _accountState;
    if (s != null) {
      _accountState = s.copyWith(
        aiEnabled: on,
        consents: {...s.consents, ConsentKind.ai: consent},
      );
    }
    notifyListeners();
  }

  /// The privacy-change notice (019), dismissed with "Got it". It goes at
  /// once and blocks nothing: a failed save brings it back on the next read,
  /// the honest result (as the web). `invalid_value` means another notice
  /// is out now, so the account is read again: never a loop on the old one.
  Future<void> dismissPolicyNotice() async {
    final s = _accountState;
    final id = s?.policyNoticeId;
    if (s == null || id == null) return;
    _accountWrites++;
    _accountState = s.copyWith(policyNoticeSeen: id);
    notifyListeners();
    try {
      await account.markPolicyNotice(id);
    } on AppFailure catch (e) {
      if (e.code == 'invalid_value') await refreshAccount();
    }
  }

  /// The v2 notice (043), dismissed with "Got it": the same rules as
  /// [dismissPolicyNotice].
  Future<void> dismissPolicyNoticeV2() async {
    final s = _accountState;
    final id = s?.policyNoticeV2Id;
    if (s == null || id == null) return;
    _accountWrites++;
    _accountState = s.copyWith(policyNoticeV2Seen: id);
    notifyListeners();
    try {
      await account.markPolicyNoticeV2(id);
    } on AppFailure catch (e) {
      if (e.code == 'invalid_value') await refreshAccount();
    }
  }

  /// Me → AI tone / focus areas. Throws [AppFailure] (decision 111).
  Future<void> updateAiStyle({Tone? tone, Set<FocusArea>? focus}) async {
    try {
      await account.updateAiSettings(tone: tone, focus: focus);
    } on AppFailure {
      await _signOutIfAccountGone();
      rethrow;
    }
    _accountWrites++;
    _accountState = _accountState?.copyWith(tone: tone, focusAreas: focus);
    notifyListeners();
  }

  /// The balance a reflect call returned (Me → AI credits stays current).
  void applyCredits(int balance) {
    final s = _accountState;
    if (s == null || s.creditBalance == balance) return;
    _accountWrites++;
    _accountState = s.copyWith(creditBalance: balance);
    notifyListeners();
  }

  /// Me → Appearance (decision 133): this device only.
  ThemeMode get themeMode => switch (prefs.appearance) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) async {
    await prefs.setAppearance(mode.name);
    notifyListeners();
  }

  /// Piggybow Plus's extra theme (decision 246), this device only: applied
  /// while the date Plus runs to hasn't passed; past it, the default.
  PlusPalette? get palette => parsePalette(prefs.palette, clock.nowUtc());

  /// The stored choice's name, whatever its date (Me shows it as chosen).
  PlusPalette? get chosenPalette => storedPaletteName(prefs.palette);

  /// [palette] null: back to the default. [until]: when Plus runs out.
  Future<void> setPalette(PlusPalette? palette, DateTime? until) async {
    await prefs.setPalette(
      palette == null || until == null ? null : encodePalette(palette, until),
    );
    notifyListeners();
  }

  /// With Plus on, the stored choice runs to the entitlement's end, so a
  /// renewal never resets the theme (UX, #277).
  Future<void> refreshPaletteUntil(DateTime until) async {
    final name = chosenPalette;
    if (name == null || prefs.palette == encodePalette(name, until)) return;
    await setPalette(name, until);
  }

  /// Me → Language & region. The language is this device's UI language and
  /// the profile's (the server writes AI replies' Get-help label in it);
  /// the time zone defines "today".
  /// Throws [AppFailure] (decision 111: the row keeps the saved value).
  Future<void> updateRegion({
    String? locale,
    String? timeZone,
    String? country,
  }) async {
    try {
      await account.updateProfile(
        locale: locale,
        timeZone: timeZone,
        country: country,
      );
    } on AppFailure {
      await _signOutIfAccountGone();
      rethrow;
    }
    if (locale != null) {
      await chooseLanguage(locale);
      // Emails go by the auth metadata (send-email). A failure here doesn't
      // undo the language; the next change tries again.
      try {
        await auth.updateLanguage(locale);
      } on AppFailure {
        // Keeps the sign-up language for email until then.
      }
    }
    _accountWrites++;
    _accountState = _accountState?.copyWith(
      locale: locale,
      timeZone: timeZone,
      country: country == '' ? null : country,
      clearCountry: country == '',
    );
    notifyListeners();
  }

  /// Me → Export my data: the server's document (export_my_data).
  Future<Map<String, dynamic>> exportMyData() async {
    try {
      return await account.exportMyData();
    } on AppFailure {
      await _signOutIfAccountGone();
      rethrow;
    }
  }

  /// Me → Delete account: deletes the account and every row, then this
  /// device forgets the session and the user's local copies (pending
  /// check-ins, drafts, caches; decision 85). Sign in then says it's done.
  /// Throws [AppFailure] if the server didn't delete (nothing is wiped).
  Future<void> deleteAccount() async {
    final uid = _user?.id;
    if (uid == null) return;
    await account.deleteMyAccount();
    try {
      await auth.signOut();
    } on AppFailure {
      // The user no longer exists; the local sign-out still happened.
    }
    await onAccountGone?.call(uid);
    // No account on the phone any more: the next open is "How was your
    // day?" (decision 216).
    await prefs.setAccountOnDevice(false);
    _endSlowStart();
    _user = null;
    _accountState = null;
    _pendingPassword = null;
    _setSignedOutReason(SignedOutReason.deleted);
    notifyListeners();
  }

  /// Where the app was opened (a deep link) while the start screen showed.
  String? _resumeAt;

  /// Where the user must be, given where they are going (null = stay).
  String? redirect(String location) {
    if (_startState != StartState.done) {
      if (location == Routes.start) return null;
      _resumeAt = location;
      return Routes.start;
    }
    // Restored (or signed out): go where the app was opened, else Today;
    // the usual rules then apply to that place.
    final target = location == Routes.start
        ? (_resumeAt ?? Routes.home)
        : location;
    if (location == Routes.start) _resumeAt = null;
    return onboardingRedirect(
          // The no-signup start skips the Language screen: the device
          // language if shipped, else English; Me changes it.
          languageChosen: languageChosen || anonStart,
          welcomeSeen: welcomeSeen,
          anonStart: anonStart,
          accountOnDevice: prefs.accountOnDevice,
          signedIn: _user != null,
          hasConsents:
              _accountState?.hasRequiredConsents(PolicyVersions.required) ??
              false,
          // An anonymous account never sees Setup: its defaults are
          // retried on the next start if they failed (review B1).
          onboarded:
              (_accountState?.onboarded ?? false) ||
              (_user?.isAnonymous ?? false),
          hasPendingConsents: _pendingConsents != null,
          hasPendingEmail: _pendingEmail != null,
          location: target,
        ) ??
        (target == location ? null : target);
  }
}

/// The start screen's state while a stored session is restored.
enum StartState { done, restoring, failed }

/// The routing rules of M3, as a pure function.
String? onboardingRedirect({
  required bool languageChosen,
  required bool welcomeSeen,
  bool anonStart = false,
  bool accountOnDevice = false,
  required bool signedIn,
  required bool hasConsents,
  required bool onboarded,
  required bool hasPendingConsents,
  required bool hasPendingEmail,
  required String location,
}) {
  String? to(String path) => location == path ? null : path;

  if (!languageChosen) return to(Routes.language);

  if (!signedIn) {
    if (!Routes.signedOut.contains(location)) {
      // Decision 216: a phone with no account starts on "How was your
      // day?"; one that had an account (signed out) on Sign in.
      if (anonStart) return accountOnDevice ? Routes.signin : Routes.firstOpen;
      return welcomeSeen ? Routes.signin : Routes.welcome;
    }
    if (location == Routes.firstOpen && !anonStart) return Routes.welcome;
    // Signup needs the consents first; the check-email page needs an email.
    if (location == Routes.signup && !hasPendingConsents) return Routes.consent;
    if (location == Routes.checkEmail && !hasPendingEmail) return Routes.signin;
    return null;
  }

  if (!hasConsents) return to(Routes.consent);
  if (!onboarded) return to(Routes.setup);
  final inOnboarding =
      location == Routes.language ||
      location == Routes.setup ||
      Routes.signedOut.contains(location);
  return inOnboarding ? Routes.home : null;
}
