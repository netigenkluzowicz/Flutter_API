import 'package:flutter_api/src/banner_ad_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BannerAdGate gate;

  setUp(() => gate = BannerAdGate());

  test('banners are not allowed before consent reports canRequestAds', () {
    expect(gate.value, isFalse);
  });

  test('withdrawn consent closes the gate and invalidates a pending load', () {
    gate.setRequestAllowed(true);
    expect(gate.value, isTrue);
    final loadGeneration = gate.generation;

    gate.setRequestAllowed(false);

    expect(gate.value, isFalse);
    expect(gate.isCurrent(loadGeneration), isFalse);
  });

  test('the no-ads flag overrides a granted consent', () {
    gate.setRequestAllowed(true);
    gate.setDisabled(true);
    expect(gate.value, isFalse);

    gate.setDisabled(false);
    expect(gate.value, isTrue);
  });

  test('re-enabling the format does not grant consent by itself', () {
    gate.setDisabled(true);
    gate.setDisabled(false);

    expect(gate.value, isFalse);
  });

  test('listeners are notified once per effective change', () {
    var notifications = 0;
    gate.addListener(() => notifications++);

    gate.setRequestAllowed(true);
    gate.setRequestAllowed(true);
    expect(notifications, 1);

    // Consent is already missing, so disabling changes nothing effective.
    gate.setRequestAllowed(false);
    expect(notifications, 2);
    gate.setDisabled(true);
    expect(notifications, 2);
  });
}
