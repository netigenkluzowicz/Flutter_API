import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Store-agnostic metadata used to select one Google Play base plan/offer.
///
/// [value] is the caller-owned object returned when this candidate wins.
class SubscriptionOfferCandidate<T> {
  const SubscriptionOfferCandidate({
    required this.value,
    required this.basePlanId,
    required this.offerTags,
    required this.hasFreeTrial,
    this.offerId,
  });

  final T value;
  final String basePlanId;
  final String? offerId;
  final List<String> offerTags;
  final bool hasFreeTrial;
}

/// Selects an offer deterministically instead of relying on product list order.
///
/// For a regular purchase, a base plan (an entry without [offerId]) is
/// preferred. For a trial, callers may select the offer by a Play Console tag.
T? selectSubscriptionOffer<T>(
  Iterable<SubscriptionOfferCandidate<T>> candidates, {
  String? basePlanId,
  String? offerTag,
  required bool requiresFreeTrial,
}) {
  final matches = candidates.where((candidate) {
    if (candidate.hasFreeTrial != requiresFreeTrial) return false;
    if (basePlanId != null && candidate.basePlanId != basePlanId) return false;
    if (offerTag != null && !candidate.offerTags.contains(offerTag)) {
      return false;
    }
    return true;
  }).toList();

  if (matches.isEmpty) return null;
  if (!requiresFreeTrial) {
    for (final candidate in matches) {
      if (candidate.offerId == null) return candidate.value;
    }
  }
  return matches.first.value;
}

/// Selects store-normalized offer metadata by base plan and optional tag.
SubscriptionOfferDetails? selectSubscriptionOfferDetails(
  Iterable<SubscriptionOfferDetails> offers, {
  String? basePlanId,
  String? offerTag,
  required bool requiresFreeTrial,
}) => selectSubscriptionOffer(
  offers
      .map(
        (offer) => SubscriptionOfferCandidate<SubscriptionOfferDetails>(
          value: offer,
          basePlanId: offer.basePlanId ?? '',
          offerId: offer.offerId,
          offerTags: offer.offerTags,
          hasFreeTrial: offer.hasFreeTrial,
        ),
      )
      .toList(),
  basePlanId: basePlanId,
  offerTag: offerTag,
  requiresFreeTrial: requiresFreeTrial,
);

/// Store-normalized subscription information suitable for a paywall.
///
/// Values are copied from the store response; this package never invents a
/// trial duration, price, or Google Play offer token.
class SubscriptionOfferDetails {
  const SubscriptionOfferDetails({
    required this.productDetails,
    required this.productId,
    required this.formattedRecurringPrice,
    this.basePlanId,
    this.offerId,
    this.offerTags = const <String>[],
    this.offerToken,
    this.recurringPeriod,
    this.freeTrialPeriod,
  });

  factory SubscriptionOfferDetails.fromProductDetails(ProductDetails product) {
    if (product is! GooglePlayProductDetails) {
      return SubscriptionOfferDetails(
        productDetails: product,
        productId: product.id,
        formattedRecurringPrice: product.price,
      );
    }
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) {
      return SubscriptionOfferDetails(
        productDetails: product,
        productId: product.id,
        formattedRecurringPrice: product.price,
      );
    }

    final offer = offers[index];
    final trial = offer.pricingPhases.where(
      (phase) => phase.priceAmountMicros == 0,
    );
    final recurring = offer.pricingPhases.lastWhere(
      (phase) => phase.priceAmountMicros > 0,
      orElse: () => offer.pricingPhases.last,
    );
    return SubscriptionOfferDetails(
      productDetails: product,
      productId: product.id,
      basePlanId: offer.basePlanId,
      offerId: offer.offerId,
      offerTags: List.unmodifiable(offer.offerTags),
      offerToken: offer.offerIdToken,
      formattedRecurringPrice: recurring.formattedPrice,
      recurringPeriod: recurring.billingPeriod,
      freeTrialPeriod: trial.isEmpty ? null : trial.first.billingPeriod,
    );
  }

  /// The exact product reference to pass to [PaymentService.buyNonConsumable].
  final ProductDetails productDetails;
  final String productId;
  final String? basePlanId;
  final String? offerId;
  final List<String> offerTags;
  final String? offerToken;
  final String formattedRecurringPrice;
  final String? recurringPeriod;
  final String? freeTrialPeriod;

  bool get hasFreeTrial => freeTrialPeriod != null;

  /// Matches fixed-length ISO-8601 trial periods such as `P3D` and `P1W`.
  /// Calendar periods containing months or years intentionally return false,
  /// because their duration is not a fixed number of hours.
  bool matchesFreeTrial(Duration expected) {
    final period = freeTrialPeriod;
    if (period == null) return false;
    final match = RegExp(r'^P(?:(\d+)W)?(?:(\d+)D)?$').firstMatch(period);
    if (match == null) return false;
    final weeks = int.parse(match.group(1) ?? '0');
    final days = int.parse(match.group(2) ?? '0');
    return Duration(days: weeks * 7 + days) == expected;
  }
}
