import 'package:flutter_api/subscription_offer_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const candidates = [
    SubscriptionOfferCandidate(
      value: 'annual-trial',
      basePlanId: 'annual',
      offerId: 'intro',
      offerTags: ['free-trial'],
      hasFreeTrial: true,
    ),
    SubscriptionOfferCandidate(
      value: 'monthly',
      basePlanId: 'monthly',
      offerTags: [],
      hasFreeTrial: false,
    ),
    SubscriptionOfferCandidate(
      value: 'annual',
      basePlanId: 'annual',
      offerTags: [],
      hasFreeTrial: false,
    ),
  ];

  test('selects a trial by base plan and offer tag', () {
    expect(
      selectSubscriptionOffer(
        candidates,
        basePlanId: 'annual',
        offerTag: 'free-trial',
        requiresFreeTrial: true,
      ),
      'annual-trial',
    );
  });

  test('selects the regular base plan without relying on list length', () {
    expect(
      selectSubscriptionOffer(
        candidates,
        basePlanId: 'annual',
        requiresFreeTrial: false,
      ),
      'annual',
    );
  });

  test('returns null when the requested trial is unavailable', () {
    expect(
      selectSubscriptionOffer(
        candidates,
        basePlanId: 'monthly',
        requiresFreeTrial: true,
      ),
      isNull,
    );
  });
}
