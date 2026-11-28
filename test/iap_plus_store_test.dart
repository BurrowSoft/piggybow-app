import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:piggybow/features/plus/iap_plus_store.dart';
import 'package:piggybow/features/plus/plus_store.dart';

/// The store layer over in_app_purchase (pinned), with a fake gateway: the
/// plans, what the store account owns, what a purchase reports, and each
/// way a store's sheet can end.
class _Gateway implements IapGateway {
  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  List<PlusPlan> offered = const [
    PlusPlan(period: PlusPeriod.month, price: '£2.99', trialOffered: false, handle: 'm'),
    PlusPlan(period: PlusPeriod.year, price: '£19.99', trialOffered: true, handle: 'y'),
  ];
  List<PlusProof>? owns = const [];
  Object? ownedError;
  final bought = <Object>[];
  final completed = <Object>[];

  /// What a buy makes the store report.
  List<PurchaseDetails> Function()? onBuy;

  @override
  Stream<List<PurchaseDetails>> get purchases => stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<PlusPlan>> plans() async => offered;

  @override
  Future<bool> buy(Object handle) async {
    bought.add(handle);
    if (onBuy case final make?) scheduleMicrotask(() => stream.add(make()));
    return true;
  }

  @override
  Future<List<PlusProof>?> owned() async {
    if (ownedError case final e?) throw e;
    return owns;
  }

  @override
  Future<void> complete(Object handle) async => completed.add(handle);

  int manageCalls = 0;
  @override
  Future<void> manageSubscriptions() async => manageCalls++;
}

PurchaseDetails _p(
  PurchaseStatus status, {
  String token = 'tok',
  String? id = 'GPA.1',
  String productId = plusPlayProductId,
  bool pending = true,
}) => PurchaseDetails(
  purchaseID: id,
  productID: productId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: token,
    source: 'test',
  ),
  transactionDate: null,
  status: status,
)..pendingCompletePurchase = pending;

PlayPhase _phase(int micros, String price, String period, {int cycles = 0}) =>
    (micros: micros, price: price, period: period, cycles: cycles);

PlayOffer _offer(String plan, String? offerId, List<PlayPhase> phases) =>
    (basePlanId: plan, offerId: offerId, phases: phases, handle: '$plan/${offerId ?? 'base'}');

void main() {
  const yearly = PlusPlan(period: PlusPeriod.year, price: '£19.99', trialOffered: true, handle: 'y');

  test("the plans: the store's own, none when purchases aren't available", () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    final plans = await store.plans();
    expect([for (final p in plans) (p.period, p.price, p.trialOffered)], [
      (PlusPeriod.month, '£2.99', false),
      (PlusPeriod.year, '£19.99', true),
    ]);
    g.available = false;
    expect(await store.plans(), isEmpty);
  });

  test('Play: bought → the purchase token, still to finish; finished once', () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.purchased, token: 'play-token')];
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    final out = await store.buy(yearly);
    expect(g.bought, ['y']);
    final proof = (out as PlusBought).proof;
    expect([proof.token, proof.productId, proof.needsFinish], ['play-token', plusPlayProductId, true]);
    await store.finish(proof);
    expect(g.completed, hasLength(1));
  });

  test('Apple: the transaction id', () async {
    final g = _Gateway()
      ..onBuy = () => [
        _p(PurchaseStatus.purchased, token: 'jws', id: '2000000123', productId: plusAppleYearlyId),
      ];
    final store = IapPlusStore(source: PlusSource.apple, gateway: g);
    final out = await store.buy(yearly);
    expect((out as PlusBought).proof.token, '2000000123');
  });

  test('cancelled, pending, an error: each its own outcome', () async {
    for (final (status, want) in [
      (PurchaseStatus.canceled, isA<PlusCancelled>()),
      (PurchaseStatus.pending, isA<PlusPending>()),
      (PurchaseStatus.error, isA<PlusBuyFailed>()),
    ]) {
      final g = _Gateway()..onBuy = () => [_p(status)];
      final store = IapPlusStore(source: PlusSource.play, gateway: g);
      expect(await store.buy(yearly), want, reason: '$status');
    }
  });

  test('a plan the store gave no handle: a buy fails without a sheet', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    const none = PlusPlan(period: PlusPeriod.month, price: '£2.99', trialOffered: false);
    expect(await store.buy(none), isA<PlusBuyFailed>());
    expect(g.bought, isEmpty);
  });

  test("owned: Plus's own purchases, once each; null whenever the store can't say", () async {
    final g = _Gateway()
      ..owns = const [
        PlusProof(token: 'a', productId: plusPlayProductId),
        PlusProof(token: 'a', productId: plusPlayProductId),
        PlusProof(token: 'x', productId: 'another_product'),
        PlusProof(token: '', productId: plusPlayProductId),
        PlusProof(token: 'b', productId: plusAppleMonthlyId),
      ];
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    expect((await store.owned())!.map((p) => p.token), ['a', 'b']);
    g.owns = const [];
    expect(await store.owned(), isEmpty, reason: "the store's word: none");
    g.owns = null;
    expect(await store.owned(), isNull);
    g
      ..owns = const []
      ..ownedError = StateError('the store app is not answering');
    expect(await store.owned(), isNull);
    g
      ..ownedError = null
      ..available = false;
    expect(await store.owned(), isNull);
  });

  test('finish: only a purchase that still waits', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    await store.finish(const PlusProof(token: 't', productId: plusPlayProductId, handle: 'done'));
    expect(g.completed, isEmpty);
    await store.finish(
      const PlusProof(token: 't', productId: plusPlayProductId, handle: 'open', needsFinish: true),
    );
    expect(g.completed, ['open']);
  });

  // A cancelled or failed transaction still waiting is completed, or
  // StoreKit reports it again on every start; one already completed is left
  // alone.
  for (final status in [PurchaseStatus.canceled, PurchaseStatus.error]) {
    test('${status.name}: completed if still waiting, never handed over', () async {
      final waiting = _p(status);
      final g = _Gateway()..onBuy = () => [waiting];
      final store = IapPlusStore(source: PlusSource.apple, gateway: g);
      final out = await store.buy(yearly);
      expect(out, status == PurchaseStatus.canceled ? isA<PlusCancelled>() : isA<PlusBuyFailed>());
      await Future<void>.delayed(Duration.zero);
      expect(g.completed, [waiting]);
      expect(store.takeUnclaimed(), isEmpty);
    });
  }

  test('a cancel already completed: nothing completed again', () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.canceled, pending: false)];
    final store = IapPlusStore(source: PlusSource.apple, gateway: g);
    await store.buy(yearly);
    await Future<void>.delayed(Duration.zero);
    expect(g.completed, isEmpty);
  });

  test('takeUnclaimed: purchases reported with nobody waiting, announced, once each, '
      'then gone; another product is not Plus', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    var pings = 0;
    store.changes.addListener(() => pings++);
    expect(store.takeUnclaimed(), isEmpty, reason: 'and now it listens');
    g.stream.add([_p(PurchaseStatus.purchased, token: 'z', productId: 'another_product')]);
    await Future<void>.delayed(Duration.zero);
    expect(pings, 0);
    g.stream.add([
      _p(PurchaseStatus.purchased, token: 'left'),
      _p(PurchaseStatus.restored, token: 'left'),
      _p(PurchaseStatus.purchased, token: 'other'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(pings, 1);
    final taken = store.takeUnclaimed();
    expect(taken.map((p) => p.token), ['left', 'other']);
    expect(taken.every((p) => p.needsFinish), isTrue);
    expect(store.takeUnclaimed(), isEmpty);
  });

  group("playPlans: Play's base plans and offers, as the paywall shows them", () {
    final monthly = _offer(plusPlayMonthlyPlan, null, [_phase(2990000, '£2.99', 'P1M')]);
    final yearlyBase = _offer(plusPlayYearlyPlan, null, [_phase(19990000, '£19.99', 'P1Y')]);
    final freeWeek = _offer(plusPlayYearlyPlan, 'free-week', [
      _phase(0, 'Free', 'P1W', cycles: 1),
      _phase(19990000, '£19.99', 'P1Y'),
    ]);

    test('monthly first; the free week on the plan Play offers it on, bought with it', () {
      final plans = playPlans([yearlyBase, freeWeek, monthly]);
      expect([for (final p in plans) (p.period, p.price, p.trialOffered, p.handle)], [
        (PlusPeriod.month, '£2.99', false, 'monthly/base'),
        (PlusPeriod.year, '£19.99', true, 'yearly/free-week'),
      ]);
    });

    test('7 days counts as a week; any other offer is not the free week', () {
      final sevenDays = _offer(plusPlayYearlyPlan, 'seven', [
        _phase(0, 'Free', 'P7D', cycles: 1),
        _phase(19990000, '£19.99', 'P1Y'),
      ]);
      expect(playPlans([yearlyBase, sevenDays]).single.trialOffered, isTrue);
      for (final other in [
        _offer(plusPlayYearlyPlan, 'three-days', [_phase(0, 'Free', 'P3D', cycles: 1)]),
        _offer(plusPlayYearlyPlan, 'two-weeks', [_phase(0, 'Free', 'P1W', cycles: 2)]),
        _offer(plusPlayYearlyPlan, 'cheaper-first-year', [_phase(9990000, '£9.99', 'P1Y', cycles: 1)]),
      ]) {
        final plan = playPlans([yearlyBase, other]).single;
        expect([plan.trialOffered, plan.handle], [false, 'yearly/base'], reason: '${other.offerId}');
      }
    });

    test('a plan with no base plan, or no paid phase, is not on sale; other plans are ignored', () {
      expect(playPlans([freeWeek, monthly]).map((p) => p.period), [PlusPeriod.month]);
      expect(playPlans([_offer(plusPlayMonthlyPlan, null, [_phase(0, 'Free', 'P1M')])]), isEmpty);
      expect(playPlans([_offer('weekly', null, [_phase(990000, '£0.99', 'P1W')])]), isEmpty);
      expect(playPlans(const []), isEmpty);
    });

    test('playFreeWeek: free, billed once, a week', () {
      expect(playFreeWeek(_phase(0, 'Free', 'P1W', cycles: 1)), isTrue);
      expect(playFreeWeek(_phase(0, 'Free', 'P7D', cycles: 1)), isTrue);
      expect(playFreeWeek(_phase(1, '£0.00', 'P1W', cycles: 1)), isFalse);
      expect(playFreeWeek(_phase(0, 'Free', 'P1W', cycles: 0)), isFalse);
      expect(playFreeWeek(_phase(0, 'Free', 'P1M', cycles: 1)), isFalse);
    });
  });

  test("Play's subscription page for Plus, in the Play Store app", () {
    expect(
      playSubscriptionsUri('com.burrowsoft.piggybow').toString(),
      'https://play.google.com/store/account/subscriptions?sku=piggybow_plus&package=com.burrowsoft.piggybow',
    );
  });

  test("Plus's product ids, and nothing else", () {
    for (final id in [plusPlayProductId, plusAppleMonthlyId, plusAppleYearlyId]) {
      expect(isPlusProduct(id), isTrue, reason: id);
    }
    expect(isPlusProduct('piggybow_plus_weekly'), isFalse);
    expect(isPlusProduct(''), isFalse);
  });
}
