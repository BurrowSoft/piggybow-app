import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/local_prefs.dart';
import 'package:piggybow/data/fake_backend.dart';
import 'package:piggybow/data/models.dart';
import 'package:piggybow/session/app_session.dart';

import 'helpers.dart';

AppSession sessionOn(
  FakeBackend backend, {
  Future<void> Function(String)? onAccountGone,
  Future<void> Function(String)? onSessionEnded,
}) => AppSession(
  onAccountGone: onAccountGone,
  onSessionEnded: onSessionEnded,
  auth: backend,
  account: backend,
  prefs: MemoryLocalPrefs(localeCode: 'en', welcomeSeen: true),
  device: FakeDevice(),
  shippedLocales: const ['en'],
);

void main() {
  test('a stored session restores the user and account (→ Today)', () async {
    final backend = FakeBackend()
      ..addUser(
        'sam@example.invalid',
        'password1',
        consents: currentConsents,
        onboarded: true,
      );
    await backend.signIn(email: 'sam@example.invalid', password: 'password1');

    final session = sessionOn(backend);
    await session.restore();
    expect(session.user?.email, 'sam@example.invalid');
    expect(session.redirect('/home'), isNull);
  });

  test('no stored session → signed out (→ Sign in)', () async {
    final session = sessionOn(FakeBackend());
    await session.restore();
    expect(session.user, isNull);
    expect(session.redirect('/home'), Routes.signin);
  });

  test(
    'offline at start: the start screen offers Try again, session kept',
    () async {
      final backend = FakeBackend()
        ..addUser('sam@example.invalid', 'password1');
      await backend.signIn(email: 'sam@example.invalid', password: 'password1');
      backend.failNext = AppFailure.offline;

      final session = sessionOn(backend);
      await session.restore();
      expect(session.user, isNull);
      expect(session.startState, StartState.failed);
      expect(session.startFailure, AppFailure.offline);
      expect(session.redirect('/home'), Routes.start, reason: 'not Sign in');
      expect(backend.currentUser, isNotNull, reason: 'kept for Try again');
    },
  );

  test('a server error at start counts as generic, session kept', () async {
    final backend = FakeBackend()..addUser('sam@example.invalid', 'password1');
    await backend.signIn(email: 'sam@example.invalid', password: 'password1');
    backend.failNext = const AppFailure('internal_error');

    final session = sessionOn(backend);
    await session.restore();
    expect(session.startFailure, AppFailure.generic);
    expect(backend.currentUser, isNotNull);
  });

  test('a session the server rejects is signed out', () async {
    final backend = FakeBackend()..addUser('sam@example.invalid', 'password1');
    await backend.signIn(email: 'sam@example.invalid', password: 'password1');
    backend.failNext = const AppFailure('not_authenticated');

    final session = sessionOn(backend);
    await session.restore();
    expect(session.user, isNull);
    expect(backend.currentUser, isNull);
  });

  test('an account deleted elsewhere: restore signs out', () async {
    final backend = FakeBackend()
      ..addUser(
        'gone@example.invalid',
        'password1',
        consents: currentConsents,
        onboarded: true,
      );
    await backend.signIn(email: 'gone@example.invalid', password: 'password1');
    backend.deleteUser('gone@example.invalid');

    final wiped = <String>[];
    final session = sessionOn(
      backend,
      onAccountGone: (uid) async => wiped.add(uid),
    );
    await session.restore();
    expect(session.user, isNull);
    expect(backend.currentUser, isNull, reason: 'stale session dropped');
    expect(wiped, ['fake-1'], reason: 'the user local data is wiped');
    expect(session.signedOutReason, SignedOutReason.accountGone);
    expect(session.redirect('/home'), Routes.signin);
  });

  test(
    'a session revoked elsewhere (account exists): signed out, data kept',
    () async {
      final backend = FakeBackend()
        ..addUser(
          'reset@example.invalid',
          'password1',
          consents: currentConsents,
          onboarded: true,
        );
      await backend.signIn(
        email: 'reset@example.invalid',
        password: 'password1',
      );
      backend.revokeSession();

      final wiped = <String>[];
      final ended = <String>[];
      final session = sessionOn(
        backend,
        onAccountGone: (uid) async => wiped.add(uid),
        onSessionEnded: (uid) async => ended.add(uid),
      );
      await session.restore();
      expect(session.user, isNull);
      expect(backend.currentUser, isNull);
      expect(
        wiped,
        isEmpty,
        reason: 'the account exists: no full wipe (decision 81)',
      );
      expect(ended, ['fake-1'], reason: 'drop cached rows, keep unsynced');
      expect(session.signedOutReason, SignedOutReason.sessionEnded);
      expect(session.redirect('/home'), Routes.signin);
    },
  );

  test('the client drops the session after a rejected refresh (no error code) '
      '→ signed out with sessionEndedNotice, data kept', () async {
    final backend = FakeBackend()
      ..addUser(
        'bg@example.invalid',
        'password1',
        consents: currentConsents,
        onboarded: true,
      );
    await backend.signIn(email: 'bg@example.invalid', password: 'password1');
    final wiped = <String>[];
    final ended = <String>[];
    final session = sessionOn(
      backend,
      onAccountGone: (uid) async => wiped.add(uid),
      onSessionEnded: (uid) async => ended.add(uid),
    );
    await session.restore();
    expect(session.redirect('/home'), isNull, reason: 'signed in');

    backend.dropSessionAfterFailedRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(session.user, isNull);
    expect(session.signedOutReason, SignedOutReason.sessionEnded);
    expect(wiped, isEmpty);
    expect(ended, ['fake-1']);
    expect(session.redirect('/home'), Routes.signin);
  });

  test('launch: the token fails, then the background refresh drops the '
      'session → the notice still shows', () async {
    final backend = FakeBackend()..addUser('late@example.invalid', 'password1');
    await backend.signIn(email: 'late@example.invalid', password: 'password1');
    backend.failNext = AppFailure.generic; // e.g. "JWT expired"
    final session = sessionOn(backend);
    await session.restore();
    expect(session.signedOutReason, SignedOutReason.none);

    backend.dropSessionAfterFailedRefresh();
    await Future<void>.delayed(Duration.zero);
    expect(session.signedOutReason, SignedOutReason.sessionEnded);
  });

  test('a server hiccup (generic error) keeps the stored session', () async {
    final backend = FakeBackend()..addUser('sam@example.invalid', 'password1');
    await backend.signIn(email: 'sam@example.invalid', password: 'password1');
    backend.failNext = AppFailure.generic;

    final session = sessionOn(backend);
    await session.restore();
    expect(session.user, isNull, reason: 'not routed in without the account');
    expect(backend.currentUser, isNotNull, reason: 'kept for the next launch');
  });

  test(
    'account deleted mid-onboarding: the next write signs out (not stuck)',
    () async {
      final backend = FakeBackend()
        ..addUser('new@example.invalid', 'password1');
      final session = sessionOn(backend);
      await session.signIn(email: 'new@example.invalid', password: 'password1');
      // No consent is required in v0.1, so a new account goes on to Setup.
      expect(session.redirect('/home'), Routes.setup);

      backend.deleteUser('new@example.invalid');
      await expectLater(
        session.recordConsents(),
        throwsA(isA<AppFailure>()),
      );
      expect(session.user, isNull);
      expect(
        session.redirect(Routes.consent),
        isNull,
        reason: 'signed-out page',
      );
      expect(session.redirect('/home'), Routes.signin);
    },
  );
}
