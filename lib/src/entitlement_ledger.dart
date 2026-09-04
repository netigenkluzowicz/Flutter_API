import 'dart:async';

class EntitlementRecord<T> {
  const EntitlementRecord({
    required this.productId,
    required this.purchase,
    required this.isSubscription,
    required this.lastVerifiedAt,
  });

  final String productId;
  final T purchase;
  final bool isSubscription;
  final DateTime lastVerifiedAt;
}

/// Small store-agnostic entitlement store used by [PaymentService].
class EntitlementLedger<T> {
  final Map<String, EntitlementRecord<T>> _records = {};

  Iterable<EntitlementRecord<T>> get records => _records.values;
  bool contains(String productId) => _records.containsKey(productId);

  void grant({
    required String productId,
    required T purchase,
    required bool isSubscription,
    required DateTime verifiedAt,
  }) {
    _records[productId] = EntitlementRecord(
      productId: productId,
      purchase: purchase,
      isSubscription: isSubscription,
      lastVerifiedAt: verifiedAt,
    );
  }

  EntitlementRecord<T>? revoke(String productId) => _records.remove(productId);

  Iterable<EntitlementRecord<T>> subscriptionsDueForVerification(
    DateTime now,
    Duration interval,
  ) => _records.values.where(
    (record) =>
        record.isSubscription &&
        now.difference(record.lastVerifiedAt) >= interval,
  );
}

/// Outcome of the application-provided backend verification callback.
enum EntitlementVerificationOutcome { verified, invalid, error, timedOut }

/// Store-independent callback runner. Keeping it small makes the security
/// boundary testable without mocking the platform purchase stream.
class EntitlementVerifier<T> {
  const EntitlementVerifier({required this.timeout});

  final Duration timeout;

  Future<EntitlementVerificationOutcome> verify(
    T purchase,
    Future<bool> Function(T purchase) callback,
  ) async {
    try {
      return await callback(purchase).timeout(timeout)
          ? EntitlementVerificationOutcome.verified
          : EntitlementVerificationOutcome.invalid;
    } on TimeoutException {
      return EntitlementVerificationOutcome.timedOut;
    } catch (_) {
      return EntitlementVerificationOutcome.error;
    }
  }
}
