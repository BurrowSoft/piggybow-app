import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piggybow/app.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/core/device.dart';
import 'package:piggybow/core/local_day.dart';
import 'package:piggybow/core/local_prefs.dart';
import 'package:piggybow/core/policy.dart';
import 'package:piggybow/core/services.dart';
import 'package:piggybow/data/device_backend.dart';
import 'package:piggybow/data/models.dart';
import 'package:piggybow/features/reminder/reminder_plan.dart';
import 'package:piggybow/features/reminder/reminder_scheduler.dart';
import 'package:piggybow/journal/journal_store.dart';
import 'package:piggybow/router.dart';
import 'package:piggybow/session/app_session.dart';

class FakeDevice implements DeviceContext {
  FakeDevice({
    this.languageCode = 'en',
    this.countryCode = 'TH',
    this.localeName = 'en_US',
  });

  @override
  final String languageCode;

  @override
  final String? countryCode;

  @override
  final String localeName;

  @override
  Future<String> timeZone() async => 'Asia/Bangkok';
}

/// The reminders as the phone would hold them.
class FakeReminderScheduler implements ReminderScheduler {
  /// What is scheduled now (empty after a cancel).
  List<PlannedReminder> scheduled = const [];
  ReminderCopy? copy;
  int replaces = 0;
  int cancels = 0;

  /// A reminder tapped and not yet answered; a test taps one with [tap].
  @override
  final ValueNotifier<bool> tapPending = ValueNotifier<bool>(false);

  /// A reminder tapped (or the app started from one).
  void tap() {
    tapPending.value = true;
  }

  @override
  bool takeTap() {
    if (!tapPending.value) return false;
    tapPending.value = false;
    return true;
  }

  @override
  Future<void> listen() async {}

  @override
  Future<void> replaceAll(List<PlannedReminder> plan, ReminderCopy copy) async {
    replaces++;
    scheduled = List.of(plan);
    this.copy = copy;
  }

  /// Makes [cancelAll] fail (a wipe step that fails).
  bool failCancel = false;

  @override
  Future<void> cancelAll() async {
    if (failCancel) throw StateError('no notifications service');
    cancels++;
    scheduled = const [];
  }
}

class FakeNotifications implements NotificationPermission {
  int requests = 0;

  /// How many times Me opened the phone's notification settings.
  int settingsOpened = 0;

  @override
  Future<void> openSettings() async => settingsOpened++;
  bool grant = true;

  /// Whether notifications are allowed now (a granted request sets it).
  bool enabled = true;

  @override
  Future<bool> granted() async => enabled;

  @override
  Future<bool> request() async {
    requests++;
    enabled = grant;
    return grant;
  }
}

/// The consents at the current versions (none is required in v0.1).
const currentConsents = [
  ConsentItem(ConsentKind.privacy, PolicyVersions.privacy),
  ConsentItem(ConsentKind.terms, PolicyVersions.terms),
  ConsentItem(ConsentKind.age18, PolicyVersions.age18),
];

/// Everything a widget test needs to drive the app, started as main() does:
/// the device account (made on the first start), the session, the router.
class TestApp {
  TestApp({
    String deviceLanguage = 'en',
    String? deviceCountry = 'TH',
    String deviceLocaleName = 'en_US',
    String? chosenLocale,
    String? deviceAccount,
    this.shippedLocales = const ['en'],
    this.appLock,
    this.currency = 'THB',
    this.onboarded = true,
    this.config = const AppConfig(flavor: Flavor.staging),
    Clock? clock,
  }) : clock = clock ?? testClock,
       prefs = MemoryLocalPrefs(
         localeCode: chosenLocale,
         deviceAccount: deviceAccount,
       ),
       device = FakeDevice(
         languageCode: deviceLanguage,
         countryCode: deviceCountry,
         localeName: deviceLocaleName,
       );

  /// The app's clock (the session and services); [MovableClock] to move it.
  final Clock clock;
  final MemoryLocalPrefs prefs;
  final FakeDevice device;
  final reminders = FakeReminderScheduler();
  final notifications = FakeNotifications();
  int stagingErrors = 0;
  final List<String> shippedLocales;

  /// App lock; null = the feature off.
  final AppLock? appLock;

  /// The journal's currency.
  final String currency;

  /// Whether onboarding is done: tests start on Home unless they say not.
  final bool onboarded;

  /// The build's configuration (a Sentry DSN, the policy and help links).
  final AppConfig config;

  late final DeviceBackend backend;
  late final AppSession session;

  /// The journal, in memory; entry ids are entry-1, entry-2…
  late final JournalStore journal;
  late final LocalDay localDay;
  int _ids = 0;

  /// Device account ids: device-1, then device-2 after Delete everything…
  int _deviceIds = 0;

  late final services = AppServices(
    clock: clock,
    localDay: localDay,
    journal: journal,
    reminders: reminders,
    notifications: notifications,
    appLock: appLock,
    stagingTestError: () => stagingErrors++,
    onboarded: onboarded,
  );

  /// Opens the journal and today (call before adding test data; [pump]
  /// calls it when a test didn't).
  Future<void> openJournal() async {
    if (_journalOpen) return;
    _journalOpen = true;
    journal = await JournalStore.inMemory(
      clock: clock,
      newId: () => 'entry-${++_ids}',
    );
    await journal.setCurrency(currency);
    if (onboarded) await journal.setOnboarded();
    localDay = LocalDay(clock: clock, device: device);
    await localDay.refresh();
  }

  bool _journalOpen = false;

  Future<void> pump(WidgetTester tester, {String? location}) async {
    await initializeDateFormatting();
    // The store works on real time (not the test's fake one).
    await tester.runAsync(openJournal);
    backend = await DeviceBackend.open(
      prefs: prefs,
      timeZone: await device.timeZone(),
      country: device.countryCode,
      newId: () => 'device-${++_deviceIds}',
      now: clock.nowUtc,
    );
    session = AppSession(
      auth: backend,
      account: backend,
      prefs: prefs,
      device: device,
      aiEnabled: false,
      anonStart: true,
      // No periodic retry timer in tests (none may be left pending).
      reconnectEvery: null,
      shippedLocales: shippedLocales,
      clock: clock,
    );
    await session.restore();
    await tester.pumpWidget(
      PiggybowApp(
        config: config,
        session: session,
        services: services,
        router: buildRouter(
          session: session,
          initialLocation: location ?? Routes.home,
          onboarded: services.onboarded,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Finder byId(String id) => find.bySemanticsIdentifier(id);

extension Driver on WidgetTester {
  /// Scrolls a lazily built list until [id] exists.
  Future<void> revealId(String id) async {
    if (byId(id).evaluate().isEmpty) {
      await scrollUntilVisible(
        byId(id),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await ensureVisible(byId(id));
  }

  Future<void> tapId(String id) async {
    await revealId(id);
    await pumpAndSettle();
    await tap(byId(id));
    await pumpAndSettle();
  }

  Future<void> enterId(String id, String text) async {
    await enterText(
      find.descendant(of: byId(id), matching: find.byType(TextField)),
      text,
    );
    await pumpAndSettle();
  }

  void expectScreen(String id) =>
      expect(byId(id), findsOneWidget, reason: 'expected $id');
}

/// A clock a test moves by hand.
class MovableClock extends Clock {
  MovableClock(this.now);

  DateTime now;

  @override
  DateTime nowUtc() => now;
}

/// Tests run at Friday 2 October 2026, 08:30 in Bangkok (01:30 UTC).
final testClock = Clock(fixed: DateTime.parse('2026-10-02T08:30:00+07:00'));
