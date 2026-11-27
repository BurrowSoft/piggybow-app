import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:piggybow/data/plus.dart';
import 'package:piggybow/features/plus/iap_plus_store.dart';
import 'package:piggybow/features/plus/plus_store.dart';

/// The store layer over in_app_purchase (UX: approved, pinned), with a fake
/// gateway: the proof plus-store gets, the account it's tied to, and each
/// way a store's sheet can end.
class _Gateway implements IapGateway {
  final stream = StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  ({Object handle, String price, bool trial, String? offerPrice})? offer = (handle: 'p', price: '£49.99', trial: true, offerPrice: null);
  bool? askedOffer;
  final bought = <String>[];
  final restoredFor = <String>[];
  final completed = <PurchaseDetails>[];

  /// What a buy or a restore makes the store report.
  List<PurchaseDetails> Function()? onBuy;
  List<PurchaseDetails> Function()? onRestore;

  @override
  Stream<List<PurchaseDetails>> get purchases => stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<({Object handle, String price, bool trial, String? offerPrice})?> product(String id, {bool offer = false}) async {
    askedOffer = offer;
    return this.offer;
  }

  @override
  Future<bool> buy(Object handle, {required String applicationUserName}) async {
    bought.add(applicationUserName);
    if (onBuy case final make?) scheduleMicrotask(() => stream.add(make()));
    return true;
  }

  @override
  Future<void> restore({required String applicationUserName}) async {
    restoredFor.add(applicationUserName);
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
  const uid = 'AAAA1111-2222-4333-8444-555555555555';

  test("Play's account id: sha-256 of the lower-cased uid, hex (as plus-store's)", () {
    expect(playAccountId('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(playAccountId(uid), playAccountId(uid.toLowerCase()));
    expect(playAccountId(uid), hasLength(64));
  });

  test('the product: the store price and its own word on the free week', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    final p = (await store.product())!;
    expect([p.price, p.trialOffered], ['£49.99', true]);
    g.available = false;
    expect(await store.product(), isNull);
  });

  test("the Christmas special: asked only when told, the store's own first-year "
      'price, and no free week beside it', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    await store.product();
    expect(g.askedOffer, isFalse);
    g.offer = (handle: 'o', price: '£49.99', trial: true, offerPrice: '£24.99');
    final p = (await store.product(offer: true))!;
    expect(g.askedOffer, isTrue);
    expect([p.price, p.offerPrice, p.trialOffered], ['£49.99', '£24.99', false]);
  });

  test('Play: bought → the purchase token, tied to the hashed account; finished once verified', () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.purchased, token: 'play-token')];
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    await store.product();
    final out = await store.buy(accountId: uid);
    expect(g.bought, [playAccountId(uid)]);
    expect(out, isA<PlusBought>());
    final proof = (out as PlusBought).proof;
    expect([proof.token, proof.productId], ['play-token', plusProductId]);
    await store.finish(proof);
    expect(g.completed, hasLength(1));
  });

  test("Apple: the transaction id, tied to the uid itself (appAccountToken)", () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.purchased, token: 'jws', id: '2000000123')];
    final store = IapPlusStore(source: PlusSource.apple, gateway: g);
    final out = await store.buy(accountId: uid);
    expect(g.bought, [uid.toLowerCase()], reason: 'a lower-case UUID, as appAccountToken');
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
      expect(await store.buy(accountId: uid), want, reason: '$status');
    }
  });

  test('no product here: a buy fails without a sheet', () async {
    final g = _Gateway()..offer = null;
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    expect(await store.buy(accountId: uid), isA<PlusBuyFailed>());
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
    final found = await store.restore(accountId: uid);
    expect(g.restoredFor, [playAccountId(uid)]);
    expect(found.map((p) => p.token), ['left', 'a', 'b']);
  });

  test('finish: only a purchase still waiting to be completed', () async {
    final g = _Gateway();
    final store = IapPlusStore(source: PlusSource.play, gateway: g);
    await store.finish(PlusProof(token: 't', productId: plusProductId, handle: _p(PurchaseStatus.purchased, pending: false)));
    expect(g.completed, isEmpty);
  });

  // The Reviewer's payments audit (UX, 14 Nov): a cancelled or failed
  // transaction still waiting is completed, or StoreKit reports it again on
  // every start; one already completed is left alone.
  for (final status in [PurchaseStatus.canceled, PurchaseStatus.error]) {
    test('${status.name}: completed if still waiting, never verified', () async {
      final waiting = _p(status);
      final g = _Gateway()..onBuy = () => [waiting];
      final store = IapPlusStore(source: PlusSource.apple, gateway: g);
      final out = await store.buy(accountId: uid);
      expect(out, status == PurchaseStatus.canceled ? isA<PlusCancelled>() : isA<PlusBuyFailed>());
      await Future<void>.delayed(Duration.zero);
      expect(g.completed, [waiting]);
      expect(store.takeUnclaimed(), isEmpty);
    });
  }

  test('a cancel already completed: nothing completed again', () async {
    final g = _Gateway()..onBuy = () => [_p(PurchaseStatus.canceled, pending: false)];
    final store = IapPlusStore(source: PlusSource.apple, gateway: g);
    await store.buy(accountId: uid);
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
