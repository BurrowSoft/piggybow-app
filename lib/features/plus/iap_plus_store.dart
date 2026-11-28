import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show PurchaseStateWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'
    show InAppPurchaseStoreKitPlatformAddition;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' show SK2Product, SK2Transaction;
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart'
    show SKProductDiscountPaymentMode, SKProductDiscountWrapper, SKRequestMaker, SKSubscriptionPeriodUnit;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// A Play pricing phase: its price in micros (an int, never a float), the
/// store's formatted price, its ISO 8601 billing period ("P1M") and how many
/// times it bills.
typedef PlayPhase = ({int micros, String price, String period, int cycles});

/// One Play offer as [playPlans] reads it: its base plan, its offer id (null
/// for the base plan itself), its phases and the store's own object.
typedef PlayOffer = ({String basePlanId, String? offerId, List<PlayPhase> phases, Object handle});

/// Whether a Play phase is a free week: free, billed once, for a week.
bool playFreeWeek(PlayPhase phase) =>
    phase.micros == 0 && phase.cycles == 1 && (phase.period == 'P1W' || phase.period == 'P7D');

/// Plus's plan from Play's offers: the yearly base plan alone (decision 85;
/// any other base plan is ignored). It is on sale when its base plan is, at
/// the base plan's paid price. It has the free week when Play returns an
/// offer on it that starts with a free week (Play returns an offer only to
/// an eligible account): buying the plan then buys that offer. Any other
/// offer is ignored, so the app never calls something else a free week.
List<PlusPlan> playPlans(List<PlayOffer> offers) {
  final mine = offers.where((o) => o.basePlanId == plusPlayYearlyPlan);
  final base = mine.where((o) => o.offerId == null).firstOrNull;
  final paid = base?.phases.where((p) => p.micros > 0).lastOrNull;
  if (base == null || paid == null) return const [];
  final trial = mine
      .where((o) => o.offerId != null && o.phases.isNotEmpty && playFreeWeek(o.phases.first))
      .firstOrNull;
  return [
    PlusPlan(
      period: PlusPeriod.year,
      price: paid.price,
      trialOffered: trial != null,
      handle: (trial ?? base).handle,
    ),
  ];
}

/// Play's own page for Plus's subscription; it opens in the Play Store app.
Uri playSubscriptionsUri(String packageName) => Uri.https(
  'play.google.com',
  '/store/account/subscriptions',
  {'sku': plusPlayProductId, 'package': packageName},
);

/// What the store layer needs from in_app_purchase, so the logic below is
/// tested without a store (IapPlusStore takes a fake).
abstract interface class IapGateway {
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> isAvailable();

  /// The plans the store offers this account (the yearly plan alone).
  Future<List<PlusPlan>> plans();
  Future<bool> buy(Object handle);

  /// The store account's active purchases; null when the store can't say.
  Future<List<PlusProof>?> owned();

  /// Finishes the purchase behind [handle] (Play's acknowledgement,
  /// StoreKit's finish).
  Future<void> complete(Object handle);

  /// The store's own subscription page.
  Future<void> manageSubscriptions();
}

/// Google Play Billing or StoreKit 2 through in_app_purchase 3.3.1
/// (pinned). Everything happens between the app and the store on the
/// phone (decision 79).
class IapPlusStore implements PlusStore {
  IapPlusStore({required this.source, IapGateway? gateway})
    : _gateway = gateway ?? PluginIapGateway(source);

  @override
  final PlusSource source;
  final IapGateway _gateway;

  /// How long a purchase sheet may stay open before it counts as failed.
  static const buyLimit = Duration(minutes: 10);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<PlusBuyOutcome>? _buying;

  /// Purchases the store reported with nobody waiting: handed over by
  /// [takeUnclaimed], announced on [changes].
  final _unclaimed = <PlusProof>[];
  final _changes = _Changes();

  @override
  Listenable get changes => _changes;

  void _listen() => _sub ??= _gateway.purchases.listen(_onPurchases);

  PlusProof _proof(PurchaseDetails p) => PlusProof(
    token: source == PlusSource.play
        ? p.verificationData.serverVerificationData
        : (p.purchaseID ?? ''),
    productId: p.productID,
    handle: p,
    needsFinish: p.pendingCompletePurchase,
  );

  void _onPurchases(List<PurchaseDetails> list) {
    var unclaimed = false;
    for (final p in list) {
      if (!isPlusProduct(p.productID)) continue;
      final buying = _buying;
      switch (p.status) {
        case PurchaseStatus.pending:
          if (buying != null && !buying.isCompleted) buying.complete(const PlusPending());
        case PurchaseStatus.purchased:
          if (buying != null && !buying.isCompleted) {
            buying.complete(PlusBought(_proof(p)));
          } else {
            _unclaimed.add(_proof(p));
            unclaimed = true;
          }
        case PurchaseStatus.restored:
          _unclaimed.add(_proof(p));
          unclaimed = true;
        case PurchaseStatus.canceled:
          if (buying != null && !buying.isCompleted) buying.complete(const PlusCancelled());
          _completeQuietly(p);
        case PurchaseStatus.error:
          if (buying != null && !buying.isCompleted) buying.complete(const PlusBuyFailed());
          _completeQuietly(p);
      }
    }
    if (unclaimed) _changes.ping();
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
  Future<List<PlusPlan>> plans() async {
    _listen();
    try {
      if (!await _gateway.isAvailable()) return const [];
      return await _gateway.plans();
    } on Object {
      return const [];
    }
  }

  @override
  Future<PlusBuyOutcome> buy(PlusPlan plan) async {
    _listen();
    final handle = plan.handle;
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
  Future<List<PlusProof>?> owned() async {
    _listen();
    try {
      if (!await _gateway.isAvailable()) return null;
      final found = await _gateway.owned();
      if (found == null) return null;
      // Plus's own purchases, one proof per purchase.
      final seen = <String>{};
      return [
        for (final p in found)
          if (isPlusProduct(p.productId) && p.token.isNotEmpty && seen.add(p.token)) p,
      ];
    } on Object {
      return null;
    }
  }

  @override
  Future<void> finish(PlusProof proof) async {
    final handle = proof.handle;
    if (proof.needsFinish && handle != null) await _gateway.complete(handle);
  }
}

class _Changes extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The real store. Play: the subscription's yearly base plan and its offers;
/// the free week is bought when Play returns it (only to an eligible
/// account). Apple: StoreKit 2, which says whether this Apple ID may have a
/// product's introductory offer.
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
  Future<List<PlusPlan>> plans() async {
    if (source == PlusSource.play) {
      final res = await _iap.queryProductDetails({plusPlayProductId});
      return playPlans([
        for (final o in res.productDetails.whereType<GooglePlayProductDetails>())
          ?_playOffer(o),
      ]);
    }
    final res = await _iap.queryProductDetails({plusAppleYearlyId});
    final p = res.productDetails.where((d) => d.id == plusAppleYearlyId).firstOrNull;
    if (p == null) return const [];
    return [
      PlusPlan(
        period: PlusPeriod.year,
        price: p.price,
        trialOffered: await _appleFreeWeek(plusAppleYearlyId),
        handle: p,
      ),
    ];
  }

  PlayOffer? _playOffer(GooglePlayProductDetails o) {
    final i = o.subscriptionIndex;
    final details = o.productDetails.subscriptionOfferDetails;
    if (i == null || details == null || i >= details.length) return null;
    final d = details[i];
    return (
      basePlanId: d.basePlanId,
      offerId: d.offerId,
      phases: [
        for (final ph in d.pricingPhases)
          (
            micros: ph.priceAmountMicros,
            price: ph.formattedPrice,
            period: ph.billingPeriod,
            cycles: ph.billingCycleCount,
          ),
      ],
      handle: o,
    );
  }

  /// StoreKit 2's word for this Apple ID on [id]'s introductory offer.
  Future<bool> _appleFreeWeek(String id) async {
    try {
      if (!await SK2Product.isIntroductoryOfferEligible(id)) return false;
      // StoreKit 2's wrapper doesn't expose the introductory offer, so
      // StoreKit 1's introductoryPrice says which it is.
      final sk1 = await SKRequestMaker().startProductRequest([id]);
      final intro = sk1.products.isEmpty ? null : sk1.products.first.introductoryPrice;
      return appleFreeWeek(eligible: true, intro: intro);
    } on Object {
      return false;
    }
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
  Future<List<PlusProof>?> owned() async {
    if (source == PlusSource.play) {
      final res = await _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
          .queryPastPurchases();
      if (res.error != null) return null;
      return [
        for (final p in res.pastPurchases)
          // A pending payment isn't Plus yet, and can't be finished.
          if (p.billingClientPurchase.purchaseState == PurchaseStateWrapper.purchased)
            PlusProof(
              token: p.verificationData.serverVerificationData,
              productId: p.productID,
              handle: p,
              needsFinish: p.pendingCompletePurchase,
            ),
      ];
    }
    // Both lists hold verified transactions only (the plugin drops the rest).
    final unfinished = {for (final t in await SK2Transaction.unfinishedTransactions()) t.id};
    return [
      for (final t in await SK2Transaction.currentEntitlements())
        PlusProof(
          token: t.id,
          productId: t.productId,
          handle: t,
          needsFinish: unfinished.contains(t.id),
        ),
    ];
  }

  @override
  Future<void> complete(Object handle) async {
    if (handle is PurchaseDetails) {
      if (handle.pendingCompletePurchase) await _iap.completePurchase(handle);
    } else if (handle is SK2Transaction) {
      await SK2Transaction.finish(int.parse(handle.id));
    }
  }

  @override
  Future<void> manageSubscriptions() async {
    if (source == PlusSource.apple) {
      await _iap
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>()
          .showManageSubscriptions();
      return;
    }
    final info = await PackageInfo.fromPlatform();
    await launchUrl(
      playSubscriptionsUri(info.packageName),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// The store this phone buys from; null where there's none (web, desktop).
PlusStore? platformPlusStore() {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return IapPlusStore(source: PlusSource.play);
  if (Platform.isIOS) return IapPlusStore(source: PlusSource.apple);
  return null;
}
