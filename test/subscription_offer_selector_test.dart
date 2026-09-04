import 'package:flutter_api/subscription_offer_selector.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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

  group('SubscriptionOfferDetails', () {
    final product = ProductDetails(
      id: 'premium_yearly',
      title: 'Premium',
      description: '',
      price: r'$29.99',
      rawPrice: 29.99,
      currencyCode: 'USD',
    );

    SubscriptionOfferDetails offer(String? trial) => SubscriptionOfferDetails(
      productDetails: product,
      productId: product.id,
      basePlanId: 'annual',
      offerId: 'intro',
      offerTags: const ['free-trial'],
      offerToken: 'play-token',
      formattedRecurringPrice: r'$29.99',
      recurringPeriod: 'P1Y',
      freeTrialPeriod: trial,
    );

    test('exposes an exact three-day free trial and purchase token', () {
      final details = offer('P3D');

      expect(details.hasFreeTrial, isTrue);
      expect(details.matchesFreeTrial(const Duration(days: 3)), isTrue);
      expect(details.offerToken, 'play-token');
      expect(details.formattedRecurringPrice, r'$29.99');
      expect(details.recurringPeriod, 'P1Y');
    });

    test('does not confuse another trial duration with three days', () {
      final details = offer('P7D');

      expect(details.matchesFreeTrial(const Duration(days: 3)), isFalse);
      expect(details.matchesFreeTrial(const Duration(days: 7)), isTrue);
    });

    test('reports no trial when store metadata has none', () {
      final details = offer(null);

      expect(details.hasFreeTrial, isFalse);
      expect(details.matchesFreeTrial(const Duration(days: 3)), isFalse);
    });

    test('selects normalized metadata by base plan and offer tag', () {
      final selected = selectSubscriptionOfferDetails(
        [offer('P3D')],
        basePlanId: 'annual',
        offerTag: 'free-trial',
        requiresFreeTrial: true,
      );

      expect(selected?.offerToken, 'play-token');
    });
  });
}
