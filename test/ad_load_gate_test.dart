import 'package:flutter_api/src/ad_load_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalidates an in-flight load when consent is withdrawn', () {
    final gate = AdLoadGate()..setRequestAllowed(true);
    final loadGeneration = gate.generation;

    gate.setRequestAllowed(false);

    expect(gate.canUseAds, isFalse);
    expect(gate.isCurrent(loadGeneration), isFalse);
  });

  test(
    'does not revalidate a previous load after consent is granted again',
    () {
      final gate = AdLoadGate()..setRequestAllowed(true);
      final firstLoadGeneration = gate.generation;

      gate.setRequestAllowed(false);
      gate.setRequestAllowed(true);

      expect(gate.isCurrent(firstLoadGeneration), isFalse);
      expect(gate.isCurrent(gate.generation), isTrue);
    },
  );

  test('premium/no-ads disabling invalidates a pending load', () {
    final gate = AdLoadGate()..setRequestAllowed(true);
    final loadGeneration = gate.generation;

    gate.setDisabled(true);

    expect(gate.canUseAds, isFalse);
    expect(gate.isCurrent(loadGeneration), isFalse);
  });

  test('retries until the configured maximum number of failed loads', () {
    expect(
      shouldRetryAdLoad(failedAttempts: 1, maxFailedLoadAttempts: 2),
      isTrue,
    );
    expect(
      shouldRetryAdLoad(failedAttempts: 2, maxFailedLoadAttempts: 2),
      isFalse,
    );
  });
}
