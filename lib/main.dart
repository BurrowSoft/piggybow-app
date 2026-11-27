import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'core/app_lock.dart';
import 'core/clock.dart';
import 'core/device.dart';
import 'core/local_day.dart';
import 'core/local_prefs.dart';
import 'core/sentry_setup.dart';
import 'core/services.dart';
import 'core/startup_trace.dart';
import 'data/device_backend.dart';
import 'features/pig/pig_view.dart';
import 'features/reminder/reminder_scheduler.dart';
import 'journal/journal_store.dart';
import 'l10n/gen/app_localizations.dart';
import 'money/currency.dart';
import 'router.dart';
import 'session/app_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  const device = PlatformDeviceContext();

  // The start-up steps don't depend on each other: start them all, then
  // wait (cold start = the slowest step, not the sum). Every region's date
  // symbols, so dates follow the device region.
  final dates = initializeDateFormatting();
  // The pigs, decoded before the first frame: Home's pig is never late.
  final pigsLoad = precachePigs();
  final prefsLoad = SharedLocalPrefs.load();
  final timeZoneLoad = device.timeZone();
  // Read before the first frame: a cold start with the lock on must never
  // render the app unlocked.
  final appLock = config.appLockEnabled
      ? AppLock(
          store: const KeystoreSecretStore(),
          biometrics: DeviceBiometrics(),
          firstRun: const PrefsFirstRunMarker(),
        )
      : null;
  // FAKE_NOW pins the time in staging test builds (ignored in prod).
  final clock = Clock(fixed: config.fakeNow);
  final journalLoad = JournalStore.open(clock: clock);
  // "Today" follows the phone's own time zone, read now and on every resume.
  final localDay = LocalDay(clock: clock, device: device);
  final dayLoad = localDay.refresh();
  AppLifecycleListener(onResume: () => unawaited(localDay.refresh()));

  StartupTrace.mark('prefs');
  final prefs = await prefsLoad;
  // v0.1 runs on the phone only: no account, no server.
  StartupTrace.mark('backend');
  final backend = await DeviceBackend.open(
    prefs: prefs,
    timeZone: await timeZoneLoad,
    country: device.countryCode,
  );
  final lockLoad = appLock?.load(userId: backend.currentUser?.id);

  final session = AppSession(
    auth: backend,
    account: backend,
    prefs: prefs,
    device: device,
    aiEnabled: false,
    anonStart: true,
    clock: clock,
    shippedLocales: config.shippedLocaleCodes(
      AppLocalizations.supportedLocales.map((l) => l.languageCode),
    ),
  );
  unawaited(session.restore());

  StartupTrace.mark('dates');
  await dates;
  // Still before the first real screen: the app never renders unlocked.
  StartupTrace.mark('lock');
  if (lockLoad != null) await lockLoad;

  StartupTrace.mark('journal');
  await dayLoad;
  final journal = await journalLoad;
  // Until onboarding asks, the journal's currency is the phone's (else USD).
  if (await journal.currency() == null) {
    await journal.setCurrency(
      defaultCurrency(
        WidgetsBinding.instance.platformDispatcher.locale.toString(),
      ),
    );
  }

  StartupTrace.mark('services');
  final services = AppServices(
    clock: clock,
    localDay: localDay,
    journal: journal,
    reminders: PlatformReminderScheduler(),
    notifications: const PlatformNotificationPermission(),
    appLock: appLock,
  );
  // The pig's reaction to an Add lasts until the app goes to the background.
  AppLifecycleListener(onHide: () => services.lastAdd.value = null);

  Widget app(List<NavigatorObserver> observers) => PiggybowApp(
    config: config,
    session: session,
    services: services,
    router: buildRouter(session: session, observers: observers),
  );

  // Without a DSN (dev, CI, tests, and v0.1 so far) Sentry stays off entirely.
  await pigsLoad;
  StartupTrace.mark('run-app');
  if (config.sentryDsn.isEmpty) {
    runApp(app(const []));
    StartupTrace.mark('running');
    return;
  }

  await SentryFlutter.init(
    (options) => configureSentry(options, config),
    appRunner: () => runApp(app([piggybowNavigatorObserver()])),
  );
  StartupTrace.mark('running');
}
