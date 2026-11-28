import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/features/plus/fake_plus_store.dart';
import 'package:piggybow/features/plus/plus_entitlement.dart';
import 'package:piggybow/features/plus/plus_screen.dart';
import 'package:piggybow/features/plus/plus_store.dart';

import 'app_lock_test.dart' show FakeBiometrics;
import 'helpers.dart';

/// Piggybow Plus in the app (decision 79): Me's rows, the paywall at the
/// store's own prices, a purchase finished at once, Restore, the store's
/// cancel line per platform, Delete everything's line while Plus is on, and
/// a build without Plus showing none of it.
void main() {
  const owned = PlusProof(token: 't1', productId: plusPlayProductId);
  const withPlus = AppConfig(flavor: Flavor.staging, plusEnabled: true);

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Piggybow',
      packageName: 'com.burrowsoft.piggybow',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // Delete everything sweeps the export cache: a real folder where the app
  // asks for its temporary directory.
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('pb_plus');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => temp.path);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    temp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// Frames with real time between them: the wipe sweeps the cache with real
  /// file calls.
  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<({TestApp app, FakePlusStore store, MemoryPlusHint hint})> open(
    WidgetTester tester, {
    FakePlusStore? store,
    AppConfig config = withPlus,
    String location = '/me',
    bool plus = true,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    final s = store ?? FakePlusStore();
    final hint = MemoryPlusHint();
    final app = TestApp(
      config: config,
      plus: plus ? PlusEntitlement(store: s, hint: hint, clock: testClock) : null,
    );
    await tester.runAsync(app.openJournal);
    await app.pump(tester, location: location);
    await settle(tester, byId(location == '/me' ? 'me-happy' : 'plus-restore'));
    return (app: app, store: s, hint: hint);
  }

  testWidgets('a build without Plus: no Plus row, and nothing to gate', (tester) async {
    await open(tester, plus: false, config: const AppConfig(flavor: Flavor.staging));
    expect(byId('me-plus'), findsNothing);
    expect(find.text('Piggybow Plus'), findsNothing);
    final context = tester.element(byId('me-screen'));
    expect(await requirePlus(context), isFalse);
    await tester.pumpAndSettle();
    expect(byId('plus-screen'), findsNothing);
    await tester.tapId('me-delete');
    expect(byId('me-delete-plus-line'), findsNothing);
  });

  testWidgets("Me → Piggybow Plus: the paywall at the store's price, the yearly plan alone "
      'with its free week, and Google Play\'s cancel line', (tester) async {
    await open(tester);
    expect(find.text('More goals, your own categories and themes'), findsOneWidget);
    await tester.tapId('me-plus');
    await settle(tester, byId('plus-plan-yearly'));
    tester.expectScreen('plus-screen');
    for (final id in ['plus-benefit-goals', 'plus-benefit-categories', 'plus-benefit-themes']) {
      expect(byId(id), findsOneWidget, reason: id);
    }
    // Yearly only (decision 85): one plan.
    expect(byId('plus-plan-yearly'), findsOneWidget);
    expect(byId('plus-plan-monthly'), findsNothing);
    // With the free week, its line alone: the price never shows twice.
    expect(find.text('Free for 7 days, then £19.99 a year'), findsOneWidget);
    expect(find.text('£19.99 a year'), findsNothing);
    expect(byId('plus-plan-yearly-price'), findsNothing);
    expect(find.text('Start yearly'), findsNothing);
    expect(find.text('Start your free week'), findsOneWidget);
    expect(find.text('Cancel anytime in Google Play.'), findsOneWidget);
    expect(find.text('Cancel anytime in the App Store.'), findsNothing);
    // No link before its page is live.
    expect(byId('plus-terms'), findsNothing);
    expect(byId('plus-privacy'), findsNothing);
  });

  testWidgets('no free week offered: the yearly price line, and its own Start', (
    tester,
  ) async {
    await open(tester, store: FakePlusStore(trialOffered: false), location: '/plus');
    expect(find.text('£19.99 a year'), findsOneWidget);
    expect(byId('plus-plan-yearly-trial'), findsNothing);
    expect(find.text('Start yearly'), findsOneWidget);
    expect(find.text('Start your free week'), findsNothing);
  });

  testWidgets("the iPhone: the App Store's cancel line, and no other store named", (
    tester,
  ) async {
    await open(tester, store: FakePlusStore(source: PlusSource.apple), location: '/plus');
    expect(find.text('Cancel anytime in the App Store.'), findsOneWidget);
    expect(find.textContaining('Google Play'), findsNothing);
  });

  testWidgets('Terms of Use and Privacy Policy, once their pages are live', (tester) async {
    await open(
      tester,
      location: '/plus',
      config: const AppConfig(
        flavor: Flavor.staging,
        plusEnabled: true,
        termsUrl: 'https://example.invalid/terms',
        privacyUrl: 'https://example.invalid/privacy',
      ),
    );
    expect(byId('plus-terms'), findsOneWidget);
    expect(byId('plus-privacy'), findsOneWidget);
  });

  testWidgets('a price with a space stays whole', (tester) async {
    await open(
      tester,
      store: FakePlusStore(yearly: r'R$ 149,90', trialOffered: false),
      location: '/plus',
    );
    final nbsp = String.fromCharCode(0x00A0);
    expect(find.text('R\$${nbsp}149,90 a year'), findsOneWidget);
    expect(wholePrice('1 234,00 €'), '1${nbsp}234,00$nbsp€');
  });

  testWidgets('Start: bought, finished at once, Plus on; Me then offers Manage subscription', (
    tester,
  ) async {
    final o = await open(tester);
    await tester.tapId('me-plus');
    await settle(tester, byId('plus-plan-yearly-start'));
    await tester.tapId('plus-plan-yearly-start');
    expect(o.store.bought, [PlusPeriod.year]);
    expect(o.store.finished, ['fake-token-1']);
    tester.expectScreen('plus-on');
    await tester.tapId('plus-manage');
    expect(o.store.manageCalls, 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('More goals, your own categories and themes'), findsNothing);
    await tester.tapId('me-plus-manage');
    expect(o.store.manageCalls, 2);
  });

  testWidgets('a pending payment: its note, and Plus waits for the approval', (tester) async {
    await open(
      tester,
      store: FakePlusStore()..nextOutcome = const PlusPending(),
      location: '/plus',
    );
    await tester.tapId('plus-plan-yearly-start');
    expect(
      find.text('Your purchase is waiting for the store to confirm. Plus turns on as soon as it does.'),
      findsOneWidget,
    );
    expect(byId('plus-on'), findsNothing);
  });

  testWidgets('Restore: none found says so; a purchase found turns Plus on', (tester) async {
    final o = await open(tester, location: '/plus');
    await tester.tapId('plus-restore');
    expect(find.text('No Plus subscription was found for this store account.'), findsOneWidget);
    o.store.owns = const [owned];
    await tester.tapId('plus-restore');
    tester.expectScreen('plus-on');
    expect(find.text('Plus is back on. Welcome back!'), findsOneWidget);
  });

  testWidgets('no plans on this phone: its line, and Restore still there', (tester) async {
    await open(tester, store: FakePlusStore()..available = false, location: '/plus');
    expect(byId('plus-unavailable'), findsOneWidget);
    expect(byId('plus-plan-yearly'), findsNothing);
    expect(byId('plus-restore'), findsOneWidget);
  });

  for (final (source, line) in [
    (
      PlusSource.play,
      'Your Plus subscription keeps running until you cancel it in Google Play.',
    ),
    (
      PlusSource.apple,
      'Your Plus subscription keeps running until you cancel it in the App Store.',
    ),
  ]) {
    testWidgets("Delete everything while Plus is on (${source.name}): the store's line, "
        'and its page', (tester) async {
      final o = await open(tester, store: FakePlusStore(source: source)..owns = const [owned]);
      await tester.tapId('me-delete');
      expect(find.text(line), findsOneWidget);
      await tester.tapId('me-delete-plus-manage');
      expect(o.store.manageCalls, 1);
      await tester.tapId('me-delete-cancel');
      expect(find.text('Delete everything?'), findsNothing);
    });
  }

  testWidgets("Forgot PIN's erase while Plus is on: the same line, and the store's page", (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    addTearDown(tester.view.reset);
    // No fingerprint asked for as the lock shows (as in lock_screen_test).
    final lock = AppLock(
      store: MemorySecretStore(),
      biometrics: FakeBiometrics()..has = false,
      firstRun: MemoryFirstRunMarker(),
      iterations: 50,
    );
    await tester.runAsync(() => lock.setPin('2468'));
    lock.lockNow();
    final store = FakePlusStore()..owns = const [owned];
    final app = TestApp(
      appLock: lock,
      config: withPlus,
      plus: PlusEntitlement(store: store, hint: MemoryPlusHint(), clock: testClock),
    );
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    await waitFor(tester, byId('lock-screen'));
    await tester.tapId('lock-forgot');
    await tester.tapId('lock-forgot-erase');
    expect(
      find.text('Your Plus subscription keeps running until you cancel it in Google Play.'),
      findsOneWidget,
    );
    await tester.tapId('lock-erase-plus-manage');
    expect(store.manageCalls, 1);
    await tester.tapId('lock-erase-cancel');
    tester.expectScreen('lock-screen');
  });

  testWidgets('Delete everything while Plus is off: nothing about Plus', (tester) async {
    await open(tester);
    await tester.tapId('me-delete');
    expect(find.text('Delete everything?'), findsOneWidget);
    expect(byId('me-delete-plus-line'), findsNothing);
  });

  testWidgets('Delete everything erases the launch hint', (tester) async {
    final o = await open(tester, store: FakePlusStore()..owns = const [owned]);
    expect(o.hint.until, isNotNull);
    await tester.tapId('me-delete');
    await tester.tapId('me-delete-confirm');
    await waitFor(tester, byId('onb-welcome'));
    tester.expectScreen('onb-welcome');
    expect(o.hint.until, isNull);
  });

  testWidgets('requirePlus: with Plus off the paywall opens; with Plus on it passes', (
    tester,
  ) async {
    final o = await open(tester);
    final context = tester.element(byId('me-screen'));
    bool? answer;
    final asked = requirePlus(context).then((on) => answer = on);
    await settle(tester, byId('plus-restore'));
    tester.expectScreen('plus-screen');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await asked;
    expect(answer, isFalse);

    o.store.owns = const [owned];
    await o.app.plus!.refresh();
    expect(await requirePlus(context), isTrue);
  });
}
