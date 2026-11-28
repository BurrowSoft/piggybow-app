import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:piggybow/features/plus/iap_plus_store.dart';
import 'package:piggybow/features/plus/plus_store.dart';

/// The store layer over in_app_purchase (pinned), with a fake gateway: what
/// a purchase reports, and each way a store's sheet can end.
class _Gateway implements IapGateway {
  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  ({Object handle, String price, bool trial})? offer = (handle: 'p', price: '£49.99', trial: true);
  final bought = <Object>[];
  int restores = 0;
  final completed = <PurchaseDetails>[];

  /// What a buy or a restore makes the store report.
  List<PurchaseDetails> Function()? onBuy;
  List<PurchaseDetails> Function()? onRestore;

  @override
  Stream<List<PurchaseDetails>> get purchases => stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<({Object handle, String price, bool trial})?> product(String id) async => offer;

  @override
  Future<bool> buy(Object handle) async {
    bought.add(handle);
    if (onBuy case final make?) scheduleMicrotask(() => stream.add(make()));
    return true;
  }

  @override
  Future<void> restore() async {
    restores++;
    if (onRestore case final make?) scheduleMicrotask(() => stream.add(make()));
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async => completed.add(purchase);

  int manageCalls = 0;
  @override
  Future<void> manageSubscriptions() async => manageCalls++;
}

PurchaseDetails _p(PurchaseStatus status, {String token = 'tok', String? id = 'GPA.1', bool pending = true}) =>
    PurchaseDetails(
      purchaseID: id,
      productID: plusProductId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: token,
        source: 'test',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = pending;

void main() {
  test('the product: the store price and its own word on the free week', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    final p = (await store.product())!;
    expect([p.price, p.trialOffered], ['£49.99', true]);
    g.available = false;
    expect(await store.product(), isNull);
  });

  test("Play: bought → the purchase token and the product's handle; finished once", () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.purchased, token: 'play-token')];
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    await store.product();
    final out = await store.buy();
    expect(g.bought, ['p']);
    expect(out, isA<PlusBought>());
    final proof = (out as PlusBought).proof;
    expect([proof.token, proof.productId], ['play-token', plusProductId]);
    await store.finish(proof);
    expect(g.completed, hasLength(1));
  });

  test('Apple: the transaction id', () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.purchased, token: 'jws', id: '2000000123')];
    final store = IapPlusStore(source: PlusSource.apple, gateway: g);
    final out = await store.buy();
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
      expect(await store.buy(), want, reason: '$status');
    }
  });

  test('no product here: a buy fails without a sheet', () async {
    final g = _Gateway()..offer = null;
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    expect(await store.buy(), isA<PlusBuyFailed>());
    expect(g.bought, isEmpty);
  });

  test('Restore: what the store reports, once per token, and a purchase nobody waited for', () async {
    final g = _Gateway()
      ..onRestore = () => [
        _p(PurchaseStatus.restored, token: 'a'),
        _p(PurchaseStatus.restored, token: 'a'),
        _p(PurchaseStatus.restored, token: 'b'),
      ];
    final store = IapPlusStore(source: PlusSource.play, gateway: g, restoreQuiet: Duration.zero);
    await store.product();
    // A purchase reported with nobody buying (finished elsewhere, or left over).
    g.stream.add([_p(PurchaseStatus.purchased, token: 'left')]);
    await Future<void>.delayed(Duration.zero);
    final found = await store.restore();
    expect(g.restores, 1);
    expect(found.map((p) => p.token), ['left', 'a', 'b']);
  });

  test('finish: only a purchase still waiting to be completed', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    await store.finish(PlusProof(token: 't', productId: plusProductId, handle: _p(PurchaseStatus.purchased, pending: false)));
    expect(g.completed, isEmpty);
  });

  // A cancelled or failed transaction still waiting is completed, or
  // StoreKit reports it again on every start; one already completed is left
  // alone.
  for (final status in [PurchaseStatus.canceled, PurchaseStatus.error]) {
    test('${status.name}: completed if still waiting, never handed over', () async {
      final waiting = _p(status);
      final g = _Gateway()..onBuy = () => [waiting];
      final store = IapPlusStore(source: PlusSource.apple, gateway: g);
      final out = await store.buy();
      expect(out, status == PurchaseStatus.canceled ? isA<PlusCancelled>() : isA<PlusBuyFailed>());
      await Future<void>.delayed(Duration.zero);
      expect(g.completed, [waiting]);
      expect(store.takeUnclaimed(), isEmpty);
    });
  }

  test('a cancel already completed: nothing completed again', () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.canceled, pending: false)];
    final store = IapPlusStore(source: PlusSource.apple, gateway: g);
    await store.buy();
    await Future<void>.delayed(Duration.zero);
    expect(g.completed, isEmpty);
  });

  test('takeUnclaimed: purchases reported with nobody waiting, once each, '
      'then gone', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    expect(store.takeUnclaimed(), isEmpty, reason: 'and now it listens');
    g.stream.add([
      _p(PurchaseStatus.purchased, token: 'left'),
      _p(PurchaseStatus.restored, token: 'left'),
      _p(PurchaseStatus.purchased, token: 'other'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(store.takeUnclaimed().map((p) => p.token), ['left', 'other']);
    expect(store.takeUnclaimed(), isEmpty);
  });
}
