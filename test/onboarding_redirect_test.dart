import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/session/app_session.dart';

String? go(
  String location, {
  bool language = true,
  bool welcome = false,
  bool signedIn = false,
  bool consents = false,
  bool onboarded = false,
  bool pendingConsents = false,
  bool pendingEmail = false,
}) => onboardingRedirect(
  languageChosen: language,
  welcomeSeen: welcome,
  signedIn: signedIn,
  hasConsents: consents,
  onboarded: onboarded,
  hasPendingConsents: pendingConsents,
  hasPendingEmail: pendingEmail,
  location: location,
);

void main() {
  test('no language yet → Language, from anywhere', () {
    expect(go('/home', language: false), Routes.language);
    expect(go(Routes.signin, language: false), Routes.language);
    expect(go(Routes.language, language: false), isNull);
  });

  test('signed out: first launch → Welcome, returning → Sign in', () {
    expect(go('/home'), Routes.welcome);
    expect(go('/home', welcome: true), Routes.signin);
    expect(go(Routes.setup, welcome: true), Routes.signin);
    for (final path in Routes.signedOut.difference({
      Routes.signup,
      Routes.checkEmail,
      // Flag off → Welcome (anon_start_test.dart).
      Routes.firstOpen,
    })) {
      expect(go(path), isNull, reason: path);
    }
  });

  test('Create account needs the consents first', () {
    expect(go(Routes.signup), Routes.consent);
    expect(go(Routes.signup, pendingConsents: true), isNull);
  });

  test('Check email needs a pending signup', () {
    expect(go(Routes.checkEmail), Routes.signin);
    expect(go(Routes.checkEmail, pendingEmail: true), isNull);
  });

  test('signed in without current consents → Consent', () {
    expect(go('/home', signedIn: true), Routes.consent);
    expect(go(Routes.setup, signedIn: true), Routes.consent);
    expect(go(Routes.consent, signedIn: true), isNull);
  });

  test('signed in, consented, not set up → Setup', () {
    expect(go('/home', signedIn: true, consents: true), Routes.setup);
    expect(go(Routes.setup, signedIn: true, consents: true), isNull);
  });

  test('fully onboarded: tabs allowed, onboarding pages → Today', () {
    expect(go('/me', signedIn: true, consents: true, onboarded: true), isNull);
    for (final path in [
      Routes.signin,
      Routes.welcome,
      Routes.setup,
      Routes.language,
      Routes.consent,
    ]) {
      expect(
        go(path, signedIn: true, consents: true, onboarded: true),
        Routes.home,
        reason: path,
      );
    }
  });
}
