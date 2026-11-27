import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'
    show InAppPurchaseStoreKitPlatformAddition;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' show SK2Product;
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart'
    show SKProductDiscountPaymentMode, SKProductDiscountWrapper, SKRequestMaker, SKSubscriptionPeriodUnit;

import '../../data/plus.dart';
import 'plus_store.dart';

/// Play's obfuscatedAccountId for a person: sha-256 of the lower-cased user
/// id, hex. The same as plus-store's playAccountId (supabase/functions/
/// plus-store/stores.ts); Google asks for a hash, never the id itself.
String playAccountId(String userId) =>
    sha256.convert(utf8.encode(userId.toLowerCase())).toString();

/// Apple's introductory offer as the app shows it (iOS plan S11), from
/// StoreKit's answers alone. Apple has one at a time:
/// - the free week (free, exactly one week: the app says "7-day free
///   trial") → the trial;
/// - the Christmas special (pay up front, one year) → its price, in the
///   style of StoreKit's own yearly price ([yearly], [yearlyRaw]);
/// - anything else, no intro, an unread one or an ineligible Apple ID →
///   neither. StoreKit 2 says "eligible" with no offer configured too.
({bool trial, String? offerPrice}) appleIntro({
  required bool eligible,
  required SKProductDiscountWrapper? intro,
  required String yearly,
  required double yearlyRaw,
}) {
  const ({bool trial, String? offerPrice}) none = (trial: false, offerPrice: null);
  if (!eligible || intro == null) return none;
  final unit = intro.subscriptionPeriod.unit, units = intro.subscriptionPeriod.numberOfUnits;
  if (intro.paymentMode == SKProductDiscountPaymentMode.freeTrail) {
    final week =
        intro.numberOfPeriods == 1 &&
        ((unit == SKSubscriptionPeriodUnit.week && units == 1) ||
            (unit == SKSubscriptionPeriodUnit.day && units == 7));
    return week ? (trial: true, offerPrice: null) : none;
  }
  final year = unit == SKSubscriptionPeriodUnit.year && units == 1 && intro.numberOfPeriods == 1;
  if (year && intro.paymentMode == SKProductDiscountPaymentMode.payUpFront && intro.price.isNotEmpty) {
    return (
      trial: false,
      offerPrice: storeStylePrice(
        yearly: yearly,
        yearlyRaw: yearlyRaw,
        amount: intro.price,
        symbol: intro.priceLocale.currencySymbol,
      ),
    );
  }
  return none;
}

/// [amount] (StoreKit 1's plain decimal, "29.99") written the way StoreKit
/// wrote the yearly price for this storefront ([yearly], e.g. "59,99 €",
/// "R$ 299,90", "¥6,000"; [yearlyRaw] its value): the same currency text,
/// decimal mark, digit grouping and number of decimals. When [yearly] can't
/// be read that way, the plugin's own SK1 form, [symbol] + [amount].
String storeStylePrice({
  required String yearly,
  required double yearlyRaw,
  required String amount,
  required String symbol,
}) {
  final fallback = '$symbol$amount';
  final value = double.tryParse(amount);
  final m = RegExp('\\d(?:[\\d.,\'    ’]*\\d)?').firstMatch(yearly);
  if (value == null || value <= 0 || m == null || yearlyRaw <= 0) return fallback;
  final number = m.group(0)!;
  final digits = number.replaceAll(RegExp(r'\D'), '');
  final decimals = digits.length - yearlyRaw.truncate().toString().length;
  if (decimals < 0 || decimals > 3 || digits.length > 15) return fallback;
  // The digits read back as the yearly price, or the style isn't this one.
  var scale = 1;
  for (var i = 0; i < decimals; i++) {
    scale *= 10;
  }
  if ((int.parse(digits) - yearlyRaw * scale).abs() > 0.5) return fallback;
  var whole = number, mark = '';
  if (decimals > 0) {
    mark = number[number.length - decimals - 1];
    if (RegExp(r'\d').hasMatch(mark)) return fallback;
    whole = number.substring(0, number.length - decimals - 1);
  }
  final seps = whole.replaceAll(RegExp(r'\d'), '').split('').toSet();
  if (seps.length > 1) return fallback;
  final group = seps.isEmpty ? '' : seps.first;
  final fixed = value.toStringAsFixed(decimals).split('.');
  var out = fixed[0];
  if (group.isNotEmpty) {
    final b = StringBuffer();
    for (var i = 0; i < out.length; i++) {
      if (i > 0 && (out.length - i) % 3 == 0) b.write(group);
      b.write(out[i]);
    }
    out = b.toString();
  }
  if (decimals > 0) out = '$out$mark${fixed[1]}';
  return yearly.replaceRange(m.start, m.end, out);
}

/// What the store layer needs from in_app_purchase, so the logic below is
/// tested without a store (IapPlusStore takes a fake).
abstract interface class IapGateway {
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> isAvailable();

  /// The product to sell, its formatted yearly price, whether the free
  /// week is offered to this account and, with [offer], the store's
  /// first-year price when the Christmas special is offered to it; null when
  /// the store has no such product.
  Future<({Object handle, String price, bool trial, String? offerPrice})?> product(
    String id, {
    bool offer = false,
  });
  Future<bool> buy(Object handle, {required String applicationUserName});
  Future<void> restore({required String applicationUserName});
  Future<void> complete(PurchaseDetails purchase);

  /// Apple's manage-subscriptions sheet; nothing on Play.
  Future<void> manageSubscriptions();
}

/// Google Play Billing or StoreKit 2 through in_app_purchase 3.3.1 (UX:
/// approved, pinned; RevenueCat out). The proof goes to plus-store: Play's
/// purchase token, Apple's transaction id.
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

  /// Play: the hash. Apple: the uid as a lower-case UUID. StoreKit 2 passes
  /// it to the transaction as appAccountToken only when it parses as a UUID
  /// (the plugin's UUID(uuidString:)), and drops it silently otherwise.
  String _userName(String accountId) =>
      source == PlusSource.play ? playAccountId(accountId) : accountId.toLowerCase();

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
  /// every start). Nothing was bought: nothing to verify.
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
  Future<PlusProduct?> product({bool offer = false}) async {
    _listen();
    try {
      if (!await _gateway.isAvailable()) return null;
      final p = await _gateway.product(plusProductId, offer: offer);
      if (p == null) return null;
      _handle = p.handle;
      return PlusProduct(
        price: p.price,
        trialOffered: p.offerPrice == null && p.trial,
        offerPrice: p.offerPrice,
        offerFromStore: source == PlusSource.apple,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<PlusBuyOutcome> buy({required String accountId}) async {
    _listen();
    final handle = _handle ?? (await product() == null ? null : _handle);
    if (handle == null) return const PlusBuyFailed();
    final waiting = _buying = Completer<PlusBuyOutcome>();
    try {
      final started = await _gateway.buy(handle, applicationUserName: _userName(accountId));
      if (!started) return const PlusBuyFailed();
      return await waiting.future.timeout(buyLimit, onTimeout: () => const PlusBuyFailed());
    } on Object {
      return const PlusBuyFailed();
    } finally {
      _buying = null;
    }
  }

  @override
  Future<List<PlusProof>> restore({required String accountId}) async {
    _listen();
    final found = _restoring = [..._unclaimed];
    _unclaimed.clear();
    try {
      await _gateway.restore(applicationUserName: _userName(accountId));
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

/// The real store. Play: one product with offers (the base plan "yearly"
/// and "free-trial-7d"); the free offer is bought when Play returns it (only
/// to an eligible account). Apple: StoreKit 2, which says whether this Apple
/// ID may have the introductory offer.
class PluginIapGateway implements IapGateway {
  // StoreKit 2 is the plugin's only default now (enableStoreKit2 is
  // deprecated for it): appAccountToken goes through SK2's purchase options.
  PluginIapGateway(this.source);

  final PlusSource source;
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<({Object handle, String price, bool trial, String? offerPrice})?> product(
    String id, {
    bool offer = false,
  }) async {
    final res = await _iap.queryProductDetails({id});
    if (res.productDetails.isEmpty) return null;
    if (source == PlusSource.play) {
      final offers = res.productDetails.whereType<GooglePlayProductDetails>().toList();
      if (offers.isEmpty) return null;
      GooglePlayProductDetails? base, trial, christmas;
      String? christmasPrice;
      for (final o in offers) {
        final i = o.subscriptionIndex;
        final details = o.productDetails.subscriptionOfferDetails;
        if (i == null || details == null) continue;
        final d = details[i];
        if (d.offerId == null) base ??= o;
        if (d.pricingPhases.isNotEmpty && d.pricingPhases.first.priceAmountMicros == 0) {
          trial ??= o;
        }
        // The Christmas special (the owner's Play setup): its own offer id, a
        // first phase of one paid year; Play returns it only to an
        // eligible account. Its price is the phase's own formatted price.
        final first = d.pricingPhases.isEmpty ? null : d.pricingPhases.first;
        if (offer &&
            d.offerId == plusOfferId &&
            first != null &&
            first.priceAmountMicros > 0 &&
            first.billingPeriod == 'P1Y') {
          christmas ??= o;
          christmasPrice ??= first.formattedPrice;
        }
      }
      // The special replaces the free week while it runs.
      final sell = christmas ?? trial ?? base ?? offers.first;
      // The yearly price: the base plan's (its one phase), never the trial's 0.
      final priced = base ?? sell;
      final offers0 = priced.productDetails.subscriptionOfferDetails;
      final phases = offers0?[priced.subscriptionIndex ?? 0].pricingPhases;
      final paid = (phases ?? const []).where((ph) => ph.priceAmountMicros > 0);
      final price = paid.isNotEmpty ? paid.last.formattedPrice : priced.price;
      return (
        handle: sell,
        price: price,
        trial: christmas == null && trial != null,
        offerPrice: christmasPrice,
      );
    }
    // Apple: [offer] isn't used. StoreKit applies its introductory offer on
    // its own dates to every eligible Apple ID, so the app reports what
    // StoreKit offers (S11), whatever the app's window and the row say.
    final p = res.productDetails.first;
    var eligible = false;
    try {
      // StoreKit 2's own answer for this Apple ID.
      eligible = await SK2Product.isIntroductoryOfferEligible(id);
    } on Object {
      eligible = false;
    }
    // StoreKit 2's wrapper doesn't expose the introductory offer, so
    // StoreKit 1's introductoryPrice says which it is, with its amount.
    SKProductDiscountWrapper? intro;
    if (eligible) {
      try {
        final sk1 = await SKRequestMaker().startProductRequest([id]);
        intro = sk1.products.isEmpty ? null : sk1.products.first.introductoryPrice;
      } on Object {
        intro = null;
      }
    }
    final a = appleIntro(eligible: eligible, intro: intro, yearly: p.price, yearlyRaw: p.rawPrice);
    return (handle: p, price: p.price, trial: a.trial, offerPrice: a.offerPrice);
  }

  @override
  Future<bool> buy(Object handle, {required String applicationUserName}) {
    final details = handle as ProductDetails;
    final PurchaseParam param = details is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: details,
            applicationUserName: applicationUserName,
            offerToken: details.offerToken,
          )
        : PurchaseParam(productDetails: details, applicationUserName: applicationUserName);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore({required String applicationUserName}) =>
      _iap.restorePurchases(applicationUserName: applicationUserName);

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
