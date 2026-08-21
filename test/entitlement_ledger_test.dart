import 'dart:async';

import 'package:flutter_api/src/entitlement_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntitlementVerifier', () {
    const verifier = EntitlementVerifier<String>(
      timeout: Duration(milliseconds: 10),
    );

    test(
      'grants purchased and restored entitlements only after true callback',
      () async {
        expect(
          await verifier.verify('purchased', (_) async => true),
          EntitlementVerificationOutcome.verified,
        );
        expect(
          await verifier.verify('restored', (_) async => true),
          EntitlementVerificationOutcome.verified,
        );
      },
    );

    test('rejects false callback, errors and timeouts', () async {
      expect(
        await verifier.verify('invalid', (_) async => false),
        EntitlementVerificationOutcome.invalid,
      );
      expect(
        await verifier.verify('error', (_) => Future<bool>.error('backend')),
        EntitlementVerificationOutcome.error,
      );
      expect(
        await verifier.verify('timeout', (_) => Completer<bool>().future),
        EntitlementVerificationOutcome.timedOut,
      );
    });
  });

  group('EntitlementLedger', () {
    test(
      'subscription is due for re-verification but non-consumable is not',
      () {
        final ledger = EntitlementLedger<String>();
        final verifiedAt = DateTime(2026, 1, 1, 12);
        ledger.grant(
          productId: 'subscription',
          purchase: 'subscription',
          isSubscription: true,
          verifiedAt: verifiedAt,
        );
        ledger.grant(
          productId: 'one-time',
          purchase: 'one-time',
          isSubscription: false,
          verifiedAt: verifiedAt,
        );

        expect(
          ledger
              .subscriptionsDueForVerification(
                verifiedAt.add(const Duration(hours: 1)),
                const Duration(hours: 1),
              )
              .map((record) => record.productId),
          ['subscription'],
        );
      },
    );

    test(
      'revocation removes entitlement, while an empty ledger means no restore',
      () {
        final ledger = EntitlementLedger<String>();
        expect(ledger.records, isEmpty);
        ledger.grant(
          productId: 'premium',
          purchase: 'premium',
          isSubscription: true,
          verifiedAt: DateTime(2026),
        );

        expect(ledger.revoke('premium')?.productId, 'premium');
        expect(ledger.records, isEmpty);
      },
    );

    test('granting the same product twice is idempotent', () {
      final ledger = EntitlementLedger<String>();
      ledger.grant(
        productId: 'subscription',
        purchase: 'first-event',
        isSubscription: true,
        verifiedAt: DateTime(2026),
      );
      ledger.grant(
        productId: 'subscription',
        purchase: 'renewal-event',
        isSubscription: true,
        verifiedAt: DateTime(2026, 2),
      );

      expect(ledger.records, hasLength(1));
      expect(ledger.records.single.purchase, 'renewal-event');
    });

    test(
      'revoking one subscription preserves an independent lifetime product',
      () {
        final ledger = EntitlementLedger<String>();
        ledger.grant(
          productId: 'subscription',
          purchase: 'subscription',
          isSubscription: true,
          verifiedAt: DateTime(2026),
        );
        ledger.grant(
          productId: 'lifetime',
          purchase: 'lifetime',
          isSubscription: false,
          verifiedAt: DateTime(2026),
        );

        ledger.revoke('subscription');

        expect(ledger.contains('subscription'), isFalse);
        expect(ledger.contains('lifetime'), isTrue);
      },
    );
  });
}
