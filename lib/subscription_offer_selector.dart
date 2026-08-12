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
