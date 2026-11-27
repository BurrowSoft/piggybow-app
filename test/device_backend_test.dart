import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/local_prefs.dart';
import 'package:piggybow/data/device_backend.dart';
import 'package:piggybow/data/models.dart';
import 'package:piggybow/data/repositories.dart';
import 'package:piggybow/session/app_session.dart';

import 'helpers.dart';

/// v0.1's backend: the phone only. A device account stands in for the
/// server's: made on the first start, kept in the phone's prefs, never sent
/// anywhere; the email paths don't exist.
void main() {
  var ids = 0;
  String nextId() => 'id-${++ids}';
  final created = DateTime.utc(2026, 11, 28, 1, 30);

  Future<DeviceBackend> open(
    MemoryLocalPrefs prefs, {
    String timeZone = 'Asia/Bangkok',
  }) => DeviceBackend.open(
    prefs: prefs,
    timeZone: timeZone,
    country: 'TH',
    newId: nextId,
    now: () => created,
  );

  setUp(() => ids = 0);

  test('the first start makes the device account: set up, reminder off, '
      "the phone's zone", () async {
    final prefs = MemoryLocalPrefs();
    final backend = await open(prefs);

    final user = backend.currentUser!;
    expect(user.id, 'id-1');
    expect(user.isAnonymous, isTrue);
    expect(user.email, isEmpty);
    final state = await backend.load();
    expect(state.onboarded, isTrue);
    expect(state.reminderOn, isFalse);
    expect(state.reminderTime, ReminderTime.defaultTime);
    expect(state.timeZone, 'Asia/Bangkok');
    expect(state.country, 'TH');
    expect(state.locale, 'en');
    expect(state.consents, isEmpty);
    expect(prefs.deviceAccount, contains('"created_at":"2026-11-28T01:30:00.000Z"'));
  });

  test('the next start reads it back: the same id; the zone follows the phone',
      () async {
    final prefs = MemoryLocalPrefs();
    await open(prefs);
    final again = await open(prefs, timeZone: 'Europe/London');
    expect(again.currentUser!.id, 'id-1');
    expect((await again.load()).timeZone, 'Europe/London');
    // Saved too, so a later start without a zone change keeps it.
    expect(prefs.deviceAccount, contains('"time_zone":"Europe/London"'));
  });

  test('settings are kept on the phone across starts', () async {
    final prefs = MemoryLocalPrefs();
    final backend = await open(prefs);
    await backend.updateReminder(on: true, time: const ReminderTime(7, 30));
    await backend.updateProfile(country: '');
    await backend.updateLanguage('th');
    await backend.recordConsents(const [
      ConsentItem(ConsentKind.privacy, 'v1'),
    ]);
    await backend.completeSetup(const SetupChoices(reminderOn: false));

    final state = await (await open(prefs)).load();
    expect(state.reminderOn, isFalse, reason: 'Setup set it last');
    expect(state.reminderTime, ReminderTime.defaultTime);
    expect(state.country, isNull);
    expect(state.locale, 'th');
    expect(state.consents[ConsentKind.privacy]?.version, 'v1');
    expect(state.onboarded, isTrue);
  });

  test('an unreadable copy starts afresh (it holds settings only)', () async {
    final prefs = MemoryLocalPrefs(deviceAccount: '{not json');
    final backend = await open(prefs);
    expect(backend.currentUser!.id, 'id-1');
    expect(prefs.deviceAccount, contains('"id":"id-1"'));
  });

  test('delete forgets it; the next start makes a new one', () async {
    final prefs = MemoryLocalPrefs();
    final backend = await open(prefs);
    await backend.deleteMyAccount();
    expect(backend.currentUser, isNull);
    expect(prefs.deviceAccount, isNull);
    await expectLater(backend.load(), throwsA(AppFailure.accountGone));
    expect((await open(prefs)).currentUser!.id, 'id-2');
  });

  test('a start after delete through the session: a new device account',
      () async {
    final prefs = MemoryLocalPrefs();
    final backend = await open(prefs);
    await backend.deleteMyAccount();
    final user = await backend.signInAnonymously(
      profile: const SignupProfile(
        locale: 'en',
        timeZone: 'Asia/Bangkok',
        country: 'TH',
        consents: [],
      ),
    );
    expect(user.id, 'id-2');
    expect((await backend.load()).onboarded, isFalse);
    // Asked again with one in place: the same account, never a second one.
    final same = await backend.signInAnonymously(
      profile: const SignupProfile(
        locale: 'en',
        timeZone: 'Asia/Bangkok',
        country: null,
        consents: [],
      ),
    );
    expect(same.id, 'id-2');
  });

  test('no email paths on the phone; signing out keeps everything', () async {
    final prefs = MemoryLocalPrefs();
    final backend = await open(prefs);
    const profile = SignupProfile(
      locale: 'en',
      timeZone: 'UTC',
      country: null,
      consents: [],
    );
    expect(
      () => backend.signUp(email: 'a@example.invalid', password: 'x', profile: profile),
      throwsUnsupportedError,
    );
    expect(
      () => backend.signIn(email: 'a@example.invalid', password: 'x'),
      throwsUnsupportedError,
    );
    expect(() => backend.addEmail('a@example.invalid'), throwsUnsupportedError);
    expect(() => backend.setPassword('x'), throwsUnsupportedError);
    expect(() => backend.resendConfirmation('a@example.invalid'), throwsUnsupportedError);
    expect(() => backend.sendPasswordReset('a@example.invalid'), throwsUnsupportedError);
    expect(() => backend.updateAiSettings(enabled: true), throwsUnsupportedError);
    expect(await backend.ageSignalOn(), isFalse);

    await backend.signOut();
    expect(backend.currentUser?.id, 'id-1');
    expect(prefs.deviceAccount, isNotNull);
  });

  test('the session runs on it: a start signs in at once and routes to Home',
      () async {
    final prefs = MemoryLocalPrefs();
    final backend = await open(prefs);
    final session = AppSession(
      auth: backend,
      account: backend,
      prefs: prefs,
      device: FakeDevice(),
      aiEnabled: false,
      anonStart: true,
      reconnectEvery: null,
      shippedLocales: const ['en'],
    );
    await session.restore();
    expect(session.startState, StartState.done);
    expect(session.user?.id, 'id-1');
    expect(session.accountState?.timeZone, 'Asia/Bangkok');
    expect(session.redirect(Routes.home), isNull);
    expect(session.redirect(Routes.start), Routes.home);
    session.dispose();
  });
}
