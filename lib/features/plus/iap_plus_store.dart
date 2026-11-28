import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'
    show InAppPurchaseStoreKitPlatformAddition;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' show SK2Product;
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart'
    show SKProductDiscountPaymentMode, SKProductDiscountWrapper, SKRequestMaker, SKSubscriptionPeriodUnit;

import 'plus_store.dart';

/// Whether Apple's introductory offer for this Apple ID is the free week,
/// from StoreKit's answers alone: free, for exactly one week (7 days counts
/// as a week). Anything else, no intro, an unread one or an ineligible
/// Apple ID: no free week. StoreKit 2 says "eligible" with no offer
/// configured too.
bool appleFreeWeek({required bool eligible, required SKProductDiscountWrapper? intro}) {
  if (!eligible || intro == null) return false;
  if (intro.paymentMode != SKProductDiscountPaymentMode.freeTrail) return false;
  final unit = intro.subscriptionPeriod.unit, units = intro.subscriptionPeriod.numberOfUnits;
  return intro.numberOfPeriods == 1 &&
      ((unit == SKSubscriptionPeriodUnit.week && units == 1) ||
          (unit == SKSubscriptionPeriodUnit.day && units == 7));
}

/// What the store layer needs from in_app_purchase, so the logic below is
/// tested without a store (IapPlusStore takes a fake).
abstract interface class IapGateway {
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> isAvailable();

  /// The product to sell, its formatted price and whether the free week is
  /// offered to this account; null when the store has no such product.
  Future<({Object handle, String price, bool trial})?> product(String id);
  Future<bool> buy(Object handle);
  Future<void> restore();
  Future<void> complete(PurchaseDetails purchase);

  /// Apple's manage-subscriptions sheet; nothing on Play.
  Future<void> manageSubscriptions();
}

/// Google Play Billing or StoreKit 2 through in_app_purchase 3.3.1
/// (pinned). Everything happens between the app and the store on the
/// phone (decision 79).
class IapPlusStore implements PlusStore {
  IapPlusStore({
    required this.source,
    IapGateway? gateway,
    this.restoreQuiet = const Duration(seconds: 3),
  }) : _gateway = gateway ?? PluginIapGateway(source);

  @override
  final PlusSource source;
  final IapGateway _gateway;

  /// How long a Restore listens for what the store reports.
  final Duration restoreQuiet;

  /// How long a purchase sheet may stay open before it counts as failed.
  static const buyLimit = Duration(minutes: 10);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<PlusBuyOutcome>? _buying;
  List<PlusProof>? _restoring;
  Object? _handle;

  /// Purchases the store reported with nobody waiting (finished elsewhere,
  /// or left unfinished last time): handed back by the next Restore.
  final _unclaimed = <PlusProof>[];

  void _listen() => _sub ??= _gateway.purchases.listen(_onPurchases);

  PlusProof _proof(PurchaseDetails p) => PlusProof(
    token: source == PlusSource.play
        ? p.verificationData.serverVerificationData
        : (p.purchaseID ?? ''),
    productId: p.productID,
    handle: p,
  );

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      if (p.productID != plusProductId) continue;
      final buying = _buying;
      switch (p.status) {
        case PurchaseStatus.pending:
          if (buying != null && !buying.isCompleted) buying.complete(const PlusPending());
        case PurchaseStatus.purchased:
          if (buying != null && !buying.isCompleted) {
            buying.complete(PlusBought(_proof(p)));
          } else {
            _unclaimed.add(_proof(p));
          }
        case PurchaseStatus.restored:
          (_restoring ?? _unclaimed).add(_proof(p));
        case PurchaseStatus.canceled:
          if (buying != null && !buying.isCompleted) buying.complete(const PlusCancelled());
          _completeQuietly(p);
        case PurchaseStatus.error:
          if (buying != null && !buying.isCompleted) buying.complete(const PlusBuyFailed());
          _completeQuietly(p);
      }
    }
  }

  /// A cancelled or failed transaction still waiting to be completed is
  /// completed (StoreKit keeps it in the queue otherwise, and reports it on
  /// every start). Nothing was bought: nothing to count.
  void _completeQuietly(PurchaseDetails p) {
    if (!p.pendingCompletePurchase) return;
    unawaited(_gateway.complete(p).catchError((Object _) {}));
  }

  @override
  Future<void> manageSubscriptions() => _gateway.manageSubscriptions();

  @override
  List<PlusProof> takeUnclaimed() {
    _listen();
    final seen = <String>{};
    final out = [
      for (final p in _unclaimed)
        if (p.token.isNotEmpty && seen.add(p.token)) p,
    ];
    _unclaimed.clear();
    return out;
  }

  @override
  Future<PlusProduct?> product() async {
    _listen();
    try {
      if (!await _gateway.isAvailable()) return null;
      final p = await _gateway.product(plusProductId);
      if (p == null) return null;
      _handle = p.handle;
      return PlusProduct(price: p.price, trialOffered: p.trial);
    } on Object {
      return null;
    }
  }

  @override
  Future<PlusBuyOutcome> buy() async {
    _listen();
    final handle = _handle ?? (await product() == null ? null : _handle);
    if (handle == null) return const PlusBuyFailed();
    final waiting = _buying = Completer<PlusBuyOutcome>();
    try {
      final started = await _gateway.buy(handle);
      if (!started) return const PlusBuyFailed();
      return await waiting.future.timeout(buyLimit, onTimeout: () => const PlusBuyFailed());
    } on Object {
      return const PlusBuyFailed();
    } finally {
      _buying = null;
    }
  }

  @override
  Future<List<PlusProof>> restore() async {
    _listen();
    final found = _restoring = [..._unclaimed];
    _unclaimed.clear();
    try {
      await _gateway.restore();
      // The store reports restored purchases on the stream, with no "done":
      // listen a moment.
      await Future<void>.delayed(restoreQuiet);
    } on Object {
      // Nothing found, as far as anyone can tell.
    } finally {
      _restoring = null;
    }
    // One proof per token (the same purchase can come twice).
    final seen = <String>{};
    return [
      for (final p in found)
        if (p.token.isNotEmpty && seen.add(p.token)) p,
    ];
  }

  @override
  Future<void> finish(PlusProof proof) async {
    final p = proof.handle;
    if (p is PurchaseDetails && p.pendingCompletePurchase) await _gateway.complete(p);
  }
}

/// The real store. Play: one product with offers (the base plan, and the
/// free week as an offer); the free week is bought when Play returns it
/// (only to an eligible account). Apple: StoreKit 2, which says whether
/// this Apple ID may have the introductory offer.
class PluginIapGateway implements IapGateway {
  // StoreKit 2 is the plugin's only default now (enableStoreKit2 is
  // deprecated for it).
  PluginIapGateway(this.source);

  final PlusSource source;
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<({Object handle, String price, bool trial})?> product(String id) async {
    final res = await _iap.queryProductDetails({id});
    if (res.productDetails.isEmpty) return null;
    if (source == PlusSource.play) {
      final offers = res.productDetails.whereType<GooglePlayProductDetails>().toList();
      if (offers.isEmpty) return null;
      GooglePlayProductDetails? base, trial;
      for (final o in offers) {
        final i = o.subscriptionIndex;
        final details = o.productDetails.subscriptionOfferDetails;
        if (i == null || details == null) continue;
        final d = details[i];
        if (d.offerId == null) base ??= o;
        if (d.pricingPhases.isNotEmpty && d.pricingPhases.first.priceAmountMicros == 0) {
          trial ??= o;
        }
      }
      final sell = trial ?? base ?? offers.first;
      // The price: the base plan's (its one phase), never the trial's 0.
      final priced = base ?? sell;
      final offers0 = priced.productDetails.subscriptionOfferDetails;
      final phases = offers0?[priced.subscriptionIndex ?? 0].pricingPhases;
      final paid = (phases ?? const []).where((ph) => ph.priceAmountMicros > 0);
      final price = paid.isNotEmpty ? paid.last.formattedPrice : priced.price;
      return (handle: sell, price: price, trial: trial != null);
    }
    // Apple: StoreKit applies its introductory offer to every eligible
    // Apple ID, so the app reports what StoreKit offers.
    final p = res.productDetails.first;
    var eligible = false;
    try {
      // StoreKit 2's own answer for this Apple ID.
      eligible = await SK2Product.isIntroductoryOfferEligible(id);
    } on Object {
      eligible = false;
    }
    // StoreKit 2's wrapper doesn't expose the introductory offer, so
    // StoreKit 1's introductoryPrice says which it is.
    SKProductDiscountWrapper? intro;
    if (eligible) {
      try {
        final sk1 = await SKRequestMaker().startProductRequest([id]);
        intro = sk1.products.isEmpty ? null : sk1.products.first.introductoryPrice;
      } on Object {
        intro = null;
      }
    }
    return (handle: p, price: p.price, trial: appleFreeWeek(eligible: eligible, intro: intro));
  }

  @override
  Future<bool> buy(Object handle) {
    final details = handle as ProductDetails;
    final PurchaseParam param = details is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(productDetails: details, offerToken: details.offerToken)
        : PurchaseParam(productDetails: details);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(PurchaseDetails purchase) => _iap.completePurchase(purchase);

  @override
  Future<void> manageSubscriptions() async {
    if (source != PlusSource.apple) return;
    await _iap
        .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>()
        .showManageSubscriptions();
  }
}

/// The store this phone buys from; null where there's none (web, desktop).
PlusStore? platformPlusStore() {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return IapPlusStore(source: PlusSource.play);
  if (Platform.isIOS) return IapPlusStore(source: PlusSource.apple);
  return null;
}
